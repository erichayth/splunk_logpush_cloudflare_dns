__author__ = "Eric Hayth <ehayth@cloudflare.com>"
__version__ = "2.0.0"
__date__ = "2026-03-10"

"""
You are free to use, copy, and modify this script for your own purposes.

Attribution is appreciated but not required. Provided as-is, with no warranty.

This version configures Logpush for DNS logs to a Splunk HEC endpoint over SSL (port 8088).
"""

import requests
import time
import json
import urllib.parse
from getpass import getpass


def read_zones(file_path):
    with open(file_path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def create_logpush_job(cf_token, zone_id, zone_name, splunk_url, splunk_token, source_type, channel_id, insecure=False):
    """
    Creates a Logpush job for DNS logs targeting a Splunk HEC endpoint.

    The destination_conf format for Splunk is:
        splunk://<SPLUNK_URL>/services/collector/raw?channel=<CHANNEL>&insecure=<BOOL>&sourcetype=<TYPE>&header_Authorization=Splunk%20<TOKEN>
    """
    headers = {
        "Authorization": f"Bearer {cf_token}",
        "Content-Type": "application/json",
    }

    logpush_job_name = f"{zone_name}-dns-splunk"
    logpush_url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/logpush/jobs"

    # URL-encode the Splunk HEC token for the Authorization header value
    encoded_token = urllib.parse.quote(f"Splunk {splunk_token}", safe="")

    # Build the Splunk destination configuration
    destination_conf = (
        f"splunk://{splunk_url}/services/collector/raw"
        f"?channel={channel_id}"
        f"&insecure={str(insecure).lower()}"
        f"&sourcetype={source_type}"
        f"&header_Authorization={encoded_token}"
    )

    logpush_job_body = {
        "name": logpush_job_name,
        "destination_conf": destination_conf,
        "logpull_options": "fields=ColoCode,EDNSSubnet,EDNSSubnetLength,QueryName,QueryType,ResponseCached,ResponseCode,SourceIP,Timestamp&timestamps=rfc3339",
        "dataset": "dns_logs",
    }

    create_response = requests.post(logpush_url, headers=headers, data=json.dumps(logpush_job_body))
    create_response.raise_for_status()
    return create_response.json().get("result", {}).get("id")


def enable_logpush_job(cf_token, zone_id, logpush_id):
    headers = {
        "Authorization": f"Bearer {cf_token}",
        "Content-Type": "application/json",
    }
    enable_url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/logpush/jobs/{logpush_id}"
    enable_body = {"enabled": True}
    enable_response = requests.put(enable_url, headers=headers, data=json.dumps(enable_body))
    enable_response.raise_for_status()
    return enable_response.json().get("success", False)


def main():
    cf_token = getpass("Enter Cloudflare API Token: ")

    # Splunk HEC configuration
    splunk_host = input("Enter Splunk HEC hostname or IP (e.g. splunk.example.com): ")
    splunk_port = input("Enter Splunk HEC port [8088]: ").strip() or "8088"
    splunk_url = f"{splunk_host}:{splunk_port}"
    splunk_token = getpass("Enter Splunk HEC Token: ")
    source_type = input("Enter Splunk sourcetype [cloudflare:dns]: ").strip() or "cloudflare:dns"
    channel_id = input("Enter Splunk HEC Channel ID (UUID): ")
    insecure_input = input("Allow insecure (skip TLS verification)? [y/N]: ").strip().lower()
    insecure = insecure_input in ("y", "yes")

    zones_file = input("Enter the path to a text file containing the list of zones by name: ")
    zones = read_zones(zones_file)

    for zone_name in zones:
        zone_id = None
        zone_lookup = requests.get(
            f"https://api.cloudflare.com/client/v4/zones?name={zone_name}",
            headers={"Authorization": f"Bearer {cf_token}"},
        ).json().get("result")

        if zone_lookup:
            zone_id = zone_lookup[0].get("id")
        else:
            print(f"No zone found for the domain name: {zone_name}")
            continue

        try:
            logpush_id = create_logpush_job(
                cf_token, zone_id, zone_name,
                splunk_url, splunk_token, source_type, channel_id, insecure,
            )
            if logpush_id and enable_logpush_job(cf_token, zone_id, logpush_id):
                print(f"Logpush job enabled for Zone: {zone_name} (ID: {zone_id}), Job ID: {logpush_id}")
            else:
                print(f"Error enabling logpush job for zone: {zone_name}")
        except requests.exceptions.HTTPError as e:
            print(f"API error for zone {zone_name}: {e}")
            print(f"Response: {e.response.text}")
        except Exception as e:
            print(f"Unexpected error for zone {zone_name}: {e}")

        time.sleep(2)


if __name__ == "__main__":
    main()
