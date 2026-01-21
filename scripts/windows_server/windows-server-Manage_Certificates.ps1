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

function Write-LogMessage {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
    
    switch ($Level) {
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage }
    }
}

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
    
    Write-LogMessage "Importing PFX certificate from: $Path" -Level Info
    
    try {
        # Validate file exists
        if (-not (Test-Path $Path)) {
            Write-LogMessage "Certificate file not found: $Path" -Level Error
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
        
        Write-LogMessage "  ✓ Certificate imported successfully" -Level Success
        Write-LogMessage "    Subject: $($cert.Subject)" -Level Info
        Write-LogMessage "    Thumbprint: $($cert.Thumbprint)" -Level Info
        Write-LogMessage "    Issuer: $($cert.Issuer)" -Level Info
        Write-LogMessage "    Valid From: $($cert.NotBefore)" -Level Info
        Write-LogMessage "    Valid To: $($cert.NotAfter)" -Level Info
        
        # Check if expired
        if ($cert.NotAfter -lt (Get-Date)) {
            Write-LogMessage "    ⚠ WARNING: Certificate is expired!" -Level Warning
        }
        
        # Check validity period
        $daysRemaining = ($cert.NotAfter - (Get-Date)).Days
        if ($daysRemaining -lt 30 -and $daysRemaining -gt 0) {
            Write-LogMessage "    ⚠ WARNING: Certificate expires in $daysRemaining days" -Level Warning
        }
        
        $script:CertificatesImported++
        return $true
    }
    catch {
        Write-LogMessage "  ✗ Error importing PFX certificate: $($_.Exception.Message)" -Level Error
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
    
    Write-LogMessage "Importing CER certificate from: $Path" -Level Info
    
    try {
        # Validate file exists
        if (-not (Test-Path $Path)) {
            Write-LogMessage "Certificate file not found: $Path" -Level Error
            $script:OperationsFailed++
            return $false
        }
        
        # Import certificate
        $cert = Import-Certificate -FilePath $Path -CertStoreLocation "Cert:\$Location\$StoreName" -ErrorAction Stop
        
        Write-LogMessage "  ✓ Certificate imported successfully" -Level Success
        Write-LogMessage "    Subject: $($cert.Subject)" -Level Info
        Write-LogMessage "    Thumbprint: $($cert.Thumbprint)" -Level Info
        Write-LogMessage "    Issuer: $($cert.Issuer)" -Level Info
        
        $script:CertificatesImported++
        return $true
    }
    catch {
        Write-LogMessage "  ✗ Error importing CER certificate: $($_.Exception.Message)" -Level Error
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
    
    Write-LogMessage "Importing certificate chain from: $Path" -Level Info
    
    try {
        # Import root CA to Root store
        $rootCert = Import-Certificate -FilePath $Path -CertStoreLocation "Cert:\$Location\Root" -ErrorAction Stop
        Write-LogMessage "  ✓ Root CA imported to Trusted Root store" -Level Success
        
        # Import intermediate to CA store
        $intermediateCert = Import-Certificate -FilePath $Path -CertStoreLocation "Cert:\$Location\CA" -ErrorAction SilentlyContinue
        if ($intermediateCert) {
            Write-LogMessage "  ✓ Intermediate CA imported to Intermediate CA store" -Level Success
        }
        
        $script:CertificatesImported++
        return $true
    }
    catch {
        Write-LogMessage "  ✗ Error importing certificate chain: $($_.Exception.Message)" -Level Error
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
    
    Write-LogMessage "Exporting certificate with thumbprint: $CertThumbprint" -Level Info
    
    try {
        # Find certificate
        $cert = Get-ChildItem -Path Cert:\LocalMachine\My, Cert:\LocalMachine\Root, Cert:\LocalMachine\CA -Recurse |
            Where-Object { $_.Thumbprint -eq $CertThumbprint } |
            Select-Object -First 1
        
        if (-not $cert) {
            Write-LogMessage "Certificate not found: $CertThumbprint" -Level Error
            $script:OperationsFailed++
            return $false
        }
        
        Write-LogMessage "  Found certificate: $($cert.Subject)" -Level Info
        
        # Create output directory if needed
        $outputDir = Split-Path -Path $Output -Parent
        if ($outputDir -and (-not (Test-Path $outputDir))) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        
        if ($IncludePrivateKey) {
            # Export with private key (PFX)
            if (-not $cert.HasPrivateKey) {
                Write-LogMessage "  ⚠ Certificate does not have a private key" -Level Warning
                $IncludePrivateKey = $false
            }
            else {
                # Generate password for export
                $exportPassword = ConvertTo-SecureString -String "ExportPassword123!" -AsPlainText -Force
                
                Export-PfxCertificate -Cert $cert -FilePath $Output -Password $exportPassword -ErrorAction Stop | Out-Null
                
                Write-LogMessage "  ✓ Certificate exported with private key (PFX)" -Level Success
                Write-LogMessage "    Export password: ExportPassword123!" -Level Warning
                Write-LogMessage "    Output: $Output" -Level Info
                
                $script:CertificatesExported++
                return $true
            }
        }
        
        # Export without private key (CER)
        Export-Certificate -Cert $cert -FilePath $Output -ErrorAction Stop | Out-Null
        
        Write-LogMessage "  ✓ Certificate exported (CER)" -Level Success
        Write-LogMessage "    Output: $Output" -Level Info
        
        $script:CertificatesExported++
        return $true
    }
    catch {
        Write-LogMessage "  ✗ Error exporting certificate: $($_.Exception.Message)" -Level Error
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
    Write-LogMessage "Validating certificates..." -Level Info
    
    $stores = @(
        @{ Name = 'My'; Location = 'LocalMachine'; Description = 'Personal' }
        @{ Name = 'Root'; Location = 'LocalMachine'; Description = 'Trusted Root CA' }
        @{ Name = 'CA'; Location = 'LocalMachine'; Description = 'Intermediate CA' }
        @{ Name = 'TrustedPublisher'; Location = 'LocalMachine'; Description = 'Trusted Publishers' }
    )
    
    $allIssues = @()
    
    foreach ($storeInfo in $stores) {
        Write-LogMessage "" -Level Info
        Write-LogMessage "Checking store: $($storeInfo.Description) (Cert:\$($storeInfo.Location)\$($storeInfo.Name))" -Level Info
        
        try {
            $certs = Get-ChildItem -Path "Cert:\$($storeInfo.Location)\$($storeInfo.Name)" -ErrorAction Stop
            
            if ($certs.Count -eq 0) {
                Write-LogMessage "  No certificates found" -Level Info
                continue
            }
            
            Write-LogMessage "  Found $($certs.Count) certificate(s)" -Level Info
            
            foreach ($cert in $certs) {
                $issues = Test-Certificate -Certificate $cert
                
                if ($issues.Count -gt 0) {
                    Write-LogMessage "  ⚠ $($cert.Subject)" -Level Warning
                    Write-LogMessage "    Thumbprint: $($cert.Thumbprint)" -Level Warning
                    Write-LogMessage "    Issues: $($issues -join ', ')" -Level Warning
                    
                    $allIssues += [PSCustomObject]@{
                        Store = $storeInfo.Description
                        Subject = $cert.Subject
                        Thumbprint = $cert.Thumbprint
                        Issues = $issues -join ', '
                        NotAfter = $cert.NotAfter
                    }
                }
                else {
                    Write-LogMessage "  ✓ $($cert.Subject)" -Level Success
                }
            }
        }
        catch {
            Write-LogMessage "  ✗ Error checking store: $($_.Exception.Message)" -Level Error
        }
    }
    
    return $allIssues
}

#endregion

#region Certificate Cleanup

function Remove-ExpiredCertificates {
    Write-LogMessage "Removing expired certificates..." -Level Info
    
    $stores = @('My', 'Root', 'CA', 'TrustedPublisher')
    $location = 'LocalMachine'
    
    foreach ($storeName in $stores) {
        Write-LogMessage "" -Level Info
        Write-LogMessage "Checking store: $storeName" -Level Info
        
        try {
            $certs = Get-ChildItem -Path "Cert:\$location\$storeName" -ErrorAction Stop
            $expiredCerts = $certs | Where-Object { $_.NotAfter -lt (Get-Date) }
            
            if ($expiredCerts.Count -eq 0) {
                Write-LogMessage "  No expired certificates found" -Level Info
                continue
            }
            
            Write-LogMessage "  Found $($expiredCerts.Count) expired certificate(s)" -Level Warning
            
            foreach ($cert in $expiredCerts) {
                try {
                    Remove-Item -Path "Cert:\$location\$storeName\$($cert.Thumbprint)" -Force -ErrorAction Stop
                    
                    Write-LogMessage "  ✓ Removed: $($cert.Subject)" -Level Success
                    Write-LogMessage "    Expired: $($cert.NotAfter.ToString('yyyy-MM-dd'))" -Level Info
                    
                    $script:CertificatesRemoved++
                }
                catch {
                    Write-LogMessage "  ✗ Failed to remove: $($cert.Subject) - $($_.Exception.Message)" -Level Error
                    $script:OperationsFailed++
                }
            }
        }
        catch {
            Write-LogMessage "  ✗ Error accessing store: $($_.Exception.Message)" -Level Error
        }
    }
}

#endregion

#region Certificate Reporting

function Get-CertificateInventory {
    Write-LogMessage "Generating certificate inventory..." -Level Info
    
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
            Write-LogMessage "Error accessing store $($storeInfo.Description): $($_.Exception.Message)" -Level Warning
        }
    }
    
    return $inventory
}

function Save-CertificateReport {
    Write-LogMessage "Saving certificate report..." -Level Info
    
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
        
        Write-LogMessage "Certificate report saved to: $reportFile" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Error generating report: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

#endregion

#region Main Execution

function Main {
    $scriptStartTime = Get-Date
    
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Certificate Management" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Script: $scriptName" -Level Info
    Write-LogMessage "Log File: $LogFile" -Level Info
    Write-LogMessage "Started: $scriptStartTime" -Level Info
    Write-LogMessage "" -Level Info
    
    # Check prerequisites
    if (-not (Test-IsAdministrator)) {
        Write-LogMessage "This script requires Administrator privileges" -Level Error
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
            Write-LogMessage "CertificatePath parameter is required for import operations" -Level Error
            exit 1
        }
        
        Import-PFXCertificate -Path $CertificatePath -CertPassword $Password -StoreName $Store -Location $StoreLocation
        $operationPerformed = $true
    }
    
    # Import CER
    if ($ImportCER) {
        if (-not $CertificatePath) {
            Write-LogMessage "CertificatePath parameter is required for import operations" -Level Error
            exit 1
        }
        
        Import-CERCertificate -Path $CertificatePath -StoreName $Store -Location $StoreLocation
        $operationPerformed = $true
    }
    
    # Export certificate
    if ($ExportCertificate) {
        if (-not $Thumbprint -or -not $OutputPath) {
            Write-LogMessage "Thumbprint and OutputPath parameters are required for export operations" -Level Error
            exit 1
        }
        
        Export-Certificate -CertThumbprint $Thumbprint -Output $OutputPath -IncludePrivateKey:$ExportPrivateKey
        $operationPerformed = $true
    }
    
    # Validate certificates
    if ($ValidateCertificates) {
        $issues = Get-CertificateValidationReport
        
        if ($issues.Count -gt 0) {
            Write-LogMessage "" -Level Info
            Write-LogMessage "Found $($issues.Count) certificate(s) with issues" -Level Warning
        }
        else {
            Write-LogMessage "" -Level Info
            Write-LogMessage "All certificates are valid" -Level Success
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
        Write-LogMessage "No operation specified, generating certificate inventory..." -Level Info
        Write-LogMessage "" -Level Info
        
        Get-CertificateValidationReport | Out-Null
    }
    
    # Generate report
    Save-CertificateReport | Out-Null
    
    # Summary
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    
    Write-LogMessage "" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Certificate Management Summary" -Level Info
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Certificates Imported: $script:CertificatesImported" -Level Info
    Write-LogMessage "Certificates Exported: $script:CertificatesExported" -Level Info
    Write-LogMessage "Certificates Removed: $script:CertificatesRemoved" -Level Info
    Write-LogMessage "Operations Failed: $script:OperationsFailed" -Level Info
    Write-LogMessage "Duration: $([math]::Round($duration.TotalSeconds, 2)) seconds" -Level Info
    Write-LogMessage "Log file: $LogFile" -Level Info
    
    if ($script:OperationsFailed -eq 0) {
        Write-LogMessage "Certificate management completed successfully!" -Level Success
        exit 0
    }
    else {
        Write-LogMessage "Certificate management completed with $script:OperationsFailed failures" -Level Warning
        exit 1
    }
}

# Execute main function
try {
    Main
}
catch {
    Write-LogMessage "Fatal error: $($_.Exception.Message)" -Level Error
    Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}

#endregion
