# Octo for iPhone

A native SwiftUI player for Octo and any Subsonic server, built and installed
from Windows or Linux with [xtool](https://github.com/xtool-org/xtool). No Mac
is needed.

On iPhone every glass surface is Apple's own Liquid Glass: the tab bar, the
mini player in its accessory, the player's controls and the icon.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/OctoKit` | Talking to the server: signing, the models, stream and cover addresses, play rules. Foundation only. |
| `Sources/Octo` | The app: SwiftUI screens, the player (AVFoundation), lock screen and remote controls. |
| `Tests/OctoKitTests` | OctoKit's tests. They run on Linux. |
| `AppIcon.icon` | The Icon Composer icon, written by `tools/appicon/make_app_icon.py ios`. |
| `Resources/AppIcon.png` | The flat icon for builds without the compiled `Assets.car`. |
| `Info.plist`, `xtool.yml` | What xtool adds to the app bundle. |

## Set up once (WSL on Windows)

1. Install the Swift 6.4 toolchain with swiftly, then `usbmuxd` and
   `libimobiledevice-utils` from apt, and the xtool AppImage on the `PATH`
   (the steps are in xtool's
   [Linux guide](https://github.com/xtool-org/xtool/blob/main/Documentation/xtool.docc/Installation-Linux.md)).
2. Download Xcode 27 as a `.xip` from Apple's developer downloads.
3. Run `xtool setup` and sign in with an App Store Connect API key (Team key,
   App Manager role), then point it at the `.xip`.

The phone does not need USB passthrough. With WSL's mirrored networking,
Windows' Apple Mobile Device Service is reachable from WSL:

```bash
export USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015
idevice_id -l
```

The phone must be plugged in (or paired over Wi-Fi) and trusted on Windows,
and Developer Mode must be on.

## Build and run

```bash
cd ios
USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015 xtool dev
```

## Test

```bash
cd ios
OCTO_KIT_ONLY=1 swift test
```

`OCTO_KIT_ONLY=1` leaves the app target out, since SwiftUI does not exist on
Linux.

## The icon

`python tools/appicon/make_app_icon.py ios` writes `AppIcon.icon`, the flat
`Resources/AppIcon.png`, and the octopus's paths the app draws itself. Liquid
Glass needs the `.icon` compiled into `Assets.car` by Apple's `actool`, which
only runs on macOS: the `iOS icon` workflow does that on a GitHub macOS runner.
