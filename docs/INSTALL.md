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
move `Soonbar.app` to Applications. Releases are signed and notarized by Apple, so it opens normally.

Versions before 0.7.0 weren't notarized. If one of those shows "Apple could not verify…", click **Done**, then
**System Settings → Privacy & Security → Open Anyway**, or install the current version instead.

## Build from source

For Macs whose organization blocks downloaded apps, or to run unreleased changes. Needs the Command Line Tools
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
