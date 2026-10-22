# Monitor Brightness

A small native macOS menu bar app that controls external monitor hardware brightness using DDC/CI (VCP `0x10`). Built for Apple Silicon, macOS 13 or later. No dependencies, Dock icon, server, or network access.

## Build and run

Install Apple's Command Line Tools, then run:

```sh
bash scripts/build.sh
open build/MonitorBrightness.app
```

Move the pointer to the external monitor you want to adjust, then open the sun icon in that display's menu bar. The menu shows only that display's brightness slider and name. Moving the pointer to another display will not redirect an existing slider to a different monitor. Built-in displays use macOS's native brightness controls. No keyboard brightness-key interception is included.

Screen targeting uses macOS display IDs matched to DDC framebuffer connections; unmatched or ambiguous connections are disabled. Values are scaled against the monitor's reported maximum. Writes are debounced and serialized off the UI thread, then read back for confirmation. The app refreshes on menu opening, display configuration changes, and wake.

## Install

After building, drag `build/MonitorBrightness.app` into `/Applications`, or run:

```sh
ditto build/MonitorBrightness.app /Applications/MonitorBrightness.app
open /Applications/MonitorBrightness.app
```

Keep the app in Applications before enabling **Launch at Login**. This is an experimental, locally built app. Builds are ad-hoc signed, not Developer ID signed or notarized; downloaded binaries may be blocked by Gatekeeper. Building from source is the supported distribution method for now.

## Troubleshooting

Enable DDC/CI in the monitor's on-screen settings. A direct cable may work when a dock does not. HDR and some monitor presets can lock hardware brightness. Quit other DDC controller apps if requests conflict. Use **Refresh Displays** to reread brightness after changing it elsewhere.

Read-only hardware diagnostics:

```sh
build/MonitorBrightness.app/Contents/MacOS/MonitorBrightness --diagnose
```

By default, the app enables a slider only after receiving a valid brightness response. For monitors that may accept writes but cannot return brightness, enable **Allow Unverified Brightness Control**. This session-only option exposes a manual slider assuming a 0–100 hardware range. Its initial value is unknown (shown as a dash); no command is sent until you move the slider. “Sent” only confirms transport success, so check the physical monitor for a change. There is no software dimming fallback. Intel Macs, Apple-native brightness protocols, and DisplayLink are outside the current scope.

## Checks

```sh
bash scripts/test.sh
```

Tests cover response checksum, length, unsupported VCP replies, invalid ranges, and 16-bit values. Physical brightness changes require a supported connected monitor and must be checked on the hardware.

Hardware brightness read/write/readback has been verified with a Lenovo 27Q-11 on an Apple M4 Pro. This is limited hardware coverage, not universal monitor compatibility. A Ugreen CM639 adapter path returned invalid replies during testing. Adapter, cable, monitor mode, and macOS version can affect DDC support.

## Implementation notes

Uses dynamically resolved private IOAVService I2C functions and external `DCPAVServiceProxy` registry entries. macOS updates can change these interfaces. Packet framing was checked against the [MonitorControl implementation](https://github.com/MonitorControl/MonitorControl/blob/main/MonitorControl/Support/Arm64DDC.swift). No third-party source is bundled.

## Contributing

Bug reports should include your Mac/chip, macOS version, monitor model, connection path, and whether the monitor's own brightness setting changes. Remove serial numbers and personal paths from diagnostic output before posting. Run `bash scripts/test.sh` and `bash scripts/build.sh` before submitting a change.

## Credits and license

Transport research references: [MonitorControl](https://github.com/MonitorControl/MonitorControl), [m1ddc](https://github.com/waydabber/m1ddc), and [AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC). These projects helped document Apple's private display interfaces.

MIT license; see [LICENSE](LICENSE).
