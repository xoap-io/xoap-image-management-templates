<#
.SYNOPSIS
    Manage Certificates for Windows Server

.DESCRIPTION
    Imports, exports, and manages certificates in Windows certificate stores.
    Supports PFX, CER, P7B formats, certificate validation, and automated
    deployment. Optimized for Windows Server 2025 and Packer workflows.

.NOTES
    File Name      : windows-server-Manage_Certificates.ps1
    Prerequisite   : PowerShell 5.1 or higher, Administrator privileges
    Copyright      : XOAP.io
    
.EXAMPLE
    .\windows-server-Manage_Certificates.ps1 -ImportPFX -CertificatePath "C:\certs\server.pfx" -Password "P@ssw0rd" -Store "My" -StoreLocation "LocalMachine"
    Imports a PFX certificate into the local machine personal store
    
.EXAMPLE
    .\windows-server-Manage_Certificates.ps1 -ImportCER -CertificatePath "C:\certs\ca.cer" -Store "Root" -StoreLocation "LocalMachine"
    Imports a CA certificate into the trusted root store
    
.EXAMPLE
    .\windows-server-Manage_Certificates.ps1 -ExportCertificate -Thumbprint "A1B2C3..." -OutputPath "C:\export\cert.cer"
    Exports a certificate by thumbprint
    
.PARAMETER ImportPFX
    Import a PFX certificate file
    
.PARAMETER ImportCER
    Import a CER certificate file
    
.PARAMETER ExportCertificate
    Export a certificate
    
.PARAMETER CertificatePath
    Path to the certificate file
    
.PARAMETER Password
    Password for PFX certificate
    
.PARAMETER Store
    Certificate store name (My, Root, CA, TrustedPublisher, etc.)
    
.PARAMETER StoreLocation
    Store location (LocalMachine or CurrentUser)
    
.PARAMETER Thumbprint
    Certificate thumbprint
    
.PARAMETER OutputPath
    Output path for exported certificate
    
.PARAMETER ValidateCertificates
    Validate all certificates in stores
    
.PARAMETER RemoveExpired
    Remove expired certificates
#>

[CmdletBinding()]
param(
    [switch]$ImportPFX,
    [switch]$ImportCER,
    [switch]$ExportCertificate,
    [string]$CertificatePath,
    [securestring]$Password,
    [string]$PasswordPlainText,
    [ValidateSet('My', 'Root', 'CA', 'TrustedPublisher', 'TrustedPeople', 'Trust', 'Disallowed')]
    [string]$Store = 'My',
    [ValidateSet('LocalMachine', 'CurrentUser')]
    [string]$StoreLocation = 'LocalMachine',
    [string]$Thumbprint,
    [string]$OutputPath,
    [switch]$ValidateCertificates,
    [switch]$RemoveExpired,
    [switch]$ExportPrivateKey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$LogDir = 'C:\xoap-logs'
$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$scriptName-$timestamp.log"

# Statistics tracking
$script:CertificatesImported = 0
$script:CertificatesExported = 0
$script:CertificatesRemoved = 0
$script:OperationsFailed = 0

#region Helper Functions

$script:Component = 'Certificates'
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = "[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $script:Component, $Message
    Write-Host $line
}

