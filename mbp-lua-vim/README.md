# MBP Neovim Implementation

MBP Spec v2026.p.0.0.0

Neovim implementation using `vim.json` for JSON encoding/decoding. No external dependencies.

## Requirements

- Neovim 0.6+ (for `vim.json`)

## Setup

Copy the `mbp-lua-vim/` directory into your Neovim runtime path (e.g., `lua/` directory of your plugin).

```
mbp-lua-vim/
├── mbp-vim.lua          -- library (don't edit)
├── main.lua             -- parse loop template (customize for your app)
└── blocks/
    └── replace.lua      -- sample block (copy pattern for new blocks)
```

```lua
-- In your plugin, require main.lua:
local mbp_main = require("main")

-- Build prompt
local prompt = mbp_main.build_prompt("Replace hello with world in 'hello there'")

-- After getting LLM response:
local reply, leftover = mbp_main.process_response(llm_output)

-- Or use streaming:
local processor = mbp_main.create_stream_processor()
-- ... feed chunks with processor:feed(chunk) ...
local reply, leftover = processor:finish()
```

`main.lua` is the file you customize — register your blocks, set up folders, adjust the system prompt. `mbp-vim.lua` is the library. Block files in `blocks/` follow a standard pattern.

## Block Definition Fields

See [block-schema.md](../mbp/block-schema.md) for the full schema. In Lua, the `function` field is named `func` since `function` is a reserved keyword.

## Block File Pattern

Each block is a separate Lua module that returns a `block()` function. See `blocks/replace.lua` as a template:

```lua
local M = {}

function M.block()
  return {
    name = "my-block",
    description = "Does something useful.",
    arguments = { input = "string" },
    argument_descriptions = { input = "The input value." },
    argument_order = { "input" },
    isFunction = true,
    hasReturn = true,
    returnDescription = "The result.",
    func = function(args)
      return do_something(args.input)
    end,
  }
end

return M
```

Register it:

```lua
local my_block = require("blocks.my-block")
mbp.register_block(registry, my_block.block())
```

## API

### Registration

**`mbp.register_block(registry, block)`** — Register a block definition. Auto-assigns unique ID from name (appends `-1`, `-2` for duplicates). Sets defaults for `visible` (true) and `parallelSafe` (false). Returns the block with ID assigned.

**`mbp.register_folder(folder_map, path, block_ids, description?, expanded?)`** — Register a folder with block IDs, a description, and an optional expanded flag. Merges if path exists, deduplicates. Description tells the LLM what the folder contains. Expanded folders dump their blocks into the system prompt directly.

```lua
local folders = {}
mbp.register_folder(folders, "utils/", { "replace", "grep" }, "Text manipulation utilities")
mbp.register_folder(folders, "io/", { "read-file", "write-file" }, "File system operations", true) -- expanded
```

### DOC Generation

**`mbp.block_to_doc(block, prefix?)`** — Generate a single MBPB-DOC line. Optional prefix for folder-scoped IDs.

**`mbp.blocks_to_prompt(registry)`** — Generate all MBPB-DOC lines for visible blocks. Sorted by ID for deterministic output.

### Folders

**`mbp.list_folder(folder_map, registry, folder_path)`** — Generate DOC lines for blocks in a folder (with folder-prefixed IDs) plus subfolder listings with descriptions.

**`mbp.strip_folder_prefix(block_id, folder_map)`** — Strip the longest matching folder prefix from a block ID.

**`mbp.expanded_folders_to_prompt(folder_map, registry)`** — Generate DOC lines for all blocks in expanded folders with prefixed IDs.

**`mbp.folder_listing_to_prompt(folder_map)`** — Generate listing of non-expanded folders with descriptions for the system prompt.

**`mbp.has_non_expanded_folders(folder_map)`** — Returns true if any folders need `list-folder` for discovery.

**`mbp.create_list_folder_block(folder_map, registry)`** — Returns a block definition for the built-in `list-folder` block, pre-bound to your folder map and registry.

```lua
-- Only register list-folder if there are non-expanded folders to discover
if mbp.has_non_expanded_folders(folders) then
  mbp.register_block(registry, mbp.create_list_folder_block(folders, registry))
end
```

### Parser

**`mbp.parse(response)`** — Parse an LLM response. Returns `blocks`, `retries`, `leftover`.

- `blocks`: list of `{ id, args, index }`
- `retries`: list of `{ id, index, error }` for malformed blocks
- `leftover`: text outside blocks (trimmed)

