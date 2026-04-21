# JiraMenu

A tiny macOS menubar app for searching your Jira Cloud instance. Click the
magnifying-glass icon in the menubar (or use the keyboard shortcut you
configure), type an issue key, paste a Jira URL, or search free-text —
then hit Enter to open the result in your browser.

Built in SwiftUI for macOS 13+. Credentials live in the system Keychain.
No analytics, no telemetry, no third-party dependencies.

## Install

Via Homebrew (recommended):

```sh
brew tap emic0017/jira-menu
brew install --cask jira-menu
```

Or download the DMG directly from the
[latest release](https://github.com/EMIC0017/jira-menu/releases/latest)
and drag `JiraMenu.app` into `/Applications`.

## First launch — approve the unsigned app

**JiraMenu is not signed with an Apple Developer ID.** On macOS 15 (Sequoia)
and later, that means the first time you try to open it, the system will
block it with a dialog like:

> "JiraMenu.app" Not Opened
> Apple could not verify "JiraMenu.app" is free of malware that may harm
> your Mac or compromise your privacy.

This is macOS being cautious about unidentified developers. The app is
fine; you just need to approve it once. The right-click → Open bypass
that worked on older macOS was removed — you have to approve it through
System Settings now.

**Steps:**

1. Double-click `JiraMenu.app` (or run `open /Applications/JiraMenu.app`).
   The "Not Opened" dialog will appear. Click **Done** — *not* "Move to
   Trash", which would delete the app.
2. Open **System Settings** → **Privacy & Security**.
3. Scroll to the bottom. Under **Security**, you'll see a banner:
   > "JiraMenu.app" was blocked to protect your Mac.
4. Click **Open Anyway**.
5. Authenticate with Touch ID or your password.
6. One more confirmation dialog appears — click **Open**.

That's it. The approval is remembered for this install; you won't see
the dialog again until the next time you upgrade (reinstall regenerates
the signature hash, and macOS treats it as a different binary).

### Why every upgrade re-triggers this

macOS keys the approval to the app's exact code-signature hash. Each
build produces a fresh ad-hoc hash, so an upgrade via
`brew upgrade --cask jira-menu` requires the same approval flow again.
The only way to avoid this is Developer ID signing + Apple notarization,
which costs $99/year for an Apple Developer Program membership — not
currently worth it for this personal project. If that changes, the
friction goes away.

## First-run setup

On first launch, JiraMenu shows a settings window asking for:

- **Jira site URL** — e.g. `https://your-company.atlassian.net`
- **Email** — the Atlassian account email you'd use to log in
- **API token** — generated at
  [id.atlassian.com/manage-profile/security/api-tokens](https://id.atlassian.com/manage-profile/security/api-tokens)

Credentials are stored in the macOS Keychain, not in a config file. They
never leave your machine except to talk to your Jira instance's REST API.

After saving, the settings window closes and the menubar icon appears.
Click it to open the search popover.

## Using it

Click the menubar icon. The popover opens with a search field. Three
input modes, detected automatically:

| You type… | JiraMenu does… |
|---|---|
| `PSO-1234` | Direct lookup of that exact issue |
| `https://company.atlassian.net/browse/PSO-1234` | Extracts the key from the URL, same as above |
| `login flow bug` | JQL `text ~ "…"` search across all issues you can see |

Click any result (or press Enter on the first one) to open
`/browse/KEY` in your default browser.

## Uninstall

```sh
brew uninstall --cask --zap jira-menu   # removes the app and Keychain items
brew untap emic0017/jira-menu           # optional: also drop the tap
```

`--zap` is the Homebrew convention for "also clean up the app's
user-level traces" — in this case the preferences plist, app-scripts
dir, and sandbox container under `~/Library`.

## Building from source

Requires Xcode 16 (Swift 6) and macOS 13+.

```sh
git clone https://github.com/EMIC0017/jira-menu.git
cd jira-menu
./scripts/build-app.sh 0.0.0-dev
open build/JiraMenu.app
```

The build script produces a universal (`arm64` + `x86_64`) release
binary and stages it into a proper `.app` bundle with the correct
`Info.plist`. If you have a self-signed code-signing cert named
`JiraMenu Dev` in your login keychain (see
[`docs/setup-signing-cert.md`](docs/setup-signing-cert.md)), it'll use
that; otherwise it falls back to ad-hoc signing.

Run tests with:

```sh
swift test
```

## Releasing

Tag a commit on `main` with a `vX.Y.Z` tag and push; the GitHub Actions
workflow builds the DMG, uploads it to a new GitHub Release, and
auto-bumps the Homebrew cask in
[`EMIC0017/homebrew-jira-menu`](https://github.com/EMIC0017/homebrew-jira-menu).

```sh
git tag v0.1.4
git push origin v0.1.4
```

See [`.github/workflows/release.yml`](.github/workflows/release.yml) for
the full pipeline.

## License

MIT.
