param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($null -eq $Arguments) {
    $Arguments = @()
}
else {
    $Arguments = @($Arguments)
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$defaultConfigPath = Join-Path $scriptRoot 'ResolveCodexContext.json'
$platformInfoScriptName = 'ResolvePlatformInfo.ps1'
$defaultEnabledScripts = @($platformInfoScriptName)
$allowedEnabledScripts = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::Ordinal)
[void]$allowedEnabledScripts.Add($platformInfoScriptName)

function Show-CodexContextHelp {
    @'
ResolveCodexContext.ps1

Usage:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .codex\HelperScripts\Windows\ResolveCodexContext.ps1 [--help]
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .codex\HelperScripts\Windows\ResolveCodexContext.ps1 [--config <path>] [--outputJsonPath <path>]

Parameters:
  --help                  Show this help message and exit.
  --config <path>         Read the specified JSON config file. Defaults to ResolveCodexContext.json next to this script.
  --outputJsonPath <path> Write the JSON result to the specified path. Existing files are overwritten. Defaults to terminal output only.

Config:
  EnabledScripts controls which discovery scripts run. Allowed values:
    ResolvePlatformInfo.ps1

'@ | Write-Output
}

if (($Arguments.Count -eq 1) -and ($Arguments[0] -eq '--help')) {
    Show-CodexContextHelp
    exit 0
}

. (Join-Path $scriptRoot $platformInfoScriptName)

function Resolve-CodexUserPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathValue
    )

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $PathValue))
}

function Write-CodexJson {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Context,

        [string]$OutputJsonPath = ''
    )

    $json = ($Context | ConvertTo-Json -Depth 8) -replace '\r?\n', "`n"

    if ([string]::IsNullOrWhiteSpace($OutputJsonPath)) {
        $json | Write-Output
        return
    }

    $resolvedOutput = Resolve-CodexUserPath -PathValue $OutputJsonPath
    $outputDirectory = Split-Path -Parent $resolvedOutput
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    [System.IO.File]::WriteAllText(
        $resolvedOutput,
        $json + "`n",
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Write-CodexInvalidInputAndExit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Code,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$OutputJsonPath = ''
    )

    $context = [ordered]@{
        Status = 'InvalidInput'
        Messages = @(
            [ordered]@{
                Level = 'Error'
                Code = $Code
                Text = $Message
            }
        )
    }

    Write-CodexJson -Context $context -OutputJsonPath $OutputJsonPath
    exit 1
}

function Read-CodexConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [string]$OutputJsonPath = ''
    )

    $resolvedConfig = Resolve-CodexUserPath -PathValue $ConfigPath
    if (-not (Test-Path -LiteralPath $resolvedConfig -PathType Leaf)) {
        Write-CodexInvalidInputAndExit -Code 'ConfigNotFound' -Message "Config file not found: $resolvedConfig" -OutputJsonPath $OutputJsonPath
    }

    try {
        $text = Get-Content -Raw -Encoding UTF8 -LiteralPath $resolvedConfig
        $object = $text | ConvertFrom-Json
        return [pscustomobject]@{
            Path = $resolvedConfig
            Text = $text
            Object = $object
        }
    }
    catch {
        Write-CodexInvalidInputAndExit -Code 'ConfigInvalid' -Message $_.Exception.Message -OutputJsonPath $OutputJsonPath
    }
}

