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
import base64
import binascii
import json
import os
import pathlib
import sys
import time
import urllib.request
import urllib.error

import jwt as pyjwt

POLL_WAITS = (20, 40, 60, 90)


def private_key() -> str:
    """The signing key as PEM text, however it happens to be supplied.

    ASC_KEY_P8 is stored base64-encoded, because the workflow decodes it
    before handing the file to altool. This script was passing that same
    base64 blob straight to PyJWT, which rejected it with "Unable to load PEM
    file ... MalformedFraming". It only ever ran on the altool-failure path,
    so the crash sat unnoticed behind a failure it was written to rule out.

    Prefer the file the workflow already wrote — it is the exact bytes altool
    authenticated with — and fall back to the environment variable, decoding
    it only if it is not already PEM.
    """
    key_id = os.environ["ASC_KEY_ID"]
    on_disk = pathlib.Path.home() / "private_keys" / f"AuthKey_{key_id}.p8"
    if on_disk.is_file():
        text = on_disk.read_text()
        if "PRIVATE KEY" in text:
            return text

    raw = os.environ["ASC_KEY_P8"]
    if "PRIVATE KEY" in raw:
        return raw
    try:
        decoded = base64.b64decode(raw, validate=False).decode()
    except (binascii.Error, UnicodeDecodeError) as exc:
        raise SystemExit(f"ASC_KEY_P8 is neither PEM nor base64 PEM: {exc}")
    if "PRIVATE KEY" not in decoded:
        raise SystemExit("ASC_KEY_P8 decoded to something that is not a PEM key")
    return decoded


def token() -> str:
    return pyjwt.encode(
        {
            "iss": os.environ["ASC_ISSUER_ID"],
            "exp": int(time.time()) + 900,
            "aud": "appstoreconnect-v1",
        },
        private_key(),
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
