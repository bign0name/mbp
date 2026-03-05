-- Sample block: replace
-- Plain text string replacement (no patterns/regex).
-- Copy this file as a template for creating new blocks.

local M = {}

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

--- Returns the block definition for registration.
---@return table block definition
function M.block()
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

return M
