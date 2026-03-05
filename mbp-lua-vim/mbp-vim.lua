-- MBP Neovim Implementation
-- Requires Neovim (uses vim.json for JSON encode/decode).

local mbp = {}

---------------------------------------------------------------------------
-- JSON backend (vim.json)
---------------------------------------------------------------------------

local function json_encode(val) return vim.json.encode(val) end
local function json_decode(str) return vim.json.decode(str) end

---------------------------------------------------------------------------
-- String utilities (internal)
---------------------------------------------------------------------------

local function escape_json_string(s)
  s = s:gsub("\\", "\\\\")
  s = s:gsub('"', '\\"')
  s = s:gsub("\n", "\\n")
  s = s:gsub("\r", "\\r")
  s = s:gsub("\t", "\\t")
  return s
end

local function skip_whitespace(str, pos)
  while pos <= #str and str:sub(pos, pos):match("%s") do
    pos = pos + 1
  end
  return pos
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

--- Register a block in the registry. Auto-assigns unique ID from name.
--- Sets defaults for visible (true) and parallelSafe (false).
---@param registry table
---@param block table
---@return table block with id assigned
function mbp.register_block(registry, block)
  local base = block.name
  local id = base
  local suffix = 1
  while registry[id] do
    id = base .. "-" .. tostring(suffix)
    suffix = suffix + 1
  end
  block.id = id
  if block.visible == nil then block.visible = true end
  if block.parallelSafe == nil then block.parallelSafe = false end
  registry[id] = block
  return block
end

