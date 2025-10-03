# MBP Lua Implementation

## Setup
- Requires Lua 5.1+ (compatible with Neovim's LuaJIT).
- Dependencies: None (pure Lua).
- Installation: Copy `mbp.lua` into your Neovim plugin dir or require path.
- Usage: `local mbp = require("mbp")`
- Supported features: See root `FEATURES.md` (initially parsing, prompt gen, basic execution).

## Defining Blocks
In your code:
```lua
local blocks = {
  replace = {
    name = "replace",
    id = "replace",
    description = "Replaces text.",
    arguments = { search = "string", replace = "string", text = "string" },
    argument_descriptions = { search = "String to find.", replace = "Replacement.", text = "Input text." },
    isFunction = true,
    hasReturn = true,
    func = function(args)
      local text = args.text or ""
      return text:gsub(args.search, args.replace)
    end
  },
  -- Add list-folder func to scan dir and return {MBPB-DOC} strings
}
```

## Generating Prompt
```lua
local prompt = mbp.generate_prompt(blocks, user_prompt, regular_system_prompt)
-- Send to LLM
```

## Parse Loop Example
Copy/adapt this into your Neovim plugin for handling LLM responses:
```lua
local mbp = require("mbp")

-- In your AI loop:
local llm_output = get_llm_response(prompt)  -- Your LLM call
local parsed_blocks, leftover = mbp.parse_mbp_blocks(llm_output)

-- Detect errors (user app logic, e.g., validate args)
local error_message = ""  -- Set if error, e.g., "Invalid arg 'search': expected string, got number"
if error_message ~= "" then
  local retry_prompt = mbp.generate_retry_prompt(error_message, llm_output, prompt)
  -- Resend retry_prompt to LLM, handle in loop
else
  local return_str = mbp.process_blocks(blocks, parsed_blocks)
  if return_str ~= "" then
    prompt = prompt .. "\nBlock returns: " .. return_str
    -- Resend to LLM if needed
  end
  -- Use leftover as final output if no more calls
end
```

## Notes
- Parsing handles basic cases; expand for nested args/errors.
- Integrate with Neovim: e.g., use in code gen plugin via vim.api.nvim_buf_set_lines.
- For list-folder: Implement func to scan .mbpb/blocks dir.
