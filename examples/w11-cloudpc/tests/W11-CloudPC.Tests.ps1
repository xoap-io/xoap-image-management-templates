# Pester 5 smoke test for the Windows 11 Windows 365 CloudPC golden image (azure-arm).
# Run during the build by the pester-validate action; a failed assertion aborts the build so a
# bad image is never captured to the managed image / Compute Gallery version.
#
# Asserts: client Windows 11 SKU, Azure guest agent + WinRM present, BitLocker is OFF on the OS
# volume (Windows 365 forbids BitLocker in the image), and the Windows 365-required inbox apps
# survived debloat (the -CloudPCSafe path must keep them).

Describe "Windows 11 CloudPC golden image" {

    BeforeAll {
        $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userP   = [System.Environment]::GetEnvironmentVariable('Path', 'User')
        $env:PATH = (@($machine, $userP) | Where-Object { $_ }) -join ';'
    }

    Context "Identity" {
        It "is a client SKU (Windows 11)" {
            (Get-CimInstance Win32_OperatingSystem).Caption | Should -Match "Windows 11"
        }
    }

    Context "Azure platform" {
        It "has the Azure VM guest agent (WindowsAzureGuestAgent) installed" {
            (Get-Service -Name WindowsAzureGuestAgent -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Remote management" {
        It "has WinRM running" {
            (Get-Service -Name WinRM).Status | Should -Be 'Running'
        }
    }

    Context "BitLocker (must be OFF for Windows 365)" {
        It "has BitLocker OFF on the OS volume" {
            # Prefer the BitLocker cmdlet; fall back to manage-bde if the module is unavailable.
            $status = $null
            if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
                $status = (Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue).ProtectionStatus
                $status | Should -Be 'Off'
            }
            else {
                $out = & manage-bde.exe -status $env:SystemDrive 2>$null | Out-String
                $out | Should -Match 'Protection\s+Off'
            }
        }
    }

    Context "Windows 365-required inbox apps (kept by -CloudPCSafe debloat)" {
        It "has the Microsoft Store (WindowsStore) present" {
            (Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like '*WindowsStore*' }) | Should -Not -BeNullOrEmpty
        }
        It "has the .NET / VCLibs Store dependency framework present" {
            (Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like '*VCLibs*' }) | Should -Not -BeNullOrEmpty
        }
    }
}
