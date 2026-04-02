# StructuredDataExtraction Module — Usage Guide

This PowerShell module uses an AI model to extract structured JSON data from unstructured text. It requires PowerShell 7.4 or later and an OpenAI-compatible API endpoint.

## Importing the Module

```powershell
Import-Module .\out\StructuredDataExtraction
```

---

## Step 1 — Configure the AI Endpoint

Call `Set-AIEndpoint` once per session before any extraction. The configuration is process-wide and persists until you call it again or the session ends.

```powershell
# OpenAI
$key = Read-Host -Prompt 'API key' -AsSecureString
Set-AIEndpoint -Model 'gpt-4o-mini' -ApiKey $key

# Azure OpenAI or any other OpenAI-compatible endpoint
Set-AIEndpoint -BaseUrl 'https://<resource>.openai.azure.com/openai/deployments/<deployment>' `
               -Model 'gpt-4o' `
               -ApiKey $key
```

**Parameters**

| Parameter  | Required | Default                         | Description                                                    |
|------------|----------|---------------------------------|----------------------------------------------------------------|
| `-Model`   | Yes      | —                               | Model name passed to the API (e.g. `gpt-4o`, `gpt-4o-mini`)  |
| `-ApiKey`  | Yes      | —                               | API key as a `SecureString`                                    |
| `-BaseUrl` | No       | `https://api.openai.com/v1`     | Override for Azure OpenAI or local compatible endpoints        |
| `-PassThru`| No       | —                               | Emit the endpoint object to the pipeline                       |

Calling `Set-AIEndpoint` again with different values replaces the current configuration immediately; the internal chat client is rebuilt on the next `Get-StructuredData` call.

To verify the active configuration:

```powershell
Get-AIEndpoint
```

---

## Step 2 — Extract Structured Data

`Get-StructuredData` is the main cmdlet. It sends `InputText` to the configured AI model and returns a JSON string. There are four ways to use it depending on how much control you need over the output shape.

### Output

The cmdlet always outputs a **raw JSON string**. Pipe to `ConvertFrom-Json` to get a PowerShell object:

```powershell
$result = "..." | Get-StructuredData -Prompt "..." | ConvertFrom-Json
```

Use `-Verbose` to see the system prompt that was sent to the model.

---

### Mode 1 — Prompt only (free-form JSON)

Use `-Prompt` alone when you want JSON output but don't need to enforce a specific schema. The prompt must fully describe the desired output shape because no schema is passed to the model.

```powershell
$text = "John Smith, age 34, works at Contoso as a software engineer. Email: j.smith@contoso.com"

$json = Get-StructuredData -InputText $text `
    -Prompt "Extract the person's name, age, company, job title, and email as a JSON object."

$json | ConvertFrom-Json
```

---

### Mode 2 — Inline JSON schema

Use `-Schema` to pass a JSON Schema string. The model is constrained to produce output that conforms to the schema. `-Prompt` is optional additional instruction appended to the default extraction system prompt.

```powershell
$schema = @'
{
  "type": "object",
  "required": ["name", "email"],
  "properties": {
    "name":  { "type": "string" },
    "email": { "type": "string" },
    "age":   { "type": ["integer", "null"] }
  },
  "additionalProperties": false
}
'@

$text = "Jane Doe, 29, jane@example.com"

$json = Get-StructuredData -InputText $text -Schema $schema
$json | ConvertFrom-Json
```

Add `-Prompt` to give domain-specific extraction hints without replacing the built-in extraction instruction:

```powershell
Get-StructuredData -InputText $text -Schema $schema `
    -Prompt "The email may appear after 'contact:' or 'email:' prefixes."
```

---

### Mode 3 — Schema file

Use `-SchemaFile` when your schema lives on disk. The file is read each call, so for batch processing use Mode 4 instead.

```powershell
Get-StructuredData -InputText $text -SchemaFile '.\schema\cli-command-schema.json'
```

---

### Mode 4 — Reusable config (recommended for batch processing)

Use `Set-StructuredDataConfig` to build a `StructuredDataConfig` object once, then pass it via `-DataConfig` for every subsequent call. This avoids re-reading the schema file on every input and lets you customise the system prompt, schema name, and schema description once up front.

```powershell
# Build the config once
$config = Set-StructuredDataConfig `
    -SchemaFile '.\schema\cli-command-schema.json' `
    -SchemaName  'cli-command' `
    -Prompt 'Pay special attention to options listed under "Global Arguments".'

# Use it for many inputs
$helpTexts | ForEach-Object {
    Get-StructuredData -InputText $_ -DataConfig $config | ConvertFrom-Json
}
```

`Set-StructuredDataConfig` also accepts an inline schema string via `-Schema` instead of `-SchemaFile`:

```powershell
$config = Set-StructuredDataConfig -Schema $schema -Prompt "Use null for any field not mentioned."
```

**`Set-StructuredDataConfig` parameters**

| Parameter            | Required    | Description                                                                       |
|----------------------|-------------|-----------------------------------------------------------------------------------|
| `-Schema`            | Yes (or -SchemaFile) | JSON Schema as an inline string                                       |
| `-SchemaFile`        | Yes (or -Schema)     | Path to a JSON Schema file                                            |
| `-Prompt`            | No          | Extra instructions appended to the default extraction system prompt               |
| `-SchemaName`        | No          | Logical name for the schema sent to the API (default: `structured-data-extraction`) |
| `-SchemaDescription` | No          | Description of the schema sent to the API                                         |

---

## Pipeline Input

`Get-StructuredData` accepts `-InputText` from the pipeline. Each piped value is processed as a separate extraction call:

```powershell
# Extract from multiple files
Get-ChildItem .\logs\*.txt | Get-Content -Raw | ForEach-Object {
    Get-StructuredData -InputText $_ -DataConfig $config
} | ConvertFrom-Json
```

---

## Error Handling

- If `Set-AIEndpoint` has not been called, `Get-StructuredData` terminates with error ID `EndpointNotConfigured`.
- If the model returns invalid JSON, the call is retried up to 3 times. After all retries fail, a non-terminating error with ID `JsonExtractionFailed` is written. Use `-ErrorAction Stop` to turn it into a terminating error.
- If a schema file path does not exist, `Set-StructuredDataConfig` terminates immediately with error ID `SchemaFileNotFound`.

```powershell
# Stop on extraction failure
Get-StructuredData -InputText $text -DataConfig $config -ErrorAction Stop
```

---

## Quick Reference

```
Set-AIEndpoint   -Model <string> -ApiKey <securestring> [-BaseUrl <string>] [-PassThru]
Get-AIEndpoint

Set-StructuredDataConfig  -Schema <string>     [-Prompt <string>] [-SchemaName <string>] [-SchemaDescription <string>]
Set-StructuredDataConfig  -SchemaFile <string> [-Prompt <string>] [-SchemaName <string>] [-SchemaDescription <string>]

Get-StructuredData  -InputText <string>  -Prompt <string>                           # free-form JSON
Get-StructuredData  -InputText <string>  -Schema <string>     [-Prompt <string>]    # inline schema
Get-StructuredData  -InputText <string>  -SchemaFile <string> [-Prompt <string>]    # schema file
Get-StructuredData  -InputText <string>  -DataConfig <StructuredDataConfig>         # reusable config
```
