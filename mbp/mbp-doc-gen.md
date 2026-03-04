# MBPB-DOC Generation

## Overview
MBPB-DOC lines are generated from block definitions to present available blocks to the LLM in the system prompt. The generation module reads a single block definition object and outputs the compact DOC format, including only LLM-visible fields.

## Generation Input and Output

**Input**: Block definition object (the same object used for parsing and execution)

**Output**: Single-line MBPB-DOC string

## Field Mapping

| Block Definition Field | Included | MBPB-DOC Field | Notes |
|----------------------|----------|----------------|-------|
| `id` | Yes | First quoted string | Direct copy |
| `description` | Yes | `"description"` | Direct copy |
| `hasReturn` | Yes | `"hasReturn"` | Direct copy (boolean, not quoted) |
| `returnDescription` | If hasReturn | `"returnDescription"` | Only included when hasReturn is true |
| `arguments` | Yes | Merged into `"args"` | Keys become `name`, values become `type` |
| `argument_descriptions` | Yes | Merged into `"args"` | Values become `description` per arg |
| `name` | No | — | ID is used instead |
| `isFunction` | No | — | Internal flag |
| `parallelSafe` | No | — | Internal flag |
| `visible` | No | — | Internal flag (blocks with visible: false are skipped entirely) |
| `function` | No | — | Internal reference |

## Pseudocode

### Generate DOC from Block Definition

```
function block_to_doc(block):
    args_array = build_args_array(block.arguments, block.argument_descriptions)
    args_json = json_encode(args_array)

    doc = '{MBPB-DOC "' + block.id + '"'
    doc = doc + ', "description": "' + escape_string(block.description) + '"'
    doc = doc + ', "hasReturn": ' + to_string(block.hasReturn)
    if block.hasReturn and block.returnDescription:
        doc = doc + ', "returnDescription": "' + escape_string(block.returnDescription) + '"'
    doc = doc + ', "args": ' + args_json
    doc = doc + '/MBPB-DOC}'

    return doc
```

### Build Args Array

```
function build_args_array(arguments, argument_descriptions):
    args = []

    for each key in arguments:
        arg = {
            "name": key,
            "type": arguments[key]
        }

        if argument_descriptions has key:
            arg["description"] = argument_descriptions[key]

        -- If type is "object" and sub-argument structure is defined,
        -- recursively build sub_args (implementation-specific)

        args = append(args, arg)

    return args
```

### Generate System Prompt Blocks Section

```
function blocks_to_prompt(blocks):
    lines = []

    for each block in blocks:
        if block.visible == false:
            continue
        line = block_to_doc(block)
        lines = append(lines, line)

    return join(lines, newline)
```

### Auto-Generate Block IDs with Suffix

Called during block registration. Assigns unique IDs based on name, appending `-1`, `-2`, etc. for duplicates.

```
function register_block(registry, block):
    base_id = block.name
    id = base_id
    suffix = 1

    while registry has id:
        id = base_id + "-" + to_string(suffix)
        suffix = suffix + 1

    block.id = id
    registry[id] = block
    return block
```

### Register Folder

Adds blocks to a folder path. Merges if the path already exists.

```
function register_folder(folder_map, path, block_ids):
    if folder_map has path:
        for each id in block_ids:
            if id not in folder_map[path]:
                append(folder_map[path], id)
    else:
        folder_map[path] = block_ids
```

### Folder-Aware DOC Generation

When `list-folder` is called, generate DOC lines for blocks in that folder with the folder path prepended to the ID.

```
function list_folder(folder_map, registry, folder_path):
    if folder_map does not have folder_path:
        return ""

    block_ids = folder_map[folder_path]
    lines = []

    for each id in block_ids:
        block = registry[id]
        if block.visible == false:
            continue
        -- Prepend folder path to ID for the DOC line
        doc = block_to_doc_with_prefix(block, folder_path)
        lines = append(lines, doc)

    -- Include subfolders
    for each path in folder_map:
        if path starts with folder_path and path != folder_path:
            -- Only direct children (one level deeper)
            remaining = substring(path, length(folder_path), end)
            remaining_stripped = remove_trailing_slash(remaining)
            if remaining_stripped does not contain "/":
                lines = append(lines, "Subfolder: " + path)

    return join(lines, newline)

function block_to_doc_with_prefix(block, prefix):
    args_array = build_args_array(block.arguments, block.argument_descriptions)
    args_json = json_encode(args_array)

    doc = '{MBPB-DOC "' + prefix + block.id + '"'
    doc = doc + ', "description": "' + escape_string(block.description) + '"'
    doc = doc + ', "hasReturn": ' + to_string(block.hasReturn)
    if block.hasReturn and block.returnDescription:
        doc = doc + ', "returnDescription": "' + escape_string(block.returnDescription) + '"'
    doc = doc + ', "args": ' + args_json
    doc = doc + '/MBPB-DOC}'

    return doc
```

## Example

### Input Block Definition
```json
{
    "name": "tag-files",
    "id": "tag-files",
    "description": "Applies tags to specified files.",
    "arguments": {
        "tags": "array",
        "paths": "array",
        "recursive": "boolean"
    },
    "argument_descriptions": {
        "tags": "List of tag strings to apply.",
        "paths": "List of file paths to tag.",
        "recursive": "Whether to tag files in subdirectories."
    },
    "isFunction": true,
    "hasReturn": false,
    "parallelSafe": true
}
```

### Output MBPB-DOC
```
{MBPB-DOC "tag-files", "description": "Applies tags to specified files.", "hasReturn": false, "args": [{"name": "tags", "type": "array", "description": "List of tag strings to apply."}, {"name": "paths", "type": "array", "description": "List of file paths to tag."}, {"name": "recursive", "type": "boolean", "description": "Whether to tag files in subdirectories."}]/MBPB-DOC}
```

## Notes
- Output must always be single-line (no newlines within a DOC entry) to minimize context window usage.
- `escape_string` must handle quotes and special characters in description text.
- Argument order in output should match the order defined in the block.
- `blocks_to_prompt` output is inserted into the system prompt template (see [system-prompt.md](system-prompt.md)).
- `register_block` should be called for each block during app setup. ID suffix assignment happens once at registration, not during parsing.
- Blocks with `visible: false` are skipped by both `blocks_to_prompt` and `list_folder`.
- `list_folder` prepends the folder path to block IDs so the LLM calls them with the full path (e.g., `utils/replace`).
- `returnDescription` is only included in DOC output when the block has `hasReturn: true`.

Reply generation (MBPB-RET, MBPB-TRY) is in [mbp-reply.md](mbp-reply.md).
