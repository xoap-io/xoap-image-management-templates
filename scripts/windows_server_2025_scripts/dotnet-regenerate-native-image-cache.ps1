# Optimized .NET native image cache regeneration for Windows Server 2022

$ErrorActionPreference = 'Stop'

try {
    if ([Environment]::Is64BitOperatingSystem) {
        Log "Updating and executing queued items for 64-bit .NET Framework..."
        Invoke-Expression "$env:windir\microsoft.net\framework\v4.0.30319\ngen.exe update /force /queue"
        Invoke-Expression "$env:windir\microsoft.net\framework64\v4.0.30319\ngen.exe update /force /queue"
        Invoke-Expression "$env:windir\microsoft.net\framework\v4.0.30319\ngen.exe executequeueditems"
        Invoke-Expression "$env:windir\microsoft.net\framework64\v4.0.30319\ngen.exe executequeueditems"
    } else {
        Log "Updating and executing queued items for 32-bit .NET Framework..."
        Invoke-Expression "$env:windir\microsoft.net\framework\v4.0.30319\ngen.exe update /force /queue"
        Invoke-Expression "$env:windir\microsoft.net\framework\v4.0.30319\ngen.exe executequeueditems"
    }
    Log ".NET native image cache regeneration complete."
} catch {
    Log "Error: $($_.Exception.Message)"
    exit 1
}
