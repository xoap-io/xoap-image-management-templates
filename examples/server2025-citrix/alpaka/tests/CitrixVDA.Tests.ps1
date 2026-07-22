# Pester 5 validation for the Windows Server 2025 Citrix VDA (Server/MCS) master image.
# Run in-build by the pester-validate action; a failed assertion aborts the build so a
# broken master image is never converted to a template / captured for an MCS catalog.

Describe "Windows Server 2025 Citrix VDA master image" {

    Context "Identity" {
        It "is a Server SKU (Windows Server 2025)" {
            (Get-CimInstance Win32_OperatingSystem).Caption | Should -Match "Windows Server 2025"
        }
    }

    Context "Citrix VDA" {
        It "has a Citrix VDA service installed (BrokerAgent / CitrixWakeupAgent)" {
            $svc = Get-Service -Name 'BrokerAgent', 'CitrixWakeupAgent' -ErrorAction SilentlyContinue
            $svc | Should -Not -BeNullOrEmpty
        }
        It "has the Citrix Virtual Desktop Agent registry key" {
            Test-Path 'HKLM:\SOFTWARE\Citrix\VirtualDesktopAgent' | Should -Be $true
        }
        It "records an installed Citrix VDA product in the uninstall registry" {
            $paths = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )
            $vda = Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match 'Citrix.*Virtual Delivery Agent' }
            $vda | Should -Not -BeNullOrEmpty
        }
    }

    Context "Remote management" {
        It "has WinRM running" {
            (Get-Service -Name WinRM).Status | Should -Be 'Running'
        }
    }
}
