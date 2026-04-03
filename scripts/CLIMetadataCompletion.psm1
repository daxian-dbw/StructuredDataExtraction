<#
.SYNOPSIS
    Registers PowerShell tab completion for a CLI tool using pre-generated CLI metadata JSON files.

.DESCRIPTION
    Loads the JSON metadata files produced by Invoke-CLIMetadataExtraction.ps1 and registers
    an ArgumentCompleter for the target CLI tool that completes:
      - Subcommands at each level of the command hierarchy
      - Option names (long form, short form, and aliases) for each subcommand
      - Enumerated argument values for options that have a fixed set of allowed values

    The CLI tool name is inferred from the leaf folder name of $MetadataDir.
    Import this module to register the completer. The metadata cache and metadata directory
    are stored as module-scope variables and persist for the lifetime of the module.

.EXAMPLE
    # Register completion for winget:
    Import-Module .\scripts\Register-CLICompletion.psm1 -ArgumentList Q:\yard\del\winget

.EXAMPLE
    # Register completion for az:
    Import-Module .\scripts\Register-CLICompletion.psm1 -ArgumentList Q:\yard\del\az
#>

# ---------------------------------------------------------------------------
# Module parameters -- passed via -ArgumentList when importing.
# ---------------------------------------------------------------------------
param(
    [Parameter(Mandatory)]
    [string] $MetadataDir,

    [Parameter(Mandatory)]
    [switch] $SkipCompleterRegistration
)

# ---------------------------------------------------------------------------
# Module-scope state -- persists for the lifetime of the loaded module.
# No need for GetNewClosure(); the completer script block runs in module scope
# and can access these variables directly via $script:.
# ---------------------------------------------------------------------------

$script:MetadataDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($MetadataDir)

# The CLI tool name is the leaf folder name of the metadata directory (e.g. 'winget', 'az').
$script:CliName = Split-Path $script:MetadataDir -Leaf

# Keyed by "<baseDir>|<cmdPath joined by />"; populated lazily on first access.
$script:MetaCache = @{}

# ---------------------------------------------------------------------------
# Helper functions (script scope -- visible to the completer block)
# ---------------------------------------------------------------------------

# Loads the *-cli.json metadata file for the given command folder path and returns the parsed object.
# The expected file is named "<folder-leaf>-cli.json" inside $folderPath.
# Results are stored in $script:MetaCache (keyed by $folderPath) so each file is read
# and parsed only once per session, regardless of how many times Tab is pressed.
# Returns $null if the file does not exist or cannot be parsed.
function LoadMeta([string]$folderPath) {
    if ($script:MetaCache.ContainsKey($folderPath)) {
        return $script:MetaCache[$folderPath]
    }

    $name = Split-Path $folderPath -Leaf
    $file = Join-Path $folderPath "$name-cli.json"
    $result = $null
    if (Test-Path $file) {
        try {
            $result = Get-Content $file -Raw | ConvertFrom-Json
        } catch {}
    }
    $script:MetaCache[$folderPath] = $result
    return $result
}

# Returns $true if the *-cli.json file exists for the given command folder path, without reading it.
# Used in the resolution loop to find the deepest valid subcommand path cheaply.
# The expected file is named "<folder-leaf>-cli.json" inside $folderPath.
function TestMeta([string]$folderPath) {
    $name = Split-Path $folderPath -Leaf
    return (Test-Path (Join-Path $folderPath "$name-cli.json"))
}

# Emits CompletionResult objects for every option name (long form, alias, and short form)
# in the metadata whose name starts with $prefix.
# All three name forms are surfaced so the user can Tab-complete -q as well as --query.
function CompleteOptions($metadata, [string]$prefix) {
    foreach ($opt in $metadata.Options) {
        $names = @($opt.Name) + @($opt.Alias) + @($opt.Short) | Where-Object { $_ }
        foreach ($name in $names) {
            if ($name -like "$prefix*") {
                [System.Management.Automation.CompletionResult]::new(
                    $name, $name,
                    [System.Management.Automation.CompletionResultType]::ParameterName,
                    $opt.Description
                )
            }
        }
    }
}

