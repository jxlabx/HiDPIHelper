[简体中文](README.zh-CN.md) | English

<p align="center"><img src="Assets/AppIcon.png" width="128" alt="HiDPI Helper icon"></p>
<h1 align="center">HiDPI Helper</h1>
<p align="center">Text at just the right size on your external display.</p>

A lightweight macOS menu bar app for switching HiDPI modes, creating display overrides, and restoring a saved mode after login, wake, or reconnection. Built with Swift and system frameworks, with no third-party runtime dependencies.

## Features

- Select an external display and set your preferred desktop dimensions.
- Switch to HiDPI or to a native mode explicitly identified by macOS.
- Automatically restore the previous mode unless you confirm within 15 seconds.
- Launch at login and restore the last saved display mode.
- Generate, install, check, and restore display overrides independently of other display tools.
- Preserve existing settings, back up before installation, and verify installed bytes.
- Includes a 2048 × 1152 preset for the DELL U2518D; enter custom dimensions for other models.
- English and Simplified Chinese interfaces, following your preferred system language, with a GitHub link at the bottom of the window.

## Requirements and tested scope

Requires **macOS 13 or later**. Build from source on Apple silicon or Intel Macs; release archive names identify their architecture.

| Scope | Status |
| --- | --- |
| External display selection and vendor/model-specific overrides | Implemented |
| Configuration generation and restoration for 16:9, 16:10, and ultrawide dimensions | Covered by isolated tests |
| DELL U2518D at 2048 × 1152 HiDPI | Installation, restart, and automatic restoration verified on hardware |
| Other displays, connections, GPUs, or macOS versions | Require verification; macOS may reject the requested mode |
| Multiple displays | Select and install overrides separately; automatic restoration manages only the last saved display |
| Built-in or virtual displays, EDID editing, HDR controls | Not supported |

Overrides apply to a **vendor and model**, affecting displays of the same model. Automatic restoration also matches the hardware serial number. If multiple displays have identical identifiers, the app will not automatically choose one.

Allowed target dimensions are 320–8192 pixels wide and 200–8192 pixels high. These are input limits, not hardware guarantees. Keep the panel’s native aspect ratio where possible. Larger rendering dimensions increase GPU and memory usage.

## Install and use

1. Download the archive for your architecture from [Releases](https://github.com/jxlabx/HiDPIHelper/releases), or build from source below.
2. Move `HiDPI Helper.app` to Applications, open it, and select an external display.
3. Enter the desired desktop dimensions and click **Save Target Size**. Changing the target disables automatic restoration; enable it again after confirming the new mode.
4. Click **Use HiDPI**. If the mode is unavailable, click **Create / Repair…** and complete administrator authentication in Terminal.
5. After installation, save your work and restart. Reopen the app, check the configuration, switch to the target mode, and click **Keep Changes** within 15 seconds.
6. Enable **Launch at Login** and automatic restoration as needed.

Release builds are ad-hoc signed and **not notarized by Apple**. Follow your environment’s software policies, or build locally from source.

Closing the window leaves the app running in the menu bar. Use **Quit** in the menu bar menu to exit. An unconfirmed mode change is restored on exit.

Before moving the app, disable Launch at Login; enable it again after moving. Check the login item after replacing the app during an upgrade.

## How scaling works

For a 2560 × 1440 panel with a 2048 × 1152 desktop:

```text
2048 × 1152 desktop layout
        ↓ Draw at 2× pixel precision
4096 × 2304 rendered image
        ↓ macOS scales to the panel
2560 × 1440 physical pixels
```

Text and controls appear approximately 25% larger. HiDPI draws at higher precision but still involves resampling: it cannot add physical pixels or guarantee the sharpness of integer scaling.

The generator requests scaling modes without modifying EDID. **Successful installation does not mean the mode is active.** macOS or the hardware may reject it; check the actual mode after restarting.

## System files and restoration

Override location:

```text
/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<vendor-hex>/DisplayProductID-<product-hex>
```

Backups and installation records:

```text
/Library/Application Support/LocalHiDPIHelper/<vendor>-<product>/
```

**Restore Previous Configuration…** restores the state before the most recent actual installation for that model. If no override existed, the installed file is moved into the backup directory. Backups are retained. If another tool has modified the override since installation, restoration stops to preserve those changes. Restart after restoring.

Changing system overrides requires administrator authentication. The app does not store your password, install a persistent privileged service, or disable system protections. Avoid managing the same model’s override with multiple tools simultaneously.

## Build from source

Install the Xcode Command Line Tools, then run:

```sh
./Scripts/test.sh
./Scripts/build.sh
```

The app is built at `dist/HiDPI Helper.app`. Building does not install system overrides, change the current display mode, or register a login item.

Packaging defaults to the current architecture. To select one explicitly:

```sh
BUILD_ARCH=arm64 ./Scripts/package.sh
BUILD_ARCH=x86_64 ./Scripts/package.sh
```

Regenerate the icon with `./Scripts/generate-icon.sh`. Vector paths in `Assets/GenerateIcon.swift` produce sizes from 16 to 1024 pixels.

## Command line

The bundled `ConfigTool` reads an explicit JSON profile:

```json
{
  "vendorID": 4268,
  "productID": 16700,
  "serialNumber": 0,
  "width": 2048,
  "height": 1152
}
```

```sh
APP='dist/HiDPI Helper.app'
"$APP/Contents/MacOS/ConfigTool" check profile.json
"$APP/Contents/MacOS/ConfigTool" generate profile.json display.plist
sudo "$APP/Contents/MacOS/ConfigTool" install profile.json
sudo "$APP/Contents/MacOS/ConfigTool" restore profile.json
"$APP/Contents/MacOS/HiDPIHelper" --diagnose
```

Tests cover different vendor/model identifiers and dimensions, installation into an empty directory, repeated installation, preservation of existing settings, restoration, invalid input, subsequent modifications, and symbolic links. Tests write only inside the project’s build directory, never to system overrides.

## Project layout

```text
Sources/App/          Interface, mode switching, and automatic restoration
Sources/Core/         Shared configuration rules, installation records, and mode discovery
Sources/ConfigTool/   Administrator configuration commands
Tests/                Isolated configuration tests
Scripts/              Build, test, icon, and packaging scripts
Resources/            App metadata and icon
Assets/               Icon source and preview
```

## Contributing and license

Report your display model, macOS version, chip architecture, connection type, and observed behavior through [Issues](https://github.com/jxlabx/HiDPIHelper/issues). Remove serial numbers and other personal information from logs. Hardware verification reports should describe the exact environment and what was tested.

Released under the [MIT License](LICENSE).
