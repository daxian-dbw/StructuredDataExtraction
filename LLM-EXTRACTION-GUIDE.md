# LLM Prompt Template for CLI Help Extraction

Use this template when instructing an LLM to extract structured information from CLI help content.

## Prompt Template

```
You are tasked with extracting structured information from CLI help content to enable tab-completion. 
When given the CLI help content, analyze it and extract the information according to the provided JSON schema.
Pay special attention to:

1. **Command Name**: Extract the primary command name (without parent CLI prefix)
2. **Options Parsing**: 
   - Separate long-form options (--name) from short-form (-n)
   - Group aliases correctly (--name and --subscription are aliases)
   - Extract allowed values from "Allowed values:", "Valid values:", etc. Use `null` for open-ended inputs

Please respond with valid JSON that conforms to the provided schema. Ensure all required fields are present and data types are correct.
```
