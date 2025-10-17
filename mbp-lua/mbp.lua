local mbp = {}

function mbp.generate_prompt(blocks, user_prompt, regular_system_prompt)
  local mbp_prompt = (regular_system_prompt or "") .. "\n\n" ..
    "You are an AI that performs actions by structuring outputs with MBP. MBP lets you call blocks for actions. Call with {MBPB \"id\", \"args\": [ {\"arg_name\": value}, ... ] }. Multiple calls ok, inline or at end. If hasReturn: true, expect output back. Use list-folder to query blocks in specific folders if needed.\n\n" ..
    "Examples:\n" ..
    "- Call replace: {MBPB \"replace\", \"args\": [ {\"search\": \"foo\"}, {\"replace\": \"bar\"}, {\"text\": \"foo world\"} ] }\n" ..
    "- Call list-folder: {MBPB \"list-folder\", \"args\": [ {\"folder_path\": \"utils/text\"} ] }\n" ..
    "- No calls: Regular text output.\n\n" ..
    "Available blocks:\n"
  for _, block in pairs(blocks) do
    local args_str = {}
    for arg_name, arg_type in pairs(block.arguments or {}) do
      table.insert(args_str, string.format("{\"name\": \"%s\", \"type\": \"%s\", \"description\": \"%s\"}", arg_name, arg_type, block.argument_descriptions[arg_name] or ""))
    end
    mbp_prompt = mbp_prompt .. string.format("{MBPB-DOC \"%s\", \"description\": \"%s\", \"hasReturn\": %s, \"args\": [ %s ] }\n",
      block.name, block.description or "", block.hasReturn and "true" or "false", table.concat(args_str, ", "))
  end
  mbp_prompt = mbp_prompt .. "\nUser prompt: " .. user_prompt
  return mbp_prompt
end

function mbp.parse_mbp_blocks(output)
  local blocks = {}
  local leftover = output
  local start_pos = 1
  while true do
    local s, e = string.find(leftover, "{MBPB", start_pos)
    if not s then break end
    local block_end = string.find(leftover, "}", e)
    if not block_end then break end  -- Malformed
    local block_str = string.sub(leftover, s, block_end)
    -- Basic parsing (expand as needed)
    local id = block_str:match("{MBPB \"(.-)\"")
    local args_str = block_str:match("\"args\": %[(.-)%]")
    local args = {}
    if args_str then
      for k, v in args_str:gmatch("{\"(.-)\": \"(.-)\"}") do
        args[k] = v
      end
    end
    table.insert(blocks, {id = id, args = args})
    leftover = string.sub(leftover, 1, s-1) .. string.sub(leftover, block_end+1)
    start_pos = 1
  end
  return blocks, leftover:match("^%s*(.-)%s*$")  -- Trim leftover
end

function mbp.process_blocks(blocks_def, parsed_blocks)
  local returns = {}
  for _, block in ipairs(parsed_blocks) do
    local def = blocks_def[block.id]
    if def and def.isFunction then
      local result = def.func(block.args)
      if def.hasReturn then
        table.insert(returns, result)
      end
    else
      -- Custom logic here
    end
  end
  return table.concat(returns, "\n")
end

function mbp.generate_retry_prompt(error_message, previous_llm_output, original_prompt)
  return "Error in previous response: " .. error_message .. "\n\n" ..
         "Previous response: " .. previous_llm_output .. "\n\n" ..
         "Retry correctly.\n\n" ..
         original_prompt
end

return mbp
