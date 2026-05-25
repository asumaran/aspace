# Release secrets setup

The release workflow (`.github/workflows/release.yml`) is fully functional
without any secrets — it produces an ad-hoc signed release. Adding the
secrets below upgrades the release with proper Apple signing, notarization,
and Sparkle update signing.

All secrets go in **Settings → Secrets and variables → Actions → Repository
secrets** on GitHub.

## Sparkle update signing (recommended first)

Sparkle uses its own EdDSA key pair, independent of Apple. Without this,
the in-app "Check for Updates" menu item will work but won't install any
update (no signature to verify).

### 1. Generate the key pair

Download the Sparkle release tarball once on your machine:

```bash
curl -fL -o /tmp/sparkle.tar.xz \
  https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz
mkdir /tmp/sparkle && tar -xJf /tmp/sparkle.tar.xz -C /tmp/sparkle
/tmp/sparkle/bin/generate_keys
```

`generate_keys` writes the private key to your login Keychain (so it
isn't sitting in a file) and prints the public key.

To export the private key for the GitHub secret:

```bash
/tmp/sparkle/bin/generate_keys -x sparkle-private.key
cat sparkle-private.key  # paste this into the SPARKLE_PRIVATE_KEY secret
rm sparkle-private.key   # do not commit
```

### 2. Add secrets

| Secret | Value |
|--------|-------|
| `SPARKLE_PRIVATE_KEY` | Contents of `sparkle-private.key` (single line, base64) |
| `SPARKLE_PUBLIC_KEY`  | Public key printed by `generate_keys` (single line, base64) |

The public key is then injected into `Info.plist` as `SUPublicEDKey` at
build time so the installed app can verify update signatures.

## Apple Developer ID signing + notarization (optional)

Without this, users opening the app for the first time see a Gatekeeper
warning ("can't be opened because Apple cannot check it for malicious
software"). With it, the app launches cleanly.

Requires an Apple Developer account ($99 / year) and a "Developer ID
Application" certificate.

### 1. Export the certificate as .p12

In Keychain Access, find "Developer ID Application: Your Name (TEAMID)",
right-click → Export → format `.p12` → set a password.

```bash
base64 -i cert.p12 -o cert.p12.b64
cat cert.p12.b64  # paste into APPLE_DEVELOPER_CERT_B64
rm cert.p12 cert.p12.b64
```

### 2. App-specific password for notarization

In <https://appleid.apple.com> → Sign-In and Security → App-Specific
Passwords, generate one for "aspace notarytool". Save it.

### 3. Add secrets

| Secret | Value |
|--------|-------|
| `APPLE_DEVELOPER_CERT_B64`  | base64 of the exported `.p12` |
| `APPLE_DEVELOPER_CERT_PASS` | The password you chose when exporting |
| `APPLE_DEVELOPER_TEAM_ID`   | 10-character team ID (visible in your Developer Portal) |
| `APPLE_NOTARY_USER`         | Your Apple ID email |
| `APPLE_NOTARY_PASS`         | The app-specific password generated above |

## Verifying

After adding the secrets, tag a release (`git tag v0.x.y && git push origin
v0.x.y`). The workflow logs will show which optional steps fired.

A fully-signed release:
- `codesign -dv --verbose=4 /Applications/Aspace.app` shows your Team ID
  and "Authority=Developer ID Application…"
- `spctl -a -vv -t exec /Applications/Aspace.app` says "accepted, source=Notarized Developer ID"
- `appcast.xml` in `main` has a new `<item>` with a valid
  `sparkle:edSignature`