$LogDir = 'C:\xoap-logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDir ("{0}-{1}.log" -f [IO.Path]::GetFileNameWithoutExtension($PSCommandPath), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $script:LogFile -Append | Out-Null
} catch { Write-Host ("[{0}] [WARN] [Certificates] Transcript unavailable: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) }

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

#endregion

#region Certificate Import

function Import-PFXCertificate {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [securestring]$CertPassword,
        
        [Parameter(Mandatory)]
        [string]$StoreName,
        
        [Parameter(Mandatory)]
        [string]$Location
    )
    
    Write-Log "Importing PFX certificate from: $Path" -Level INFO
    
    try {
        # Validate file exists
        if (-not (Test-Path $Path)) {
            Write-Log "Certificate file not found: $Path" -Level ERROR
            $script:OperationsFailed++
            return $false
        }
        
        # Import certificate
        $importParams = @{
            FilePath = $Path
            CertStoreLocation = "Cert:\$Location\$StoreName"
            Exportable = $true
        }
        
        if ($CertPassword) {
            $importParams['Password'] = $CertPassword
        }
        
        $cert = Import-PfxCertificate @importParams -ErrorAction Stop
        
        Write-Log "  [OK] Certificate imported successfully" -Level INFO
        Write-Log "    Subject: $($cert.Subject)" -Level INFO
        Write-Log "    Thumbprint: $($cert.Thumbprint)" -Level INFO
        Write-Log "    Issuer: $($cert.Issuer)" -Level INFO
        Write-Log "    Valid From: $($cert.NotBefore)" -Level INFO
        Write-Log "    Valid To: $($cert.NotAfter)" -Level INFO
        
        # Check if expired
        if ($cert.NotAfter -lt (Get-Date)) {
            Write-Log "    [WARN] WARNING: Certificate is expired!" -Level WARN
        }
        
        # Check validity period
        $daysRemaining = ($cert.NotAfter - (Get-Date)).Days
        if ($daysRemaining -lt 30 -and $daysRemaining -gt 0) {
            Write-Log "    [WARN] WARNING: Certificate expires in $daysRemaining days" -Level WARN
        }
        
        $script:CertificatesImported++
        return $true
    }
    catch {
        Write-Log "  [FAIL] Error importing PFX certificate: $($_.Exception.Message)" -Level ERROR
        $script:OperationsFailed++
        return $false
    }
}

function Import-CERCertificate {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$StoreName,
        
        [Parameter(Mandatory)]
        [string]$Location
    )
    
    Write-Log "Importing CER certificate from: $Path" -Level INFO
    
    try {
        # Validate file exists
        if (-not (Test-Path $Path)) {
            Write-Log "Certificate file not found: $Path" -Level ERROR
            $script:OperationsFailed++
            return $false
        }
        
        # Import certificate
        $cert = Import-Certificate -FilePath $Path -CertStoreLocation "Cert:\$Location\$StoreName" -ErrorAction Stop
        
        Write-Log "  [OK] Certificate imported successfully" -Level INFO
        Write-Log "    Subject: $($cert.Subject)" -Level INFO
        Write-Log "    Thumbprint: $($cert.Thumbprint)" -Level INFO
        Write-Log "    Issuer: $($cert.Issuer)" -Level INFO
        
        $script:CertificatesImported++
        return $true
    }
    catch {
        Write-Log "  [FAIL] Error importing CER certificate: $($_.Exception.Message)" -Level ERROR
        $script:OperationsFailed++
        return $false
    }
}

function Import-CertificateChain {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$Location
    )
    
    Write-Log "Importing certificate chain from: $Path" -Level INFO
    
    try {
        # Import root CA to Root store
        $rootCert = Import-Certificate -FilePath $Path -CertStoreLocation "Cert:\$Location\Root" -ErrorAction Stop
        Write-Log "  [OK] Root CA imported to Trusted Root store" -Level INFO
        
        # Import intermediate to CA store
        $intermediateCert = Import-Certificate -FilePath $Path -CertStoreLocation "Cert:\$Location\CA" -ErrorAction SilentlyContinue
        if ($intermediateCert) {
            Write-Log "  [OK] Intermediate CA imported to Intermediate CA store" -Level INFO
        }
        
        $script:CertificatesImported++
        return $true
    }
    catch {
        Write-Log "  [FAIL] Error importing certificate chain: $($_.Exception.Message)" -Level ERROR
        $script:OperationsFailed++
        return $false
    }
}

#endregion

#region Certificate Export

function Export-Certificate {
    param(
        [Parameter(Mandatory)]
        [string]$CertThumbprint,
        
        [Parameter(Mandatory)]
        [string]$Output,
        
        [switch]$IncludePrivateKey
    )
    
    Write-Log "Exporting certificate with thumbprint: $CertThumbprint" -Level INFO
    
    try {
        # Find certificate
        $cert = Get-ChildItem -Path Cert:\LocalMachine\My, Cert:\LocalMachine\Root, Cert:\LocalMachine\CA -Recurse |
            Where-Object { $_.Thumbprint -eq $CertThumbprint } |
            Select-Object -First 1
        
        if (-not $cert) {
            Write-Log "Certificate not found: $CertThumbprint" -Level ERROR
            $script:OperationsFailed++
            return $false
        }
        
        Write-Log "  Found certificate: $($cert.Subject)" -Level INFO
        
        # Create output directory if needed
        $outputDir = Split-Path -Path $Output -Parent
        if ($outputDir -and (-not (Test-Path $outputDir))) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        
        if ($IncludePrivateKey) {
            # Export with private key (PFX)
            if (-not $cert.HasPrivateKey) {
                Write-Log "  [WARN] Certificate does not have a private key" -Level WARN
                $IncludePrivateKey = $false
            }
            else {
                # Generate password for export
                $exportPassword = ConvertTo-SecureString -String "ExportPassword123!" -AsPlainText -Force
                
                Export-PfxCertificate -Cert $cert -FilePath $Output -Password $exportPassword -ErrorAction Stop | Out-Null
                
                Write-Log "  [OK] Certificate exported with private key (PFX)" -Level INFO
                Write-Log "    Export password: ExportPassword123!" -Level WARN
                Write-Log "    Output: $Output" -Level INFO
                
                $script:CertificatesExported++
                return $true
            }
        }
        
        # Export without private key (CER)
        Export-Certificate -Cert $cert -FilePath $Output -ErrorAction Stop | Out-Null
        
        Write-Log "  [OK] Certificate exported (CER)" -Level INFO
        Write-Log "    Output: $Output" -Level INFO
        
        $script:CertificatesExported++
        return $true
    }
    catch {
        Write-Log "  [FAIL] Error exporting certificate: $($_.Exception.Message)" -Level ERROR
        $script:OperationsFailed++
        return $false
    }
}

