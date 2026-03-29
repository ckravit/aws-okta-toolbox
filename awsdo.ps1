# awsdo.ps1
# Run any command inside the aws-okta-toolbox container without dealing with
# docker run boilerplate. Your current directory is automatically mounted so
# local files are accessible inside the container.
#
# Usage:
#   .\awsdo.ps1 aws s3 ls
#   .\awsdo.ps1 aws s3 cp .\myfile.csv s3://my-bucket/uploads/
#   .\awsdo.ps1 aws ec2 describe-instances --output table
#   .\awsdo.ps1 bash
#
# Tip:
#   If you need to run many commands in a row, ".\awsdo.ps1 bash" is usually
#   more efficient than starting a new container for each command.

param(
    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
    [string[]]$Command
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

function Test-DockerAvailable {
    $null = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $?) {
        Write-Error "Docker is not installed or not available in PATH."
        exit 1
    }
}

function Invoke-CredentialCheck {
    param(
        [string]$AwsDir,
        [string]$Profile,
        [string]$Region,
        [string]$Image
    )

    docker run --rm `
        -v "${AwsDir}:/root/.aws" `
        -e "AWS_PROFILE=$Profile" `
        -e "AWS_DEFAULT_REGION=$Region" `
        $Image `
        aws sts get-caller-identity --output text --query UserId 1>$null 2>$null

    if ($LASTEXITCODE -ne 0) {
        Write-Host "AWS credentials are missing or expired for profile: $Profile"
        Write-Host "Run .\okta-auth.ps1 to authenticate or refresh your session, then try again."
        exit 1
    }
}

$Profile = Get-ValueOrDefault $env:AWS_PROFILE "default"
$Region  = Get-ValueOrDefault $env:AWS_DEFAULT_REGION "us-west-2"
$AwsDir  = Join-Path $env:USERPROFILE ".aws"
$Image   = "aws-okta-toolbox"

# Default mount is current directory. Override with $env:AWSDO_MOUNT_DIR
# for a different path.
$MountDir = if ([string]::IsNullOrWhiteSpace($env:AWSDO_MOUNT_DIR)) {
    (Get-Location).Path
} else {
    $env:AWSDO_MOUNT_DIR
}

New-Item -ItemType Directory -Force -Path $AwsDir | Out-Null

if (-not (Test-Path -LiteralPath $MountDir)) {
    Write-Error "Mount directory does not exist: $MountDir"
    exit 1
}

Test-DockerAvailable
Invoke-CredentialCheck -AwsDir $AwsDir -Profile $Profile -Region $Region -Image $Image

docker run --rm -it `
    -v "${AwsDir}:/root/.aws" `
    -v "${MountDir}:/work" `
    -w /work `
    -e "AWS_PROFILE=$Profile" `
    -e "AWS_DEFAULT_REGION=$Region" `
    $Image `
    @Command

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}