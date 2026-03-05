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
| `argument_order` | Yes | Controls `"args"` order | Determines iteration order (see below) |
| `name` | No | — | ID is used instead |
| `isFunction` | No | — | Internal flag |
| `parallelSafe` | No | — | Internal flag |
| `visible` | No | — | Internal flag (blocks with visible: false are skipped entirely) |
| `function` | No | — | Internal reference |

## Pseudocode

### Generate DOC from Block Definition

Optional `prefix` is used by `list_folder` to prepend the folder path to the block ID (e.g., `utils/` + `replace` → `utils/replace`). For top-level DOC generation, omit or pass empty string.

```
function block_to_doc(block, prefix?):
    id = (prefix or "") + block.id
    args_array = build_args_array(block.arguments, block.argument_descriptions, block.argument_order)
    args_json = json_encode(args_array)

    doc = '{MBPB-DOC "' + id + '"'
    doc = doc + ', "description": "' + escape_string(block.description) + '"'
    doc = doc + ', "hasReturn": ' + to_string(block.hasReturn)
    if block.hasReturn and block.returnDescription:
        doc = doc + ', "returnDescription": "' + escape_string(block.returnDescription) + '"'
    doc = doc + ', "args": ' + args_json
    doc = doc + '/MBPB-DOC}'

    return doc
```

### Build Args Array

Uses `argument_order` to control output order when present. If omitted, iterates keys in implementation-defined order. **Recommended**: Always provide `argument_order` — some languages (e.g., Lua) have non-deterministic map iteration, meaning args would appear in different orders across runs without it.

```
function build_args_array(arguments, argument_descriptions, argument_order):
    args = []

    -- Determine iteration order
    if argument_order is not null and length(argument_order) > 0:
        keys = argument_order
    else:
        keys = get_keys(arguments)  -- implementation-defined order

    for each key in keys:
        if arguments does not have key:
            continue  -- skip if argument_order references a missing key

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

The registry is a map keyed by block ID. Sort keys before iterating for deterministic output across runs.

```
function blocks_to_prompt(registry):
    ids = sorted(get_keys(registry))
    lines = []

    for each id in ids:
        block = registry[id]
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

Adds blocks to a folder path with a description and optional expanded flag. Each folder entry stores block IDs, a description, and whether to dump contents into the system prompt. Merges block IDs if the path already exists. Copies input list to avoid shared references.

```
function register_folder(folder_map, path, block_ids, description?, expanded?):
    if folder_map does not have path:
        folder_map[path] = {
            block_ids: [],
            description: description or "",
            expanded: expanded or false
        }

    folder = folder_map[path]

    for each id in block_ids:
        if id not in folder.block_ids:
            append(folder.block_ids, id)

    if description is not null:
        folder.description = description
    if expanded is not null:
        folder.expanded = expanded
```

### Strip Folder Prefix

Strips the longest matching folder prefix from a block ID. Used during execution to look up the block definition in the flat registry when the LLM calls it with a folder-prefixed ID (e.g., `utils/replace` → `replace`).

```
function strip_folder_prefix(block_id, folder_map):
    best_match = ""

    for each path in folder_map:
        if block_id starts with path and length(path) > length(best_match):
            best_match = path

    if best_match != "":
        return substring(block_id, length(best_match) + 1, end)

    return block_id
```

### Folder-Aware DOC Generation

When `list-folder` is called, generate DOC lines for blocks in that folder with the folder path prepended to the ID via the `prefix` parameter of `block_to_doc`. Subfolder listings include descriptions when available.

```
function list_folder(folder_map, registry, folder_path):
    if folder_map does not have folder_path:
        return ""

    folder = folder_map[folder_path]
    lines = []

    for each id in folder.block_ids:
        block = registry[id]
        if block.visible == false:
            continue
        doc = block_to_doc(block, folder_path)
        lines = append(lines, doc)

    -- Include subfolders (direct children only)
    for each path in folder_map:
        if path starts with folder_path and path != folder_path:
            remaining = substring(path, length(folder_path), end)
            remaining_stripped = remove_trailing_slash(remaining)
            if remaining_stripped does not contain "/":
                subfolder = folder_map[path]
                if subfolder.description != "":
                    lines = append(lines, "Subfolder: " + path + " - " + subfolder.description)
                else:
                    lines = append(lines, "Subfolder: " + path)

    return join(lines, newline)
```