#endregion

#region Certificate Validation

function Test-Certificate {
    param(
        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )
    
    $issues = @()
    
    # Check if expired
    if ($Certificate.NotAfter -lt (Get-Date)) {
        $issues += "EXPIRED (expired on $($Certificate.NotAfter.ToString('yyyy-MM-dd')))"
    }
    
    # Check if not yet valid
    if ($Certificate.NotBefore -gt (Get-Date)) {
        $issues += "NOT YET VALID (valid from $($Certificate.NotBefore.ToString('yyyy-MM-dd')))"
    }
    
    # Check expiration within 30 days
    $daysRemaining = ($Certificate.NotAfter - (Get-Date)).Days
    if ($daysRemaining -lt 30 -and $daysRemaining -gt 0) {
        $issues += "EXPIRES SOON ($daysRemaining days remaining)"
    }
    
    # Check for self-signed
    if ($Certificate.Subject -eq $Certificate.Issuer) {
        $issues += "SELF-SIGNED"
    }
    
    # Check private key
    if (-not $Certificate.HasPrivateKey) {
        $issues += "NO PRIVATE KEY"
    }
    
    return $issues
}

function Get-CertificateValidationReport {
    Write-Log "Validating certificates..." -Level INFO
    
    $stores = @(
        @{ Name = 'My'; Location = 'LocalMachine'; Description = 'Personal' }
        @{ Name = 'Root'; Location = 'LocalMachine'; Description = 'Trusted Root CA' }
        @{ Name = 'CA'; Location = 'LocalMachine'; Description = 'Intermediate CA' }
        @{ Name = 'TrustedPublisher'; Location = 'LocalMachine'; Description = 'Trusted Publishers' }
    )
    
    $allIssues = @()
    
    foreach ($storeInfo in $stores) {
        Write-Log "Checking store: $($storeInfo.Description) (Cert:\$($storeInfo.Location)\$($storeInfo.Name))" -Level INFO
        
        try {
            $certs = Get-ChildItem -Path "Cert:\$($storeInfo.Location)\$($storeInfo.Name)" -ErrorAction Stop
            
            if ($certs.Count -eq 0) {
                Write-Log "  No certificates found" -Level INFO
                continue
            }
            
            Write-Log "  Found $($certs.Count) certificate(s)" -Level INFO
            
            foreach ($cert in $certs) {
                $issues = Test-Certificate -Certificate $cert
                
                if ($issues.Count -gt 0) {
                    Write-Log "  [WARN] $($cert.Subject)" -Level WARN
                    Write-Log "    Thumbprint: $($cert.Thumbprint)" -Level WARN
                    Write-Log "    Issues: $($issues -join ', ')" -Level WARN
                    
                    $allIssues += [PSCustomObject]@{
                        Store = $storeInfo.Description
                        Subject = $cert.Subject
                        Thumbprint = $cert.Thumbprint
                        Issues = $issues -join ', '
                        NotAfter = $cert.NotAfter
                    }
                }
                else {
                    Write-Log "  [OK] $($cert.Subject)" -Level INFO
                }
            }
        }
        catch {
            Write-Log "  [FAIL] Error checking store: $($_.Exception.Message)" -Level ERROR
        }
    }
    
    return $allIssues
}

#endregion

#region Certificate Cleanup

