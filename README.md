# Cloudflare DNS Logpush to Splunk HEC

Scripts for automating the creation of [Cloudflare Logpush](https://developers.cloudflare.com/logs/logpush/) jobs for DNS logs, pushing to a **Splunk HTTP Event Collector (HEC)** endpoint over SSL (port 8088). Available in both Python and PowerShell.

## Files

| File | Description |
|------|-------------|
| [`zone_dns_logpush_v3.py`](zone_dns_logpush_v3.py) | Python script to create and enable Splunk-targeted Logpush jobs |
| [`zone_dns_logpush_v3.ps1`](zone_dns_logpush_v3.ps1) | PowerShell equivalent of the Python script |
| [`zone_dns_logpush_v3_python.txt`](zone_dns_logpush_v3_python.txt) | Detailed documentation for the Python script |
| [`zone_dns_logpush_v3_powershell.txt`](zone_dns_logpush_v3_powershell.txt) | Detailed documentation for the PowerShell script |

## Prerequisites

- A **Cloudflare API Token** with the following permissions:
  - Zone > Logs > Edit
  - Zone > Zone > Read
- A **Splunk HEC endpoint** configured for SSL (port 8088)
- A **Splunk HEC Token**
- A **Splunk HEC Channel ID** (UUID format)
- A **text file** containing one zone (domain) name per line

### Python

- Python 3.6+
- The `requests` library:
  ```
  pip install requests
  ```

### PowerShell

- PowerShell 5.1+ (Windows) or PowerShell Core 7+ (macOS/Linux)
- No external modules required

## Usage

### Python

```bash
python zone_dns_logpush_v3.py
```

### PowerShell

```powershell
# Windows
.\zone_dns_logpush_v3.ps1

# macOS / Linux
pwsh zone_dns_logpush_v3.ps1
```

Both scripts prompt interactively for:

| Prompt | Default | Notes |
|--------|---------|-------|
| Cloudflare API Token | — | Hidden input |
| Splunk HEC hostname or IP | — | e.g. `splunk.example.com` |
| Splunk HEC port | `8088` | Press Enter to accept default |
| Splunk HEC Token | — | Hidden input |
| Splunk sourcetype | `cloudflare:dns` | Press Enter to accept default |
| Splunk HEC Channel ID | — | UUID format |
| Allow insecure (skip TLS)? | `N` | Set to `y` only for self-signed certs |
| Path to zones file | — | One domain per line |

## Zones File Format

A plain text file with one domain name per line. Blank lines are ignored.

```
example.com
example.org
mysite.net
```

## Splunk Destination Format

The scripts construct the following `destination_conf` for each Logpush job:

```
splunk://<HOST>:<PORT>/services/collector/raw?channel=<CHANNEL_ID>&insecure=<true|false>&sourcetype=<SOURCE_TYPE>&header_Authorization=Splunk%20<HEC_TOKEN>
```

## DNS Log Fields

Each job is configured to push the following fields:

| Field | Description |
|-------|-------------|
| `ColoCode` | IATA code of the Cloudflare data center |
| `EDNSSubnet` | EDNS Client Subnet (ECS) if present |
| `EDNSSubnetLength` | Prefix length of the EDNS Client Subnet |
| `QueryName` | The queried domain name |
| `QueryType` | DNS query type (A, AAAA, CNAME, MX, etc.) |
| `ResponseCached` | Whether the response was served from cache |
| `ResponseCode` | DNS response code (NOERROR, NXDOMAIN, etc.) |
| `SourceIP` | IP address of the DNS client |
| `Timestamp` | Timestamp of the query (RFC 3339 format) |

## How It Works

1. Reads zone names from the provided text file
2. Looks up each zone's ID via the Cloudflare API
3. Creates a Logpush job for DNS logs targeting the Splunk HEC endpoint
4. Enables the job via a separate API call
5. Waits 2 seconds between zones to respect API rate limits

If a zone is not found or an API call fails, the error is logged and processing continues to the next zone.

## Example Output

```
Processing zone: example.com
Logpush job enabled for Zone: example.com (ID: abc123), Job ID: 45678
Processing zone: example.org
Logpush job enabled for Zone: example.org (ID: def456), Job ID: 45679
Processing zone: nonexistent.com
WARNING: No zone found for the domain name: nonexistent.com
Done.
```

## License

Free to use, copy, and modify. Attribution appreciated but not required. Provided as-is, with no warranty.
