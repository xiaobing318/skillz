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

function Get-JsonMember {
    param(
        [Parameter(Mandatory = $true)][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-SchemaNode {
    param(
        [Parameter(Mandatory = $true)][object]$Schema,
        [Parameter(Mandatory = $true)][string[]]$Path
    )

    $current = $Schema
    foreach ($segment in $Path) {
        $current = Get-JsonMember -InputObject $current -Name $segment
        if ($null -eq $current) {
            return $null
        }
    }

    return $current
}

function Assert-Description {
    param(
        [Parameter(Mandatory = $true)][object]$Schema,
        [Parameter(Mandatory = $true)][string[]]$Path
    )

    $node = Get-SchemaNode -Schema $Schema -Path $Path
    $pathText = $Path -join "."
    Assert-True ($null -ne $node) "Schema node '$pathText' should exist."

    $description = Get-JsonMember -InputObject $node -Name "description"
    Assert-True (($description -is [string]) -and ($description.Trim().Length -gt 0)) `
        "Schema node '$pathText' should have a non-empty description."
    Assert-True ($description -match '[\u4e00-\u9fff]') `
        "Schema node '$pathText' description should include Chinese text."
}

function Assert-DefaultOrExamples {
    param(
        [Parameter(Mandatory = $true)][object]$Schema,
        [Parameter(Mandatory = $true)][string[]]$Path
    )

    $node = Get-SchemaNode -Schema $Schema -Path $Path
    $pathText = $Path -join "."
    Assert-True ($null -ne $node) "Schema node '$pathText' should exist."

    $hasDefault = $null -ne $node.PSObject.Properties["default"]
    $hasExamples = $false
    $examplesProperty = $node.PSObject.Properties["examples"]
    if ($null -ne $examplesProperty -and $null -ne $examplesProperty.Value) {
        $hasExamples = @($examplesProperty.Value).Count -gt 0
    }

    Assert-True ($hasDefault -or $hasExamples) `
        "Schema node '$pathText' should have default or examples for editor hints."
}

function Assert-SchemaPathRules {
    param([Parameter(Mandatory = $true)][object]$Schema)

    $pathNode = Get-SchemaNode -Schema $Schema -Path @("properties", "path")
    Assert-True ($null -ne $pathNode) "Schema path property should exist."

    $pathRef = Get-JsonMember -InputObject $pathNode -Name "`$ref"
    Assert-True ($pathRef -eq "#/`$defs/nonEmptyString") `
        "Schema path property should not require an HTTP path unconditionally."

    $hasHttpPathCondition = $false
    foreach ($rule in @(Get-JsonMember -InputObject $Schema -Name "allOf")) {
        $transportConst = Get-SchemaNode -Schema $rule -Path @("if", "properties", "transport", "const")
        $thenPathRef = Get-SchemaNode -Schema $rule -Path @("then", "properties", "path", "`$ref")
        if ($transportConst -eq "http" -and $thenPathRef -eq "#/`$defs/httpPath") {
            $hasHttpPathCondition = $true
        }
    }

    Assert-True $hasHttpPathCondition `
        "Schema should require path to start with '/' only when transport is http."
}

function Invoke-TestJsonValidation {
    param(
        [Parameter(Mandatory = $true)][string]$Json,
        [Parameter(Mandatory = $true)][string]$SchemaJson
    )

    $testJson = Get-Command Test-Json -ErrorAction SilentlyContinue
    if ($null -eq $testJson) {
        return $null
    }

    try {
        return [bool](Test-Json -Json $Json -Schema $SchemaJson -ErrorAction Stop)
    }
    catch {
        return $false
    }
}

function Assert-TestJsonValidation {
    param(
        [Parameter(Mandatory = $true)][string]$Json,
        [Parameter(Mandatory = $true)][string]$SchemaJson,
        [Parameter(Mandatory = $true)][bool]$ExpectedValid,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $actual = Invoke-TestJsonValidation -Json $Json -SchemaJson $SchemaJson
    if ($null -eq $actual) {
        return
    }

    Assert-True ($actual -eq $ExpectedValid) $Message
}

function New-MinimalSchemaConfigJson {
    param([hashtable]$Override = @{})

    $config = [ordered]@{
        skillsRoot = @("x")
        transport = "http"
        host = "127.0.0.1"
        port = 8765
        path = "/mcp"
        python = [ordered]@{
            interpreter = @("mock-python")
        }
    }

    foreach ($key in $Override.Keys) {
        $config[$key] = $Override[$key]
    }

    return ($config | ConvertTo-Json -Depth 20)
}

function Assert-SchemaMetadata {
    $schemaPath = Join-Path $PSScriptRoot "SetupAndRunSchema.json"
    $schemaJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $schemaPath
    $schema = $schemaJson | ConvertFrom-Json

    $topDescription = Get-JsonMember -InputObject $schema -Name "description"
    Assert-True (($topDescription -is [string]) -and ($topDescription.Trim().Length -gt 0)) `
        "Schema should have a top-level description."
    Assert-True ($topDescription -match '[\u4e00-\u9fff]') `
        "Schema top-level description should include Chinese text."

    $descriptionPaths = @(
        @("properties", "`$schema"),
        @("properties", "skillsRoot"),
        @("properties", "transport"),
        @("properties", "host"),
        @("properties", "port"),
        @("properties", "path"),
        @("properties", "corsOrigins"),
        @("properties", "corsAllowCredentials"),
        @("properties", "corsAllowPrivateNetwork"),
        @("properties", "python"),
        @("properties", "logging"),
        @("`$defs", "pythonConfig", "properties", "interpreter"),
        @("`$defs", "pythonConfig", "properties", "uvSync"),
        @("`$defs", "pythonConfig", "properties", "frozen"),
        @("`$defs", "loggingConfig", "properties", "verbose"),
        @("`$defs", "loggingConfig", "properties", "log"),
        @("`$defs", "loggingConfig", "properties", "logPath")
    )
    foreach ($path in $descriptionPaths) {
        Assert-Description -Schema $schema -Path $path
    }

    $hintPaths = @(
        @("properties", "skillsRoot"),
        @("properties", "transport"),
        @("properties", "host"),
        @("properties", "port"),
        @("properties", "path"),
        @("properties", "corsOrigins"),
        @("properties", "corsAllowCredentials"),
        @("properties", "corsAllowPrivateNetwork"),
        @("`$defs", "pythonConfig", "properties", "interpreter"),
        @("`$defs", "pythonConfig", "properties", "uvSync"),
        @("`$defs", "pythonConfig", "properties", "frozen"),
        @("`$defs", "loggingConfig", "properties", "verbose"),
        @("`$defs", "loggingConfig", "properties", "log"),
        @("`$defs", "loggingConfig", "properties", "logPath")
    )
    foreach ($path in $hintPaths) {
        Assert-DefaultOrExamples -Schema $schema -Path $path
    }

    Assert-SchemaPathRules -Schema $schema

    $examples = Get-JsonMember -InputObject $schema -Name "examples"
    Assert-True ($null -ne $examples) "Schema should include top-level examples."
    Assert-True (@($examples).Count -gt 0) "Schema should include at least one top-level example."

    $configJson = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot "SetupAndRun.json")
    Assert-TestJsonValidation -Json $configJson -SchemaJson $schemaJson -ExpectedValid $true `
        -Message "Current SetupAndRun.json should pass SetupAndRunSchema.json when Test-Json is available."

    foreach ($example in @($examples)) {
        $exampleJson = $example | ConvertTo-Json -Depth 20
        Assert-TestJsonValidation -Json $exampleJson -SchemaJson $schemaJson -ExpectedValid $true `
            -Message "Schema top-level examples should pass SetupAndRunSchema.json when Test-Json is available."
    }

    $singleStringSkillsRoot = New-MinimalSchemaConfigJson -Override @{
        skillsRoot = "x"
    }
    Assert-TestJsonValidation -Json $singleStringSkillsRoot -SchemaJson $schemaJson -ExpectedValid $false `
        -Message "Schema should reject single-string skillsRoot."

    $singleStringInterpreter = New-MinimalSchemaConfigJson -Override @{
        python = [ordered]@{
            interpreter = "mock-python"
        }
    }
    Assert-TestJsonValidation -Json $singleStringInterpreter -SchemaJson $schemaJson -ExpectedValid $false `
        -Message "Schema should reject single-string python.interpreter."

    $emptySkillsRoot = New-MinimalSchemaConfigJson -Override @{
        skillsRoot = @()
    }
    Assert-TestJsonValidation -Json $emptySkillsRoot -SchemaJson $schemaJson -ExpectedValid $false `
        -Message "Schema should reject empty skillsRoot candidate arrays."

    $emptyInterpreter = New-MinimalSchemaConfigJson -Override @{
        python = [ordered]@{
            interpreter = @()
        }
    }
    Assert-TestJsonValidation -Json $emptyInterpreter -SchemaJson $schemaJson -ExpectedValid $false `
        -Message "Schema should reject empty python.interpreter candidate arrays."

    $httpPathWithoutSlash = New-MinimalSchemaConfigJson -Override @{
        path = "mcp"
    }
    Assert-TestJsonValidation -Json $httpPathWithoutSlash -SchemaJson $schemaJson -ExpectedValid $false `
        -Message "Schema should reject an HTTP path that does not start with '/'."

    $stdioPlainPath = New-MinimalSchemaConfigJson -Override @{
        transport = "stdio"
        path = "unused"
    }
    Assert-TestJsonValidation -Json $stdioPlainPath -SchemaJson $schemaJson -ExpectedValid $true `
        -Message "Schema should allow a non-HTTP path value for stdio transport."

    $ssePlainPath = New-MinimalSchemaConfigJson -Override @{
        transport = "sse"
        path = "unused"
    }
    Assert-TestJsonValidation -Json $ssePlainPath -SchemaJson $schemaJson -ExpectedValid $true `
        -Message "Schema should allow a non-HTTP path value for sse transport."

    $wildcardCredentials = New-MinimalSchemaConfigJson -Override @{
        corsOrigins = @("*")
        corsAllowCredentials = $true
    }
    Assert-TestJsonValidation -Json $wildcardCredentials -SchemaJson $schemaJson -ExpectedValid $false `
        -Message "Schema should reject corsAllowCredentials=true with wildcard corsOrigins."

    $privateNetworkWithoutOrigins = New-MinimalSchemaConfigJson -Override @{
        corsOrigins = @()
        corsAllowPrivateNetwork = $true
    }
    Assert-TestJsonValidation -Json $privateNetworkWithoutOrigins -SchemaJson $schemaJson -ExpectedValid $false `
        -Message "Schema should reject corsAllowPrivateNetwork=true without explicit corsOrigins."

    $privateNetworkWildcard = New-MinimalSchemaConfigJson -Override @{
        corsOrigins = @("*")
        corsAllowPrivateNetwork = $true
    }
    Assert-TestJsonValidation -Json $privateNetworkWildcard -SchemaJson $schemaJson -ExpectedValid $false `
        -Message "Schema should reject corsAllowPrivateNetwork=true with wildcard corsOrigins."
}

