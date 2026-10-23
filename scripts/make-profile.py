#!/usr/bin/env python3
"""Turn an IT Hub menu.json into a configuration profile (.mobileconfig) for Jamf or any MDM.

Usage: make-profile.py menu.json output.mobileconfig [--org "Org Name"] [--name "Display name"]
The profile sets the edu.slc.ithub preference domain with the same keys as the JSON file.
"""
import argparse, json, plistlib, uuid, sys
from pathlib import Path

DOMAIN = "edu.slc.ithub"

def build(settings: dict, org: str, name: str) -> dict:
    payload_uuid, profile_uuid = str(uuid.uuid4()).upper(), str(uuid.uuid4()).upper()
    return {
        "PayloadContent": [{
            "PayloadType": DOMAIN,
            "PayloadIdentifier": f"{DOMAIN}.settings.{payload_uuid}",
            "PayloadUUID": payload_uuid,
            "PayloadVersion": 1,
            "PayloadDisplayName": "IT Hub settings",
            "PayloadEnabled": True,
            "settings": settings,
        }],
        "PayloadDisplayName": name,
        "PayloadDescription": "Quick Actions, health thresholds, branding and feature switches for IT Hub.",
        "PayloadIdentifier": f"{DOMAIN}.profile",
        "PayloadOrganization": org,
        "PayloadType": "Configuration",
        "PayloadScope": "System",
        "PayloadUUID": profile_uuid,
        "PayloadVersion": 1,
        "PayloadRemovalDisallowed": False,
    }

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("source"); ap.add_argument("output")
    ap.add_argument("--org", default="IT"); ap.add_argument("--name", default="IT Hub")
    args = ap.parse_args()
    doc = json.loads(Path(args.source).read_text())
    settings = doc.get("settings")
    if not isinstance(settings, dict):
        print("source is not an IT Hub menu.json (missing settings object)", file=sys.stderr); return 1
    Path(args.output).write_bytes(plistlib.dumps(build(settings, args.org, args.name), fmt=plistlib.FMT_XML))
    print(f"Wrote {args.output} (domain {DOMAIN}, {len(settings.get('content', []))} quick-action groups)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