# If $prevToken matches a known option that declares enumerated Arguments in the schema,
# emits CompletionResult objects for each allowed value that starts with $prefix.
# Returns after the first match -- only one option can be the "previous token" at a time.
# Options with null Arguments (free-form input) produce no completions and fall through.
function CompleteArgValues($metadata, [string]$prevToken, [string]$prefix) {
    foreach ($opt in $metadata.Options) {
        if ($null -eq $opt.Arguments) { continue }
        $names = @($opt.Name) + @($opt.Alias) + @($opt.Short) | Where-Object { $_ }
        if ($prevToken -in $names) {
            foreach ($val in $opt.Arguments) {
                if ($val -like "$prefix*") {
                    [System.Management.Automation.CompletionResult]::new(
                        $val, $val,
                        [System.Management.Automation.CompletionResultType]::ParameterValue,
                        $val
                    )
                }
            }
            return
        }
    }
}

# ---------------------------------------------------------------------------
# Register the completer
# ---------------------------------------------------------------------------

if (-not (Test-Path $script:MetadataDir)) {
    Write-Warning "'$script:CliName' metadata not found at '$script:MetadataDir'. Tab completion will not be registered."
    return
}

[scriptblock]$script:CliCompleterBlock = {
    param($wordToComplete, $commandAst, $cursorPosition)

    # All tokens after the root CLI command.
    $tokens = @($commandAst.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.ToString() })

    # Split into "complete" tokens (fully typed) and the word being completed (may be empty).
    # When $wordToComplete is non-empty it matches the last AST element -- keep it out of
    # completeTokens so we don't mistake it for a resolved subcommand or previous flag.
    [string[]]$completeTokens = if ([string]::IsNullOrEmpty($wordToComplete)) {
        $tokens
    } else {
        @($tokens | Select-Object -SkipLast 1)
    }

    $previousToken = if ($completeTokens.Count -gt 0) { $completeTokens[-1] } else { $null }

    # Collect subcommand segments (bare words, not flags) from the completed tokens.
    $subPath = [System.Collections.Generic.List[string]]::new()
    foreach ($tok in $completeTokens) {
        if (-not $tok.StartsWith('-')) { $subPath.Add($tok) }
    }

    # Resolve the deepest metadata folder that actually exists by walking subcommand segments.
    # TestMeta only checks file existence — no file I/O or JSON parsing — so the loop is cheap.
    $currentFolder = $script:MetadataDir
    foreach ($seg in $subPath) {
        $nextFolder = Join-Path $currentFolder $seg
        if (TestMeta $nextFolder) {
            $currentFolder = $nextFolder
        } else {
            break
        }
    }

    $meta = LoadMeta $currentFolder
    if ($null -eq $meta) { return }

    # 1. Current word looks like a flag -> complete option names.
    if ($wordToComplete.StartsWith('-')) {
        CompleteOptions $meta $wordToComplete
        return
    }

    # 2. Previous token is a flag -> complete its enumerated argument values (if any).
    if ($previousToken -and $previousToken.StartsWith('-')) {
        CompleteArgValues $meta $previousToken $wordToComplete
        return
    }

    # 3. Complete subcommand names.
    if ($meta.Subcommands) {
        foreach ($sub in $meta.Subcommands) {
            if ($sub.Name -like "$wordToComplete*") {
                [System.Management.Automation.CompletionResult]::new(
                    $sub.Name, $sub.Name,
                    [System.Management.Automation.CompletionResultType]::ParameterValue,
                    $sub.Description
                )
            }
        }
    }
}

if ($SkipCompleterRegistration) {
    # This is to enable the 'PSNativeToolCompletion' module to deliver completions the first time the user presses Tab for an unregistered CLI command.
    #
    # To register the completer and call the completer on user hitting the tab key for the first time, the 'PSNativeToolCompletion'
    # module needs to retrieve the completer script block and explicitly call it after the registration.
    #
    # It looks for the completer script block by searching for 'Register-ArgumentCompleter' in the '__<cliName>.ps1' script,
    # so in this scenario, the '__<cliName>.ps1' needs to call 'Register-ArgumentCompleter' itself, and we need to make sure
    # the completer script block and related functions and variables are exported so it can do so.
    Write-Verbose "$script:CliName tab completion script block created but NOT registered (metadata: $script:MetadataDir)"
    Export-ModuleMember `
        -Function @('LoadMeta', 'TestMeta', 'CompleteOptions', 'CompleteArgValues') `
        -Variable @('MetadataDir', 'CliName', 'CliCompleterBlock')
} else {
    # Register the argument completer for the CLI command, and the user will be ready to go.
    Register-ArgumentCompleter -Native -CommandName $script:CliName -ScriptBlock $script:CliCompleterBlock
    Write-Verbose "$script:CliName tab completion registered (metadata: $script:MetadataDir)"

    # Keep helper functions and state variables private.
    Export-ModuleMember -Function @() -Variable @()
}
