Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:OriginalArguments = @($args)
$script:SetupBoundParameters = @{}
$ConfigPath = $null
$ConfigureOnly = $false
$NoLaunch = $false
$PrintCommand = $false
$Help = $false

function Fail-Parameter {
    param([Parameter(Mandatory = $true)][string]$Message)

    throw $Message
}

function Test-SetupArgumentLooksLikeOption {
    param([object]$Value)

    if ($null -eq $Value) {
        return $false
    }

    return ([string]$Value).StartsWith("-")
}

function Set-SetupParsedParameter {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string]$ParameterName
    )

    if ($script:SetupBoundParameters.ContainsKey($Name)) {
        Fail-Parameter "Parameter $ParameterName was specified more than once."
    }

    $script:SetupBoundParameters[$Name] = $Value
    Set-Variable -Name $Name -Value $Value -Scope Script
}

function Read-SetupRequiredArgumentValue {
    param(
        [Parameter(Mandatory = $true)][object[]]$Arguments,
        [Parameter(Mandatory = $true)][int]$Index,
        [Parameter(Mandatory = $true)][string]$ParameterName
    )

    $valueIndex = $Index + 1
    if ($valueIndex -ge $Arguments.Count) {
        Fail-Parameter "Missing value for parameter $ParameterName."
    }

    $value = [string]$Arguments[$valueIndex]
    if ([string]::IsNullOrWhiteSpace($value)) {
        Fail-Parameter "Missing value for parameter $ParameterName."
    }
    if (Test-SetupArgumentLooksLikeOption -Value $value) {
        Fail-Parameter "Missing value for parameter $ParameterName."
    }

    return $value
}

