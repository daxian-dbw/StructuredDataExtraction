

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

function Get-HelpText {
    param(
        [string]   $Tool,
        [string[]] $SubcommandPath   # empty for the root command
    )

    $helpArgs = $SubcommandPath.Count -gt 0 ? $SubcommandPath + '--help' : , '--help'

    # Capture both stdout and stderr; many tools write help to stderr
    $output = & $Tool @helpArgs 2>&1
    return ($output | Out-String).Trim()
}

function Get-OutputPath {
    param(
        [string]   $BaseDir,
        [string]   $Tool,
        [string[]] $CommandPath   # full path e.g. @('source','add')
    )

    # Every command gets its own folder; the JSON file is named <command>-cli.json.
    # e.g. CommandPath = @('source','add')   →  <BaseDir>/<Tool>/source/add/add-cli.json
    #      CommandPath = @('source')         →  <BaseDir>/<Tool>/source/source-cli.json
    #      CommandPath = @()                 →  <BaseDir>/<Tool>/<Tool>-cli.json
    $commandName = if ($CommandPath.Count -gt 0) { $CommandPath[-1] } else { $Tool }

    $folder = Join-Path $BaseDir $Tool
    foreach ($segment in $CommandPath) {
        $folder = Join-Path $folder $segment
    }

    return [PSCustomObject]@{
        Folder = $folder
        File   = Join-Path $folder "$commandName-cli.json"
        Name   = $commandName
    }
}

function Invoke-Extract {
    param(
        [string]   $Tool,
        [string]   $BaseDir,
        [object]   $Config,
        [string[]] $CommandPath,
        [int]      $Depth,
        [switch]   $Force
    )

    # Iterative BFS using an explicit queue — avoids stack overflow on deep CLIs
    # like az or kubectl that can have hundreds of nested subcommands.
    $queue = [System.Collections.Generic.Queue[psobject]]::new()
    $queue.Enqueue([pscustomobject]@{ Path = [string[]]$CommandPath; Depth = $Depth })
    $JsonSchema = $Config.JsonResponseFormat.JsonSchema.Schema.ToString()

    while ($queue.Count -gt 0) {
        $item        = $queue.Dequeue()
        $cmdPath     = [string[]]$item.Path
        $remaining   = $item.Depth
        $paths       = Get-OutputPath -BaseDir $BaseDir -Tool $Tool -CommandPath $cmdPath
        $displayPath = if ($cmdPath.Count -gt 0) { "$Tool $($cmdPath -join ' ')" } else { $Tool }

        # --- determine whether to extract or reuse a cached file ---------------
        $data = $null

        if (-not $Force -and (Test-Path $paths.File)) {
            Write-Verbose "Skipping (already extracted): $($paths.File)"
            try {
                $data = Get-Content $paths.File -Raw | ConvertFrom-Json
            } catch {
                Write-Warning "Cached file is invalid JSON, re-extracting: $($paths.File)"
            }
        }

        if ($null -eq $data) {
            Write-Host "- Extracting: $displayPath" -ForegroundColor Green

            $helpText = Get-HelpText -Tool $Tool -SubcommandPath $cmdPath
            if ([string]::IsNullOrWhiteSpace($helpText)) {
                Write-Warning "No help output for: $displayPath — skipping."
                continue
            }

            $json = Get-StructuredData -InputText $helpText -DataConfig $Config -ErrorAction Stop

            ## Validate the generated JSON against the schema
            if ($JsonSchema) {
                try {
                    $null = Test-Json -Json $json -Schema $JsonSchema -ErrorAction Stop
                } catch {
                    $tempFile = New-TemporaryFile
                    Set-Content -Path $tempFile -Value $json -Encoding UTF8
                    Write-Host "JSON validation failed for: $displayPath. Generated JSON is saved at $tempFile." -ForegroundColor Red
                    throw
                }
            }

            $data = $json | ConvertFrom-Json

            $null = New-Item -ItemType Directory -Path $paths.Folder -Force
            Set-Content -Path $paths.File -Value $json -Encoding UTF8
            Write-Verbose "Saved: $($paths.File)"
        }

        # --- enqueue subcommands for the next BFS level --------------------
        if ($data.Subcommands -and $data.Subcommands.Count -gt 0) {
            if ($remaining -le 0) {
                Write-Warning "Max depth reached at '$displayPath' — skipping $($data.Subcommands.Count) subcommand(s)."
                continue
            }

            foreach ($sub in $data.Subcommands) {
                $queue.Enqueue([pscustomobject]@{
                    Path  = [string[]]($cmdPath + $sub.Name)
                    Depth = $remaining - 1
                })
            }
        }
    }
}

<#
.SYNOPSIS
    Recursively extracts CLI command metadata to structured JSON files.

