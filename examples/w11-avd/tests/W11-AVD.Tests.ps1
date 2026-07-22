# Pester 5 smoke test for the Windows 11 multi-session AVD golden image (azure-arm).
# Run during the build by the pester-validate action; a failed assertion aborts the build so a
# bad image is never captured to the managed image / Compute Gallery version.
#
# Asserts: client Windows 11 SKU, Azure guest agent + WinRM present, and the AVD-specific
# configuration this set installs — FSLogix service + profile-container registry, and the
# Teams/AVD IsWVDEnvironment marker.

Describe "Windows 11 AVD golden image" {

    BeforeAll {
        # A WinRM session inherits the PATH from when the WinRM service started, so it does not
        # see machine-PATH updates made during this build. Rebuild PATH from the registry so
        # Get-Command resolves tools the same way a fresh login would.
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

    Context "FSLogix profile containers" {
        It "has the FSLogix service (frxsvc) installed" {
            (Get-Service -Name frxsvc -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        }
        It "has the FSLogix Profiles registry key present" {
            Test-Path 'HKLM:\SOFTWARE\FSLogix\Profiles' | Should -Be $true
        }
    }

    Context "Teams / AVD environment" {
        It "is marked as a WVD/AVD environment (IsWVDEnvironment=1)" {
            $key = 'HKLM:\SOFTWARE\Microsoft\Teams'
            (Get-ItemProperty -Path $key -Name IsWVDEnvironment -ErrorAction SilentlyContinue).IsWVDEnvironment | Should -Be 1
        }
    }
}
