# MBP Feature List

Tracks the implementation status of MBP features across supported languages.

| Feature            | Description                                              | Lua | Rust |
|--------------------|----------------------------------------------------------|-----|------|
| Block Parsing      | Parse MBP blocks from LLM output                         | ✅  | 🚧   |
| Error Retrying     | Helper for generating retry prompts on parse/process errors | ✅  | ❌   |
| Folder Block       | `list-folder` block to return block metadata in a folder | ❌  | ❌   |
| MBPB Package Mgr   | Clone and manage MBP blocks                              | ❌  | ❌   |
| Parallel Execution | Support async execution of multiple blocks               | ❌  | ❌   |

