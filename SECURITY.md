# Security

Shore is a public alpha of a local macOS menu-bar app. This note is the honest security posture for the tree as published. It is not a penetration test and it is not a claim of notarization.

## What this build is not

- Not Developer ID signed
- Not notarized, and not stapled
- Not an App Store build
- Not sandboxed
- Not a promise of commercial island or shelf polish

An ad-hoc or unsigned build will trip Gatekeeper. For a binary you compiled yourself, or a DMG attached to this GitHub project by the maintainer: right-click `Shore.app` → **Open** → **Open**. Or use System Settings → Privacy & Security → **Open Anyway**. Do not disable Gatekeeper globally, and do not `xattr -cr` downloads you did not build.

`scripts/package-dmg.sh` signs with `CODE_SIGN_IDENTITY` (default `-`, ad-hoc) and does not run `notarytool`.

## Data leaving the machine

No telemetry, no analytics, no account, and no API keys are expected in this repo. A scan of the working tree and of git history found no committed `.env`, credentials, tokens, or private keys.

The app does not ship a network client. Now-playing, battery, and volume stay on device:

| Source | What it reads | Network |
| --- | --- | --- |
| MediaRemote (private system framework, `dlopen` of a fixed path) | Now-playing title, artist, artwork, transport commands | No |
| IOKit power sources | Internal battery level and charging | No |
| CoreAudio default output device | Volume and mute | No |
| UserDefaults | Island toggles and the parked-file list | No |

The MediaRemote handle is opened with `RTLD_LOCAL` so those symbols are not dumped into the process-global namespace. The path is the system framework, not a path from a drop or a setting.

## Entitlements and TCC

`Shore/Shore.entitlements` keeps a single App Sandbox decision. Xcode has Hardened Runtime enabled (`ENABLE_HARDENED_RUNTIME = YES`) for Debug and Release. The identity is ad-hoc (`CODE_SIGN_IDENTITY = "-"`), so Hardened Runtime here is a build setting on an unsigned-for-distribution binary, not a notarized runtime.

| Entitlement | Value | Why |
| --- | --- | --- |
| `com.apple.security.app-sandbox` | `false` | Sandbox stays off so now-playing can `dlopen` the private MediaRemote framework. Turning the sandbox on is a separate change and would break that path until it is redesigned. |

Not set, because the app does not use them:

- Accessibility (`AXIsProcessTrusted` and similar are not called)
- Microphone, camera, or speech recognition
- Screen Recording
- Automation / Apple Events (`com.apple.security.automation.apple-events` was removed; nothing sends `NSAppleScript` or `osascript`)
- Hardened Runtime exceptions such as `com.apple.security.cs.disable-library-validation`, JIT, or unsigned dyld environment variables

`Shore/Info.plist` has no privacy usage-description keys. Do not add those strings unless a feature actually prompts for that TCC service. `LSUIElement` only hides the Dock icon.

Reveal in Finder uses `NSWorkspace.activateFileViewerSelecting`. That is Launch Services, not a scripting entitlement. With the sandbox off, the removed Apple Events entitlement was not doing useful work.

## File shelf paths

Parking stores a reference. It does not copy the file into Application Support, and removing or clearing a token does not delete the file on disk.

Accepted drops and values restored from UserDefaults must pass `ParkedFilePath.accept`:

1. File URL only (`file:` scheme). `http` and other schemes are refused.
2. Local host only (empty host or `localhost`). A `file://` URL aimed at another machine is refused.
3. Absolute path. Relative strings are refused so they cannot be resolved against the process working directory. The old `file://` string strip was removed for that reason.
4. Lexically standardized, then symlink-resolved. A leftover `..` or `.` component is refused.
5. The resolved path must still sit inside the directory of the path that was dropped (that directory’s own symlinks are resolved first). A symlink that points at another directory is refused. The check uses a trailing path separator so a folder named `Park` does not contain `ParkEvil`.
6. The file or folder must exist. Missing paths are dropped.

Nothing in the shelf, the drag basket, or the packaging script feeds a parked path to a shell. `package-dmg.sh` quotes its paths and only runs `xcodebuild` / `hdiutil` with fixed project arguments.

## Reporting

Open a [GitHub issue](https://github.com/realvaleh/Shore/issues) for bugs. If the report describes a vulnerability and private vulnerability reporting is enabled on the repo, use that instead of a public issue so the details are not published before a fix.

## License

[MIT](LICENSE) © 2026 Valeh.
