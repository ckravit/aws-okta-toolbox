# awstunnel.ps1 — Windows equivalent of awstunnel.sh
# Start an SSM port-forwarding tunnel to a remote target.
#
# Usage:
#   .\awstunnel.ps1 jupyter      <instance-id> [remote-port] [local-port]
#   .\awstunnel.ps1 port-forward <instance-id> <remote-host> <remote-port> [local-port]
#   .\awstunnel.ps1 db           <instance-id> <remote-host> <remote-port> [local-port]
#
# Examples:
#   .\awstunnel.ps1 jupyter i-0abc1234
#   .\awstunnel.ps1 jupyter i-0abc1234 8888
#   .\awstunnel.ps1 jupyter i-0abc1234 8888 8889
#   .\awstunnel.ps1 port-forward i-0abc1234 internal.example.local 443
#   .\awstunnel.ps1 port-forward i-0abc1234 internal.example.local 443 8443
#   .\awstunnel.ps1 db i-0abc1234 my-rds.cluster.us-west-2.rds.amazonaws.com 5432

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TunnelType,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$InstanceId,

    [Parameter(Position = 2)]
    [string]$Arg1,

    [Parameter(Position = 3)]
    [string]$Arg2,

    [Parameter(Position = 4)]
    [string]$Arg3
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

function Test-Port {
    param(
        [string]$Value,
        [string]$Name
    )

    $parsed = 0
    if (-not [int]::TryParse($Value, [ref]$parsed) -or $parsed -lt 1 -or $parsed -gt 65535) {
        Write-Error "$Name must be an integer between 1 and 65535. Got: $Value"
        exit 1
    }

    return $parsed
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
        Write-Error "AWS credentials are missing or expired for profile: $Profile"
        Write-Host "Run .\okta-auth.ps1 to re-authenticate, then try again."
        exit 1
    }
}

function Start-SsmTunnel {
    param(
        [string]$ContainerName,
        [string]$AwsDir,
        [string]$Profile,
        [string]$Region,
        [string]$Image,
        [int]$LocalPort,
        [string]$InstanceId,
        [string]$RemoteHost,
        [int]$RemotePort
    )

    docker run --rm -it `
        --name $ContainerName `
        -p "${LocalPort}:${LocalPort}" `
        -v "${AwsDir}:/root/.aws" `
        -e "AWS_PROFILE=$Profile" `
        -e "AWS_DEFAULT_REGION=$Region" `
        $Image `
        aws ssm start-session `
            --region "$Region" `
            --profile "$Profile" `
            --target "$InstanceId" `
            --document-name AWS-StartPortForwardingSessionToRemoteHost `
            --parameters "host=$RemoteHost,portNumber=$RemotePort,localPortNumber=$LocalPort"

    if ($LASTEXITCODE -ne 0) {
        Write-Error "SSM tunnel command failed."
        exit $LASTEXITCODE
    }
}

$Profile = Get-ValueOrDefault $env:AWS_PROFILE "default"
$Region  = Get-ValueOrDefault $env:AWS_DEFAULT_REGION "us-west-2"
$AwsDir  = Join-Path $env:USERPROFILE ".aws"
$Image   = "aws-okta-toolbox"

New-Item -ItemType Directory -Force -Path $AwsDir | Out-Null

Test-DockerAvailable
Invoke-CredentialCheck -AwsDir $AwsDir -Profile $Profile -Region $Region -Image $Image

switch ($TunnelType.ToLowerInvariant()) {

    "jupyter" {
        $RemotePort = if ($Arg1) { Test-Port $Arg1 "remote-port" } else { 8888 }
        $LocalPort  = if ($Arg2) { Test-Port $Arg2 "local-port" } else { $RemotePort }

        Write-Host "Jupyter tunnel: localhost:$LocalPort -> $InstanceId`:localhost:$RemotePort"
        Write-Host "Open http://localhost:$LocalPort in your browser."
        Write-Host "Press Ctrl-C to stop."

        Start-SsmTunnel `
            -ContainerName "ssm-jupyter-$LocalPort" `
            -AwsDir $AwsDir `
            -Profile $Profile `
            -Region $Region `
            -Image $Image `
            -LocalPort $LocalPort `
            -InstanceId $InstanceId `
            -RemoteHost "localhost" `
            -RemotePort $RemotePort
    }

    "port-forward" {
        if ([string]::IsNullOrWhiteSpace($Arg1) -or [string]::IsNullOrWhiteSpace($Arg2)) {
            Write-Error "Usage: .\awstunnel.ps1 port-forward <instance-id> <remote-host> <remote-port> [local-port]"
            exit 1
        }

        $RemoteHost = $Arg1
        $RemotePort = Test-Port $Arg2 "remote-port"
        $LocalPort  = if ($Arg3) { Test-Port $Arg3 "local-port" } else { $RemotePort }

        Write-Host "Tunnel: localhost:$LocalPort -> $RemoteHost`:$RemotePort via $InstanceId"
        Write-Host "Press Ctrl-C to stop."

        Start-SsmTunnel `
            -ContainerName "ssm-port-forward-$LocalPort" `
            -AwsDir $AwsDir `
            -Profile $Profile `
            -Region $Region `
            -Image $Image `
            -LocalPort $LocalPort `
            -InstanceId $InstanceId `
            -RemoteHost $RemoteHost `
            -RemotePort $RemotePort
    }

    "db" {
        if ([string]::IsNullOrWhiteSpace($Arg1) -or [string]::IsNullOrWhiteSpace($Arg2)) {
            Write-Error "Usage: .\awstunnel.ps1 db <instance-id> <remote-host> <remote-port> [local-port]"
            exit 1
        }

        $RemoteHost = $Arg1
        $RemotePort = Test-Port $Arg2 "remote-port"
        $LocalPort  = if ($Arg3) { Test-Port $Arg3 "local-port" } else { $RemotePort }

        Write-Host "DB tunnel: localhost:$LocalPort -> $RemoteHost`:$RemotePort via $InstanceId"
        Write-Host "Press Ctrl-C to stop."

        Start-SsmTunnel `
            -ContainerName "ssm-db-$LocalPort" `
            -AwsDir $AwsDir `
            -Profile $Profile `
            -Region $Region `
            -Image $Image `
            -LocalPort $LocalPort `
            -InstanceId $InstanceId `
            -RemoteHost $RemoteHost `
            -RemotePort $RemotePort
    }

    default {
        Write-Error "Unknown tunnel type: $TunnelType"
        Write-Host "Valid values: jupyter, port-forward, db"
        exit 1
    }
}