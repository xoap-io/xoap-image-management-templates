# Pester 5 validation for the Windows 11 Enterprise Hyper-V (Gen2) base golden image.
# Staged + run in-build by the pester-validate action BEFORE sysprep; a failed assertion aborts the
# build so a bad image is never captured.

Describe "Windows 11 Hyper-V base golden image" {

    Context "Identity / OS build" {
        It "is a client SKU (Windows 11)" {
            (Get-CimInstance Win32_OperatingSystem).Caption | Should -Match "Windows 11"
        }
    }

    Context "Guest tools" {
        It "has the Hyper-V Data Exchange (integration) service present" {
            (Get-Service -Name vmickvpexchange -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
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
