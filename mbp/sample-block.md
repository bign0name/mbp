# Sample Block: replace

Reference block for language implementations. Implement this first to verify the full MBP pipeline: registration, DOC generation, system prompt, LLM call, parsing, execution, error handling, return, and retry.

## Block Definition

```json
{
  "name": "replace",
  "id": "replace",
  "description": "Replaces all occurrences of a search string with a replacement string.",
  "arguments": {
    "search": "string",
    "replace": "string",
    "text": "string"
  },
  "argument_descriptions": {
    "search": "The string to search for.",
    "replace": "The string to replace with.",
    "text": "The input text."
  },
  "isFunction": true,
  "hasReturn": true,
  "returnDescription": "The text with all replacements applied.",
  "parallelSafe": true,
  "visible": true
}
```

## Generated MBPB-DOC

```
{MBPB-DOC "replace", "description": "Replaces all occurrences of a search string with a replacement string.", "hasReturn": true, "returnDescription": "The text with all replacements applied.", "args": [{"name": "search", "type": "string", "description": "The string to search for."}, {"name": "replace", "type": "string", "description": "The string to replace with."}, {"name": "text", "type": "string", "description": "The input text."}]/MBPB-DOC}
```

## LLM Call

```
{MBPB "replace", "args": {"search": "hello", "replace": "world", "text": "hello there, hello again"}/MBPB}
```

## Return (sent back to LLM)

```
{MBPB-RET "replace", "index": 1}
world there, world again
{/MBPB-RET}
```

## Error Return Example

```
{MBPB-RET "replace", "index": 1, "error": true}
Missing required argument: text
{/MBPB-RET}
```

## Retry Example (parse failure)

```
{MBPB-TRY "replace", "index": 1}
Malformed JSON in args object
{/MBPB-TRY}
```

## Full Execution Pseudocode

### Block Function

The actual logic. Returns a value or throws an error.

```
function replace_function(args):
    -- Validate required arguments
    if args.search == null:
        throw error("Missing required argument: search")
    if args.replace == null:
        throw error("Missing required argument: replace")
    if args.text == null:
        throw error("Missing required argument: text")

    return string_replace_all(args.text, args.search, args.replace)
```

### Registration

```
-- Create block definition
replace_block = {
    name: "replace",
    description: "Replaces all occurrences of a search string with a replacement string.",
    arguments: { search: "string", replace: "string", text: "string" },
    argument_descriptions: {
        search: "The string to search for.",
        replace: "The string to replace with.",
        text: "The input text."
    },
    isFunction: true,
    hasReturn: true,
    returnDescription: "The text with all replacements applied.",
    parallelSafe: true,
    visible: true,
    function: replace_function
}

-- Register (auto-assigns ID)
register_block(registry, replace_block)
```

### Full App Loop

Shows the complete flow from LLM response to reply.

```
-- 1. Parse LLM response
blocks, retries, leftover = parse(llm_response)

-- 2. Execute blocks with error catching
results = execute_blocks(blocks, registry)

-- 3. Generate reply (handles returns, errors, and retries)
reply = generate_reply(results, retries, registry)

-- 4. Send reply back to LLM (if there's anything to send)
if reply != null:
    send_to_llm(reply)
```

### Manual Execution (isFunction: false example)

For blocks where the app handles execution instead of the module.

```
-- App catches error and uses generate_return directly
for each block in blocks:
    block_def = registry[block.id]

    if not block_def.isFunction:
        -- App handles this block
        try:
            result = app_custom_handler(block)
            if block_def.hasReturn:
                ret = generate_return(block.id, block.index, result, false)
                append_to_reply(ret)
        catch error:
            ret = generate_return(block.id, block.index, to_string(error), true)
            append_to_reply(ret)
```

## Verification Checklist

1. Register block → ID assigned as `replace`
2. Generate DOC → matches MBPB-DOC above (includes `returnDescription`)
3. Insert DOC into system prompt → LLM sees the block
4. Parse LLM call → extracted block has id `replace`, args with search/replace/text, index 1
5. Execute with valid args → returns modified string
6. Execute with missing arg → throws error, caught by wrapper
7. Wrap success in MBPB-RET → `{MBPB-RET "replace", "index": 1} ... {/MBPB-RET}`
8. Wrap error in MBPB-RET → `{MBPB-RET "replace", "index": 1, "error": true} ... {/MBPB-RET}`
9. Test malformed block → parser generates MBPB-TRY with ID and index
10. Full loop → parse, execute, generate reply, send back
