# CLI Command Schema for Structured Data Extraction

This JSON schema (`cli-command-schema.json`) is designed to help Large Language Models (LLMs) extract structured information from CLI help content in a consistent format that enables tab-completion and command understanding.

## Schema Overview

The schema defines a standardized structure for representing CLI commands with the following key components:

### Core Properties

- **Name**: The command name (without parent command prefix)
- **Description**: What the command does
- **Options**: Array of all available command-line options
- **Subcommands**: (Optional) Available subcommands

### Option Properties

Each option in the `Options` array contains:

- **Name**: Primary long-form name (e.g., `--output`)
- **Alias**: Alternative long-form names (e.g., `["--subscription"]`)
- **Short**: Short-form variants (e.g., `["-o ", "-h "]`)
- **Description**: Complete description including constraints and defaults
- **Arguments**: Enumerated allowed values (if applicable)

## Extraction Guidelines for LLMs

When using this schema to extract information from CLI help content:

### 1. Command Identification
- Look for the main command name in headers like "Command", "Usage:", or after CLI prefixes
- Example: From "az configure : Manage Azure CLI configuration" → extract "configure"

### 2. Option Parsing
- Parse both "Arguments", "Global Arguments" sections
- Handle multiple formats:
  ```
  --name --subscription -n -s  : Description
  --output -o        : Description. Allowed values: json, yaml.
  --debug            : Description
  ```

### 3. Alias and Short Form Handling
- Separate long-form aliases from short forms
- Include spaces after short options if shown (e.g., "-n " vs "-n")
- Example: `--name --subscription -n -s` becomes:
  - Name: `--name`
  - Alias: `["--subscription"]`
  - Short: `["-n ", "-s "]`

### 4. Argument Value Extraction
- Look for phrases like "Allowed values:", "Valid values:", "Possible values:"
- Extract comma-separated or space-separated value lists
- Set to `null` for boolean flags or options accepting arbitrary input

## Example Usage

Given the help text for `az configure`, the schema produces:

```json
{
  "Name": "configure",
  "Description": "Manage Azure CLI configuration. This command is interactive.",
  "Options": [
    {
      "Name": "--name",
      "Alias": ["--subscription"],
      "Short": ["-n ", "-s "],
      "Description": "Name or ID of subscription.",
      "Arguments": null,
      "Type": "string",
      "Category": "Arguments"
    },
    {
      "Name": "--scope",
      "Alias": null,
      "Short": null,
      "Description": "Scope of defaults. Using \"local\" for settings only effective under current folder. Allowed values: global, local. Default: global.",
      "Arguments": ["global", "local"],
      "Type": "string",
      "Category": "Arguments"
    }
    // ... more options
  ]
}
```

## Benefits for Tab-Completion

This structured format enables:

1. **Option Discovery**: Quick lookup of all available options
2. **Alias Support**: Multiple ways to reference the same option
3. **Value Completion**: Enumerated values for specific options
4. **Context Awareness**: Categorization helps prioritize relevant options
5. **Type Safety**: Data type information for validation

## Validation

The schema includes validation rules for:
- Required properties
- Proper option naming patterns (-- for long, - for short)
- Consistent data types
- Logical structure

Use a JSON Schema validator to ensure extracted data conforms to this specification.