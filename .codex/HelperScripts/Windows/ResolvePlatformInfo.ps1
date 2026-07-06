[CmdletBinding()]
param()

function Resolve-CodexPlatformInfo {
    [CmdletBinding()]
    param()

    $isWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows
    )
    $isLinux = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Linux
    )
    $isMacOS = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::OSX
    )

    $osName = if ($isWindows) {
        'Windows'
    }
    elseif ($isLinux) {
        'Linux'
    }
    elseif ($isMacOS) {
        'macOS'
    }
    else {
        'Unknown'
    }

    $rawArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    $isa = switch -Regex ($rawArchitecture) {
        '^(X64|Amd64)$' { 'AMD64'; break }
        '^(Arm64|AArch64)$' { 'ARM64'; break }
        default { $rawArchitecture }
    }

    [pscustomobject][ordered]@{
        OS = $osName
        OSVersion = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
        ISA = $isa
        RawArchitecture = $rawArchitecture
    }
}