function Initialize-SetupCommandLine {
    param([AllowEmptyCollection()][object[]]$Arguments)

    $script:SetupBoundParameters.Clear()
    $index = 0
    while ($index -lt $Arguments.Count) {
        $argument = [string]$Arguments[$index]
        if ([string]::IsNullOrWhiteSpace($argument)) {
            $index++
            continue
        }
        if (-not (Test-SetupArgumentLooksLikeOption -Value $argument)) {
            Fail-Parameter "Unexpected positional argument: $argument"
        }

        switch -CaseSensitive ($argument) {
            "--Help" {
                Set-SetupParsedParameter -Name "Help" -Value $true -ParameterName $argument
                $index++
                continue
            }
            "--ConfigPath" {
                $value = Read-SetupRequiredArgumentValue `
                    -Arguments $Arguments `
                    -Index $index `
                    -ParameterName $argument
                Set-SetupParsedParameter -Name "ConfigPath" -Value $value -ParameterName $argument
                $index += 2
                continue
            }
            "--ConfigureOnly" {
                Set-SetupParsedParameter -Name "ConfigureOnly" -Value $true -ParameterName $argument
                $index++
                continue
            }
            "--NoLaunch" {
                Set-SetupParsedParameter -Name "NoLaunch" -Value $true -ParameterName $argument
                $index++
                continue
            }
            "--PrintCommand" {
                Set-SetupParsedParameter -Name "PrintCommand" -Value $true -ParameterName $argument
                $index++
                continue
            }
            default {
                Fail-Parameter "Unknown parameter: $argument"
            }
        }
    }
}

function Show-Help {
    @"
SetupAndRun.ps1

Configure the local Python environment and start the Skillz MCP server.

Usage:
  powershell -ExecutionPolicy Bypass -File SetupAndRun\SetupAndRun.ps1 [--ConfigPath <path>] [--ConfigureOnly] [--NoLaunch] [--PrintCommand]

Options:
  --ConfigPath <path>  JSON configuration file. Defaults to SetupAndRun\SetupAndRun.json.
  --ConfigureOnly      Run the environment setup phase and then stop.
  --NoLaunch           Build and print the Skillz command without starting it.
  --PrintCommand       Print resolved diagnostic commands.
  --Help               Show this help text.

Configuration:
  skillsRoot and python.interpreter must be arrays of candidate paths. The
  script selects the first usable candidate in order. python.interpreter
  candidates may point to a Python executable, or to a directory containing
  python.exe, python.cmd, or python.bat. Relative paths are resolved from the
  JSON config file directory. uv is always run through the selected interpreter
  with 'python -m uv'; PATH uv is not used. python.uvSync controls whether the
  script runs 'uv sync'. Before launching HTTP/SSE, a matching stale Skillz
  listener on the configured skillsRoot and port is stopped automatically.
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

function Split-CommandLineTokens {
    param([string]$CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) {
        return @()
    }

    $tokens = @()
    $current = [System.Text.StringBuilder]::new()
    $quoteChar = [char]0
    foreach ($character in $CommandLine.ToCharArray()) {
        if ($character -eq '"' -or $character -eq "'") {
            if ($quoteChar -eq [char]0) {
                $quoteChar = $character
                continue
            }
            if ($quoteChar -eq $character) {
                $quoteChar = [char]0
                continue
            }
        }

        if ([char]::IsWhiteSpace($character) -and $quoteChar -eq [char]0) {
            if ($current.Length -gt 0) {
                $tokens += $current.ToString()
                $null = $current.Clear()
            }
            continue
        }

        $null = $current.Append($character)
    }

    if ($current.Length -gt 0) {
        $tokens += $current.ToString()
    }

    return $tokens
}

function Normalize-PathForComparison {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    return (($Path.Trim('"', "'") -replace '/', '\').TrimEnd('\')).ToLowerInvariant()
}

function Test-CommandLineHasSkillzToken {
    param([string[]]$Tokens)

    foreach ($token in $Tokens) {
        $normalized = Normalize-PathForComparison $token
        $leaf = @($normalized -split '\\')[-1]
        if ($leaf -in @("skillz", "skillz.exe")) {
            return $true
        }
    }

    return $false
}

function Test-CommandLineHasTokenValue {
    param(
        [string[]]$Tokens,
        [Parameter(Mandatory = $true)][string]$ExpectedValue,
        [switch]$PathValue
    )

    $expected = if ($PathValue) {
        Normalize-PathForComparison $ExpectedValue
    }
    else {
        $ExpectedValue.ToLowerInvariant()
    }

    foreach ($token in $Tokens) {
        $actual = if ($PathValue) {
            Normalize-PathForComparison $token
        }
        else {
            $token.ToLowerInvariant()
        }
        if ($actual -eq $expected) {
            return $true
        }
    }

    return $false
}

function Test-CommandLineHasPort {
    param(
        [string[]]$Tokens,
        [Parameter(Mandatory = $true)][int]$Port
    )

    for ($index = 0; $index -lt $Tokens.Count; $index++) {
        $token = $Tokens[$index].ToLowerInvariant()
        if ($token -eq "--port" -and $index + 1 -lt $Tokens.Count) {
            if ($Tokens[$index + 1] -eq [string]$Port) {
                return $true
            }
        }
        if ($token -eq "--port=$Port") {
            return $true
        }
    }

    return $false
}

function Test-SensitiveArgumentName {
    param([string]$Name)

    $normalized = $Name.TrimStart("-", "/")
    return $normalized -match '(?i)(api[-_]?key|access[-_]?token|refresh[-_]?token|token|password|passwd|pwd|secret|credential|client[-_]?secret)'
}

function Protect-CommandLineForDisplay {
    param([string]$CommandLine)

    $tokens = @(Split-CommandLineTokens $CommandLine)
    if ($tokens.Count -eq 0) {
        return "<unavailable>"
    }

    for ($index = 0; $index -lt $tokens.Count; $index++) {
        $token = $tokens[$index]
        if ($token -match '^([^=]+)=(.*)$' -and (Test-SensitiveArgumentName $matches[1])) {
            $tokens[$index] = "$($matches[1])=<redacted>"
            continue
        }

        if ((Test-SensitiveArgumentName $token) -and $index + 1 -lt $tokens.Count) {
            $tokens[$index + 1] = "<redacted>"
            $index++
        }
    }

    if ($tokens.Count -eq 1) {
        return Format-CommandArgument $tokens[0]
    }

    return Format-CommandLine $tokens[0] @($tokens[1..($tokens.Count - 1)])
}

function Format-ProcessSummary {
    param([Parameter(Mandatory = $true)][object]$ProcessInfo)

    $safeCommandLine = Protect-CommandLineForDisplay $ProcessInfo.CommandLine
    return "PID $($ProcessInfo.ProcessId) $($ProcessInfo.Name): $safeCommandLine"
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
        [string]$DisplayName,
        [bool]$Required = $false
    )

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        $DisplayName = $Name
    }

    if ($null -eq $Object) {
        if ($Required) {
            throw "Config field '$DisplayName' is required."
        }
        return @()
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        if ($Required) {
            throw "Config field '$DisplayName' is required."
        }
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

    if ($Required -and $items.Count -eq 0) {
        throw "Config field '$DisplayName' must contain at least one value."
    }

    return $items
}

function Resolve-ConfigPathValue {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$BaseDirectory
    )

    if ([System.IO.Path]::IsPathRooted($Value)) {
        return [System.IO.Path]::GetFullPath($Value)
    }

    return [System.IO.Path]::GetFullPath(
        (Join-Path $BaseDirectory $Value)
    )
}

function Resolve-PythonInterpreter {
    param(
        [Parameter(Mandatory = $true)][string]$Interpreter,
        [Parameter(Mandatory = $true)][string]$BaseDirectory
    )

    $candidate = Resolve-ConfigPathValue `
        -Value $Interpreter `
        -BaseDirectory $BaseDirectory

    if (-not (Test-Path -LiteralPath $candidate)) {
        throw "Config field 'python.interpreter' path not found: $candidate"
    }

    $item = Get-Item -LiteralPath $candidate
    if (-not $item.PSIsContainer) {
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    foreach ($fileName in @("python.exe", "python.cmd", "python.bat")) {
        $pythonPath = Join-Path $candidate $fileName
        if (Test-Path -LiteralPath $pythonPath -PathType Leaf) {
            return (Resolve-Path -LiteralPath $pythonPath).Path
        }
    }

    throw (
        "Config field 'python.interpreter' directory does not contain " +
        "python.exe, python.cmd, or python.bat: $candidate"
    )
}

function Resolve-ExistingDirectoryCandidate {
    param(
        [Parameter(Mandatory = $true)][string[]]$Candidates,
        [Parameter(Mandatory = $true)][string]$BaseDirectory,
        [Parameter(Mandatory = $true)][string]$DisplayName
    )

    $errors = @()
    foreach ($candidate in $Candidates) {
        $resolved = Resolve-ConfigPathValue `
            -Value $candidate `
            -BaseDirectory $BaseDirectory

        if (Test-Path -LiteralPath $resolved -PathType Container) {
            return (Resolve-Path -LiteralPath $resolved).Path
        }

        if (Test-Path -LiteralPath $resolved) {
            $errors += "$candidate -> $resolved is not a directory"
        }
        else {
            $errors += "$candidate -> $resolved was not found"
        }
    }

    throw (
        "No usable $DisplayName candidate found. Tried: " +
        ($errors -join "; ")
    )
}

function New-LogFilePath {
    param(
        [Parameter(Mandatory = $true)][string]$LogDirectory,
        [Parameter(Mandatory = $true)][string]$BaseDirectory
    )

    $resolvedDirectory = Resolve-ConfigPathValue `
        -Value $LogDirectory `
        -BaseDirectory $BaseDirectory
    $fileName = (Get-Date -Format "yyyy-MM-dd-HH-mm-ss") + ".log"

    return (Join-Path $resolvedDirectory $fileName)
}

function Test-PythonUv {
    param([Parameter(Mandatory = $true)][string]$PythonPath)

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $uvOutput = & $PythonPath -m uv --version 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -ne 0) {
        $installCommand = (
            (Format-CommandArgument $PythonPath) +
            " -m pip install uv"
        )
        throw (
            "uv is not available for python.interpreter '$PythonPath'. " +
            "Install uv first: $installCommand"
        )
    }

    $null = $uvOutput
}

function Get-ListeningPortProcesses {
    param([Parameter(Mandatory = $true)][int]$Port)

    $connections = @(Get-NetTCPConnection `
            -LocalPort $Port `
            -State Listen `
            -ErrorAction SilentlyContinue)
    $items = @()
    foreach ($connection in $connections) {
        $process = Get-CimInstance `
            -ClassName Win32_Process `
            -Filter "ProcessId=$($connection.OwningProcess)" `
            -ErrorAction SilentlyContinue
        $items += [pscustomobject]@{
            LocalAddress = [string]$connection.LocalAddress
            LocalPort = [int]$connection.LocalPort
            ProcessId = [int]$connection.OwningProcess
            CommandLine = if ($null -ne $process) { [string]$process.CommandLine } else { $null }
            Name = if ($null -ne $process) { [string]$process.Name } else { $null }
        }
    }
    return $items
}

function Test-SkillzProcessCommandLine {
    param(
        [string]$CommandLine,
        [Parameter(Mandatory = $true)][string]$SkillsRoot,
        [Parameter(Mandatory = $true)][int]$Port
    )

    if ([string]::IsNullOrWhiteSpace($CommandLine)) {
        return $false
    }

    $tokens = @(Split-CommandLineTokens $CommandLine)
    if (-not (Test-CommandLineHasSkillzToken -Tokens $tokens)) {
        return $false
    }
    if (-not (Test-CommandLineHasTokenValue `
                -Tokens $tokens `
                -ExpectedValue $SkillsRoot `
                -PathValue)) {
        return $false
    }

    return Test-CommandLineHasPort -Tokens $tokens -Port $Port
}

function Test-SkillzLaunchChainCommandLine {
    param([string]$CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) {
        return $false
    }

    $tokens = @(Split-CommandLineTokens $CommandLine)
    if (Test-CommandLineHasSkillzToken -Tokens $tokens) {
        return $true
    }

    foreach ($token in $tokens) {
        $normalized = Normalize-PathForComparison $token
        $leaf = @($normalized -split '\\')[-1]
        if ($leaf -in @("uv", "uv.exe")) {
            return $true
        }
    }

    return (
        $CommandLine -match '(?i)\bpython(\.exe)?("|\\s).*-m\s+uv\s+run\b' -or
        $CommandLine -match '(?i)SetupAndRun\.ps1'
    )
}

function Get-LaunchChainProcesses {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    $chain = @()
    $currentProcessId = $ProcessId
    $seen = @{}
    while ($currentProcessId -and -not $seen.ContainsKey($currentProcessId)) {
        $seen[$currentProcessId] = $true
        $process = Get-CimInstance `
            -ClassName Win32_Process `
            -Filter "ProcessId=$currentProcessId" `
            -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            break
        }
        if (-not (Test-SkillzLaunchChainCommandLine $process.CommandLine)) {
            break
        }
        $chain += $process
        if ($currentProcessId -eq $process.ParentProcessId) {
            break
        }
        $currentProcessId = [int]$process.ParentProcessId
    }

    return $chain
}

function Stop-ExistingSkillzListeners {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$SkillsRoot
    )

    $listeners = @(Get-ListeningPortProcesses -Port $Port)
    if ($listeners.Count -eq 0) {
        return
    }

    $unsafeListeners = @(
        $listeners | Where-Object {
            -not (Test-SkillzProcessCommandLine `
                    -CommandLine $_.CommandLine `
                    -SkillsRoot $SkillsRoot `
                    -Port $Port)
        }
    )
    if ($unsafeListeners.Count -gt 0) {
        $summary = ($unsafeListeners | ForEach-Object {
                Format-ProcessSummary $_
            }) -join "; "
        throw (
            "Port $Port is already in use, but the listener was not recognized " +
            "as this Skillz server. Refusing to stop it. Listener: $summary"
        )
    }

    $processesToStop = @{}
    foreach ($listener in $listeners) {
        foreach ($process in @(Get-LaunchChainProcesses -ProcessId $listener.ProcessId)) {
            if ($process.ProcessId -ne $PID) {
                $processesToStop[[int]$process.ProcessId] = $process
            }
        }
    }

    foreach ($processId in @($processesToStop.Keys)) {
        $process = $processesToStop[$processId]
        Write-Host "Stopping existing Skillz process PID $processId ($($process.Name))"
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }

    $deadline = (Get-Date).AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 250
        $remaining = @(Get-ListeningPortProcesses -Port $Port)
    } while ($remaining.Count -gt 0 -and (Get-Date) -lt $deadline)

    if ($remaining.Count -gt 0) {
        $summary = ($remaining | ForEach-Object {
                Format-ProcessSummary $_
            }) -join "; "
        throw "Port $Port is still in use after stopping existing Skillz listener: $summary"
    }
}

