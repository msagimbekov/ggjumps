"""Finds (or creates) the App Store provisioning profile for the app, signed with the given
Apple Distribution certificate, through the App Store Connect API, and installs it.

Used by .github/workflows/testflight.yml so builds sign with the one Distribution certificate
kept in the repository secrets: automatic signing created a new Development certificate on
every CI run until Apple's limit was reached.

    python3 tools/ci/app_store_profile.py <bundle id> <cert.pem> <AuthKey.p8> <key id> <issuer id>

Prints the profile's UUID on the last line. Standard library only; the JWT is signed with the
system openssl (ES256).
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1/"
PROFILE_NAME = "ggjumps CI App Store"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(sig: bytes) -> bytes:
    """ECDSA DER signature (SEQUENCE of two INTEGERs) to the 64-byte r||s JWT wants."""
    assert sig[0] == 0x30
    i = 2 if sig[1] < 0x80 else 2 + (sig[1] & 0x7F)
    out = b""
    for _ in range(2):
        assert sig[i] == 0x02
        n = sig[i + 1]
        num = sig[i + 2:i + 2 + n].lstrip(b"\x00")
        out += num.rjust(32, b"\x00")
        i += 2 + n
    return out


def token(key_path: str, key_id: str, issuer: str) -> str:
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    now = int(time.time())
    payload = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 900,
                                 "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{header}.{payload}".encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path], input=signing_input,
                         capture_output=True, check=True).stdout
    return f"{header}.{payload}.{b64url(der_to_raw(der))}"


def call(jwt: str, method: str, path: str, body=None) -> dict:
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"Bearer {jwt}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path} failed: {e.code} {e.read().decode()[:600]}")


def main() -> None:
    bundle, cert_pem, key_path, key_id, issuer = sys.argv[1:6]
    jwt = token(key_path, key_id, issuer)

    serial = subprocess.run(["openssl", "x509", "-in", cert_pem, "-noout", "-serial"],
                            capture_output=True, text=True, check=True).stdout.strip().split("=")[1]
    serial = serial.upper().lstrip("0")

    q = urllib.parse.urlencode({"filter[identifier]": bundle, "limit": 200})
    bundles = [b for b in call(jwt, "GET", f"bundleIds?{q}")["data"] if b["attributes"]["identifier"] == bundle]
    if not bundles:
        sys.exit(f"No bundle id {bundle} in the account")
    bundle_id = bundles[0]["id"]

    certs = call(jwt, "GET", "certificates?limit=200")["data"]
    matching = [c for c in certs if c["attributes"]["serialNumber"].upper().lstrip("0") == serial]
    if not matching:
        sys.exit(f"Certificate {serial} not found in the account")
    cert_id = matching[0]["id"]
    print(f"bundle {bundle} = {bundle_id}, certificate {serial} = {cert_id} "
          f"({matching[0]['attributes']['certificateType']})")

    # Reuse our profile while it is valid and still holds this certificate; otherwise make a new one.
    q = urllib.parse.urlencode({"filter[name]": PROFILE_NAME, "include": "certificates,bundleId", "limit": 50})
    profile = None
    for p in call(jwt, "GET", f"profiles?{q}")["data"]:
        rel = p["relationships"]
        ok = (p["attributes"]["profileState"] == "ACTIVE"
              and rel["bundleId"]["data"]["id"] == bundle_id
              and any(c["id"] == cert_id for c in rel["certificates"]["data"]))
        if ok:
            profile = p
            break
        print(f"removing stale profile {p['id']} ({p['attributes']['profileState']})")
        call(jwt, "DELETE", f"profiles/{p['id']}")
    if profile is None:
        profile = call(jwt, "POST", "profiles", {"data": {
            "type": "profiles",
            "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
            }}})["data"]
        print("created profile", profile["id"])

    content = base64.b64decode(profile["attributes"]["profileContent"])
    uuid = profile["attributes"]["uuid"]
    folder = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, f"{uuid}.mobileprovision"), "wb") as f:
        f.write(content)
    print(uuid)


if __name__ == "__main__":
    main()
