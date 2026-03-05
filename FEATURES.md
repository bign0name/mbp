# MBP Feature List

## Language Implementations

- mbp-lua-vim/: v2026.p.0.0.0
- mbp-rust/: todo

## Master Feature List

- Block registration with auto-ID suffix for duplicates
- MBPB-DOC generation (single-line block documentation for system prompt)
- Block parsing from LLM output (JSON-aware, handles nested MBP-like syntax in strings)
- Stream parsing (incremental token-by-token)
- Block execution with error catching
- Reply generation (MBPB-RET for returns/errors, MBPB-TRY for parse retries)
- Folder system (register folders, list-folder block, folder-prefixed IDs, prefix stripping)
- Folder descriptions (LLM sees what each folder contains before querying)
- Expanded folders (dump folder contents into system prompt, skip list-folder)
- System prompt generation (MBP instructions, examples, block docs, folder listings, return format)
- Sample block: replace (plain text matching, no regex)

## Version History

---

v2026.p.0.0.0
- Block registration with auto-ID suffix for duplicates
- MBPB-DOC generation with argument_order support and sorted registry keys
- JSON-aware single-pass parser (handles nested MBP syntax in string values)
- Stream parser for incremental parsing
- Block execution with error catching and folder-prefixed ID lookup
- Reply generation (MBPB-RET, MBPB-TRY)
- Folder system with list-folder block
- Folder descriptions for non-expanded folders
- Expanded folders (dump blocks into system prompt with prefixed IDs)
- System prompt generation with folder listings
- Sample replace block with plain text matching