--- Add block IDs to a folder path. Merges and deduplicates.
---@param folder_map table
---@param path string
---@param block_ids table
function mbp.register_folder(folder_map, path, block_ids)
  if not folder_map[path] then
    folder_map[path] = {}
  end
  local existing = folder_map[path]
  for _, id in ipairs(block_ids) do
    local found = false
    for _, eid in ipairs(existing) do
      if eid == id then found = true; break end
    end
    if not found then existing[#existing + 1] = id end
  end
end

---------------------------------------------------------------------------
-- DOC generation
---------------------------------------------------------------------------

local function build_args_array(arguments, argument_descriptions, argument_order)
  local args = {}
  local keys

  if argument_order and #argument_order > 0 then
    keys = argument_order
  else
    keys = {}
    for k in pairs(arguments or {}) do keys[#keys + 1] = k end
  end

  for _, name in ipairs(keys) do
    if arguments and arguments[name] then
      local arg = { name = name, type = arguments[name] }
      if argument_descriptions and argument_descriptions[name] then
        arg.description = argument_descriptions[name]
      end
      args[#args + 1] = arg
    end
  end

  return args
end

--- Generate a single MBPB-DOC line from a block definition.
---@param block table
---@param prefix string|nil optional folder prefix for ID
---@return string
function mbp.block_to_doc(block, prefix)
  local id = (prefix or "") .. block.id
  local args = build_args_array(block.arguments, block.argument_descriptions, block.argument_order)
  local args_json = json_encode(args)

  local doc = '{MBPB-DOC "' .. id .. '"'
  doc = doc .. ', "description": "' .. escape_json_string(block.description or "") .. '"'
  doc = doc .. ', "hasReturn": ' .. (block.hasReturn and "true" or "false")
  if block.hasReturn and block.returnDescription then
    doc = doc .. ', "returnDescription": "' .. escape_json_string(block.returnDescription) .. '"'
  end
  doc = doc .. ', "args": ' .. args_json
  doc = doc .. "/MBPB-DOC}"
  return doc
end

--- Generate MBPB-DOC lines for all visible blocks. Sorted by ID.
---@param registry table
---@return string
function mbp.blocks_to_prompt(registry)
  local lines = {}
  local ids = {}
  for id in pairs(registry) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local block = registry[id]
    if block.visible ~= false then
      lines[#lines + 1] = mbp.block_to_doc(block)
    end
  end
  return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Folders
---------------------------------------------------------------------------

--- Strip the longest matching folder prefix from a block ID.
---@param block_id string
---@param folder_map table
---@return string
function mbp.strip_folder_prefix(block_id, folder_map)
  if not folder_map then return block_id end
  local best = ""
  for path in pairs(folder_map) do
    if #path > #best and block_id:sub(1, #path) == path then
      best = path
    end
  end
  if best ~= "" then return block_id:sub(#best + 1) end
  return block_id
end

local function lookup_block(id, registry, folder_map)
  local def = registry[id]
  if not def and folder_map then
    def = registry[mbp.strip_folder_prefix(id, folder_map)]
  end
  return def
end

--- Generate DOC lines for blocks in a folder with folder-prefixed IDs.
---@param folder_map table
---@param registry table
---@param folder_path string
---@return string
function mbp.list_folder(folder_map, registry, folder_path)
  local block_ids = folder_map[folder_path]
  if not block_ids then return "" end

  local lines = {}
  for _, id in ipairs(block_ids) do
    local block = registry[id]
    if block and block.visible ~= false then
      lines[#lines + 1] = mbp.block_to_doc(block, folder_path)
    end
  end

  for path in pairs(folder_map) do
    if path ~= folder_path and path:sub(1, #folder_path) == folder_path then
      local remaining = path:sub(#folder_path + 1):gsub("/$", "")
      if not remaining:find("/") then
        lines[#lines + 1] = "Subfolder: " .. path
      end
    end
  end

  return table.concat(lines, "\n")
end

--- Create a list-folder block definition bound to a folder map and registry.
---@param folder_map table
---@param registry table
---@return table block definition
function mbp.create_list_folder_block(folder_map, registry)
  return {
    name = "list-folder",
    description = "Returns available MBP blocks in a folder",
    arguments = { folder_path = "string" },
    argument_descriptions = { folder_path = "Folder to query" },
    argument_order = { "folder_path" },
    isFunction = true,
    hasReturn = true,
    returnDescription = "MBPB-DOC lines for blocks in the folder, plus subfolder names",
    parallelSafe = true,
    visible = true,
    func = function(args)
      return mbp.list_folder(folder_map, registry, args.folder_path)
    end,
  }
end

---------------------------------------------------------------------------
-- Parser
---------------------------------------------------------------------------

local function read_quoted_string(str, pos)
  pos = skip_whitespace(str, pos)
  if str:sub(pos, pos) ~= '"' then return nil, pos end
  pos = pos + 1
  local start = pos
  local escape = false
  while pos <= #str do
    local ch = str:sub(pos, pos)
    if escape then
      escape = false
    elseif ch == "\\" then
      escape = true
    elseif ch == '"' then
      return str:sub(start, pos - 1), pos + 1
    end
    pos = pos + 1
  end
  return nil, pos
end

local function extract_json_object(str, pos)
  if str:sub(pos, pos) ~= "{" then return nil, pos end
  local start = pos
  local depth = 0
  local in_string = false
  local escape = false
  while pos <= #str do
    local ch = str:sub(pos, pos)
    if escape then
      escape = false
    elseif in_string then
      if ch == "\\" then
        escape = true
      elseif ch == '"' then
        in_string = false
      end
    else
      if ch == '"' then
        in_string = true
      elseif ch == "{" then
        depth = depth + 1
      elseif ch == "}" then
        depth = depth - 1
        if depth == 0 then
          return str:sub(start, pos), pos + 1
        end
      end
    end
    pos = pos + 1
  end
  return nil, pos
end

local function try_extract_id(str, start)
  local pos = start + 6
  local id = read_quoted_string(str, pos)
  return id
end

local function parse_block(str, start)
  local pos = start + 6 -- skip "{MBPB "

  local id, new_pos = read_quoted_string(str, pos)
  if not id then return nil, start end
  pos = new_pos

  pos = skip_whitespace(str, pos)
  if str:sub(pos, pos) ~= "," then return nil, start end
  pos = skip_whitespace(str, pos + 1)

  if str:sub(pos, pos + 5) ~= '"args"' then return nil, start end
  pos = skip_whitespace(str, pos + 6)
  if str:sub(pos, pos) ~= ":" then return nil, start end
  pos = skip_whitespace(str, pos + 1)

  local args_str, args_end = extract_json_object(str, pos)
  if not args_str then return nil, start end
  pos = args_end

  pos = skip_whitespace(str, pos)
  if str:sub(pos, pos + 5) ~= "/MBPB}" then return nil, start end
  pos = pos + 6

  local ok, args = pcall(json_decode, args_str)
  if not ok then return nil, start end

  return { id = id, args = args }, pos
end

--- Parse an LLM response into blocks, retries, and leftover text.
---@param response string
---@return table blocks, table retries, string leftover
function mbp.parse(response)
  local blocks = {}
  local retries = {}
  local leftover = ""
  local pos = 1
  local block_index = 0

  while pos <= #response do
    local s = response:find("{MBPB ", pos, true)
    if not s then
      leftover = leftover .. response:sub(pos)
      break
    end

    leftover = leftover .. response:sub(pos, s - 1)
    block_index = block_index + 1

    local block, end_pos = parse_block(response, s)
    if not block then
      local end_tag = response:find("/MBPB}", s, true)
      if end_tag then
        local partial_id = try_extract_id(response, s)
        retries[#retries + 1] = {
          id = partial_id or "unknown",
          index = block_index,
          error = "Failed to parse block",
        }
        pos = end_tag + 6
      else
        leftover = leftover .. "{MBPB "
        pos = s + 6
        block_index = block_index - 1
      end
    else
      block.index = block_index
      blocks[#blocks + 1] = block
      pos = end_pos
    end
  end

  leftover = leftover:match("^%s*(.-)%s*$") or ""
  return blocks, retries, leftover
end

---------------------------------------------------------------------------
-- Stream parser
---------------------------------------------------------------------------

--- Create a stream parser for incremental (token-by-token) parsing.
---@return table parser object with :feed(text) and :get_leftover()
function mbp.create_stream_parser()
  local parser = {
    buffer = "",
    scan_pos = 1,
    block_index = 0,
    blocks = {},
    retries = {},
  }

  function parser:feed(text)
    self.buffer = self.buffer .. text
    local new_blocks = {}
    local new_retries = {}

    while true do
      local s = self.buffer:find("{MBPB ", self.scan_pos, true)
      if not s then break end

      self.block_index = self.block_index + 1
      local block, end_pos = parse_block(self.buffer, s)

      if not block then
        local end_tag = self.buffer:find("/MBPB}", s, true)
        if end_tag then
          local partial_id = try_extract_id(self.buffer, s)
          local retry = {
            id = partial_id or "unknown",
            index = self.block_index,
            error = "Failed to parse block",
          }
          new_retries[#new_retries + 1] = retry
          self.retries[#self.retries + 1] = retry
          self.scan_pos = end_tag + 6
        else
          self.block_index = self.block_index - 1
          break
        end
      else
        block.index = self.block_index
        new_blocks[#new_blocks + 1] = block
        self.blocks[#self.blocks + 1] = block
        self.scan_pos = end_pos
      end
    end

    return new_blocks, new_retries
  end

  function parser:get_leftover()
    local _, _, lo = mbp.parse(self.buffer)
    return lo
  end

  return parser
end

---------------------------------------------------------------------------
-- Reply generation
---------------------------------------------------------------------------

--- Build an MBPB-RET tag.
---@param block_id string
---@param index number
---@param content string|nil
---@param is_error boolean
---@return string
function mbp.generate_return(block_id, index, content, is_error)
  local tag
  if is_error then
    tag = '{MBPB-RET "' .. block_id .. '", "index": ' .. tostring(index) .. ', "error": true}'
  else
    tag = '{MBPB-RET "' .. block_id .. '", "index": ' .. tostring(index) .. "}"
  end
  return tag .. "\n" .. (content or "") .. "\n{/MBPB-RET}"
end

--- Build an MBPB-TRY tag.
---@param block_id string|nil
---@param index number
---@param error_message string
---@return string
function mbp.generate_retry(block_id, index, error_message)
  local id = block_id or "unknown"
  return '{MBPB-TRY "' .. id .. '", "index": ' .. tostring(index) .. "}\n"
    .. error_message .. "\n{/MBPB-TRY}"
end

--- Execute parsed blocks against registry. Catches errors.
---@param blocks table parsed blocks from mbp.parse
---@param registry table
---@param folder_map table|nil
---@return table results
function mbp.execute_blocks(blocks, registry, folder_map)
  local results = {}
  for _, block in ipairs(blocks) do
    local def = lookup_block(block.id, registry, folder_map)

    if not def then
      results[#results + 1] = {
        block = block,
        is_error = true,
        content = "Unknown block: " .. block.id,
      }
    elseif def.isFunction and def.func then
      local ok, ret = pcall(def.func, block.args)
      if ok then
        results[#results + 1] = { block = block, is_error = false, content = ret }
      else
        results[#results + 1] = { block = block, is_error = true, content = tostring(ret) }
      end
    else
      results[#results + 1] = { block = block, is_error = false, content = nil, custom = true }
    end
  end
  return results
end

--- Combine execution results and parse retries into a reply string.
--- Returns nil if nothing to send.
---@param results table from execute_blocks
---@param retries table from mbp.parse
---@param registry table
---@param folder_map table|nil
---@return string|nil
function mbp.generate_reply(results, retries, registry, folder_map)
  local parts = {}

  for _, result in ipairs(results) do
    local block = result.block
    local def = lookup_block(block.id, registry, folder_map)

    if result.is_error then
      parts[#parts + 1] = mbp.generate_return(block.id, block.index, result.content, true)
    elseif not result.custom and def and def.hasReturn then
      parts[#parts + 1] = mbp.generate_return(block.id, block.index, result.content or "", false)
    end
  end

  for _, retry in ipairs(retries) do
    parts[#parts + 1] = mbp.generate_retry(retry.id, retry.index, retry.error)
  end

  if #parts == 0 then return nil end
  return table.concat(parts, "\n\n")
end

---------------------------------------------------------------------------
-- System prompt generation
---------------------------------------------------------------------------

--- Generate complete system prompt with MBP instructions and block docs.
---@param registry table
---@param user_prompt string
---@param system_prompt string|nil
---@return string
function mbp.generate_prompt(registry, user_prompt, system_prompt)
  local blocks_section = mbp.blocks_to_prompt(registry)
  return (system_prompt or "")
    .. "\n\n"
    .. "You are an AI that performs actions using MBP (Model Block Protocol). "
    .. "MBP lets you call blocks to perform actions.\n\n"
    .. 'Call format: {MBPB "id", "args": {...}/MBPB}\n\n'
    .. "Rules:\n"
    .. "- Execute ALL necessary blocks in a single response\n"
    .. "- Do NOT wait for confirmation between blocks\n"
    .. "- Multiple blocks allowed, inline or grouped\n"
    .. "- If hasReturn: true, expect output back\n"
    .. "- Use list-folder to query blocks in specific folders if needed\n\n"
    .. "Formatting:\n"
    .. "- All string values MUST be properly quoted and JSON-escaped\n"
    .. '- Use \\" for quotes inside strings, \\n for newlines, \\\\ for backslashes\n'
    .. "- Use multi-line format for blocks with long or complex arguments\n"
    .. "- If a string value contains MBP-like syntax, ensure it is properly escaped within the JSON string\n"
    .. '- Array arguments use standard JSON array syntax: ["a", "b", "c"]\n\n'
    .. "Examples:\n"
    .. '- Simple: {MBPB "replace", "args": {"search": "foo", "replace": "bar", "text": "foo world"}/MBPB}\n'
    .. '- List folder: {MBPB "list-folder", "args": {"folder_path": "utils/"}/MBPB}\n'
    .. "- Multi-line:\n"
    .. '{MBPB "tag-files", "args": {\n'
    .. '  "tags": ["utility", "core"],\n'
    .. '  "paths": ["src/utils.lua", "src/init.lua"],\n'
    .. '  "recursive": true\n'
    .. "}/MBPB}\n"
    .. "- File write:\n"
    .. '{MBPB "write-file", "args": {\n'
    .. '  "path": "test.lua",\n'
    .. '  "content": "local M = {}\\nreturn M"\n'
    .. "}/MBPB}\n"
    .. "- No blocks needed: Regular text output.\n\n"
    .. "Available blocks:\n"
    .. blocks_section
    .. "\n\n"
    .. "Returns:\n"
    .. '- Blocks with hasReturn: true will send results back in {MBPB-RET "id", "index": N} ... {/MBPB-RET} tags after all blocks execute\n'
    .. '- If any block fails, you will receive {MBPB-RET "id", "index": N, "error": true} ... {/MBPB-RET} regardless of hasReturn\n'
    .. '- If a block could not be parsed, you will receive {MBPB-TRY "id", "index": N} with an error message - fix the formatting and retry\n'
    .. "- Returns arrive after all blocks are processed - chain all blocks in a single response without waiting\n\n"
    .. "User prompt: "
    .. user_prompt
end

---------------------------------------------------------------------------
-- Sample block: replace
---------------------------------------------------------------------------

local function plain_replace_all(text, search, replacement)
  if search == "" then return text end
  local result = {}
  local pos = 1
  while pos <= #text do
    local s, e = text:find(search, pos, true) -- plain=true, no patterns
    if not s then
      result[#result + 1] = text:sub(pos)
      break
    end
    result[#result + 1] = text:sub(pos, s - 1)
    result[#result + 1] = replacement
    pos = e + 1
  end
  return table.concat(result)
end

--- Returns the sample 'replace' block definition.
---@return table block definition
function mbp.sample_replace()
  return {
    name = "replace",
    description = "Replaces all occurrences of a search string with a replacement string.",
    arguments = { search = "string", replace = "string", text = "string" },
    argument_descriptions = {
      search = "The string to search for.",
      replace = "The string to replace with.",
      text = "The input text.",
    },
    argument_order = { "search", "replace", "text" },
    isFunction = true,
    hasReturn = true,
    returnDescription = "The text with all replacements applied.",
    parallelSafe = true,
    visible = true,
    func = function(args)
      if not args.search then error("Missing required argument: search") end
      if not args.replace then error("Missing required argument: replace") end
      if not args.text then error("Missing required argument: text") end
      return plain_replace_all(args.text, args.search, args.replace)
    end,
  }
end

return mbp
