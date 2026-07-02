[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Quote-ProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -match '^[A-Za-z0-9_./:\\=-]+$') {
        return $Value
    }

    return '"' + ($Value -replace '"', '\"') + '"'
}

function Invoke-SetupAndRun {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "powershell.exe"
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $allArguments = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (Join-Path $PSScriptRoot "SetupAndRun.ps1")
    )
    foreach ($argument in $Arguments) {
        $allArguments += $argument
    }
    $psi.Arguments = (($allArguments | ForEach-Object { Quote-ProcessArgument $_ }) -join " ")

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdout
        Stderr = $stderr
    }
}

function Write-TestConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ExtraJson = ""
    )

    $json = @"
{
  "skillsRoot": "$(($script:SkillsRoot -replace '\\', '/') -replace '"', '\"')",
  "transport": "http",
  "host": "127.0.0.1",
  "port": 8765,
  "path": "/mcp",
  "corsOrigins": ["http://127.0.0.1:8282"],
  "corsAllowCredentials": false,
  "corsAllowPrivateNetwork": true,
  "python": {
    "uvSync": true,
    "frozen": true
  },
  "logging": {
    "verbose": false,
    "log": false
  }$ExtraJson
}
"@
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Write-InterpreterTestConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Interpreter
    )

    $json = @"
{
  "skillsRoot": "$(($script:SkillsRoot -replace '\\', '/') -replace '"', '\"')",
  "transport": "http",
  "host": "127.0.0.1",
  "port": 8765,
  "path": "/mcp",
  "corsOrigins": ["http://127.0.0.1:8282"],
  "corsAllowCredentials": false,
  "corsAllowPrivateNetwork": true,
  "python": {
    "interpreter": "$(($Interpreter -replace '\\', '/') -replace '"', '\"')",
    "uvSync": true,
    "frozen": true
  },
  "logging": {
    "verbose": false,
    "log": false
  }
}
"@
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skillz-setup-tests-" + [guid]::NewGuid().ToString("N"))
$mockBin = Join-Path $tempRoot "mock-bin"
$mockPythonDir = Join-Path $tempRoot "mock-python"
$emptyPythonDir = Join-Path $tempRoot "empty-python"
$badPythonDir = Join-Path $tempRoot "bad-python"
$script:SkillsRoot = Join-Path $tempRoot "skills"
$configPath = Join-Path $tempRoot "SetupAndRun.test.json"
$oldPath = $env:PATH

