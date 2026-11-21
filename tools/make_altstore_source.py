#!/usr/bin/env python3
"""Generates an AltStore/SideStore source (apps.json) for NOKBOX.
Format: https://faq.altstore.io/developers/make-a-source
"""
import argparse, datetime, json

ap = argparse.ArgumentParser()
ap.add_argument('--version', required=True)
ap.add_argument('--size', type=int, required=True)
ap.add_argument('--download-url', required=True)
ap.add_argument('--icon-url', required=True)
ap.add_argument('--out', required=True)
a = ap.parse_args()

now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
source = {
    "name": "NOKBOX",
    "subtitle": "A MUZIK JUNKIE PARADISE",
    "identifier": "com.nokbox.source",
    "iconURL": a.icon_url,
    "tintColor": "#E5121B",
    "apps": [{
        "name": "NOKBOX",
        "bundleIdentifier": "com.nokbox.nokbox",
        "developerName": "NOKBOX",
        "subtitle": "A MUZIK JUNKIE PARADISE",
        "localizedDescription": "Multi-source music & video player: local library, YouTube feed, Audius, podcasts, radio, synced lyrics, pro EQ on everything.",
        "iconURL": a.icon_url,
        "tintColor": "#E5121B",
        "category": "entertainment",
        "versions": [{
            "version": a.version,
            "date": now,
            "localizedDescription": "Automated build",
            "downloadURL": a.download_url,
            "size": a.size,
            "minOSVersion": "15.0",
        }],
        "appPermissions": {"entitlements": [], "privacy": {}},
    }],
    "news": [],
}
with open(a.out, 'w') as f:
    json.dump(source, f, indent=2)
print(json.dumps(source, indent=2))
