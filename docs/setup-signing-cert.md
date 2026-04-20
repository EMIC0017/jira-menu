# One-time: Create a stable code-signing cert

Ad-hoc signing (`codesign -s -`) generates a new identity hash every build, so
macOS sees each rebuild as a different app and re-prompts for Keychain access
even after you click "Always Allow". Signing with a self-signed cert that lives
in your login keychain gives every rebuild the same signature, so the ACL
entries you approve once will stick.

No Apple Developer account required.

## Steps

1. Open **Keychain Access.app** (Applications → Utilities).
2. Menu bar: **Keychain Access → Certificate Assistant → Create a Certificate…**
3. Fill in:
   - **Name**: `JiraMenu Dev`
     (Must match `JIRAMENU_SIGN_IDENTITY`; default is `JiraMenu Dev`.)
   - **Identity Type**: `Self Signed Root`
   - **Certificate Type**: `Code Signing`
   - Leave "Let me override defaults" **unchecked**.
4. Click **Create**, then **Continue** through the warnings, then **Done**.

The cert now lives in your login keychain. Verify it's wired up for code signing:

```sh
security find-identity -v -p codesigning | grep "JiraMenu Dev"
```

You should see one line ending in `"JiraMenu Dev"`. If so, the next
`./scripts/build-app.sh` will pick it up automatically.

## First rebuild after switching

The first build with the new cert will still prompt for Keychain access once —
the existing saved credential's ACL only knows about the old ad-hoc signatures.
Click **Always Allow** one more time. Every subsequent rebuild with this cert
will access the credential silently.

## Overriding the identity name

If you want a different name, set the env var before building:

```sh
JIRAMENU_SIGN_IDENTITY="My Custom Name" ./scripts/build-app.sh
```