```lua
local blocks, retries, leftover = mbp.parse(llm_output)
```

**`mbp.create_stream_parser()`** — Create a stream parser for incremental token-by-token parsing.

```lua
local sp = mbp.create_stream_parser()

-- Feed chunks as they arrive
local new_blocks, new_retries = sp:feed(chunk)

-- After stream ends
local leftover = sp:get_leftover()
local all_blocks = sp.blocks
local all_retries = sp.retries
```

### Reply Generation

**`mbp.generate_return(block_id, index, content, is_error)`** — Build a single MBPB-RET tag.

**`mbp.generate_retry(block_id, index, error_message)`** — Build a single MBPB-TRY tag.

**`mbp.execute_blocks(blocks, registry, folder_map?)`** — Execute parsed blocks against registry. Catches errors. Returns list of result objects.

**`mbp.generate_reply(results, retries, registry, folder_map?)`** — Combine execution results and parse retries into a reply string. Returns `nil` if nothing to send.

### System Prompt

**`mbp.generate_prompt(registry, user_prompt, system_prompt?, folder_map?)`** — Generate complete system prompt with MBP instructions, examples, block docs, expanded folder blocks, non-expanded folder listings, and return format.

## Full Example

```lua
local mbp = require("mbp-vim")
local replace = require("blocks.replace")

local registry = {}
local folders = {}

-- Register blocks
mbp.register_block(registry, replace.block())

mbp.register_block(registry, {
  name = "write-file",
  description = "Writes content to a file at the specified path.",
  arguments = { path = "string", content = "string" },
  argument_descriptions = {
    path = "File path to write to.",
    content = "Content to write.",
  },
  argument_order = { "path", "content" },
  isFunction = true,
  hasReturn = false,
  func = function(args)
    local f = io.open(args.path, "w")
    if not f then error("Cannot open: " .. args.path) end
    f:write(args.content)
    f:close()
  end,
})

-- Register folders
mbp.register_folder(folders, "utils/", { "replace" }, "Text manipulation utilities", true) -- expanded into prompt
mbp.register_folder(folders, "io/", { "write-file" }, "File system operations") -- needs list-folder

-- Register list-folder if needed
if mbp.has_non_expanded_folders(folders) then
  mbp.register_block(registry, mbp.create_list_folder_block(folders, registry))
end

-- Generate prompt
local prompt = mbp.generate_prompt(
  registry,
  "Replace hello with world in 'hello there'",
  "You are a helpful assistant.",
  folders
)

-- Send prompt to LLM, get response...
local llm_output = get_llm_response(prompt)

-- Parse
local blocks, retries, leftover = mbp.parse(llm_output)

-- Execute
local results = mbp.execute_blocks(blocks, registry, folders)

-- Build reply
local reply = mbp.generate_reply(results, retries, registry, folders)

-- Send back to LLM if needed
if reply then
  send_to_llm(reply)
end

-- Use leftover as display text
print(leftover)
```

## Manual Block Handling (isFunction = false)

For blocks where the app handles execution:

```lua
local results = mbp.execute_blocks(blocks, registry)

for _, result in ipairs(results) do
  if result.custom then
    local block = result.block
    local ok, ret = pcall(my_handler, block.id, block.args)
    local def = registry[block.id]
    if not ok then
      local tag = mbp.generate_return(block.id, block.index, tostring(ret), true)
      -- append to reply
    elseif def.hasReturn then
      local tag = mbp.generate_return(block.id, block.index, ret or "", false)
      -- append to reply
    end
  end
end
```

## Notes

- **`argument_order`**: Recommended for all blocks. Without it, Lua's `pairs()` iterates in non-deterministic order, so args in DOC output may appear in different orders across runs. `argument_order` guarantees consistent output.
- **`func` vs `function`**: Lua reserves `function`, so block definitions use `func` for the function reference.
- **JSON-aware parser**: Correctly handles nested MBP-like syntax inside string values (e.g., writing code that contains MBP blocks). Uses single-pass brace/string tracking.
- **Plain text replace**: The sample `replace` block uses `string.find` with `plain=true`. Safe for any search string including Lua pattern metacharacters like `.`, `%`, `(`, etc.
- **JSON**: Uses Neovim's built-in `vim.json.encode` and `vim.json.decode`. No external JSON library needed.
- **Folder descriptions**: Required for non-expanded folders. Without them the LLM guesses folder contents from the path name alone.
- **Expanded folders**: Dump blocks into the system prompt with folder-prefixed IDs. The LLM sees them as available blocks without calling `list-folder`.