try {
    New-Item -ItemType Directory -Path `
        $mockBin, `
        $mockPythonDir, `
        $emptyPythonDir, `
        $badPythonDir, `
        $script:SkillsRoot `
        | Out-Null

    $mockUv = Join-Path $mockBin "uv.cmd"
    Set-Content -LiteralPath $mockUv -Encoding ASCII -Value @"
@echo off
echo MOCK_UV %*
exit /b 0
"@

    $mockPython = Join-Path $mockPythonDir "python.cmd"
    Set-Content -LiteralPath $mockPython -Encoding ASCII -Value @"
@echo off
if "%1"=="-m" if "%2"=="uv" if "%3"=="--version" (
  echo MOCK_PYTHON_UV_VERSION
  exit /b 0
)
echo MOCK_PYTHON %*
exit /b 0
"@

    $badPython = Join-Path $badPythonDir "python.cmd"
    Set-Content -LiteralPath $badPython -Encoding ASCII -Value @"
@echo off
if "%1"=="-m" if "%2"=="uv" if "%3"=="--version" (
  echo BAD_PYTHON_NO_UV 1>&2
  exit /b 1
)
echo BAD_PYTHON %*
exit /b 0
"@

    $env:PATH = "$mockBin;$oldPath"

    $result = Invoke-SetupAndRun -Arguments @("-Help") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "Help should exit 0."
    Assert-True ($result.Stdout -match "SetupAndRun.ps1") "Help output should name script."

    $result = Invoke-SetupAndRun -Arguments @("-NoSuchParameter") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Unknown parameter should fail."

    $missingConfig = Join-Path $tempRoot "missing.json"
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $missingConfig, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Missing config should fail."
    Assert-True ($result.Stderr -match "Config file not found") "Missing config error should be readable."

    Write-TestConfig -Path $configPath
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch", "-PrintCommand") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "NoLaunch should exit 0."
    Assert-True ($result.Stdout -match "Skillz MCP endpoint: http://127.0.0.1:8765/mcp") "Endpoint should be printed."
    Assert-True ($result.Stdout -match "skillz") "Skillz command should be printed."
    Assert-True ($result.Stdout -match "--directory") "Command should use the current repository directory."
    Assert-True ($result.Stdout -match "--cors-origin") "CORS option should be included."
    Assert-True ($result.Stdout -match "--cors-allow-private-network") "Private network CORS option should be included."

    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-ConfigureOnly") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "ConfigureOnly should exit 0."
    Assert-True ($result.Stdout -match "MOCK_UV sync --frozen") "ConfigureOnly should call uv sync."

    Write-InterpreterTestConfig -Path $configPath -Interpreter "mock-python"
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-ConfigureOnly") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "ConfigureOnly should support a relative Python interpreter directory."
    Assert-True ($result.Stdout -match "MOCK_PYTHON -m uv sync") "ConfigureOnly should call uv through the configured Python."
    Assert-True ($result.Stdout -match "--python") "Configured Python should be passed to uv sync."
    Assert-True ($result.Stdout -match ([regex]::Escape($mockPython))) "uv sync should use the resolved Python path."

    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch", "-PrintCommand") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "NoLaunch should support a configured Python interpreter."
    Assert-True ($result.Stdout -match ([regex]::Escape($mockPython))) "Printed command should include the configured Python."
    Assert-True ($result.Stdout -match "-m uv run --directory") "Printed command should run uv as a Python module."
    Assert-True ($result.Stdout -match "--python") "Printed command should pass --python to uv run."

    Write-InterpreterTestConfig -Path $configPath -Interpreter $mockPython
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-ConfigureOnly") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "ConfigureOnly should support a full Python executable path."
    Assert-True ($result.Stdout -match "MOCK_PYTHON -m uv sync") "Full Python path should call uv through Python."

    Write-InterpreterTestConfig -Path $configPath -Interpreter "mock-python/python.cmd"
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-ConfigureOnly") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "ConfigureOnly should support a relative Python executable path."
    Assert-True ($result.Stdout -match "MOCK_PYTHON -m uv sync") "Relative Python executable path should call uv through Python."

    Write-InterpreterTestConfig -Path $configPath -Interpreter "missing-python"
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Missing Python interpreter path should fail."
    Assert-True ($result.Stderr -match "path not found") "Missing interpreter error should be readable."

    Write-InterpreterTestConfig -Path $configPath -Interpreter "empty-python"
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Python interpreter directory without Python should fail."
    Assert-True ($result.Stderr -match "does not contain") "Missing Python executable error should be readable."

    Write-InterpreterTestConfig -Path $configPath -Interpreter "bad-python"
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Python without uv should fail."
    Assert-True ($result.Stderr -match "Install uv first") "Missing uv error should include an install hint."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","skillsRoot":"'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Invalid JSON should fail."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":"x","transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","unknown":true}'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Unknown fields should fail."
    Assert-True ($result.Stderr -match "not supported") "Unknown field error should be readable."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":"x","transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","corsOrigins":["*"],"corsAllowCredentials":true}'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Wildcard credentials should fail."
    Assert-True ($result.Stderr -match "corsAllowCredentials") "CORS credential error should be readable."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":"x","transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","corsOrigins":["*"],"corsAllowPrivateNetwork":true}'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Wildcard private network access should fail."
    Assert-True ($result.Stderr -match "corsAllowPrivateNetwork") "Private network error should be readable."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":"x","transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","corsOrigins":[],"corsAllowPrivateNetwork":true}'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Private network access without origins should fail."
    Assert-True ($result.Stderr -match "corsOrigins") "Missing origin error should be readable."

    Write-Host "SetupAndRunTests: passed"
}
finally {
    $env:PATH = $oldPath
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
