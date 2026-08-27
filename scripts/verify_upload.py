#!/usr/bin/env python3
"""Confirm a build actually reached App Store Connect.

altool exits non-zero on a 409 even when the delivery succeeded — squad comms
builds 3, 4 and 7 all went VALID at Apple while the CI step reported failure,
and an earlier attempt to "fix" it by retrying altool made things worse by
re-uploading a build that already existed. The only reliable signal is asking
App Store Connect what it actually has.

Usage: verify_upload.py <app_id> <build_number>
Env:   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8
"""
import json
import os
import sys
import time
import urllib.request
import urllib.error

import jwt as pyjwt

POLL_WAITS = (20, 40, 60, 90)


def token() -> str:
    return pyjwt.encode(
        {
            "iss": os.environ["ASC_ISSUER_ID"],
            "exp": int(time.time()) + 900,
            "aud": "appstoreconnect-v1",
        },
        os.environ["ASC_KEY_P8"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"]},
    )


def builds(app_id: str) -> list:
    request = urllib.request.Request(
        "https://api.appstoreconnect.apple.com/v1/builds"
        f"?filter[app]={app_id}&sort=-uploadedDate&limit=10",
        headers={"Authorization": "Bearer " + token()},
    )
    return json.load(urllib.request.urlopen(request))["data"]


def main() -> int:
    app_id, wanted = sys.argv[1], sys.argv[2]
    for wait in POLL_WAITS:
        time.sleep(wait)
        try:
            found = builds(app_id)
        except urllib.error.HTTPError as exc:
            print(f"App Store Connect returned {exc.code}; retrying")
            continue
        if any(b["attributes"].get("version") == wanted for b in found):
            print(f"build {wanted} is present in App Store Connect - delivered")
            return 0
        have = [b["attributes"].get("version") for b in found]
        print(f"build {wanted} not visible yet; currently {have}")
    print(f"build {wanted} never appeared - treating as a genuine failure")
    return 1


if __name__ == "__main__":
    sys.exit(main())
