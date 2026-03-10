<#
.SYNOPSIS
    Configures Cloudflare Logpush for DNS logs to a Splunk HEC endpoint over SSL (port 8088).

.DESCRIPTION
    Reads a list of zone names from a text file, looks up each zone ID via the
    Cloudflare API, creates a Logpush job targeting a Splunk HEC endpoint, and
    enables the job.

.AUTHOR
    Eric Hayth <ehayth@cloudflare.com>

.VERSION
    2.0.0

.DATE
    2026-03-10

.NOTES
    You are free to use, copy, and modify this script for your own purposes.
    Attribution is appreciated but not required. Provided as-is, with no warranty.
#>

[CmdletBinding()]
param()

# --- Helper Functions ---

function Read-Zones {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    if (-not (Test-Path $FilePath)) {
        Write-Error "Zones file not found: $FilePath"
        exit 1
    }
    return Get-Content -Path $FilePath | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() }
}

function Get-ZoneId {
    param(
        [Parameter(Mandatory)][string]$CfToken,
        [Parameter(Mandatory)][string]$ZoneName
    )
    $headers = @{
        "Authorization" = "Bearer $CfToken"
        "Content-Type"  = "application/json"
    }
    $uri = "https://api.cloudflare.com/client/v4/zones?name=$ZoneName"
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    if ($response.result -and $response.result.Count -gt 0) {
        return $response.result[0].id
    }
    return $null
}

function New-LogpushJob {
    param(
        [Parameter(Mandatory)][string]$CfToken,
        [Parameter(Mandatory)][string]$ZoneId,
        [Parameter(Mandatory)][string]$ZoneName,
        [Parameter(Mandatory)][string]$SplunkUrl,
        [Parameter(Mandatory)][string]$SplunkToken,
        [Parameter(Mandatory)][string]$SourceType,
        [Parameter(Mandatory)][string]$ChannelId,
        [Parameter(Mandatory)][bool]$Insecure
    )
    $headers = @{
        "Authorization" = "Bearer $CfToken"
        "Content-Type"  = "application/json"
    }

    $logpushUrl = "https://api.cloudflare.com/client/v4/zones/$ZoneId/logpush/jobs"
    $jobName = "$ZoneName-dns-splunk"

    # URL-encode the Splunk authorization header value
    $encodedToken = [System.Uri]::EscapeDataString("Splunk $SplunkToken")
    $insecureStr = if ($Insecure) { "true" } else { "false" }

    # Build the Splunk destination configuration
    $destinationConf = "splunk://$SplunkUrl/services/collector/raw?channel=$ChannelId&insecure=$insecureStr&sourcetype=$SourceType&header_Authorization=$encodedToken"

    $body = @{
        name             = $jobName
        destination_conf = $destinationConf
        logpull_options  = "fields=ColoCode,EDNSSubnet,EDNSSubnetLength,QueryName,QueryType,ResponseCached,ResponseCode,SourceIP,Timestamp&timestamps=rfc3339"
        dataset          = "dns_logs"
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri $logpushUrl -Headers $headers -Method Post -Body $body
    return $response.result.id
}

function Enable-LogpushJob {
    param(
        [Parameter(Mandatory)][string]$CfToken,
        [Parameter(Mandatory)][string]$ZoneId,
        [Parameter(Mandatory)][string]$LogpushId
    )
    $headers = @{
        "Authorization" = "Bearer $CfToken"
        "Content-Type"  = "application/json"
    }
    $enableUrl = "https://api.cloudflare.com/client/v4/zones/$ZoneId/logpush/jobs/$LogpushId"
    $body = @{ enabled = $true } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri $enableUrl -Headers $headers -Method Put -Body $body
    return $response.success
}

# --- Main ---

# Collect credentials and configuration
$cfTokenSecure = Read-Host -Prompt "Enter Cloudflare API Token" -AsSecureString
$cfToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($cfTokenSecure)
)

$splunkHost = Read-Host -Prompt "Enter Splunk HEC hostname or IP (e.g. splunk.example.com)"
$splunkPort = Read-Host -Prompt "Enter Splunk HEC port [8088]"
if ([string]::IsNullOrWhiteSpace($splunkPort)) { $splunkPort = "8088" }
$splunkUrl = "${splunkHost}:${splunkPort}"

$splunkTokenSecure = Read-Host -Prompt "Enter Splunk HEC Token" -AsSecureString
$splunkToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($splunkTokenSecure)
)

$sourceType = Read-Host -Prompt "Enter Splunk sourcetype [cloudflare:dns]"
if ([string]::IsNullOrWhiteSpace($sourceType)) { $sourceType = "cloudflare:dns" }

$channelId = Read-Host -Prompt "Enter Splunk HEC Channel ID (UUID)"

$insecureInput = Read-Host -Prompt "Allow insecure (skip TLS verification)? [y/N]"
$insecure = $insecureInput -match "^[yY](es)?$"

$zonesFile = Read-Host -Prompt "Enter the path to a text file containing the list of zones by name"
$zones = Read-Zones -FilePath $zonesFile

foreach ($zoneName in $zones) {
    Write-Host "Processing zone: $zoneName" -ForegroundColor Cyan

    # Look up the zone ID
    $zoneId = Get-ZoneId -CfToken $cfToken -ZoneName $zoneName
    if (-not $zoneId) {
        Write-Warning "No zone found for the domain name: $zoneName"
        continue
    }

    try {
        # Create the Logpush job
        $logpushId = New-LogpushJob `
            -CfToken $cfToken `
            -ZoneId $zoneId `
            -ZoneName $zoneName `
            -SplunkUrl $splunkUrl `
            -SplunkToken $splunkToken `
            -SourceType $sourceType `
            -ChannelId $channelId `
            -Insecure $insecure

        if ($logpushId) {
            # Enable the job
            $enabled = Enable-LogpushJob -CfToken $cfToken -ZoneId $zoneId -LogpushId $logpushId
            if ($enabled) {
                Write-Host "Logpush job enabled for Zone: $zoneName (ID: $zoneId), Job ID: $logpushId" -ForegroundColor Green
            }
            else {
                Write-Warning "Error enabling logpush job for zone: $zoneName"
            }
        }
        else {
            Write-Warning "Failed to create logpush job for zone: $zoneName"
        }
    }
    catch {
        Write-Error "Error processing zone ${zoneName}: $_"
        if ($_.Exception.Response) {
            $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Error "API Response: $responseBody"
        }
    }

    Start-Sleep -Seconds 2
}

Write-Host "Done." -ForegroundColor Green
