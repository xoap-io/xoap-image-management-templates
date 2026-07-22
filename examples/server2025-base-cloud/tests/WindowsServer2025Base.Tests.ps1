# Pester 5 validation for the Windows Server 2025 azure-arm cloud base image.
# Staged + run during the build by the pester-validate action; a failed assertion aborts the
# build so a non-compliant image is never captured to the managed image / gallery version.
#
# Asserts the three baseline outcomes this set promises: CIS hardening applied, legacy SMBv1
# removed, and the Azure guest tools installed.

Describe "Windows Server 2025 azure-arm cloud base image" {

    Context "Identity" {
        It "is a Server SKU (Windows Server 2025)" {
            (Get-CimInstance Win32_OperatingSystem).Caption | Should -Match "Windows Server 2025"
        }
    }

    Context "CIS hardening (Apply_CIS_Benchmarks)" {
        It "enforces UAC (EnableLUA = 1)" {
            (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA).EnableLUA | Should -Be 1
        }
        It "requires SMB server security signatures (RequireSecuritySignature = 1)" {
            (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name RequireSecuritySignature).RequireSecuritySignature | Should -Be 1
        }
    }

    Context "Legacy protocols (Disable_SMBv1_Legacy)" {
        It "has SMBv1 disabled on the SMB server" {
            (Get-SmbServerConfiguration).EnableSMB1Protocol | Should -Be $false
        }
        It "sets a strong LmCompatibilityLevel (>= 3)" {
            (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LmCompatibilityLevel).LmCompatibilityLevel | Should -BeGreaterOrEqual 3
        }
    }

    Context "Azure guest tools (Install_Azure_Tools)" {
        It "has the Azure VM guest agent or Az PowerShell module present" {
            $agent  = Get-Service -Name WindowsAzureGuestAgent -ErrorAction SilentlyContinue
            $module = Get-Module -ListAvailable -Name Az.Accounts -ErrorAction SilentlyContinue
            ($agent -ne $null -or $module -ne $null) | Should -Be $true
        }
    }
}