### Expanded Folders to Prompt

Generates DOC lines for all blocks in expanded folders with folder-prefixed IDs. Used by `generate_prompt` to dump expanded folder contents into the system prompt. Sorted by folder path for deterministic output.

```
function expanded_folders_to_prompt(folder_map, registry):
    lines = []

    for each path in sorted(get_keys(folder_map)):
        folder = folder_map[path]
        if not folder.expanded:
            continue
        for each id in folder.block_ids:
            block = registry[id]
            if block.visible == false:
                continue
            lines = append(lines, block_to_doc(block, path))

    return join(lines, newline)
```

### Folder Listing to Prompt

Generates a listing of non-expanded folders with descriptions for the system prompt. The LLM uses this to know which folders exist and what they contain before calling `list-folder`.

```
function folder_listing_to_prompt(folder_map):
    lines = []

    for each path in sorted(get_keys(folder_map)):
        folder = folder_map[path]
        if folder.expanded:
            continue
        if folder.description != "":
            lines = append(lines, "- " + path + " " + folder.description)
        else:
            lines = append(lines, "- " + path)

    return join(lines, newline)
```

### Has Non-Expanded Folders

Helper to check if any folders require `list-folder` for discovery. App uses this to decide whether to register the `list-folder` block.

```
function has_non_expanded_folders(folder_map):
    for each path in folder_map:
        if not folder_map[path].expanded:
            return true
    return false
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
    "argument_order": ["tags", "paths", "recursive"],
    "isFunction": true,
    "hasReturn": false,
    "parallelSafe": true
}
```

### Output MBPB-DOC
```
{MBPB-DOC "tag-files", "description": "Applies tags to specified files.", "hasReturn": false, "args": [{"name": "tags", "type": "array", "description": "List of tag strings to apply."}, {"name": "paths", "type": "array", "description": "List of file paths to tag."}, {"name": "recursive", "type": "boolean", "description": "Whether to tag files in subdirectories."}]/MBPB-DOC}
```

## Folder Structure

Each folder entry in `folder_map` contains:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `block_ids` | array | `[]` | Block IDs in this folder |
| `description` | string | `""` | Description shown to LLM in folder listings |
| `expanded` | boolean | `false` | If true, folder contents are dumped into the system prompt |

## Notes
- Output must always be single-line (no newlines within a DOC entry) to minimize context window usage.
- `escape_string` must handle quotes and special characters in description text.
- Argument order in output follows `argument_order` when present. If omitted, order is implementation-defined. Languages without deterministic key iteration (e.g., Lua) should always use `argument_order` for predictable output.
- `blocks_to_prompt` takes the registry (a map keyed by block ID) and sorts keys before iterating. This ensures deterministic DOC output across runs regardless of language-specific map iteration order.
- `blocks_to_prompt` output is inserted into the system prompt template (see [system-prompt.md](system-prompt.md)).
- `register_block` should be called for each block during app setup. ID suffix assignment happens once at registration, not during parsing.
- Blocks with `visible: false` are skipped by `blocks_to_prompt`, `list_folder`, and `expanded_folders_to_prompt`.
- `block_to_doc` accepts an optional `prefix` parameter. When omitted, the block's own ID is used directly. When provided (by `list_folder` or `expanded_folders_to_prompt`), the prefix is prepended to the ID so the LLM calls blocks with the full folder path (e.g., `utils/replace`). The prefix is never stored on the block — it is display-only.
- `strip_folder_prefix` finds the longest matching folder path prefix and removes it. Only reads folder_map keys, not values — unaffected by folder structure changes. Used when executing folder-prefixed block calls. Also used in `generate_reply` (see [mbp-reply.md](mbp-reply.md)).
- `returnDescription` is only included in DOC output when the block has `hasReturn: true`.
- Folder descriptions are required for non-expanded folders — without them the LLM guesses what a folder contains based on its path name alone.
- Expanded folders dump their blocks into the system prompt with folder-prefixed IDs. The LLM sees them as available blocks without calling `list-folder`. Use `has_non_expanded_folders` to check if `list-folder` registration is needed.

Reply generation (MBPB-RET, MBPB-TRY) is in [mbp-reply.md](mbp-reply.md).
