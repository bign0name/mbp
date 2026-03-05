# MBP Parser

## Overview
The MBP parser extracts block calls from LLM output and separates them from regular text (leftover output). It uses a JSON-aware single-pass approach to correctly handle string content that may contain MBP-like syntax.

## Input / Output

**Input**: Raw LLM response string

**Output**:
- `blocks`: Ordered list of parsed block objects, each containing `id` (string), `args` (object), and `index` (number, 1-based position in response)
- `retries`: List of retry objects for blocks that failed to parse, each containing `id` (string or "unknown"), `index` (number), and `error` (string)
- `leftover`: Regular text outside of blocks, returned as a single string. Apps can split or reformat this as needed (e.g., split by newlines, split into segments between blocks, etc.)

## Pseudocode

### Main Parse Function

```
function parse(response):
    blocks = []
    retries = []
    leftover = ""
    position = 0
    block_index = 0

    while position < length(response):
        start_index = find("{MBPB ", response, position)

        if start_index == NOT_FOUND:
            leftover = leftover + substring(response, position, end)
            break

        leftover = leftover + substring(response, position, start_index)

        block_index = block_index + 1
        block, end_position = parse_block(response, start_index)

        if block == PARSE_ERROR:
            -- Check if this looks like a complete block attempt (has end tag)
            end_tag = find("/MBPB}", response, start_index)
            if end_tag != NOT_FOUND:
                -- Extract ID if possible for the retry
                partial_id = try_extract_id(response, start_index)
                retry = {
                    id: partial_id or "unknown",
                    index: block_index,
                    error: "Failed to parse block"
                }
                retries = append(retries, retry)
                position = end_tag + 6
            else:
                -- No end tag, treat as regular text
                leftover = leftover + "{MBPB "
                position = start_index + 6
                block_index = block_index - 1  -- wasn't a real block attempt
            continue

        block.index = block_index
        blocks = append(blocks, block)
        position = end_position

    return blocks, retries, leftover
```

### Block Parsing

```
function parse_block(response, start_index):
    position = start_index + 6  -- skip "{MBPB "

    id, position = read_quoted_string(response, position)
    if id == PARSE_ERROR:
        return PARSE_ERROR, start_index

    position = skip_whitespace(response, position)
    if response[position] != ',':
        return PARSE_ERROR, start_index
    position = position + 1
    position = skip_whitespace(response, position)

    if not starts_with(response, position, '"args"'):
        return PARSE_ERROR, start_index
    position = position + 6
    position = skip_whitespace(response, position)
    if response[position] != ':':
        return PARSE_ERROR, start_index
    position = position + 1
    position = skip_whitespace(response, position)

    args_string, position = extract_json_object(response, position)
    if args_string == PARSE_ERROR:
        return PARSE_ERROR, start_index

    position = skip_whitespace(response, position)
    if not starts_with(response, position, "/MBPB}"):
        return PARSE_ERROR, start_index
    position = position + 6

    args = json_parse(args_string)
    if args == PARSE_ERROR:
        return PARSE_ERROR, start_index

    return { id: id, args: args }, position
```

### JSON-Aware Object Extraction

Core of the parser. Tracks brace depth and string boundaries to correctly handle nested content.

```
function extract_json_object(response, position):
    if response[position] != '{':
        return PARSE_ERROR, position

    start = position
    depth = 0
    in_string = false
    escape_next = false

    while position < length(response):
        char = response[position]

        if escape_next:
            escape_next = false
            position = position + 1
            continue

        if in_string:
            if char == '\\':
                escape_next = true
            else if char == '"':
                in_string = false
        else:
            if char == '"':
                in_string = true
            else if char == '{':
                depth = depth + 1
            else if char == '}':
                depth = depth - 1
                if depth == 0:
                    position = position + 1
                    return substring(response, start, position), position

        position = position + 1

    return PARSE_ERROR, position
```

### Read Quoted String

```
function read_quoted_string(response, position):
    position = skip_whitespace(response, position)
    if response[position] != '"':
        return PARSE_ERROR, position

    position = position + 1
    start = position
    escape_next = false

    while position < length(response):
        char = response[position]

        if escape_next:
            escape_next = false
            position = position + 1
            continue

        if char == '\\':
            escape_next = true
        else if char == '"':
            value = substring(response, start, position)
            position = position + 1
            return value, position

        position = position + 1

    return PARSE_ERROR, position
```

### Try Extract ID

Best-effort ID extraction for failed blocks (used in retry generation).

```
function try_extract_id(response, start_index):
    position = start_index + 6  -- skip "{MBPB "
    id, _ = read_quoted_string(response, position)
    if id == PARSE_ERROR:
        return null
    return id
```

## Stream Parsing

For streaming LLM responses (e.g., token-by-token), the parser works incrementally on a growing buffer using index-based tracking.

```
function create_stream_parser():
    return {
        buffer: "",
        scan_position: 0,
        block_index: 0,
        blocks: [],
        retries: []
    }

function feed(parser, new_text):
    parser.buffer = parser.buffer + new_text
    completed_blocks = []
    new_retries = []

    while true:
        start_index = find("{MBPB ", parser.buffer, parser.scan_position)

        if start_index == NOT_FOUND:
            break

        parser.block_index = parser.block_index + 1
        block, end_position = parse_block(parser.buffer, start_index)

        if block == PARSE_ERROR:
            end_tag_index = find("/MBPB}", parser.buffer, start_index)
            if end_tag_index != NOT_FOUND:
                -- Malformed block with end tag: generate retry
                partial_id = try_extract_id(parser.buffer, start_index)
                retry = {
                    id: partial_id or "unknown",
                    index: parser.block_index,
                    error: "Failed to parse block"
                }
                new_retries = append(new_retries, retry)
                parser.retries = append(parser.retries, retry)
                parser.scan_position = end_tag_index + 6
                continue
            else:
                -- No end tag yet, wait for more data
                parser.block_index = parser.block_index - 1
                break

        block.index = parser.block_index
        completed_blocks = append(completed_blocks, block)
        parser.blocks = append(parser.blocks, block)
        parser.scan_position = end_position

    return completed_blocks, new_retries

function get_leftover(parser):
    -- Call after stream ends to get text outside blocks
    _, _, leftover = parse(parser.buffer)
    return leftover
```

`scan_position` advances past completed blocks so they aren't re-parsed. Incomplete blocks (no end tag yet) cause the parser to wait for more data. When the stream ends, call `get_leftover` to extract text outside blocks.

## Notes
- Naive regex breaks on nested MBP blocks within string arguments. The JSON-aware parser handles this correctly with negligible overhead.
- When a block fails to parse and has a complete end tag, the parser generates a retry (MBPB-TRY) with the block ID and index. If no end tag exists, the start tag is treated as regular text.
- The `json_parse` call uses the language's built-in JSON parser — the args object is standard JSON once extracted from the MBPB tags. **MBP does not provide a JSON implementation.** Language implementations must use their platform's JSON library (e.g., `JSON.parse` in JS/TS, `json` module in Python, `vim.json` in Neovim, `encoding/json` in Go, etc.).
- Apps can structure leftover text however they want (single string, array of segments, etc.).
- Block index is 1-based and tracks position in the LLM's response across both successful blocks and failed parse attempts.
