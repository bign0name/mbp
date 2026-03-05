-- MBP main template
-- Copy and customize this file for your app's parse loop.
-- This shows the full wiring pattern: register blocks, build prompt,
-- parse response, execute, and generate reply.

local mbp = require("mbp-vim")

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

local registry = {}
local folders = {}

-- Register blocks
local replace = require("blocks.replace")
mbp.register_block(registry, replace.block())

-- Register your blocks here:
-- local my_block = require("blocks.my-block")
-- mbp.register_block(registry, my_block.block())

-- Register folders (description required for non-expanded)
-- Expanded folders dump blocks into prompt directly:
-- mbp.register_folder(folders, "utils/", { "replace" }, "Text manipulation utilities", true)
-- Non-expanded folders need list-folder for discovery:
-- mbp.register_folder(folders, "io/", { "write-file" }, "File system operations")

-- Register list-folder only if needed
if mbp.has_non_expanded_folders(folders) then
  mbp.register_block(registry, mbp.create_list_folder_block(folders, registry))
end

---------------------------------------------------------------------------
-- Prompt generation
---------------------------------------------------------------------------

--- Build a complete prompt ready to send to the LLM.
---@param user_input string
---@param system_prompt string|nil
---@return string
local function build_prompt(user_input, system_prompt)
  return mbp.generate_prompt(
    registry,
    user_input,
    system_prompt or "You are a helpful assistant.",
    folders
  )
end

---------------------------------------------------------------------------
-- Batch parse loop (non-streaming)
---------------------------------------------------------------------------

--- Process a complete LLM response. Returns reply string (or nil) and leftover text.
---@param llm_response string
---@return string|nil reply, string leftover
local function process_response(llm_response)
  local blocks, retries, leftover = mbp.parse(llm_response)
  local results = mbp.execute_blocks(blocks, registry, folders)
  local reply = mbp.generate_reply(results, retries, registry, folders)
  return reply, leftover
end

---------------------------------------------------------------------------
-- Stream parse loop
---------------------------------------------------------------------------

--- Create a streaming processor.
--- Call feed() with chunks as they arrive, finish() when stream ends.
---@return table processor with :feed(chunk) and :finish()
local function create_stream_processor()
  local sp = mbp.create_stream_parser()

  local processor = {}

  --- Feed a chunk from the LLM stream.
  --- Returns newly completed blocks and retries (if any).
  ---@param chunk string
  ---@return table new_blocks, table new_retries
  function processor:feed(chunk)
    return sp:feed(chunk)
  end

  --- Call when stream ends. Executes all blocks and returns reply + leftover.
  ---@return string|nil reply, string leftover
  function processor:finish()
    local leftover = sp:get_leftover()
    local results = mbp.execute_blocks(sp.blocks, registry, folders)
    local reply = mbp.generate_reply(results, sp.retries, registry, folders)
    return reply, leftover
  end

  return processor
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------

return {
  registry = registry,
  folders = folders,
  build_prompt = build_prompt,
  process_response = process_response,
  create_stream_processor = create_stream_processor,
}
