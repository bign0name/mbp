# Model Block Protocol (MBP)

## Overview
MBP is a comprehensive, language-agnostic protocol for enabling LLMs to perform actions through structured, parseable blocks. It supports both simple single-block flows and complex multi-block workflows while remaining easy to set up. MBP provides modules to parse LLM outputs into block objects and regular output, handle folder-based block organization, and generate system prompts — allowing apps to handle blocks flexibly without server-side dependencies or heavy frameworks. Designed to minimize token costs by enabling multiple blocks per response rather than back-and-forth per action.

Apps should refer to MBP blocks as "actions" in user-facing interfaces for cleaner terminology.

## Why MBP

MBP is a set of upgrades over MCP (Model Context Protocol). The LLM chains multiple actions in a single response instead of waiting for each tool call to return before continuing, meaning fewer round trips, lower latency, and less token overhead. Everything runs locally by default. No server, no transport layer, no handshake, just a system prompt, a parser, and your functions. Registration, parsing, execution, and reply generation all happen in-process. Actions are just functions. This makes MBP a good fit for editors, CLI tools, local agents, and any app, small or large, that wants to give LLMs tool use without infrastructure. Actions organize into folders with visibility controls, so apps can dynamically expose or hide available actions. If you need server-based tools, make your action's function call a server, MBP doesn't care what happens inside the function. In the future, remote actions defined as JSON with a server endpoint will let users drop in a schema and server address, and execution happens remotely. Basically MCP, but within MBP, so remote and local actions coexist and chain in a single response. Skills are also easy to set up. Add markdown guides to a folder, list them in the system prompt, and make a block that returns the guide content when the LLM needs it.

## Objectives
- Enable LLMs to perform actions via structured blocks with unique IDs for reliable parsing and execution.
- Provide libraries to parse LLM output into a list of blocks and leftover output.
- Allow developers to define available blocks and process them in a user-controlled loop.
- Minimize token costs by enabling multiple blocks per response (no back-and-forth per action).

## Block Format

### Start and End Tags
All MBP blocks use explicit start and end tags for reliable parsing:
- **Block call:** `{MBPB ... /MBPB}`
- **Block documentation:** `{MBPB-DOC ... /MBPB-DOC}`
- **Block return:** `{MBPB-RET "id", "index": N} ... {/MBPB-RET}`
- **Block retry:** `{MBPB-TRY "id", "index": N} ... {/MBPB-TRY}`

### LLM Call Format
Used by LLM to invoke a block. Can be single-line or multi-line.

**Single-line (simple blocks):**
```
{MBPB "replace", "args": {"search": "foo", "replace": "bar", "text": "foo world"}/MBPB}
```

**Multi-line (complex blocks with code, arrays, or long content):**
```
{MBPB "write-file", "args": {
  "path": "src/main.lua",
  "content": "local M = {}\n\nfunction M.setup()\n  print('hello')\nend\n\nreturn M"
}/MBPB}
```

```
{MBPB "tag-files", "args": {
  "tags": ["utility", "core", "stable"],
  "paths": ["src/utils.lua", "src/core.lua", "src/init.lua"],
  "recursive": true
}/MBPB}
```

### Arguments Format
Arguments are a single JSON object with key-value pairs. All standard JSON types are supported:
```
"args": {"key1": "value1", "key2": 42, "flag": true, "tags": ["a", "b"], "nested": {"sub": 1}}
```

Types follow JSON conventions: strings are quoted, numbers are unquoted, booleans are `true`/`false`, arrays use `[]`, objects use `{}`, null is `null`.

## Blocks

### Block Definition
A single block definition serves both documentation generation and call parsing. One definition, two consumers — no need for separate objects.

- **name**: Block name (lowercase, use `-` for spaces, do not use `_`)
- **id**: Unique ID (auto-assigned from name, visible to LLM). If multiple blocks share a name, suffix is appended (e.g., `calculate`, `calculate-1`, `calculate-2`). LLM uses ID to call blocks.
- **description**: Natural language description for LLM (optional but recommended)
- **arguments**: Key-value pairs defining argument names and types
- **argument_descriptions**: Human-readable descriptions for each argument
- **isFunction**: Boolean (not visible to LLM) - true if block executes a predefined function, false for custom logic in parse loop
- **hasReturn**: Boolean (visible to LLM) - true if block returns a value to the LLM
- **returnDescription**: String (visible to LLM, optional) - describes what the return value contains. Only relevant when `hasReturn: true`.
- **parallelSafe**: Boolean (not visible to LLM, default: false) - true if block can execute concurrently with other parallel-safe blocks
- **visible**: Boolean (not visible to LLM, default: true) - false to exclude block from DOC generation and folder listings. Apps can toggle this to control which blocks are available to the LLM.
- **function**: Function reference (optional, requires isFunction=true) - reference to executable function, implementation is language-dependent