function Remove-ExpiredCertificates {
    Write-Log "Removing expired certificates..." -Level INFO
    
    $stores = @('My', 'Root', 'CA', 'TrustedPublisher')
    $location = 'LocalMachine'
    
    foreach ($storeName in $stores) {
        Write-Log "Checking store: $storeName" -Level INFO
        
        try {
            $certs = Get-ChildItem -Path "Cert:\$location\$storeName" -ErrorAction Stop
            $expiredCerts = $certs | Where-Object { $_.NotAfter -lt (Get-Date) }
            
            if ($expiredCerts.Count -eq 0) {
                Write-Log "  No expired certificates found" -Level INFO
                continue
            }
            
            Write-Log "  Found $($expiredCerts.Count) expired certificate(s)" -Level WARN
            
            foreach ($cert in $expiredCerts) {
                try {
                    Remove-Item -Path "Cert:\$location\$storeName\$($cert.Thumbprint)" -Force -ErrorAction Stop
                    
                    Write-Log "  [OK] Removed: $($cert.Subject)" -Level INFO
                    Write-Log "    Expired: $($cert.NotAfter.ToString('yyyy-MM-dd'))" -Level INFO
                    
                    $script:CertificatesRemoved++
                }
                catch {
                    Write-Log "  [FAIL] Failed to remove: $($cert.Subject) - $($_.Exception.Message)" -Level ERROR
                    $script:OperationsFailed++
                }
            }
        }
        catch {
            Write-Log "  [FAIL] Error accessing store: $($_.Exception.Message)" -Level ERROR
        }
    }
}

#endregion

#region Certificate Reporting

function Get-CertificateInventory {
    Write-Log "Generating certificate inventory..." -Level INFO
    
    $inventory = @()
    
    $stores = @(
        @{ Name = 'My'; Location = 'LocalMachine'; Description = 'Personal' }
        @{ Name = 'Root'; Location = 'LocalMachine'; Description = 'Trusted Root CA' }
        @{ Name = 'CA'; Location = 'LocalMachine'; Description = 'Intermediate CA' }
        @{ Name = 'TrustedPublisher'; Location = 'LocalMachine'; Description = 'Trusted Publishers' }
    )
    
    foreach ($storeInfo in $stores) {
        try {
            $certs = Get-ChildItem -Path "Cert:\$($storeInfo.Location)\$($storeInfo.Name)" -ErrorAction Stop
            
            foreach ($cert in $certs) {
                $daysRemaining = ($cert.NotAfter - (Get-Date)).Days
                $status = if ($cert.NotAfter -lt (Get-Date)) { 'Expired' } 
                         elseif ($daysRemaining -lt 30) { 'Expiring Soon' }
                         else { 'Valid' }
                
                $inventory += [PSCustomObject]@{
                    Store = $storeInfo.Description
                    Subject = $cert.Subject
                    Issuer = $cert.Issuer
                    Thumbprint = $cert.Thumbprint
                    NotBefore = $cert.NotBefore
                    NotAfter = $cert.NotAfter
                    DaysRemaining = $daysRemaining
                    Status = $status
                    HasPrivateKey = $cert.HasPrivateKey
                }
            }
        }
        catch {
            Write-Log "Error accessing store $($storeInfo.Description): $($_.Exception.Message)" -Level WARN
        }
    }
    
    return $inventory
}