function Assert-PortAvailableForLaunch {
    param(
        [Parameter(Mandatory = $true)][string]$Transport,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$SkillsRoot
    )

    if ($Transport -notin @("http", "sse")) {
        return
    }

    $listeners = @(Get-ListeningPortProcesses -Port $Port)
    if ($listeners.Count -eq 0) {
        return
    }

    $null = $listeners
    Stop-ExistingSkillzListeners -Port $Port -SkillsRoot $SkillsRoot
}

function Get-Win32ErrorMessage {
    param([Parameter(Mandatory = $true)][int]$ErrorCode)

    return ([System.ComponentModel.Win32Exception]::new($ErrorCode)).Message
}

function Initialize-JobObjectSupport {
    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw "Process tree cleanup with Windows Job Objects is only supported on Windows."
    }

    if ("SkillzSetupNativeMethods" -as [type]) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class SkillzSetupNativeMethods
{
    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct IO_COUNTERS
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetInformationJobObject(
        IntPtr hJob,
        int JobObjectInfoClass,
        ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION lpJobObjectInfo,
        int cbJobObjectInfoLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@
}

function New-ProcessCleanupJob {
    if ($env:SKILLZ_SETUP_TEST_FORCE_JOB_FAILURE) {
        throw "Forced Job Object initialization failure for SetupAndRun tests."
    }

    Initialize-JobObjectSupport

    $jobHandle = [SkillzSetupNativeMethods]::CreateJobObject([IntPtr]::Zero, $null)
    if ($jobHandle -eq [IntPtr]::Zero) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Failed to create cleanup Job Object: $(Get-Win32ErrorMessage $errorCode)"
    }

    try {
        $limitInfo = [SkillzSetupNativeMethods+JOBOBJECT_EXTENDED_LIMIT_INFORMATION]::new()
        $limitInfo.BasicLimitInformation.LimitFlags = 0x00002000
        $result = [SkillzSetupNativeMethods]::SetInformationJobObject(
            $jobHandle,
            9,
            [ref]$limitInfo,
            [Runtime.InteropServices.Marshal]::SizeOf($limitInfo)
        )
        if (-not $result) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Failed to configure cleanup Job Object: $(Get-Win32ErrorMessage $errorCode)"
        }

        return $jobHandle
    }
    catch {
        Close-NativeHandle $jobHandle
        throw
    }
}

