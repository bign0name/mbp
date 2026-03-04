# Project: MBP
MBP is a lightweight, language-agnostic protocol for enabling LLMs to perform actions through structured, parseable blocks. It supports both simple single-block flows and complex multi-block workflows while remaining easy to set up. MBP provides libraries to parse LLM outputs into block objects and regular output, allowing apps to handle blocks flexibly without server-side dependencies or heavy frameworks. Designed to minimize token costs by enabling multiple blocks per response rather than back-and-forth per action.

Apps should refer to MBP blocks as "actions" in user-facing interfaces for cleaner terminology.

## Objectives
- Enable LLMs to perform actions via structured blocks with unique IDs for reliable parsing and execution.
- Provide libraries to parse LLM output into a list of blocks and leftover output.
- Allow developers to define available blocks and process them in a user-controlled loop.
- Minimize token costs by enabling multiple blocks per response (no back-and-forth per action).
