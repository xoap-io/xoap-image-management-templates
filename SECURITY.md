# Security Policy

## Supported Versions

We release patches for security vulnerabilities in the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 2.x.x   | :white_check_mark: |
| 1.x.x   | :x:                |

## Reporting a Vulnerability

The XOAP team takes security bugs seriously. We appreciate your efforts to responsibly disclose your findings and will make every effort to acknowledge your contributions.

### How to Report a Security Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues.**

Instead, please report security vulnerabilities by emailing the XOAP security team at:

**security@xoap.io**

You should receive a response within 48 hours. If for some reason you do not, please follow up via email to ensure we received your original message.

### What to Include in Your Report

Please include the following information in your report:

- **Type of vulnerability** (e.g., credential exposure, command injection, privilege escalation)
- **Affected component(s)** (e.g., specific Packer template, PowerShell script, autounattend file)
- **Step-by-step instructions** to reproduce the issue
- **Proof-of-concept or exploit code** (if possible)
- **Impact assessment** - What can an attacker achieve?
- **Suggested remediation** (if you have ideas)
- **Your contact information** for follow-up questions

### Example Security Report

```
Subject: [SECURITY] Credential Exposure in AWS Scripts

Description:
The Install_AWS_Tools.ps1 script logs AWS credentials in plaintext
to C:\xoap-logs when encountering authentication errors.

Affected Components:
- scripts_wip/windows_server_2025_scripts/aws/Install_AWS_Tools.ps1
- Lines 45-52

Steps to Reproduce:
1. Configure invalid AWS credentials
2. Run Install_AWS_Tools.ps1
3. Check C:\xoap-logs\Install_AWS_Tools_*.log
4. Observe credentials in log file

Impact:
An attacker with local file access could retrieve AWS credentials
from log files, potentially compromising the AWS environment.

Suggested Fix:
Sanitize error messages before logging to remove sensitive data.
```

## Security Best Practices

### Credentials and Secrets

⚠️ **NEVER commit credentials or secrets to the repository**

- Use environment variables for sensitive data
- Leverage cloud provider IAM roles/managed identities
- Use Packer's `-var` flag for runtime secrets
- Enable `.gitignore` for `*.pkrvars.hcl` files containing secrets

### Autounattend Files

The autounattend files in this repository use **hardcoded default credentials** for initial provisioning:

```xml
<Password>
    <Value>xoap-admin</Value>
    <PlainText>true</PlainText>
</Password>
```

**⚠️ SECURITY NOTICE:**
- These credentials are **ONLY for initial automated setup**
- Images built with these files **MUST be sysprepped**
- Change default passwords immediately after deployment
- Use post-provisioning scripts to set secure, unique passwords
- Never deploy images with default credentials to production

### WinRM Configuration

Autounattend files configure WinRM with reduced security for automation:

```xml
<CommandLine>winrm set winrm/config/service @{AllowUnencrypted="true"}</CommandLine>
```

**⚠️ SECURITY NOTICE:**
- Unencrypted WinRM is **ONLY acceptable during image build**
- Network should be isolated during build process
- Sysprep scripts should reconfigure WinRM with encryption
- Production deployments MUST use HTTPS (port 5986) with certificates

### Cloud Provider Security

#### AWS EC2
- Use IAM instance profiles instead of access keys
- Enable IMDSv2 (Instance Metadata Service v2)
- Restrict security groups to minimum required access
- Use Systems Manager Session Manager instead of RDP where possible

#### Azure VMs
- Use Managed Identities instead of service principals
- Enable Azure Disk Encryption
- Use Azure Bastion for secure RDP access
- Implement Just-In-Time VM access

#### Google Compute Engine
- Use service accounts with minimal required permissions
- Enable OS Login for SSH/RDP access management
- Use Cloud IAP for secure remote access
- Enable disk encryption by default

### PowerShell Script Security

Our PowerShell scripts follow security best practices:

1. **Execution Policy:** Set to `RemoteSigned` during provisioning
2. **Logging:** Sensitive data sanitized before logging
3. **Error Handling:** Try-catch blocks prevent information leakage
4. **Least Privilege:** Scripts request minimum required permissions

**Best Practices:**
```powershell
# DO: Sanitize sensitive data before logging
$sanitizedUrl = $url -replace "(?<=api_key=)[^&]*", "***REDACTED***"
Write-Log "Downloading from: $sanitizedUrl"

# DON'T: Log raw credentials
Write-Log "Using password: $password"  # ❌ NEVER DO THIS
```

