#Requires -Version 7

[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$projectFile = Join-Path $PSScriptRoot 'src\StructuredDataExtraction.csproj'

dotnet publish $projectFile -c $Configuration
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Published at: $(Join-Path $PSScriptRoot 'out\StructuredDataExtraction')" -ForegroundColor Green
