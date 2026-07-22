# Pester 5 validation for the Windows Server 2025 AVD / RDSH multi-session host image.
# Staged + run in-build by the pester-validate action BEFORE sysprep; a failed assertion aborts
# the build so a bad image is never captured to the managed image / gallery version.

Describe "Windows Server 2025 AVD/RDSH golden image" {

    Context "Identity" {
        It "is a Server SKU (Windows Server 2025)" {
            (Get-CimInstance Win32_OperatingSystem).Caption | Should -Match "Windows Server 2025"
        }
    }

    Context "RD Session Host role" {
        It "has the RDS-RD-Server feature installed" {
            (Get-WindowsFeature -Name RDS-RD-Server).InstallState | Should -Be 'Installed'
        }
    }

    Context "FSLogix" {
        It "has the FSLogix Apps agent installed" {
            Test-Path 'C:\Program Files\FSLogix\Apps' | Should -Be $true
        }
        It "has the FSLogix profile-container config key" {
            Test-Path 'HKLM:\SOFTWARE\FSLogix\Profiles' | Should -Be $true
        }
    }

    Context "Remote management" {
        It "has WinRM running" {
            (Get-Service -Name WinRM).Status | Should -Be 'Running'
        }
    }
}
