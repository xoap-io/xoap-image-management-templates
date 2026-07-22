@{
    # PSScriptAnalyzer configuration for xoap-image-management-templates.
    #
    # These scripts are image-build provisioners consumed by Packer and (mid-term)
    # alpaka. Several default rules conflict with that execution model and are
    # excluded below with rationale. The CI gate (see .github/workflows/lint-scripts.yml)
    # blocks the build on Error-severity findings; Warnings are reported for triage.

    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # stdout IS the build-log channel for Packer and alpaka; Write-Host is the
        # deliberate, documented output mechanism (see docs/SCRIPT_CONTRACT.md).
        'PSAvoidUsingWriteHost',

        # Build-time credential handling for certificate import / local build accounts.
        # These are throwaway image-creation credentials, not runtime secrets.
        'PSAvoidUsingConvertToSecureStringWithPlainText',

        # Provisioners are non-interactive; -WhatIf/-Confirm plumbing is not applicable.
        'PSUseShouldProcessForStateChangingFunctions',

        # The .editorconfig governs encoding; not enforced per-file by the analyzer here.
        'PSUseBOMForUnicodeEncodedFile',

        # Script (not module) files; singular-noun cmdlet naming does not apply.
        'PSUseSingularNouns',

        # Many provisioners accept a superset of parameters for a shared calling
        # convention across the demo sets; unused-parameter noise is expected.
        'PSReviewUnusedParameter'
    )
}
