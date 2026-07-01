[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$ConfigureOnly,
    [switch]$SkipSync,
    [switch]$NoLaunch,
    [switch]$PrintCommand,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Show-Help {
    @"
SetupAndRun.ps1

Configure the local Python environment and start the Skillz MCP server.

Usage:
  powershell -ExecutionPolicy Bypass -File SetupAndRun\SetupAndRun.ps1 [-ConfigPath <path>] [-ConfigureOnly] [-SkipSync] [-NoLaunch] [-PrintCommand]

Options:
  -ConfigPath <path>  JSON configuration file. Defaults to SetupAndRun\SetupAndRun.json.
  -ConfigureOnly      Run the environment setup phase and then stop.
  -SkipSync           Skip 'uv sync'. Useful when the virtual environment is already ready.
  -NoLaunch           Build and print the Skillz command without starting it.
  -PrintCommand       Print the resolved Skillz command before running it.
  -Help               Show this help text.
"@
}

function Format-CommandArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -match '^[A-Za-z0-9_./:\\=-]+$') {
        return $Value
    }

    return "'" + ($Value -replace "'", "''") + "'"
}

function Format-CommandLine {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $parts = @((Format-CommandArgument $Command))
    foreach ($argument in $Arguments) {
        $parts += Format-CommandArgument $argument
    }
    return ($parts -join " ")
}

function Get-ConfigProperty {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Assert-KnownProperties {
    param(
        [Parameter(Mandatory = $true)][object]$Object,
        [Parameter(Mandatory = $true)][string[]]$Allowed,
        [Parameter(Mandatory = $true)][string]$Path
    )

    foreach ($property in $Object.PSObject.Properties) {
        if ($property.Name -notin $Allowed) {
            throw "Config field '$($Path).$($property.Name)' is not supported."
        }
    }
}

function Get-ConfigObject {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$DisplayName
    )

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        $DisplayName = $Name
    }

    $value = Get-ConfigProperty $Object $Name
    if ($null -eq $value) {
        return $null
    }

    if ($value -isnot [pscustomobject]) {
        throw "Config field '$DisplayName' must be an object."
    }

    return $value
}

function Get-ConfigBoolean {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [bool]$Default,
        [string]$DisplayName
    )

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        $DisplayName = $Name
    }

    if ($null -eq $Object) {
        return $Default
    }

    $value = Get-ConfigProperty $Object $Name
    if ($null -eq $value) {
        return $Default
    }

    if ($value -isnot [bool]) {
        throw "Config field '$DisplayName' must be a boolean."
    }

    return $value
}

function Get-ConfigString {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [bool]$Required,
        [string]$DisplayName
    )

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        $DisplayName = $Name
    }

    $value = Get-ConfigProperty $Object $Name
    if ($null -eq $value) {
        if ($Required) {
            throw "Config field '$DisplayName' is required."
        }
        return $null
    }

    if ($value -isnot [string]) {
        throw "Config field '$DisplayName' must be a string."
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Config field '$DisplayName' must not be empty."
    }

    return $value
}

function Get-ConfigInteger {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [bool]$Required,
        [string]$DisplayName
    )

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        $DisplayName = $Name
    }

    $value = Get-ConfigProperty $Object $Name
    if ($null -eq $value) {
        if ($Required) {
            throw "Config field '$DisplayName' is required."
        }
        return $null
    }

    if ($value -isnot [int] -and $value -isnot [long]) {
        throw "Config field '$DisplayName' must be an integer."
    }

    return [int]$value
}

function Get-ConfigStringArray {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$DisplayName
    )

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        $DisplayName = $Name
    }

    if ($null -eq $Object) {
        return @()
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return @()
    }

    $value = $property.Value
    if ($value -is [string] -or $value -isnot [System.Array]) {
        throw "Config field '$DisplayName' must be an array of strings."
    }

    $items = @()
    foreach ($item in $value) {
        if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item)) {
            throw "Config field '$DisplayName' must be an array of non-empty strings."
        }
        if ($items -contains $item) {
            throw "Config field '$DisplayName' must not contain duplicate values."
        }
        $items += $item
    }

    return $items
}

function Read-JsonConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SchemaPath
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path"
    }

    $configJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path

    if (Test-Path -LiteralPath $SchemaPath) {
        $schemaJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $SchemaPath
        $testJson = Get-Command Test-Json -ErrorAction SilentlyContinue
        if ($null -ne $testJson) {
            $valid = Test-Json -Json $configJson -Schema $schemaJson
            if (-not $valid) {
                throw "Config file does not match schema: $Path"
            }
        }
    }

    return $configJson | ConvertFrom-Json
}

