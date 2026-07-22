# Pester 5 validation for the Windows Server 2022 vsphere-iso base golden image.
# Staged + run in-build by the pester-validate action BEFORE sysprep; a failed assertion aborts the
# build so a bad template is never captured.

Describe "Windows Server 2022 vSphere base golden image" {

    Context "Identity / OS build" {
        It "is a Server SKU (Windows Server 2022)" {
            (Get-CimInstance Win32_OperatingSystem).Caption | Should -Match "Windows Server 2022"
        }
        It "reports the 10.0.20348 (Server 2022) build" {
            (Get-CimInstance Win32_OperatingSystem).Version | Should -Match "^10\.0\.20348"
        }
    }

    Context "Generalize readiness" {
        It "has the Sysprep tool present" {
            Test-Path 'C:\Windows\System32\Sysprep\sysprep.exe' | Should -Be $true
        }
        It "is not already generalized (no prior sysprep state)" {
            (Get-ItemProperty 'HKLM:\SYSTEM\Setup\Status\SysprepStatus' -ErrorAction SilentlyContinue).GeneralizationState | Should -Not -Be 4
        }
    }

    Context "Remote management" {
        It "has WinRM running" {
            (Get-Service -Name WinRM).Status | Should -Be 'Running'
        }
    }
}
