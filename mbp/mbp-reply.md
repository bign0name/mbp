# MBP Reply Generation

## Overview
After parsing and executing blocks from an LLM response, the app builds a reply to send back. This module generates MBPB-RET tags (returns and errors), MBPB-TRY tags (parse retries), and combines them into a single reply string.

## Pseudocode

### Generate Return Tag

```
function generate_return(block_id, index, content, is_error):
    if is_error:
        ret = '{MBPB-RET "' + block_id + '", "index": ' + to_string(index) + ', "error": true}'
    else:
        ret = '{MBPB-RET "' + block_id + '", "index": ' + to_string(index) + '}'

    ret = ret + newline + content + newline + '{/MBPB-RET}'
    return ret
```

### Generate Retry Tag

```
function generate_retry(block_id, index, error_message):
    if block_id:
        ret = '{MBPB-TRY "' + block_id + '", "index": ' + to_string(index) + '}'
    else:
        ret = '{MBPB-TRY "unknown", "index": ' + to_string(index) + '}'

    ret = ret + newline + error_message + newline + '{/MBPB-TRY}'
    return ret
```

### Execute Blocks and Collect Results

Wraps block execution to catch errors and pair each block with its result.

```
function execute_blocks(blocks, registry):
    results = []

    for each block in blocks:
        block_def = registry[block.id]

        if block_def == null:
            -- Unknown block ID (might be folder-prefixed, strip and retry)
            stripped_id = strip_folder_prefix(block.id)
            block_def = registry[stripped_id]

        if block_def == null:
            result = { block: block, error: true, content: "Unknown block: " + block.id }
            results = append(results, result)
            continue

        if block_def.isFunction:
            try:
                return_value = block_def.function(block.args)
                result = { block: block, error: false, content: return_value }
            catch error:
                result = { block: block, error: true, content: to_string(error) }
        else:
            -- isFunction: false, app handles in custom loop
            result = { block: block, error: false, content: null, custom: true }

        results = append(results, result)

    return results
```

### Generate Reply

Combines execution results and parse retries into a single reply string.

```
function generate_reply(results, retries, registry):
    parts = []

    -- Process execution results
    for each result in results:
        block = result.block
        block_def = registry[block.id] or registry[strip_folder_prefix(block.id)]

        if result.error:
            -- Errors always return regardless of hasReturn
            part = generate_return(block.id, block.index, result.content, true)
            parts = append(parts, part)

        else if result.custom:
            -- isFunction: false, skip (handled by app)
            continue

        else if block_def and block_def.hasReturn:
            -- Successful return
            content = result.content or ""
            part = generate_return(block.id, block.index, content, false)
            parts = append(parts, part)

        -- hasReturn: false + success = nothing

    -- Process parse retries
    for each retry in retries:
        part = generate_retry(retry.id, retry.index, retry.error)
        parts = append(parts, part)

    if length(parts) == 0:
        return null  -- Nothing to send back

    return join(parts, newline + newline)
```

## Full Flow Example

LLM sends a response with 3 blocks:

```
I'll search for the function and update both files.

{MBPB "grep", "args": {"pattern": "setup", "path": "src/"}/MBPB}

{MBPB "write-file", "args": {
  "path": "src/main.lua",
  "content": "local M = {}\nreturn M"
}/MBPB}

{MBPB "replace", "args": {"search": "old", "replace": "new", "text: "old value"}/MBPB}
```

1. Parser extracts: `grep` (index 1), `write-file` (index 2). Third block has malformed JSON (missing quote), generates retry (index 3).
2. Execute: `grep` returns matches (hasReturn: true). `write-file` succeeds (hasReturn: false, no return). 
3. Generate reply:

```
{MBPB-RET "grep", "index": 1}
src/main.lua:5: function M.setup()
src/init.lua:12: setup()
{/MBPB-RET}

{MBPB-TRY "replace", "index": 3}
Malformed JSON in args object
{/MBPB-TRY}
```

`write-file` (index 2) produced no return because `hasReturn: false` and no error. The reply contains only the grep return and the replace retry.

## Notes
- `generate_reply` returns null when there's nothing to send (all blocks succeeded with hasReturn: false and no parse errors). App can skip sending a reply in this case.
- Execution order matches block order in the LLM response. Results are processed in the same order.
- The `strip_folder_prefix` function checks known folder paths and strips matching prefixes to look up the block in the flat registry.
- For blocks with `isFunction: false`, the app handles execution in its own loop and can call `generate_return` directly with the result.