.DESCRIPTION
    For each command and discovered subcommand, invokes the tool with --help,
    normalizes the output to the CLI command JSON schema using the
    StructuredDataExtraction module, and saves one JSON file per command in a
    hierarchical folder layout:

        <OutputDir>/
        └── <ToolName>/
            ├── <ToolName>-cli.json          # root: <tool> --help
            └── <subcommand>/
                ├── <subcommand>-cli.json    # <tool> <subcommand> --help
                └── <sub-subcommand>/
                    └── <sub-subcommand>-cli.json

    The StructuredDataExtraction module must already be imported and
    Set-AIEndpoint must have been called before running this script.

.PARAMETER ToolName
    The name or full path of the CLI tool to extract (e.g., 'winget', 'az', 'git').

.PARAMETER OutputDir
    Root directory where the metadata folder for this tool will be created.

.PARAMETER DataConfig
    A StructuredDataConfig object from Set-StructuredDataConfig. If omitted, the
    built-in CLI command schema (schema\cli-command-schema.json) is used.

.PARAMETER MaxDepth
    Maximum subcommand recursion depth. Default: 10.

.PARAMETER Force
    Overwrite existing JSON files. By default, already-extracted files are skipped
    but their Subcommands list is still used to continue recursion.

.EXAMPLE
    $key = Read-Host -AsSecureString -Prompt 'API key'
    Set-AIEndpoint -Model 'gpt-4o-mini' -ApiKey $key

    Invoke-CLIMetadataExtraction -ToolName winget -OutputDir .\metadata

.EXAMPLE
    # Resume an interrupted extraction (skip already-done files, continue the rest)
    Invoke-CLIMetadataExtraction -ToolName winget -OutputDir .\metadata

.EXAMPLE
    # Use a custom DataConfig
    $config = Set-StructuredDataConfig -SchemaFile .\schema\cli-command-schema.json `
                                       -Prompt 'Focus on extracting all option aliases.'
    Invoke-CLIMetadataExtraction -ToolName az -OutputDir .\metadata -DataConfig $config
#>
function Invoke-CLIMetadataExtraction {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter(Mandatory)]
        [string]$OutputDir,

        [Parameter()]
        [object]$DataConfig,

        [Parameter()]
        [ValidateRange(1, 50)]
        [int]$MaxDepth = 10,

        [Parameter()]
        [switch]$Force
    )

    # Build a default DataConfig from the bundled CLI schema if none was supplied
    if (-not $DataConfig) {
        $schemaFile = Join-Path $PSScriptRoot 'assets\cli-command-schema.json'
        $promptFile = Join-Path $PSScriptRoot 'assets\cli-command-prompt.md'

        if (-not (Test-Path $schemaFile)) {
            throw "CLI schema not found at '$schemaFile'. Provide -DataConfig explicitly."
        } elseif (-not (Test-Path $promptFile)) {
            throw "CLI prompt not found at '$promptFile'. Provide -DataConfig explicitly."
        }

        $prompt = Get-Content -Path $promptFile -Raw
        $DataConfig = Set-StructuredDataConfig `
            -SchemaFile $schemaFile `
            -SchemaName 'cli-command-schema' `
            -SchemaDescription 'JSON schema for CLI command metadata extraction' `
            -Prompt $prompt
    }

    # Resolve OutputDir to an absolute path so relative paths survive recursion
    $OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)

    # ---------------------------------------------------------------------------
    # Run
    # ---------------------------------------------------------------------------

    Invoke-Extract `
        -Tool $ToolName `
        -BaseDir $OutputDir `
        -Config $DataConfig `
        -CommandPath @() `
        -Depth $MaxDepth `
        -Force:$Force

    Write-Host "`nExtraction complete. Output: $(Join-Path $OutputDir $ToolName)" -ForegroundColor Green
}

function New-CLICompleter {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $MetadataDir
    )

    if (-not (Test-Path $MetadataDir -PathType Container)) {
        throw "Metadata directory '$MetadataDir' does not exist or is not a directory."
    }

    # Resolve MetadataDir to an absolute path so a relative path can be used safely.
    $provider = $null
    $MetadataDir = $ExecutionContext.SessionState.Path.GetResolvedProviderPathFromPSPath($MetadataDir, [ref]$provider)

    if ($provider.Name -ne 'FileSystem') {
        throw "Metadata directory '$MetadataDir' is not on the file system. Only file system paths are supported."
    }

    $cliName = Split-Path -Leaf $MetadataDir
    $targetFile = Join-Path $HOME '.pwsh' 'completions' "__$cliName.ps1"

    $content = @'
# Import the CLI metadata completion module for {0} in the local scope.
Import-Module '{2}' -ArgumentList '{1}', $true -Scope Local

# Register the argument completer for the {0} CLI using the loaded completer block.
Register-ArgumentCompleter -Native -CommandName $CliName -ScriptBlock $CliCompleterBlock
'@
    $cliMetadataModule = Join-Path $PSScriptRoot 'assets\CLIMetadataCompletion.psm1'
    Set-Content -Path $targetFile -Encoding UTF8 -Value ($content -f $cliName, $MetadataDir, $cliMetadataModule)

    Write-Host "CLI completer script generated: $targetFile" -ForegroundColor Green
}