function Save-CertificateReport {
    Write-Log "Saving certificate report..." -Level INFO
    
    try {
        $reportFile = Join-Path $LogDir "certificates-$timestamp.txt"
        $report = @()
        
        $report += "Certificate Management Report"
        $report += "=" * 80
        $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $report += "Computer: $env:COMPUTERNAME"
        $report += ""
        
        # Session statistics
        $report += "Session Summary:"
        $report += "  Certificates Imported: $script:CertificatesImported"
        $report += "  Certificates Exported: $script:CertificatesExported"
        $report += "  Certificates Removed: $script:CertificatesRemoved"
        $report += "  Operations Failed: $script:OperationsFailed"
        $report += ""
        
        # Certificate inventory
        $inventory = Get-CertificateInventory
        
        $report += "Certificate Inventory:"
        $report += "-" * 80
        
        $groupedByStore = $inventory | Group-Object -Property Store
        
        foreach ($group in $groupedByStore) {
            $report += ""
            $report += "Store: $($group.Name) ($($group.Count) certificates)"
            $report += ""
            
            foreach ($cert in $group.Group) {
                $report += "  Subject: $($cert.Subject)"
                $report += "  Thumbprint: $($cert.Thumbprint)"
                $report += "  Issuer: $($cert.Issuer)"
                $report += "  Valid: $($cert.NotBefore.ToString('yyyy-MM-dd')) to $($cert.NotAfter.ToString('yyyy-MM-dd'))"
                $report += "  Status: $($cert.Status) ($($cert.DaysRemaining) days remaining)"
                $report += "  Private Key: $($cert.HasPrivateKey)"
                $report += ""
            }
        }
        
        # Issues summary
        $issues = $inventory | Where-Object { $_.Status -ne 'Valid' }
        if ($issues) {
            $report += ""
            $report += "Certificates Requiring Attention:"
            $report += "-" * 80
            
            foreach ($issue in $issues) {
                $report += "  $($issue.Subject) - $($issue.Status)"
                $report += "    Store: $($issue.Store)"
                $report += "    Expires: $($issue.NotAfter.ToString('yyyy-MM-dd'))"
                $report += ""
            }
        }
        
        $report -join "`n" | Set-Content -Path $reportFile -Force
        
        Write-Log "Certificate report saved to: $reportFile" -Level INFO
        return $true
    }
    catch {
        Write-Log "Error generating report: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

#endregion

#region Main Execution

function Main {
    $scriptStartTime = Get-Date

    Write-Log "===== Manage_Certificates starting ====="
    Write-Log "Log File: $LogFile"

    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-Log "This script requires Administrator privileges" -Level ERROR
        exit 1
    }
    
    # Convert plain text password to secure string if provided
    if ($PasswordPlainText) {
        $Password = ConvertTo-SecureString -String $PasswordPlainText -AsPlainText -Force
    }
    
    # Process operations
    $operationPerformed = $false
    
    # Import PFX
    if ($ImportPFX) {
        if (-not $CertificatePath) {
            Write-Log "CertificatePath parameter is required for import operations" -Level ERROR
            exit 1
        }
        
        Import-PFXCertificate -Path $CertificatePath -CertPassword $Password -StoreName $Store -Location $StoreLocation
        $operationPerformed = $true
    }
    
    # Import CER
    if ($ImportCER) {
        if (-not $CertificatePath) {
            Write-Log "CertificatePath parameter is required for import operations" -Level ERROR
            exit 1
        }
        
        Import-CERCertificate -Path $CertificatePath -StoreName $Store -Location $StoreLocation
        $operationPerformed = $true
    }
    
    # Export certificate
    if ($ExportCertificate) {
        if (-not $Thumbprint -or -not $OutputPath) {
            Write-Log "Thumbprint and OutputPath parameters are required for export operations" -Level ERROR
            exit 1
        }
        
        Export-Certificate -CertThumbprint $Thumbprint -Output $OutputPath -IncludePrivateKey:$ExportPrivateKey
        $operationPerformed = $true
    }
    
    # Validate certificates
    if ($ValidateCertificates) {
        $issues = Get-CertificateValidationReport
        
        if ($issues.Count -gt 0) {
            Write-Log "Found $($issues.Count) certificate(s) with issues" -Level WARN
        }
        else {
            Write-Log "All certificates are valid" -Level INFO
        }
        
        $operationPerformed = $true
    }
    
    # Remove expired certificates
    if ($RemoveExpired) {
        Remove-ExpiredCertificates
        $operationPerformed = $true
    }
    
    # If no operation specified, show inventory
    if (-not $operationPerformed) {
        Write-Log "No operation specified, generating certificate inventory..." -Level INFO
        
        Get-CertificateValidationReport | Out-Null
    }
    
    # Generate report
    Save-CertificateReport | Out-Null
    
    if ($script:OperationsFailed -eq 0) {
        Write-Log "===== Manage_Certificates complete in $([int]((Get-Date) - $scriptStartTime).TotalSeconds)s; imported=$script:CertificatesImported exported=$script:CertificatesExported removed=$script:CertificatesRemoved failed=$script:OperationsFailed ====="
        exit 0
    }
    else {
        Write-Log "===== Manage_Certificates complete in $([int]((Get-Date) - $scriptStartTime).TotalSeconds)s; imported=$script:CertificatesImported exported=$script:CertificatesExported removed=$script:CertificatesRemoved failed=$script:OperationsFailed =====" -Level WARN
        exit 1
    }
}

# Execute main function
try {
    Main
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}

#endregion
