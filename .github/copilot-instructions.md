# Copilot instructions for StructuredDataExtraction

## Project intent and scope

This repository is for **AI-driven extraction of CLI metadata into structured JSON**.
The generated structured JSON files can later be consumed by other tools, such as a PowerShell completion consumer, to provide rich CLI experiences.

Persist the following assumptions across future sessions unless the user explicitly changes them:

- Scope this repo to **metadata extraction and JSON generation only**.
- Treat the PowerShell completion consumer as a separate downstream project or layer.
- Generate **one normalized JSON file per command or subcommand** in a hierarchical folder for each tool.
- Store **only normalized schema output**, not raw captured help text.

## High-level architecture

The codebase currently has two main parts:

1. A C# PowerShell module packaged by `StructuredDataExtraction.psd1`. It exposes cmdlets for configuring an OpenAI-compatible endpoint and requesting structured extraction.
2. A schema-driven extraction contract under `schema\` and `example\`. `schema\cli-command-schema.json` defines the JSON shape for command metadata, `schema\validate-schema.js` validates both the schema and the checked-in example, and `LLM-EXTRACTION-GUIDE.md` plus `schema\CLI-SCHEMA-GUIDE.md` describe how help text should be turned into that schema.

1. Run a tool's help command to discover top-level commands, options, and arguments.
2. Walk subcommands recursively by invoking each discovered subcommand's help.
3. Use AI to normalize each help page into the predefined schema.
4. Persist the results as one JSON file per command or subcommand in a hierarchical folder for that tool.

## Build and validation commands

- Build the module project: `dotnet build .\src\StructuredDataExtraction.csproj`
- Publish the PowerShell module layout: `dotnet publish .\src\StructuredDataExtraction.csproj -c Release`
- Smoke-test the published module exports: `pwsh -NoLogo -NoProfile -Command "Import-Module '.\out\StructuredDataExtraction\StructuredDataExtraction.psd1' -Force; Get-Command -Module StructuredDataExtraction"`
- Validate the CLI extraction schema and bundled example: `Set-Location .\schema; npm install; node .\validate-schema.js`
- There is currently no automated .NET test project, no single-test runner, and no dedicated lint command in this repository.

## Key repository-specific guidance

- Use `StructuredDataExtraction.csproj` as the .NET entrypoint; do not rely on `StructuredDataExtraction.sln`.
- Treat the schema files and examples as the main contract surface of the project right now. When schema fields change, keep `schema\cli-command-schema.json`, `schema\validate-schema.js`, `schema\CLI-SCHEMA-GUIDE.md`, `LLM-EXTRACTION-GUIDE.md`, and `example\configure.json` aligned.
- Assume the target storage model is a hierarchical tool folder with one JSON artifact per command or subcommand.
- When validating changes to extraction behavior, prefer checking against representative help-text fixtures and the schema validator, since broader automated testing is not yet present.