function Close-NativeHandle {
    param([IntPtr]$Handle)

    if ($Handle -ne [IntPtr]::Zero) {
        [SkillzSetupNativeMethods]::CloseHandle($Handle) | Out-Null
    }
}

function Get-ChildProcessInfos {
    param([Parameter(Mandatory = $true)][int]$ParentProcessId)

    return @(
        Get-CimInstance `
            -ClassName Win32_Process `
            -Filter "ParentProcessId=$ParentProcessId" `
            -ErrorAction SilentlyContinue
    )
}

function Stop-ProcessTree {
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [int[]]$ExcludeProcessIds = @($PID)
    )

    foreach ($child in @(Get-ChildProcessInfos -ParentProcessId $ProcessId)) {
        Stop-ProcessTree `
            -ProcessId ([int]$child.ProcessId) `
            -ExcludeProcessIds $ExcludeProcessIds
    }

    if ($ProcessId -notin $ExcludeProcessIds) {
        $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($null -ne $process) {
            Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
            $process.WaitForExit(5000) | Out-Null
        }
    }
}

function Stop-TrackedSkillzProcess {
    param(
        [object]$TrackedProcess,
        [Parameter(Mandatory = $true)][string]$Transport,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$SkillsRoot
    )

    if ($null -ne $TrackedProcess -and $null -ne $TrackedProcess.Process) {
        $process = $TrackedProcess.Process
        if (-not $process.HasExited) {
            Stop-ProcessTree -ProcessId $process.Id
        }
    }

    if ($Transport -in @("http", "sse")) {
        try {
            Stop-ExistingSkillzListeners -Port $Port -SkillsRoot $SkillsRoot
        }
        catch {
            Write-Warning "Cleanup check did not stop every matching Skillz listener: $($_.Exception.Message)"
        }
    }
}

function Resolve-PowerShellHostPath {
    $currentHostPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if (-not [string]::IsNullOrWhiteSpace($currentHostPath) -and
        (Test-Path -LiteralPath $currentHostPath)) {
        return $currentHostPath
    }

    foreach ($candidate in @(
            (Join-Path $PSHOME "powershell.exe"),
            (Join-Path $PSHOME "pwsh.exe")
        )) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return "powershell.exe"
}

function Start-ParentExitWatchdog {
    param(
        [Parameter(Mandatory = $true)][int]$ParentProcessId,
        [Parameter(Mandatory = $true)][int]$RootProcessId,
        [Parameter(Mandatory = $true)][long]$RootProcessStartTimeUtcTicks,
        [Parameter(Mandatory = $true)][string]$Transport,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$SkillsRoot
    )

    $transportLiteral = Format-CommandArgument $Transport
    $skillsRootLiteral = Format-CommandArgument $SkillsRoot
    $script = @"
`$ParentProcessId = $ParentProcessId
`$RootProcessId = $RootProcessId
`$RootProcessStartTimeUtcTicks = $RootProcessStartTimeUtcTicks
`$Transport = $transportLiteral
`$Port = $Port
`$SkillsRoot = $skillsRootLiteral
function Split-CommandLineTokens {
    param([string]`$CommandLine)
    if ([string]::IsNullOrWhiteSpace(`$CommandLine)) { return @() }
    `$tokens = @()
    `$current = [System.Text.StringBuilder]::new()
    `$quoteChar = [char]0
    foreach (`$character in `$CommandLine.ToCharArray()) {
        if (`$character -eq '"' -or `$character -eq "'") {
            if (`$quoteChar -eq [char]0) { `$quoteChar = `$character; continue }
            if (`$quoteChar -eq `$character) { `$quoteChar = [char]0; continue }
        }
        if ([char]::IsWhiteSpace(`$character) -and `$quoteChar -eq [char]0) {
            if (`$current.Length -gt 0) {
                `$tokens += `$current.ToString()
                `$null = `$current.Clear()
            }
            continue
        }
        `$null = `$current.Append(`$character)
    }
    if (`$current.Length -gt 0) { `$tokens += `$current.ToString() }
    return `$tokens
}
function Normalize-PathForComparison {
    param([string]`$Path)
    if ([string]::IsNullOrWhiteSpace(`$Path)) { return "" }
    return ((`$Path.Trim('"', "'") -replace '/', '\').TrimEnd('\')).ToLowerInvariant()
}
function Test-MatchingSkillzCommandLine {
    param([string]`$CommandLine)
    `$tokens = @(Split-CommandLineTokens `$CommandLine)
    `$hasSkillz = `$false
    `$hasSkillsRoot = `$false
    `$hasPort = `$false
    `$expectedRoot = Normalize-PathForComparison `$SkillsRoot
    for (`$index = 0; `$index -lt `$tokens.Count; `$index++) {
        `$normalized = Normalize-PathForComparison `$tokens[`$index]
        `$leaf = @(`$normalized -split '\\')[-1]
        if (`$leaf -in @("skillz", "skillz.exe")) { `$hasSkillz = `$true }
        if (`$normalized -eq `$expectedRoot) { `$hasSkillsRoot = `$true }
        `$token = `$tokens[`$index].ToLowerInvariant()
        if (`$token -eq "--port" -and `$index + 1 -lt `$tokens.Count -and `$tokens[`$index + 1] -eq [string]`$Port) {
            `$hasPort = `$true
        }
        if (`$token -eq "--port=`$Port") { `$hasPort = `$true }
    }
    return (`$hasSkillz -and `$hasSkillsRoot -and `$hasPort)
}
function Stop-Tree {
    param([int]`$ProcessId)
    foreach (`$child in @(Get-CimInstance Win32_Process -Filter "ParentProcessId=`$ProcessId" -ErrorAction SilentlyContinue)) {
        Stop-Tree ([int]`$child.ProcessId)
    }
    Stop-Process -Id `$ProcessId -Force -ErrorAction SilentlyContinue
}
function Test-ExpectedRootProcess {
    `$process = Get-Process -Id `$RootProcessId -ErrorAction SilentlyContinue
    if (`$null -eq `$process) { return `$false }
    try {
        return (`$process.StartTime.ToUniversalTime().Ticks -eq `$RootProcessStartTimeUtcTicks)
    }
    catch {
        return `$false
    }
}
while (Get-Process -Id `$ParentProcessId -ErrorAction SilentlyContinue) {
    Start-Sleep -Milliseconds 250
}
`$deadline = (Get-Date).AddSeconds(20)
do {
    if (Test-ExpectedRootProcess) {
        Stop-Tree `$RootProcessId
    }
    `$remaining = @()
    if (`$Transport -in @("http", "sse")) {
        foreach (`$connection in @(Get-NetTCPConnection -LocalPort `$Port -State Listen -ErrorAction SilentlyContinue)) {
            `$process = Get-CimInstance Win32_Process -Filter "ProcessId=`$(`$connection.OwningProcess)" -ErrorAction SilentlyContinue
            if (`$null -ne `$process -and (Test-MatchingSkillzCommandLine `$process.CommandLine)) {
                Stop-Tree ([int]`$process.ProcessId)
                `$remaining += `$process
            }
        }
    }
    Start-Sleep -Milliseconds 250
} while (`$remaining.Count -gt 0 -and (Get-Date) -lt `$deadline)
"@

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = Resolve-PowerShellHostPath
    $processInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $processInfo.WorkingDirectory = [System.IO.Path]::GetTempPath()
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $watchdog = [System.Diagnostics.Process]::Start($processInfo)
    if ($null -eq $watchdog) {
        throw "Failed to start Skillz cleanup watchdog."
    }

    return $watchdog
}

function Start-TrackedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$Transport,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$SkillsRoot
    )

    $jobHandle = New-ProcessCleanupJob
    $process = $null
    $watchdog = $null
    try {
        $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $processInfo.FileName = Resolve-PowerShellHostPath
        $processInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command -"
        $processInfo.WorkingDirectory = $WorkingDirectory
        $processInfo.UseShellExecute = $false
        $processInfo.RedirectStandardInput = $true
        $processInfo.RedirectStandardOutput = $false
        $processInfo.RedirectStandardError = $false
        $processInfo.CreateNoWindow = $false

        $process = [System.Diagnostics.Process]::Start($processInfo)
        if ($null -eq $process) {
            throw "Failed to start tracked process."
        }

        $assigned = [SkillzSetupNativeMethods]::AssignProcessToJobObject(
            $jobHandle,
            $process.Handle
        )
        if (-not $assigned) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            Stop-ProcessTree -ProcessId $process.Id
            throw "Failed to assign process PID $($process.Id) to cleanup Job Object: $(Get-Win32ErrorMessage $errorCode)"
        }

        $watchdog = Start-ParentExitWatchdog `
            -ParentProcessId $PID `
            -RootProcessId $process.Id `
            -RootProcessStartTimeUtcTicks $process.StartTime.ToUniversalTime().Ticks `
            -Transport $Transport `
            -Port $Port `
            -SkillsRoot $SkillsRoot

        $commandScript = @(
            "& $(Format-CommandLine $FileName $Arguments)",
            "exit `$LASTEXITCODE"
        ) -join [Environment]::NewLine
        $process.StandardInput.WriteLine($commandScript)
        $process.StandardInput.Close()

        return [pscustomobject]@{
            Process = $process
            JobHandle = $jobHandle
            WatchdogProcess = $watchdog
        }
    }
    catch {
        if ($null -ne $watchdog -and -not $watchdog.HasExited) {
            Stop-Process -Id $watchdog.Id -Force -ErrorAction SilentlyContinue
            $watchdog.WaitForExit(5000) | Out-Null
        }
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-ProcessTree -ProcessId $process.Id
        }
        Close-NativeHandle $jobHandle
        throw
    }
}

function Invoke-TrackedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$Transport,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$SkillsRoot
    )

    $trackedProcess = $null
    try {
        $trackedProcess = Start-TrackedProcess `
            -FileName $FileName `
            -Arguments $Arguments `
            -WorkingDirectory $WorkingDirectory `
            -Transport $Transport `
            -Port $Port `
            -SkillsRoot $SkillsRoot

        while (-not $trackedProcess.Process.WaitForExit(500)) {
        }

        return $trackedProcess.Process.ExitCode
    }
    finally {
        if ($null -ne $trackedProcess) {
            Close-NativeHandle $trackedProcess.JobHandle
            Stop-TrackedSkillzProcess `
                -TrackedProcess $trackedProcess `
                -Transport $Transport `
                -Port $Port `
                -SkillsRoot $SkillsRoot
        }
    }
}

function Resolve-FirstPythonInterpreter {
    param(
        [Parameter(Mandatory = $true)][string[]]$Candidates,
        [Parameter(Mandatory = $true)][string]$BaseDirectory
    )

    $errors = @()
    foreach ($candidate in $Candidates) {
        try {
            $pythonPath = Resolve-PythonInterpreter `
                -Interpreter $candidate `
                -BaseDirectory $BaseDirectory
            Test-PythonUv $pythonPath
            return $pythonPath
        }
        catch {
            $errors += "${candidate}: $($_.Exception.Message)"
        }
    }

    throw (
        "No usable python.interpreter candidate found. Tried: " +
        ($errors -join "; ")
    )
}

function Read-JsonConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SchemaPath,
        [switch]$SkipSchemaValidation
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path"
    }

    $configJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path

    if (-not $SkipSchemaValidation -and (Test-Path -LiteralPath $SchemaPath)) {
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
        'corsAllowPrivateNetwork',
        'python',
        'logging'
    ) "config"

    $skillsRoot = @(Get-ConfigStringArray $Config "skillsRoot" "skillsRoot" $true)
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

    $corsOrigins = @(Get-ConfigStringArray $Config "corsOrigins" "corsOrigins")
    $allowCredentials = Get-ConfigBoolean $Config "corsAllowCredentials" $false "corsAllowCredentials"
    if ($allowCredentials -and ($corsOrigins -contains "*")) {
        throw "corsAllowCredentials cannot be true when corsOrigins contains '*'."
    }
    $allowPrivateNetwork = Get-ConfigBoolean $Config "corsAllowPrivateNetwork" $false "corsAllowPrivateNetwork"
    if ($allowPrivateNetwork -and ($corsOrigins.Count -eq 0)) {
        throw "corsAllowPrivateNetwork requires at least one corsOrigins entry."
    }
    if ($allowPrivateNetwork -and ($corsOrigins -contains "*")) {
        throw "corsAllowPrivateNetwork cannot be true when corsOrigins contains '*'."
    }

    $pythonConfig = Get-ConfigObject $Config "python" "python"
    if ($null -eq $pythonConfig) {
        throw "Config field 'python' is required."
    }
    Assert-KnownProperties $pythonConfig @("interpreter", "uvSync", "frozen") "config.python"
    $null = @(Get-ConfigStringArray $pythonConfig "interpreter" "python.interpreter" $true)
    $null = Get-ConfigBoolean $pythonConfig "uvSync" $true "python.uvSync"
    $null = Get-ConfigBoolean $pythonConfig "frozen" $true "python.frozen"

    $loggingConfig = Get-ConfigObject $Config "logging" "logging"
    if ($null -ne $loggingConfig) {
        Assert-KnownProperties $loggingConfig @("enableLog", "logDir") "config.logging"
        if ($null -eq (Get-ConfigProperty $loggingConfig "enableLog")) {
            throw "Config field 'logging.enableLog' is required."
        }
        if ($null -eq (Get-ConfigProperty $loggingConfig "logDir")) {
            throw "Config field 'logging.logDir' is required."
        }
        $null = Get-ConfigBoolean $loggingConfig "enableLog" $false "logging.enableLog"
        $null = Get-ConfigString $loggingConfig "logDir" $true "logging.logDir"
    }

    $null = $skillsRoot
    $null = $hostName
}

