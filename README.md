# Model Block Protocol (MBP)

## Overview
MBP is a lightweight, language-agnostic protocol for structuring Large Language Model (LLM) outputs into parseable blocks. It enables developers to define, parse, and process blocks containing arguments and values, supporting both executable functions and custom app logic. MBP provides libraries to parse LLM outputs into block objects and regular output, allowing apps to handle blocks flexibly without server-side dependencies or heavy frameworks.

## Objectives
- Enable LLMs to generate structured blocks with unique IDs for reliable parsing.
- Provide libraries to parse LLM output into a list of blocks and leftover output.
- Allow developers to define available blocks and process them in a user-controlled loop.

## Blocks

### Base Block
- Name (use `-` for spaces, all lowercase)
- ID (auto assigned, tries to use name but adds an extra identifier for duplicate IDs)
- Description (natural language description for LLM, could be optional)
- Arguments (key-value pair, can have nested arguments, should point out data type to LLM)
- Argument descriptions
- Block Flags:
  - `isFunction` (boolean, true/false, not visible to LLM): Indicates if the block executes a predefined function or requires custom logic in the parse loop.
  - `hasReturn` (boolean, true/false, visible to LLM): Indicates if the block returns a value to the LLM (e.g., grep-like functionality).
- A function to execute when called (optional, requires `isFunction` to be true)

### Folder Block
- Name: `list-folder`
- ID: Auto-assigned
- Description: Returns a list of available MBP blocks in the specified folder
- Arguments: `folder_path` (string, specifies the folder to query)
- Block Flags:
  - `isFunction`: True (executes a predefined function to list blocks)
  - `hasReturn`: True (returns block metadata to the LLM)
- Function: Scans the specified folder for MBP blocks and returns their metadata (name, ID, description, `hasReturn`, args with name/type/description)
- Output Format: Multiple single-line {MBPB-DOC} entries, e.g.:
  ```
  {MBPB-DOC "replace", "description": "Replaces text in a string", "hasReturn": true, "args": [ {"name": "search", "type": "string", "description": "String to find."}, {"name": "replace", "type": "string", "description": "Replacement."}, {"name": "text", "type": "string", "description": "Input text."} ] }
  {MBPB-DOC "grep", "description": "Searches text for matches", "hasReturn": true, "args": [ {"name": "pattern", "type": "string", "description": "Pattern to match."}, {"name": "text", "type": "string", "description": "Input text."} ] }
  ```

## Block Flags
- `isFunction`: Determines whether the block executes a predefined function (true) or requires interception for custom logic in the parse loop (false). Not exposed to the LLM to minimize context window usage.
- `hasReturn`: Specifies whether the block returns output to the LLM (true) or not (false). Visible to the LLM to inform it about expected return values.

### LLM Base Block
```
{MBPB "replace", "args": [ {"search": "print('Hello')"}, {"replace": "print('Hi')"} ] }
```
- ID
- Arguments (and nested arguments)

## System Prompt
- Regular system prompt (optional, general instructions)
- Explain MBP with overview
- Show examples of MBP use
- Available MBP blocks (as single-line {MBPB-DOC "name", "description": "...", "hasReturn": true, "args": [ {"name": "...", "type": "...", "description": "..."} ] } entries)
- User prompt

### User Options
- Leftover output supported
- Multi blocks
- Parallel execution

## Parsing
- Custom parsing required due to the custom braced style
- Loop through each MBP block
- Leftover output stored in a variable for use

## MBPB **(move to new repo)**
- `mbpb` or `mbpblocks`
- Package manager for MBP blocks
- Clones repo of MBP block into desired folder (e.g., `.mbpb/blocks`)
- Checks for upgrades
- Language-specific, needs identifier name for each block per language
- Or all blocks in a monorepo
- `.mbpb` file in project root for managing blocks in project
- Community contributions to MBPB list, manually audited
- Handle block dependencies
- Option for blocks to be pseudocode in JSON with different language implementations
- If a function doesn’t exist in the desired language, download without function for user editing
- Auto-update on `mbpblocks` run, like Homebrew
- Breaking changes warning for updates, prompts for confirmation
- Change block versions
- `mbpblocks update` (or upgrade) to update all blocks
- Folder structure support (e.g., `.mbpb/blocks/utils/text`) with `list-folder` block to query block metadata

## Flow
- User sets up Blocks
- MBP prompt gets generated with available blocks (or `list-folder` to query specific folders)
- Prompt gets sent to LLM
- LLM reply gets parsed

## Implementation Notes
- Libraries will be developed for each language
  - List of features with version, each language implementation’s README will specify supported version
- `list-folder` function implemented in libraries to scan MBPB folder structure

## Future Considerations
- Support block execution order and multi-step tasks (e.g., executing multiple blocks at once)
- Support parallel execution of blocks async (fast inference models)
- Handle invalid blocks with auto-retry functionality: app detects errors in parse loop (e.g., arg validation), uses helper to generate retry prompt explaining error, resends to LLM. No auto-loop; app handles retries.
- MBP logs
