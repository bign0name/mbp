# MBP Block Schema

## User Code Block Schema
Full schema for defining blocks in user code. Includes all fields for internal use.

```json
{
  "name": "replace",  // String: Block name (lowercase, use '-' for spaces)
  "id": "replace-1",  // String: Unique ID (auto-assigned, appends suffix for duplicates)
  "description": "Replaces occurrences of a search string with a replacement string in the given text.",  // String: Natural language description for LLM (optional)
  "arguments": [  // Array of objects: Key-value pairs for arguments, can be nested
    {
      "search": "string"  // Key: Arg name, Value: Data type hint for LLM
    },
    {
      "replace": "string"
    },
    {
      "text": "string"  // Optional: Nested example if needed
    }
  ],
  "argument_descriptions": {  // Object: Descriptions for each argument
    "search": "The string to search for.",
    "replace": "The string to replace with.",
    "text": "The input text to perform replacement on."
  },
  "isFunction": true,  // Boolean: True if executes a predefined function, false for custom logic
  "hasReturn": true,  // Boolean: True if returns value to LLM, false for void
  "function": "path/to/function"  // String: Path or reference to executable function (optional)
}
```

## LLM-Facing Block Schema
Minimal format for presenting a single block to the LLM in the system prompt. Uses custom braced syntax for consistency with call format. Shown multi-line here for readability, but delivered single-line in prompts to save context window space and match call format.

```
{MBPB-DOC
  "replace",
  "description": "Replaces occurrences of a search string with a replacement string.",
  "hasReturn": true,
  "args": [
    {
      "name": "search",
      "type": "string",
      "description": "The string to search for."
    },
    {
      "name": "replace",
      "type": "string",
      "description": "The string to use as replacement."
    },
    {
      "name": "text",
      "type": "string",
      "description": "The input text."
    }
  ]
}
```

## LLM Call Format
Custom braced format used by LLM to invoke a block. Parsed from LLM output. Always single-line for consistency and minimal context usage.

```
{MBPB "replace", "args": [ {"search": "Hello"}, {"replace": "Hi"}, {"text": "Hello world"} ] }
```

## Examples

### Example 1: Simple Replacement
LLM-Facing (in prompt, single-line):
```
{MBPB-DOC "replace", "description": "Replaces text.", "hasReturn": true, "args": [ {"name": "search", "type": "string", "description": "String to find."}, {"name": "replace", "type": "string", "description": "Replacement."}, {"name": "text", "type": "string", "description": "Input text."} ] }
```

LLM Call:
```
{MBPB "replace", "args": [ {"search": "apple"}, {"replace": "banana"}, {"text": "I like apple pie"} ] }
```

### Example 2: List Folder
LLM-Facing (in prompt, single-line):
```
{MBPB-DOC "list-folder", "description": "Returns a list of available MBP blocks in the specified folder.", "hasReturn": true, "args": [ {"name": "folder_path", "type": "string", "description": "The folder to query."} ] }
```

LLM Call:
```
{MBPB "list-folder", "args": [ {"folder_path": "utils/text"} ] }
```

### Example 3: Nested Arguments
User Code Schema:
```json
{
  "name": "complex-op",
  "id": "complex-op-1",
  "description": "Performs a complex operation.",
  "arguments": [
    {
      "input": {
        "sub1": "number",
        "sub2": "string"
      }
    },
    {
      "mode": "boolean"
    }
  ],
  "argument_descriptions": {
    "input": "Nested input params",
    "sub1": "A number value.",
    "sub2": "A string value.",
    "mode": "Operation mode."
  },
  "isFunction": true,
  "hasReturn": false
}
```

LLM-Facing (in prompt, single-line):
```
{MBPB-DOC "complex-op", "description": "Performs a complex operation.", "hasReturn": false, "args": [ {"name": "input", "type": "object", "description": "Nested input params", "sub_args": [ {"name": "sub1", "type": "number", "description": "A number value."}, {"name": "sub2", "type": "string", "description": "A string value."} ] }, {"name": "mode", "type": "boolean", "description": "Operation mode."} ] }
```

LLM Call:
```
{MBPB "complex-op", "args": [ {"input": {"sub1": 42, "sub2": "test"}}, {"mode": true} ] }
```
