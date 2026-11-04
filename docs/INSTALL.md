# Installing Soonbar

Needs macOS 14 or later (Apple silicon or Intel). The Apple Intelligence features need macOS 26 and Apple
Intelligence turned on; everything else works without them.

## The easy way

```bash
curl -fsSL https://raw.githubusercontent.com/AhmedEzzat12/soonbar/main/scripts/install-latest.sh | bash
```

This installs the latest release into Applications and opens it. Click the calendar icon in the menu bar →
**Grant Access**. From then on the app updates itself (Settings → General → Updates). Run the command again any
time to reinstall.

## Download it yourself

Get `Soonbar.zip` from the [latest release](https://github.com/AhmedEzzat12/soonbar/releases/latest), unzip it and
move `Soonbar.app` to Applications. The first launch is blocked by macOS; see below.

## "Soonbar.app" Not Opened / "Apple could not verify…"

Soonbar is free and open source but not notarized by Apple (that needs a paid developer account), so macOS
blocks copies downloaded in a browser. Do **one** of these, once. Updates the app installs itself aren't blocked.

1. **System Settings:** click **Done** on the warning, then **System Settings → Privacy & Security** → scroll to
   *Security* → **Open Anyway** next to "Soonbar.app was blocked", and confirm.
2. **Terminal:** clear the download's quarantine flag, then open the app normally:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Soonbar.app
   ```
3. **Use the easy way above:** `curl` downloads aren't quarantined, so the warning never appears.

If there's no **Open Anyway** button, or *Allow applications from* says "configured by a profile", your Mac is
managed by an organization. Options 2 and 3 usually still work; if not, build from source.

## Build from source

For Macs that block downloaded apps, or to run unreleased changes. Needs the Command Line Tools
(`xcode-select --install`); Xcode isn't required.

```bash
git clone https://github.com/AhmedEzzat12/soonbar.git
cd soonbar
scripts/update-from-source.sh          # the latest release
scripts/update-from-source.sh --main   # or the newest code
```

It builds in a temporary checkout (cleaned up even if the build fails), replaces any installed copy in
`~/Applications` and opens it. Your settings are kept. Source builds don't update themselves: run the script
again to update. Each rebuild looks like a new app to macOS, which then asks for Calendar and Reminders access
again; the [developer guide](DEVELOPMENT.md) explains how a signing certificate avoids that.