During MBPB-DOC generation, the module reads LLM-visible fields from this definition. During parsing, it matches the block ID and validates argument names/types — description fields are simply ignored. See [MBPB-DOC Generation](#mbpb-doc-generation) for the transformation details.

### Block Flags

**isFunction** (internal, not shown to LLM):
- `true`: Block executes a predefined function automatically when parsed
- `false`: Block requires custom handling in the application's parse loop

**hasReturn** (shown to LLM):
- `true`: Block returns output that will be sent back to LLM (e.g., file contents, search results)
- `false`: Block is fire-and-forget (e.g., write file, delete, create)

**parallelSafe** (internal, not shown to LLM):
- `true`: Block can execute concurrently with other parallel-safe blocks (e.g., read-only operations)
- `false`: Block must execute sequentially in order (e.g., file writes, deletes). This is the default.

### Built-in: Folder Block
- **name**: `list-folder`
- **id**: `list-folder`
- **description**: Returns a list of available MBP blocks in the specified folder
- **arguments**: `folder_path` (string)
- **isFunction**: true
- **hasReturn**: true
- **parallelSafe**: true (read-only operation)
- **Function**: Looks up the app's folder map, generates MBPB-DOC lines for blocks in the requested folder. Only returns blocks with `visible: true`. If the folder contains subfolders, includes them with descriptions in the response so the LLM can explore deeper.
- **Registration**: Only needed when non-expanded folders exist. Use `has_non_expanded_folders` to check.

## Folders

Folders are an app-level organizational concept. Blocks themselves don't know what folder they're in — the app maintains a separate folder map that groups block IDs under folder paths.

### Folder Map
The app maintains a mapping of folder paths to folder entries. Each entry contains block IDs, a description, and an expanded flag:
```
{
  "utils/": {
    "block_ids": ["replace", "grep", "split"],
    "description": "Text manipulation utilities",
    "expanded": true
  },
  "utils/text/": {
    "block_ids": ["capitalize", "truncate"],
    "description": "Text casing and truncation",
    "expanded": false
  },
  "io/": {
    "block_ids": ["write-file", "read-file"],
    "description": "File system operations",
    "expanded": false
  }
}
```

Blocks are registered once in the app's block registry (flat list). The folder map just references them by ID. The same block can appear in multiple folders.

### Folder Descriptions
Each folder has a `description` field that tells the LLM what the folder contains. This is required for non-expanded folders — without it the LLM guesses folder contents from the path name alone, which is unreliable.

Non-expanded folders appear in the system prompt as a listing with descriptions:
```
Available folders (use list-folder to see contents):
- utils/text/ Text casing and truncation
- io/ File system operations
```

When `list-folder` returns subfolders, descriptions are included:
```
Subfolder: utils/text/ - Text casing and truncation
```

### Expanded Folders
Folders with `expanded: true` have their blocks dumped directly into the system prompt with folder-prefixed IDs. The LLM sees them as available blocks without calling `list-folder`. Use this for folders the LLM should always have access to.

Folders with `expanded: false` (the default) appear in the folder listing and require `list-folder` for discovery.

### Folder-Prefixed IDs
When `list-folder` returns blocks, their IDs are prefixed with the folder path. This is how the LLM knows to call `utils/replace` instead of just `replace`.

**LLM calls `list-folder` on `utils/`:**
```
{MBPB "list-folder", "args": {"folder_path": "utils/"}/MBPB}
```

**App returns:**
```
{MBPB-DOC "utils/replace", "description": "Replaces text", "hasReturn": true, "args": [{"name": "search", "type": "string", "description": "Find"}, {"name": "replace", "type": "string", "description": "Replace with"}, {"name": "text", "type": "string", "description": "Input"}]/MBPB-DOC}
{MBPB-DOC "utils/grep", "description": "Searches for pattern", "hasReturn": true, "args": [{"name": "pattern", "type": "string", "description": "Pattern"}, {"name": "text", "type": "string", "description": "Input"}]/MBPB-DOC}
Subfolder: utils/text/ - Text casing and truncation
```

**LLM can then call blocks with the full path:**
```
{MBPB "utils/replace", "args": {"search": "foo", "replace": "bar", "text": "foo world"}/MBPB}
```

When parsing, the app strips the folder prefix to look up the block definition in its registry, then executes it normally.

### Subfolders
Subfolders are just deeper keys in the folder map. When a folder listing includes subfolders, the LLM can call `list-folder` again to explore them. Each level is one call — the LLM decides how deep to go.

### Block Visibility
Blocks with `visible: false` are excluded from folder listings and DOC generation. Apps can toggle this flag to dynamically control which blocks are available to the LLM (e.g., via a UI toggle that enables/disables tool categories).

## Block Documentation Format (MBPB-DOC)
Used in system prompts to inform LLM about available blocks. Single-line format to minimize context window usage. Auto-generated by the app from block definitions.

### Format
```
{MBPB-DOC "id", "description": "...", "hasReturn": bool, "args": [{"name": "...", "type": "...", "description": "..."}]/MBPB-DOC}
```

For blocks with `hasReturn: true`, include `returnDescription`:
```
{MBPB-DOC "id", "description": "...", "hasReturn": true, "returnDescription": "...", "args": [...]}/MBPB-DOC}
```

### Args Array
Each argument object contains:
- `name`: Argument name
- `type`: Data type (`string`, `number`, `boolean`, `object`, `array`, `null`)
- `description`: What the argument does
- `sub_args`: (optional) For nested objects or typed arrays, array of child argument definitions

### Example
```
{MBPB-DOC "write-file", "description": "Writes content to a file at the specified path", "hasReturn": false, "args": [{"name": "path", "type": "string", "description": "File path to write to"}, {"name": "content", "type": "string", "description": "Content to write"}]/MBPB-DOC}
```

## MBPB-DOC Generation

MBPB-DOC lines are auto-generated by the library module from block definitions. The transformation maps LLM-visible fields into the compact DOC format and discards internal fields.

### Field Mapping

| Block Definition Field | MBPB-DOC Field | Notes |
|----------------------|----------------|-------|
| `id` | First quoted string | Direct copy |
| `description` | `"description"` | Direct copy |
| `hasReturn` | `"hasReturn"` | Direct copy |
| `returnDescription` | `"returnDescription"` | Only included when `hasReturn: true` |
| `arguments` + `argument_descriptions` | `"args"` array | Merged (see below) |
| `name` | — | Excluded (id is used instead) |
| `isFunction` | — | Excluded (internal) |
| `parallelSafe` | — | Excluded (internal) |
| `visible` | — | Excluded (blocks with visible: false are skipped entirely) |
| `function` | — | Excluded (internal) |

### Args Array Generation
The `args` array is built by merging `arguments` and `argument_descriptions`:

For each key in `arguments`:
1. `name` ← the key name
2. `type` ← the value from `arguments` (e.g., `"string"`, `"number"`, `"array"`)
3. `description` ← the value from `argument_descriptions` for the same key

If the type is `object` and the block defines nested structure, include `sub_args` with the same format recursively.

### Example Transformation

**Block definition:**
```json
{
  "name": "write-file",
  "id": "write-file",
  "description": "Writes content to a file at the specified path.",
  "arguments": {
    "path": "string",
    "content": "string"
  },
  "argument_descriptions": {
    "path": "The file path to write to.",
    "content": "The content to write to the file."
  },
  "isFunction": true,
  "hasReturn": false,
  "parallelSafe": false,
  "visible": true,
  "function": "<function reference>"
}
```

**Generated MBPB-DOC:**
```
{MBPB-DOC "write-file", "description": "Writes content to a file at the specified path.", "hasReturn": false, "args": [{"name": "path", "type": "string", "description": "The file path to write to."}, {"name": "content", "type": "string", "description": "The content to write to the file."}]/MBPB-DOC}
```

Pseudocode for the generation module is in [mbp/mbp-doc-gen.md](mbp/mbp-doc-gen.md).

## System Prompt Structure

1. Regular system prompt
2. MBP overview and explanation (include guidance to execute all blocks in single response)
3. MBP formatting rules (JSON escaping, multi-line for complex content)
4. MBP usage examples
5. Available blocks as MBPB-DOC entries (includes expanded folder blocks with prefixed IDs)
6. Available folders listing with descriptions (only if non-expanded folders exist)
7. Return format (only if any blocks have `hasReturn: true`)
8. User prompt

See [mbp/system-prompt.md](mbp/system-prompt.md) for the full template.

## Parsing

### Overview
MBP parsing extracts block calls from LLM output and separates them from regular text. The parser must be **JSON-aware** to correctly handle blocks whose string arguments contain MBP-like syntax (e.g., a coding agent writing a file that itself contains MBP block examples).

A naive regex approach will break on nested content. The recommended implementation uses a state-tracking single-pass parser. See [mbp/mbp-parser.md](mbp/mbp-parser.md) for full pseudocode.

### Parsing Algorithm

1. **Find start tag**: Scan for `{MBPB ` (with space after MBPB)
2. **Extract block ID**: Read the first quoted string after the start tag
3. **Find args object**: Locate `"args":` followed by `{`
4. **JSON-aware object extraction**: Parse the args object by tracking:
   - **Brace depth**: Increment on `{`, decrement on `}` — but only when not inside a string
   - **String boundaries**: Track whether the current position is inside a JSON string (between unescaped `"` characters). While inside a string, all braces, tags, and delimiters are ignored.
   - **Escape sequences**: A `\"` inside a string does not end the string
   - When brace depth returns to 0, the args object is complete
5. **Find end tag**: Expect `/MBPB}` after the args object closes
6. **Collect leftover**: All text outside block boundaries is regular output

### Why JSON-Aware Parsing Matters
Consider a coding agent writing a file that contains MBP examples:
```
{MBPB "write-file", "args": {
  "path": "README.md",
  "content": "Example: {MBPB \"replace\", \"args\": {\"search\": \"x\"}/MBPB}"
}/MBPB}
```

The inner `{MBPB ... /MBPB}` is inside a JSON string value (the quotes are escaped as `\"`). A JSON-aware parser knows it's string content, not structure, and correctly finds the real closing `/MBPB}` at the end. This means MBP reliably supports any workflow, including LLMs working on MBP itself.

### Execution Order
Blocks are executed in the order they appear in the response. This is predictable and requires no additional flags.

### Handling Returns
For blocks with `hasReturn: true`:
1. Execute block
2. Collect return value
3. After all blocks processed, return values are sent back to the LLM in the next message

## Returns

### Return Format (MBPB-RET)
App-generated tags that wrap return values sent back to the LLM. The block ID and index identify which call the return corresponds to.

**Successful return:**
```
{MBPB-RET "block-id", "index": 1}
return content here
{/MBPB-RET}
```

**Error return:**
```
{MBPB-RET "block-id", "index": 2, "error": true}
File not found: src/missing.lua
{/MBPB-RET}
```

### Error Behavior
Errors always return regardless of `hasReturn`:
- `hasReturn: true` + success → MBPB-RET with content (or empty)
- `hasReturn: true` + error → MBPB-RET with error flag
- `hasReturn: false` + success → nothing
- `hasReturn: false` + error → MBPB-RET with error flag

### Multiple Returns
When the LLM calls multiple `hasReturn: true` blocks in one response, the app sends all returns together in the next message:
```
{MBPB-RET "grep", "index": 1}
src/main.lua:12: local function setup()
src/main.lua:45: local function teardown()
{/MBPB-RET}
{MBPB-RET "read-file", "index": 2}
local M = {}
function M.setup() end
return M
{/MBPB-RET}
```

### Return Description
Blocks with `hasReturn: true` should include a `returnDescription` field in their definition so the LLM knows what to expect. This is included in the MBPB-DOC as `"returnDescription"`.

### Retry Format (MBPB-TRY)
App-generated tags sent when a block fails to parse. Includes block ID (if extractable), index, and error message.

```
{MBPB-TRY "write-file", "index": 3}
Malformed JSON in args object
{/MBPB-TRY}
```

Auto-retry (MBPB-TRY) is for parse failures only. Code execution errors use MBPB-RET with error flag — MBP does not auto-retry execution errors, the LLM or user decides how to handle those.

### System Prompt
The system prompt always includes the returns and retry explanation. This covers all blocks universally since any block can error or fail to parse.

### Building Replies
Apps should use `generate_reply` from the reply module to build the complete reply string from execution results and parse retries. For `isFunction: false` blocks where the app handles execution in its own loop, use `generate_return` directly to build that block's return, then combine with the rest. Blocks with `hasReturn: true` always receive an MBPB-RET back — if the block returns nothing on success, an empty MBPB-RET is sent so the LLM is never left waiting.

Pseudocode for reply generation is in [mbp/mbp-reply.md](mbp/mbp-reply.md). Full execution example including error handling is in [mbp/sample-block.md](mbp/sample-block.md).

## Parallel Execution

By default, blocks execute sequentially in order of appearance. Implementations may optionally support parallel execution.

### App-Controlled Parallel Execution
Parallel execution is managed by the application, not the LLM. Recommended approach:

1. Mark blocks with `parallelSafe` flag in their block definition
2. `parallelSafe: true` - Block can execute concurrently (e.g., read-only operations like grep, search)
3. `parallelSafe: false` - Block must execute in order (e.g., file writes, deletes). This is the default.
4. App batches consecutive parallel-safe blocks and executes them concurrently
5. When a non-parallel-safe block is encountered, app waits for current batch to finish, then executes it sequentially

This keeps complexity out of the LLM's responsibilities and prevents race conditions from concurrent file modifications.

## Examples

### Example 1: Simple Text Replacement
**Documentation (in system prompt):**
```
{MBPB-DOC "replace", "description": "Replaces text in a string", "hasReturn": true, "returnDescription": "The text with all replacements applied", "args": [{"name": "search", "type": "string", "description": "String to find"}, {"name": "replace", "type": "string", "description": "Replacement string"}, {"name": "text", "type": "string", "description": "Input text"}]/MBPB-DOC}
```

**LLM Call:**
```
{MBPB "replace", "args": {"search": "apple", "replace": "banana", "text": "I like apple pie"}/MBPB}
```

**Return (sent back to LLM):**
```
{MBPB-RET "replace", "index": 1}
I like banana pie
{/MBPB-RET}
```

### Example 2: File Write with Array Argument (Multi-line)
**Documentation (in system prompt):**
```
{MBPB-DOC "write-files", "description": "Writes content to multiple files", "hasReturn": false, "args": [{"name": "files", "type": "array", "description": "Array of file objects with path and content"}, {"name": "overwrite", "type": "boolean", "description": "Whether to overwrite existing files"}]/MBPB-DOC}
```

**LLM Call:**
```
{MBPB "write-files", "args": {
  "files": [
    {"path": "src/utils.lua", "content": "local M = {}\n\nfunction M.helper()\n  return 42\nend\n\nreturn M"},
    {"path": "src/init.lua", "content": "local utils = require('src.utils')\nreturn utils"}
  ],
  "overwrite": true
}/MBPB}
```

### Example 3: Multiple Blocks in One Response
```
I'll create the module and its test file.

{MBPB "write-file", "args": {
  "path": "src/calculator.lua",
  "content": "local M = {}\n\nfunction M.add(a, b)\n  return a + b\nend\n\nreturn M"
}/MBPB}

{MBPB "write-file", "args": {
  "path": "tests/calculator_test.lua",
  "content": "local calc = require('src.calculator')\n\nassert(calc.add(2, 3) == 5)\nprint('Tests passed!')"
}/MBPB}

Both files have been created. The calculator module exports an add function, and the test file verifies it works correctly.
```

### Example 4: Nested Object Arguments
**Documentation:**
```
{MBPB-DOC "complex-op", "description": "Performs a complex operation", "hasReturn": false, "args": [{"name": "input", "type": "object", "description": "Nested input params", "sub_args": [{"name": "value", "type": "number", "description": "Numeric value"}, {"name": "label", "type": "string", "description": "Label"}]}, {"name": "mode", "type": "boolean", "description": "Operation mode"}]/MBPB-DOC}
```

**LLM Call:**
```
{MBPB "complex-op", "args": {"input": {"value": 42, "label": "test"}, "mode": true}/MBPB}
```

### Example 5: List Folder
**Documentation:**
```
{MBPB-DOC "list-folder", "description": "Returns available MBP blocks in a folder", "hasReturn": true, "returnDescription": "MBPB-DOC lines for blocks in the folder, plus subfolder names", "args": [{"name": "folder_path", "type": "string", "description": "Folder to query"}]/MBPB-DOC}
```

**LLM Call:**
```
{MBPB "list-folder", "args": {"folder_path": "utils/"}/MBPB}
```

**Return (sent back to LLM):**
```
{MBPB-RET "list-folder", "index": 1}
{MBPB-DOC "utils/replace", "description": "Replaces text", "hasReturn": true, "returnDescription": "Text with replacements applied", "args": [{"name": "search", "type": "string", "description": "Find"}, {"name": "replace", "type": "string", "description": "Replace with"}, {"name": "text", "type": "string", "description": "Input"}]/MBPB-DOC}
{MBPB-DOC "utils/grep", "description": "Searches for pattern", "hasReturn": true, "returnDescription": "Matching lines", "args": [{"name": "pattern", "type": "string", "description": "Pattern"}, {"name": "text", "type": "string", "description": "Input"}]/MBPB-DOC}
Subfolder: utils/text/ - Text casing and truncation
{/MBPB-RET}
```

**LLM then calls a block from the folder:**
```
{MBPB "utils/replace", "args": {"search": "hello", "replace": "world", "text": "hello there"}/MBPB}
```

## Implementation Notes
- Modules developed for each language with version-specific feature support
- A single block definition object is used for both DOC generation and call parsing
- The module provides: block registration with auto ID suffix, DOC generation (`block_to_doc` with optional folder prefix), system prompt assembly (with expanded folder blocks and non-expanded folder listings), folder map management with descriptions and expanded flag, JSON-aware block parsing (batch + stream), and reply generation (returns, errors, retries)
- `list-folder` function implemented in modules to look up folder map and generate DOC lines with subfolder descriptions
- Each language implementation's README specifies supported MBP version
- MBP does not provide a JSON implementation — language implementations must use their platform's JSON library

## mbpbs - MBP Blocks Package Manager (move to new repo)
- Package manager for MBP blocks
- `mbpbs` or `mbpblocks`
- Clones repo of MBP block into desired folder (e.g., `.mbpbs/blocks`), lazy.nvim style git clone for block distribution
- Checks for upgrades with breaking change warnings, prompts for confirmation
- Change block versions
- `mbpbs update` to update all blocks, auto-update on run like Homebrew
- Language-specific, needs identifier name for each block per language
- Or all blocks in a monorepo with pseudocode + language implementations
- Option for blocks to be pseudocode in JSON with different language implementations
- If a function doesn't exist in the desired language, download without function for user editing
- `.mbpbs` file in project root for managing blocks in project
- Community contributions to mbpbs list, manually audited
- Handle block dependencies
- Folder structure support (e.g., `.mbpbs/blocks/utils/text`) with `list-folder` block to query block metadata

## Future Considerations
- Change examples to use generic random code language files rather that lua
- Cleanable flag: optional `cleanable` field on block definitions (default: false). When true, signals that the block can be safely stripped from conversation history after execution. Lib provides `conversation.clean()` to strip all cleanable blocks from history in one call, and `conversation.clean(block)` to strip a single specific block regardless of its cleanable flag. The flag enables safe bulk cleaning without the app manually tracking which blocks are disposable.
- CI with lightweight test suite per language implementation — verify the sample-block.md checklist (registration, DOC gen, parsing, execution, returns, retries, plain text matching) as automated tests, not exhaustive coverage
- Auto-retry loop: configurable max retry attempts for parse failures (MBPB-TRY), with backoff or abort after N failures
- MBP execution logs
- Block execution hooks (before/after)
- Convenience method to load all registered blocks into system prompt without manual listing
- Standard block library shipped with each language module (file ops, HTTP, grep, shell, etc.) so apps get common blocks without writing code
- Remote blocks: blocks defined as JSON with a server endpoint, app calls the endpoint and returns the result to the LLM. Allows drag-and-drop block plugins without app code — user provides a JSON file with block schema + server address, app registers it. Execution happens on the remote server (basically MCP, but within the MBP framework — supports chaining with local blocks in a single response).
- OS-level block registry: system-wide blocks that any MBP-aware app can discover and use, installed block packs available to all MBP apps on the system