function Get-CodexEnabledScripts {
    param(
        [object]$ConfigObject,

        [Parameter(Mandatory = $true)]
        [string]$ConfigText
    )

    if (($null -eq $ConfigObject) -or ($ConfigObject -isnot [pscustomobject])) {
        throw 'Config root must be a JSON object.'
    }

    if ($ConfigText -notmatch '^\s*\{') {
        throw 'Config root must be a JSON object.'
    }

    $property = $ConfigObject.PSObject.Properties['EnabledScripts']
    if (-not $property) {
        return @($defaultEnabledScripts)
    }

    if ($ConfigText -notmatch '(?s)"EnabledScripts"\s*:\s*\[') {
        throw 'EnabledScripts must be an array of strings.'
    }

    $scripts = @()
    if ($null -ne $property.Value) {
        foreach ($item in @($property.Value)) {
            $text = [string]$item
            if ([string]::IsNullOrWhiteSpace($text)) {
                throw 'EnabledScripts contains an empty value.'
            }
            $scripts += $text
        }
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::Ordinal)
    foreach ($scriptName in $scripts) {
        if (-not $allowedEnabledScripts.Contains($scriptName)) {
            throw "Unsupported EnabledScripts value: $scriptName"
        }
        if (-not $seen.Add($scriptName)) {
            throw "Duplicate EnabledScripts value: $scriptName"
        }
    }

    return @($scripts)
}

function Test-CodexScriptEnabled {
    param(
        [string[]]$EnabledScripts,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return $EnabledScripts -contains $Name
}

function Test-CodexSupportedPlatform {
    param(
        [Parameter(Mandatory = $true)]
        [object]$PlatformInfo
    )

    $platformKey = '{0}/{1}' -f $PlatformInfo.OS, $PlatformInfo.ISA
    return $platformKey -in @(
        'Windows/AMD64',
        'Windows/ARM64',
        'Linux/AMD64',
        'Linux/ARM64',
        'macOS/ARM64'
    )
}

$configPath = $defaultConfigPath
$outputJsonPath = ''
$index = 0

while ($index -lt $Arguments.Count) {
    $argument = $Arguments[$index]
    switch ($argument) {
        '--help' {
            Show-CodexContextHelp
            exit 0
        }
        '--config' {
        if ((($index + 1) -ge $Arguments.Count) -or $Arguments[$index + 1].StartsWith('--')) {
            Write-CodexInvalidInputAndExit -Code 'MissingConfigPath' -Message '--config requires a path.' -OutputJsonPath $outputJsonPath
        }
            $configPath = $Arguments[$index + 1]
            $index += 2
            continue
        }
        '--outputJsonPath' {
        if ((($index + 1) -ge $Arguments.Count) -or $Arguments[$index + 1].StartsWith('--')) {
            Write-CodexInvalidInputAndExit -Code 'MissingOutputJsonPath' -Message '--outputJsonPath requires a path.' -OutputJsonPath $outputJsonPath
        }
            $outputJsonPath = $Arguments[$index + 1]
            $index += 2
            continue
        }
        default {
            Write-CodexInvalidInputAndExit -Code 'UnknownArgument' -Message "Unknown argument: $argument" -OutputJsonPath $outputJsonPath
        }
    }
}

$config = Read-CodexConfig -ConfigPath $configPath -OutputJsonPath $outputJsonPath

try {
    $enabledScripts = @(Get-CodexEnabledScripts -ConfigObject $config.Object -ConfigText $config.Text)
}
catch {
    Write-CodexInvalidInputAndExit -Code 'EnabledScriptsInvalid' -Message $_.Exception.Message -OutputJsonPath $outputJsonPath
}

$context = [ordered]@{
    Status = 'Ok'
}
$messages = New-Object System.Collections.Generic.List[object]

if (Test-CodexScriptEnabled -EnabledScripts $enabledScripts -Name $platformInfoScriptName) {
    $platformInfo = Resolve-CodexPlatformInfo
    $context['PlatformInfo'] = $platformInfo
    if (-not (Test-CodexSupportedPlatform -PlatformInfo $platformInfo)) {
        $context['Status'] = 'Unsupported'
    }
}

if ($enabledScripts.Count -eq 0) {
    $messages.Add([ordered]@{
        Level = 'Info'
        Code = 'NoDiscoveryScriptsEnabled'
        Text = 'EnabledScripts is empty, no discovery scripts were executed.'
    })
}

if ($messages.Count -gt 0) {
    $context['Messages'] = $messages.ToArray()
}

Write-CodexJson -Context $context -OutputJsonPath $outputJsonPath
