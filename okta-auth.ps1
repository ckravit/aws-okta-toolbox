# okta-auth.ps1 — Windows equivalent of okta-auth.sh
# Run in PowerShell whenever your AWS session expires.
# A URL will be printed — open it in your browser, approve in Okta,
# then return here to select your AWS account and role.
#
# Usage:
#   .\okta-auth.ps1
#   .\okta-auth.ps1 -Profile my-profile

param(
    [string]$Profile,
    [string]$Region
)

function Get-ValueOrDefault {
    param(
        [string]$Value,
        [string]$DefaultValue
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $DefaultValue
    }

    return $Value
}

$Profile = Get-ValueOrDefault $Profile $env:AWS_PROFILE
$Profile = Get-ValueOrDefault $Profile "default"

$Region = Get-ValueOrDefault $Region $env:AWS_DEFAULT_REGION
$Region = Get-ValueOrDefault $Region "us-west-2"

# ── Edit these two values ─────────────────────────────────────────────────────
$OktaOrgDomain    = Get-ValueOrDefault $env:OKTA_ORG_DOMAIN "mycompany.okta.com"
$OktaOidcClientId = Get-ValueOrDefault $env:OKTA_OIDC_CLIENT_ID "0oa1b2c3d4e5f6g7h8i9"
# ─────────────────────────────────────────────────────────────────────────────

if ($OktaOrgDomain -eq "mycompany.okta.com" -or $OktaOidcClientId -eq "0oa1b2c3d4e5f6g7h8i9") {
    Write-Error "Set OKTA_ORG_DOMAIN and OKTA_OIDC_CLIENT_ID as environment variables, or update the defaults in this script."
    exit 1
}

$AwsDir = Join-Path $env:USERPROFILE ".aws"
New-Item -ItemType Directory -Force -Path $AwsDir | Out-Null

Write-Host "Okta authentication -- profile: $Profile"
Write-Host ""
Write-Host "A URL will appear below. Open it in your browser and approve the Okta request."
Write-Host "Then return here to select your AWS account and role."
Write-Host ""

docker run --rm -it `
    -v "${AwsDir}:/root/.aws" `
    -e "AWS_DEFAULT_REGION=$Region" `
    aws-okta-toolbox `
    okta-aws-cli `
        --org-domain "$OktaOrgDomain" `
        --oidc-client-id "$OktaOidcClientId" `
        --write-aws-credentials `
        --aws-credentials /root/.aws/credentials `
        --profile "$Profile"

if ($LASTEXITCODE -ne 0) {
    Write-Error "okta-aws-cli failed. Credentials were not updated."
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Done. Credentials written to $(Join-Path $AwsDir 'credentials') (profile: $Profile)"