### Network Security

During image building:

- Use isolated/private networks where possible
- Restrict inbound access to build hosts only
- Block outbound access to untrusted networks
- Monitor for unusual network activity

### Supply Chain Security

To protect against supply chain attacks:

1. **Verify ISO Checksums:** Always validate Windows ISO checksums
   ```hcl
   iso_checksum = "sha256:checksum_here"
   ```

2. **Pin Tool Versions:** Specify exact versions for downloaded tools
   ```powershell
   $awsCliVersion = "2.13.0"
   ```

3. **Use HTTPS:** Always download over encrypted connections
   ```powershell
   $url = "https://example.com/tool.msi"  # ✓ HTTPS
   ```

4. **Verify Signatures:** Check digital signatures on downloaded executables
   ```powershell
   Get-AuthenticodeSignature -FilePath "tool.exe"
   ```

## Vulnerability Disclosure Process

1. **Report Received:** Security team acknowledges receipt within 48 hours
2. **Initial Assessment:** Team evaluates severity and impact within 5 business days
3. **Investigation:** Reproduce and analyze the vulnerability
4. **Fix Development:** Create and test a patch
5. **Disclosure:** Coordinate disclosure timeline with reporter
6. **Release:** Deploy fix and publish security advisory
7. **Recognition:** Credit reporter in security advisory (if desired)

### Disclosure Timeline

- **Critical vulnerabilities:** 7-14 days
- **High severity:** 30 days
- **Medium severity:** 60 days
- **Low severity:** 90 days

We may request extended timelines for complex issues requiring significant code changes.

## Security Updates

Security updates will be released as:

1. **Patch releases** (e.g., 2.0.1) for non-breaking security fixes
2. **GitHub Security Advisories** for all security vulnerabilities
3. **CHANGELOG.md updates** documenting security fixes

Subscribe to GitHub repository notifications to receive security updates.

## Security Hardening Checklist

Before deploying images built with these templates:

- [ ] Default `xoap-admin` password changed
- [ ] WinRM configured with HTTPS and certificates
- [ ] Unnecessary services disabled
- [ ] Windows Defender/antivirus enabled and updated
- [ ] Windows Firewall configured with least-privilege rules
- [ ] Latest Windows security updates installed
- [ ] Audit logging enabled
- [ ] Local administrator account renamed
- [ ] Guest account disabled
- [ ] Password policy enforced (complexity, length, expiration)
- [ ] Account lockout policy configured
- [ ] Unused features/roles removed
- [ ] Secure remote access configured (VPN, Bastion, etc.)
- [ ] Disk encryption enabled (BitLocker, LUKS, etc.)
- [ ] Security monitoring/SIEM integration configured

## Known Security Considerations

### Plaintext Credentials in Autounattend Files

**Issue:** Autounattend XML files contain plaintext passwords for `xoap-admin` user.

**Mitigation:**
- Files are only used during automated image build
- Images must be sysprepped before deployment
- Sysprep removes user accounts and resets machine identity
- Production deployments should use randomized passwords

**Status:** This is by design for automation purposes.

### Disabled UAC During Build

**Issue:** User Account Control (UAC) is disabled in autounattend files.

**Mitigation:**
- UAC disabled only during build for automation
- Sysprep scripts should re-enable UAC
- Production images should have UAC enabled

**Status:** Acceptable for build-time automation.

### Legacy Authentication Protocols

**Issue:** WinRM configured with Basic authentication and unencrypted transport.

**Mitigation:**
- Only used during initial build in isolated network
- Reconfigured with Kerberos/NTLM and HTTPS post-build
- Build network should be isolated from production

**Status:** Acceptable for build-time automation in isolated environment.

## Additional Resources

- [Microsoft Security Response Center](https://www.microsoft.com/en-us/msrc)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [CIS Benchmarks for Windows](https://www.cisecurity.org/cis-benchmarks/)
- [AWS Security Best Practices](https://aws.amazon.com/security/best-practices/)
- [Azure Security Best Practices](https://docs.microsoft.com/en-us/azure/security/fundamentals/best-practices-and-patterns)
- [Google Cloud Security Best Practices](https://cloud.google.com/security/best-practices)

## Contact

For non-security-related questions:
- GitHub Issues: [xoap-io/xoap-image-management-templates/issues](https://github.com/xoap-io/xoap-image-management-templates/issues)
- Email: support@xoap.io
- Website: https://xoap.io

For security vulnerabilities:
- Email: **security@xoap.io**

---

**Last Updated:** January 20, 2026
