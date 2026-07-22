# Pester 5 validation for the Windows 11 Citrix VDA + PVS target-device master image.
# Run in-build by the pester-validate action; a failed assertion aborts the build so a
# broken PVS master is never generalized / streamed as a vDisk.

Describe "Windows 11 Citrix VDA + PVS target-device master image" {

    Context "Identity" {
        It "is a client SKU (Windows 11)" {
            (Get-CimInstance Win32_OperatingSystem).Caption | Should -Match "Windows 11"
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
    }

    Context "PVS target-device readiness" {
        It "has a system-managed pagefile (Prepare_For_Citrix_PVS configures it via CIM)" {
            (Get-CimInstance -ClassName Win32_ComputerSystem).AutomaticManagedPagefile | Should -Be $true
        }
    }

    Context "Remote management" {
        It "has WinRM running" {
            (Get-Service -Name WinRM).Status | Should -Be 'Running'
        }
    }
}