Initialize-SetupCommandLine -Arguments $script:OriginalArguments

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
$configDirectory = Split-Path -Parent $ConfigPath
$schemaPath = Join-Path $scriptDir "SetupAndRunSchema.json"
$config = Read-JsonConfig `
    -Path $ConfigPath `
    -SchemaPath $schemaPath
Test-SkillzConfig $config

$transport = [string]$config.transport

$skillsRootCandidates = @(Get-ConfigStringArray $config "skillsRoot" "skillsRoot" $true)
$skillsRoot = Resolve-ExistingDirectoryCandidate `
    -Candidates $skillsRootCandidates `
    -BaseDirectory $configDirectory `
    -DisplayName "skillsRoot"
$willLaunch = -not $NoLaunch -and -not $ConfigureOnly
if ($willLaunch) {
    Assert-PortAvailableForLaunch `
        -Transport $transport `
        -Port ([int]$config.port) `
        -SkillsRoot $skillsRoot
}

$pythonConfig = Get-ConfigObject $config "python" "python"
$loggingConfig = Get-ConfigObject $config "logging" "logging"
$frozen = Get-ConfigBoolean $pythonConfig "frozen" $true "python.frozen"
$uvSync = Get-ConfigBoolean $pythonConfig "uvSync" $true "python.uvSync"
$pythonInterpreterCandidates = @(Get-ConfigStringArray $pythonConfig "interpreter" "python.interpreter" $true)
$pythonInterpreter = Resolve-FirstPythonInterpreter `
    -Candidates $pythonInterpreterCandidates `
    -BaseDirectory $configDirectory
