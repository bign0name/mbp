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
- ID (auto assigned, tries to just use name but adds an extra identifier for duplicate IDs)
- Description (natural language description for LLM, could be optional)
- Arguments (key-value pair, can have nested arguments, should point out data type to LLM)
- Argument descriptions
- Boolean `isFunctionBlock` (if the Block comes with a function to call or if it should be intercepted for custom logic in the parse loop)
- A function to execute when called (optional, `isFunctionBlock` needs to be set to true for this)

### Block Types

#### Custom Blocks
- Don't have a function to execute included in the file
- Set `isFunctionBlock` to false for the parse loop
- Must be intercepted in the parse loop and user executed

#### Function Blocks
- In the file have function to execute
- `isFunctionBlock` will be skipped in the parse loop
- Can be mapped to function in different file
- MBPBs should be function blocks with function in the file, but can be custom

### LLM Base Block
```json
{MBPB
  "replace",
  "args": [
    {"search": "print('Hello')"},
    {"replace": "print('Hi')"}
  ]
}
```
- ID
- Arguments (and nested arguments)

## System Prompt
- explain MBP with overview
- show examples of use of MBP
- current MBP session
    - user options
    - available mbp blocks
    - user prompt

### User Options
- leftover output supported
- multi blocks
- parallel execution?

## Parsing
- might need custom parsing due to the custom json style
- loop through each mbp block
- leftover output put variable for use

## MBPB **(move to new repo)**
- `mbpb` or `mbpblocks`
- package manager for MBP blocks
- clones repo of mbp block into desired folder
- checks for upgrades
- language specifc, need identifier name for each block for language
- or all blocks are done in monorepo
- possibly a .mbpb file in project root for managing blocks in project
- people can contribute to our mbpb list, all manually audited by us
- handle block dependencies
- option of block being pseudo code in json with different language implementations
- have function to if the function doesn't exist in desired language, then download without function and user can edit it.
- we can have an autoupdate everytime `mbpblocks` runs like homebrew
- breaking changes warning for updates, will prompt for confirmation to make sure to update
- u can change versions of blocks
- `mbpblocks update` (or upgrage) to update all blocks

## Flow
- user sets up Blocks
- MBP prompt gets generated with available blocks
- prompt gets sent to LLM
- llm reply gets parsed

## Implementation Notes
- libs will be developed for each language
    - we can have a list of features with version, then each language implementation will have readme saying which version they support
- test 

## Future Considerations
- Support block execution order and multi-step tasks (e.g., executing multiple blocks at once).
- Support parallel execution of blocks async (fast inference models)
- Handle invalid blocks with potential auto-retry functionality. (return malformed blocks back to llm with comments for each invalid value for the llm to understand its mistakes and retry)