function Test-SkillzConfig {
    param([Parameter(Mandatory = $true)][object]$Config)

    Assert-KnownProperties $Config @(
        '$schema',
        'skillsRoot',
        'transport',
        'host',
        'port',
        'path',
        'corsOrigins',
        'corsAllowCredentials',
        'python',
        'logging'
    ) "config"

    $skillsRoot = Get-ConfigString $Config "skillsRoot" $true "skillsRoot"
    $transport = Get-ConfigString $Config "transport" $true "transport"
    if ($transport -notin @("stdio", "http", "sse")) {
        throw "Config field 'transport' must be one of: stdio, http, sse."
    }

    $hostName = Get-ConfigString $Config "host" $true "host"
    $port = Get-ConfigInteger $Config "port" $true "port"
    $path = Get-ConfigString $Config "path" $true "path"

    if ($port -lt 1 -or $port -gt 65535) {
        throw "Config field 'port' must be between 1 and 65535."
    }

    if ($transport -eq "http" -and -not $path.StartsWith("/")) {
        throw "Config field 'path' must start with '/' for HTTP transport."
    }

    $corsOrigins = Get-ConfigStringArray $Config "corsOrigins" "corsOrigins"
    $allowCredentials = Get-ConfigBoolean $Config "corsAllowCredentials" $false "corsAllowCredentials"
    if ($allowCredentials -and ($corsOrigins -contains "*")) {
        throw "corsAllowCredentials cannot be true when corsOrigins contains '*'."
    }

    $pythonConfig = Get-ConfigObject $Config "python" "python"
    if ($null -ne $pythonConfig) {
        Assert-KnownProperties $pythonConfig @("uvSync", "frozen") "config.python"
        $null = Get-ConfigBoolean $pythonConfig "uvSync" $true "python.uvSync"
        $null = Get-ConfigBoolean $pythonConfig "frozen" $true "python.frozen"
    }

    $loggingConfig = Get-ConfigObject $Config "logging" "logging"
    if ($null -ne $loggingConfig) {
        Assert-KnownProperties $loggingConfig @("verbose", "log", "logPath") "config.logging"
        $null = Get-ConfigBoolean $loggingConfig "verbose" $false "logging.verbose"
        $null = Get-ConfigBoolean $loggingConfig "log" $false "logging.log"
        $logPath = Get-ConfigProperty $loggingConfig "logPath"
        if ($null -ne $logPath -and ($logPath -isnot [string] -or [string]::IsNullOrWhiteSpace($logPath))) {
            throw "Config field 'logging.logPath' must be a non-empty string."
        }
    }

    $null = $skillsRoot
    $null = $hostName
}

if ($Help) {
    Show-Help
    exit 0
}

$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDir "..")).Path

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $scriptDir "SetupAndRun.json"
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
$schemaPath = Join-Path $scriptDir "SetupAndRunSchema.json"
$config = Read-JsonConfig -Path $ConfigPath -SchemaPath $schemaPath
Test-SkillzConfig $config

$uv = Get-Command uv -ErrorAction SilentlyContinue
if ($null -eq $uv) {
    throw "uv was not found on PATH. Install uv first: https://docs.astral.sh/uv/"
}

$pythonConfig = Get-ConfigObject $config "python" "python"
$loggingConfig = Get-ConfigObject $config "logging" "logging"
$frozen = Get-ConfigBoolean $pythonConfig "frozen" $true "python.frozen"
$uvSync = Get-ConfigBoolean $pythonConfig "uvSync" $true "python.uvSync"

if ($uvSync -and -not $SkipSync) {
    $syncArgs = @("sync")
    if ($frozen) {
        $syncArgs += "--frozen"
    }

    Write-Host "Configuring Python environment in $repoRoot"
    Push-Location $repoRoot
    try {
        & $uv.Source @syncArgs
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Host "Skipping Python environment setup"
}

if ($ConfigureOnly) {
    Write-Host "Configuration phase complete."
    exit 0
}

$transport = [string]$config.transport
$runArgs = @("run", "--directory", $repoRoot)
if ($frozen) {
    $runArgs += "--frozen"
}

$runArgs += "skillz"
$runArgs += [string]$config.skillsRoot
$runArgs += "--transport"
$runArgs += $transport

if ($transport -in @("http", "sse")) {
    $runArgs += "--host"
    $runArgs += [string]$config.host
    $runArgs += "--port"
    $runArgs += [string]$config.port

    if ($transport -eq "http") {
        $runArgs += "--path"
        $runArgs += [string]$config.path
    }

    foreach ($origin in (Get-ConfigStringArray $config "corsOrigins" "corsOrigins")) {
        $runArgs += "--cors-origin"
        $runArgs += [string]$origin
    }

    if (Get-ConfigBoolean $config "corsAllowCredentials" $false "corsAllowCredentials") {
        $runArgs += "--cors-allow-credentials"
    }
}

if (Get-ConfigBoolean $loggingConfig "verbose" $false "logging.verbose") {
    $runArgs += "--verbose"
}
if (Get-ConfigBoolean $loggingConfig "log" $false "logging.log") {
    $runArgs += "--log"
    $logPath = Get-ConfigProperty $loggingConfig "logPath"
    if ($null -eq $logPath) {
        $logPath = Join-Path $repoRoot ".skillz\skillz.log"
    }
    $runArgs += "--log-file"
    $runArgs += [string]$logPath
}

$commandLine = Format-CommandLine $uv.Source $runArgs
if ($transport -eq "http") {
    $endpoint = "http://$($config.host):$($config.port)$($config.path)"
}
elseif ($transport -eq "sse") {
    $endpoint = "http://$($config.host):$($config.port)/sse"
}
else {
    $endpoint = "stdio"
}

Write-Host "Skillz MCP endpoint: $endpoint"

if ($PrintCommand -or $NoLaunch) {
    Write-Host $commandLine
}

if ($NoLaunch) {
    exit 0
}

& $uv.Source @runArgs