$uvCommand = $pythonInterpreter
$uvPrefixArgs = @("-m", "uv")

if ($uvSync) {
    $syncArgs = @($uvPrefixArgs)
    $syncArgs += "sync"
    if ($null -ne $pythonInterpreter) {
        $syncArgs += "--python"
        $syncArgs += $pythonInterpreter
    }
    if ($frozen) {
        $syncArgs += "--frozen"
    }

    $syncCommandLine = Format-CommandLine $uvCommand $syncArgs
    Write-Host "Configuring Python environment in $repoRoot"
    Write-Host "Python environment command: $syncCommandLine"
    Push-Location $repoRoot
    try {
        & $uvCommand @syncArgs
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Host "Skipping Python environment setup"
    if ($PrintCommand) {
        Write-Host "Python environment command: skipped"
    }
}

if ($ConfigureOnly) {
    Write-Host "Configuration phase complete."
    exit 0
}

$runArgs = @($uvPrefixArgs)
$runArgs += "run"
$runArgs += "--directory"
$runArgs += $repoRoot
if ($null -ne $pythonInterpreter) {
    $runArgs += "--python"
    $runArgs += $pythonInterpreter
}
if ($frozen) {
    $runArgs += "--frozen"
}

$runArgs += "skillz"
$runArgs += $skillsRoot
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
    if (Get-ConfigBoolean $config "corsAllowPrivateNetwork" $false "corsAllowPrivateNetwork") {
        $runArgs += "--cors-allow-private-network"
    }
}

if (Get-ConfigBoolean $loggingConfig "enableLog" $false "logging.enableLog") {
    $runArgs += "--log"
    $logDir = Get-ConfigString $loggingConfig "logDir" $false "logging.logDir"
    if ($null -eq $logDir) {
        $logDir = "./logs"
    }
    $runArgs += "--log-file"
    $runArgs += [string](New-LogFilePath `
            -LogDirectory $logDir `
            -BaseDirectory $configDirectory)
}

$commandLine = Format-CommandLine $uvCommand $runArgs
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

Write-Host "Skillz MCP command: $commandLine"

if ($NoLaunch) {
    exit 0
}

Assert-PortAvailableForLaunch `
    -Transport $transport `
    -Port ([int]$config.port) `
    -SkillsRoot $skillsRoot

$exitCode = Invoke-TrackedProcess `
    -FileName $uvCommand `
    -Arguments $runArgs `
    -WorkingDirectory (Get-Location).Path `
    -Transport $transport `
    -Port ([int]$config.port) `
    -SkillsRoot $skillsRoot
exit $exitCode