function Write-TestConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ExtraJson = ""
    )

    $json = @"
{
  "skillsRoot": [
    "$(($script:SkillsRoot -replace '\\', '/') -replace '"', '\"')"
  ],
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
  "skillsRoot": [
    "$(($script:SkillsRoot -replace '\\', '/') -replace '"', '\"')"
  ],
  "transport": "http",
  "host": "127.0.0.1",
  "port": 8765,
  "path": "/mcp",
  "corsOrigins": ["http://127.0.0.1:8282"],
  "corsAllowCredentials": false,
  "corsAllowPrivateNetwork": true,
  "python": {
    "interpreter": [
      "$(($Interpreter -replace '\\', '/') -replace '"', '\"')"
    ],
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

function Write-CandidateTestConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$SkillsRoots,
        [Parameter(Mandatory = $true)][string[]]$Interpreters
    )

    $config = [ordered]@{
        skillsRoot = $SkillsRoots
        transport = "http"
        host = "127.0.0.1"
        port = 8765
        path = "/mcp"
        corsOrigins = @("http://127.0.0.1:8282")
        corsAllowCredentials = $false
        corsAllowPrivateNetwork = $true
        python = [ordered]@{
            interpreter = $Interpreters
            uvSync = $true
            frozen = $true
        }
        logging = [ordered]@{
            verbose = $false
            log = $false
        }
    }

    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

Assert-SchemaMetadata

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skillz-setup-tests-" + [guid]::NewGuid().ToString("N"))
$mockBin = Join-Path $tempRoot "mock-bin"
$mockPythonDir = Join-Path $tempRoot "mock-python"
$silentPythonDir = Join-Path $tempRoot "silent-python"
$spacePythonDir = Join-Path $tempRoot "mock python"
$emptyPythonDir = Join-Path $tempRoot "empty-python"
$badPythonDir = Join-Path $tempRoot "bad-python"
$script:SkillsRoot = Join-Path $tempRoot "skills"
$otherSkillsRoot = Join-Path $tempRoot "other-skills"
$configPath = Join-Path $tempRoot "SetupAndRun.test.json"
$oldPath = $env:PATH

try {
    New-Item -ItemType Directory -Path `
        $mockBin, `
        $mockPythonDir, `
        $silentPythonDir, `
        $spacePythonDir, `
        $emptyPythonDir, `
        $badPythonDir, `
        $script:SkillsRoot, `
        $otherSkillsRoot `
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

    $silentPython = Join-Path $silentPythonDir "python.cmd"
    Set-Content -LiteralPath $silentPython -Encoding ASCII -Value @"
@echo off
if "%1"=="-m" if "%2"=="uv" if "%3"=="--version" (
  echo MOCK_SILENT_PYTHON_UV_VERSION
  exit /b 0
)
echo MOCK_SILENT_PYTHON_EXECUTED
exit /b 0
"@

    $spacePython = Join-Path $spacePythonDir "python.cmd"
    Set-Content -LiteralPath $spacePython -Encoding ASCII -Value @"
@echo off
if "%1"=="-m" if "%2"=="uv" if "%3"=="--version" (
  echo MOCK_SPACE_PYTHON_UV_VERSION
  exit /b 0
)
echo MOCK_SPACE_PYTHON %*
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
    Assert-True ($result.Stdout -match "Print resolved diagnostic commands") `
        "Help should describe PrintCommand as diagnostic command output."

    $result = Invoke-SetupAndRun -Arguments @("-NoSuchParameter") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Unknown parameter should fail."

    $missingConfig = Join-Path $tempRoot "missing.json"
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $missingConfig, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Missing config should fail."
    Assert-True ($result.Stderr -match "Config file not found") "Missing config error should be readable."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":["x"],"transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp"}'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch", "-PrintCommand") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Missing python config should fail even when uv is on PATH."
    Assert-True ($result.Stderr -match "python") "Missing python config error should be readable."
    Assert-True ($result.Stdout -notmatch "MOCK_UV") "PATH uv should not be used when python config is missing."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":"x","transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","python":{"interpreter":["mock-python"]}}'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Single-string skillsRoot should fail."
    Assert-True ($result.Stderr -match "(schema|array)") "Single-string skillsRoot error should be readable."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":["x"],"transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","python":{"interpreter":"mock-python"}}'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Single-string python.interpreter should fail."
    Assert-True ($result.Stderr -match "(schema|array)") "Single-string python.interpreter error should be readable."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":[],"transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","python":{"interpreter":["mock-python"]}}'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Empty skillsRoot array should fail."
    Assert-True ($result.Stderr -match "(schema|at least one)") "Empty skillsRoot error should be readable."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":[""],"transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","python":{"interpreter":["mock-python"]}}'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Empty skillsRoot item should fail."
    Assert-True ($result.Stderr -match "(schema|non-empty)") "Empty skillsRoot item error should be readable."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":["x","x"],"transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","python":{"interpreter":["mock-python"]}}'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Duplicate skillsRoot candidates should fail."
    Assert-True ($result.Stderr -match "(schema|duplicate)") "Duplicate skillsRoot error should be readable."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":["x"],"transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","python":{"interpreter":[]}}'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Empty python.interpreter array should fail."
    Assert-True ($result.Stderr -match "(schema|at least one)") "Empty python.interpreter error should be readable."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":["x"],"transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","python":{"interpreter":[123]}}'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Non-string python.interpreter item should fail."
    Assert-True ($result.Stderr -match "(schema|non-empty)") "Non-string python.interpreter error should be readable."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":["x"],"transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","python":{"interpreter":["mock-python","mock-python"]}}'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Duplicate python.interpreter candidates should fail."
    Assert-True ($result.Stderr -match "(schema|duplicate)") "Duplicate python.interpreter error should be readable."

    Write-TestConfig -Path $configPath
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch", "-PrintCommand") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Missing python.interpreter should fail even when uv is on PATH."
    Assert-True ($result.Stderr -match "python.interpreter") "Missing interpreter error should be readable."
    Assert-True ($result.Stdout -notmatch "MOCK_UV") "PATH uv should not be used when python.interpreter is missing."

    Write-InterpreterTestConfig -Path $configPath -Interpreter "mock-python"
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch", "-PrintCommand") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "NoLaunch should exit 0 with a configured Python interpreter."
    Assert-True ($result.Stdout -match "Skillz MCP endpoint: http://127.0.0.1:8765/mcp") "Endpoint should be printed."
    Assert-True ($result.Stdout -match "Python environment command: skipped") `
        "Skipped setup should print an explicit diagnostic when PrintCommand is used."
    Assert-True ($result.Stdout -match "Skillz MCP command:") "Skillz command label should be printed."
    Assert-True ($result.Stdout -match "skillz") "Skillz command should be printed."
    Assert-True ($result.Stdout -match "--directory") "Command should use the current repository directory."
    Assert-True ($result.Stdout -match "--cors-origin") "CORS option should be included."
    Assert-True ($result.Stdout -match "--cors-allow-private-network") "Private network CORS option should be included."
    Assert-True ($result.Stdout -match ([regex]::Escape($mockPython))) "Printed command should include the configured Python."
    Assert-True ($result.Stdout -match "-m uv run --directory") "Printed command should run uv as a Python module."
    Assert-True ($result.Stdout -match "--python") "Printed command should pass --python to uv run."
    Assert-True ($result.Stdout -notmatch "MOCK_UV") "NoLaunch should not use PATH uv."

    Write-CandidateTestConfig `
        -Path $configPath `
        -SkillsRoots @("missing-skills", $script:SkillsRoot) `
        -Interpreters @("mock-python")
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch", "-PrintCommand") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "skillsRoot should use the second candidate when the first is missing."
    Assert-True ($result.Stdout -match ([regex]::Escape($script:SkillsRoot))) "Printed command should include the selected skillsRoot."
    Assert-True ($result.Stdout -notmatch "missing-skills") "Printed command should not use the missing skillsRoot candidate."

    Write-CandidateTestConfig `
        -Path $configPath `
        -SkillsRoots @($script:SkillsRoot, $otherSkillsRoot) `
        -Interpreters @("mock-python")
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch", "-PrintCommand") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "skillsRoot should stop at the first usable candidate."
    Assert-True ($result.Stdout -match ([regex]::Escape($script:SkillsRoot))) "Printed command should include the first usable skillsRoot."
    Assert-True ($result.Stdout -notmatch ([regex]::Escape($otherSkillsRoot))) "Printed command should not include the second usable skillsRoot."

    Write-CandidateTestConfig `
        -Path $configPath `
        -SkillsRoots @("missing-skills-a", "missing-skills-b") `
        -Interpreters @("mock-python")
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "All-missing skillsRoot candidates should fail."
    Assert-True ($result.Stderr -match "No usable skillsRoot candidate") "All-missing skillsRoot error should be readable."

    Write-CandidateTestConfig `
        -Path $configPath `
        -SkillsRoots @($script:SkillsRoot) `
        -Interpreters @("missing-python", "mock-python")
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch", "-PrintCommand") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "python.interpreter should use the second candidate when the first is missing."
    Assert-True ($result.Stdout -match ([regex]::Escape($mockPython))) "Printed command should include the selected Python interpreter."

    Write-CandidateTestConfig `
        -Path $configPath `
        -SkillsRoots @($script:SkillsRoot) `
        -Interpreters @("bad-python", "mock-python")
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "python.interpreter should continue after a candidate without uv."

    Write-CandidateTestConfig `
        -Path $configPath `
        -SkillsRoots @($script:SkillsRoot) `
        -Interpreters @("mock-python", "missing-python")
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "python.interpreter should stop at the first usable candidate."

    Write-InterpreterTestConfig -Path $configPath -Interpreter "silent-python"
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath) -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "Default run should exit 0 with mock Python."
    Assert-True ($result.Stdout -match "Python environment command:") `
        "Default run should print the Python environment command label."
    Assert-True ($result.Stdout -match "-m uv sync") `
        "Default run should print the uv sync command from the wrapper script."
    Assert-True ($result.Stdout -match "Skillz MCP command:") `
        "Default run should print the Skillz MCP command label."
    Assert-True ($result.Stdout -match "-m uv run --directory") `
        "Default run should print the uv run command from the wrapper script."
    Assert-True ($result.Stdout -match "MOCK_SILENT_PYTHON_EXECUTED") `
        "Default run should execute the mock Python command."
    Assert-True ($result.Stdout -notmatch "MOCK_SILENT_PYTHON_EXECUTED -m uv") `
        "Command details should come from SetupAndRun.ps1, not mock Python argv echo."

    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-ConfigureOnly") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "ConfigureOnly should exit 0."
    Assert-True ($result.Stdout -match "Python environment command:") `
        "ConfigureOnly should print the Python environment command label."
    Assert-True ($result.Stdout -match "-m uv sync") "ConfigureOnly should print the uv sync command."
    Assert-True ($result.Stdout -match "MOCK_SILENT_PYTHON_EXECUTED") `
        "ConfigureOnly should call uv through the configured Python."
    Assert-True ($result.Stdout -match "--python") "Configured Python should be passed to uv sync."
    Assert-True ($result.Stdout -match ([regex]::Escape($silentPython))) "uv sync should use the resolved Python path."
    Assert-True ($result.Stdout -notmatch "Skillz MCP command:") `
        "ConfigureOnly should not print the Skillz launch command."
    Assert-True ($result.Stdout -notmatch "MOCK_UV") "ConfigureOnly should not use PATH uv."

    Write-InterpreterTestConfig -Path $configPath -Interpreter $mockPython
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-ConfigureOnly") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "ConfigureOnly should support a full Python executable path."
    Assert-True ($result.Stdout -match "MOCK_PYTHON -m uv sync") "Full Python path should call uv through Python."

    Write-InterpreterTestConfig -Path $configPath -Interpreter "mock-python/python.cmd"
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-ConfigureOnly") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "ConfigureOnly should support a relative Python executable path."
    Assert-True ($result.Stdout -match "MOCK_PYTHON -m uv sync") "Relative Python executable path should call uv through Python."

    Write-InterpreterTestConfig -Path $configPath -Interpreter "mock python"
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -eq 0) "NoLaunch should support a Python interpreter directory containing spaces."
    Assert-True ($result.Stdout -match "Skillz MCP command:") "NoLaunch should print the Skillz MCP command label."
    Assert-True ($result.Stdout -match ("'" + [regex]::Escape($spacePython) + "'")) `
        "Printed command should quote a Python path containing spaces."

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
    Assert-True ($result.Stdout -notmatch "MOCK_UV") "PATH uv should not be used when python.interpreter has no uv."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","skillsRoot":"'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Invalid JSON should fail."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":["x"],"transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","python":{"interpreter":["mock-python"]},"unknown":true}'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Unknown fields should fail."
    Assert-True ($result.Stderr -match "not supported") "Unknown field error should be readable."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":["x"],"transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","corsOrigins":["*"],"corsAllowCredentials":true,"python":{"interpreter":["mock-python"]}}'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Wildcard credentials should fail."
    Assert-True ($result.Stderr -match "corsAllowCredentials") "CORS credential error should be readable."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":["x"],"transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","corsOrigins":["*"],"corsAllowPrivateNetwork":true,"python":{"interpreter":["mock-python"]}}'
    $result = Invoke-SetupAndRun -Arguments @("-ConfigPath", $configPath, "-SkipSync", "-NoLaunch") -WorkingDirectory $tempRoot
    Assert-True ($result.ExitCode -ne 0) "Wildcard private network access should fail."
    Assert-True ($result.Stderr -match "corsAllowPrivateNetwork") "Private network error should be readable."

    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value '{"skillsRoot":["x"],"transport":"http","host":"127.0.0.1","port":8765,"path":"/mcp","corsOrigins":[],"corsAllowPrivateNetwork":true,"python":{"interpreter":["mock-python"]}}'
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
