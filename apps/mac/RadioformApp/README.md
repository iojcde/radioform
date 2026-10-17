# `RadioformApp`

Menu bar app for Radioform on macOS. Built with SwiftUI + AppKit.

Last reviewed: March 1, 2026.

## Purpose

`RadioformApp` is the control plane for Radioform:

- Presents onboarding and settings UI.
- Manages EQ and preset state.
- Starts `RadioformHost` when needed.
- Coordinates driver install/update prompts.

It does not run real-time DSP processing.

## Key Capabilities

- Up to 32 parametric EQ filters with scrollable controls with per-band frequency, Q, and filter type.
- Bundled presets plus user presets persisted as JSON.
- AutoEQ parametric `.txt` import/export with exact frequency, gain, Q, preamp, and filter enable states.
- Saved per-output EQ selection in Settings → Audio Outputs.
- First-run onboarding and driver installation flow.
- Sparkle-powered update checks.
- Menu bar-only interaction model.

## Fixed Spatial

The **Fixed Spatial** switch beneath the EQ controls adds a headphone virtual-speaker approximation using frequency-dependent crossfeed, a 0.25 ms contralateral delay, and quiet 2.3–6.1 ms early reflections with different paths for each ear. **Amount** blends the effect with ordinary stereo (40% by default), with a stronger middle range. Direct sound remains dominant at 100% to avoid an overly diffuse room presentation. It does not use head tracking, measured HRTFs, or Apple's Spatialize Stereo renderer, and is not an exact AirPods match.

The effect starts off for existing presets. Radioform JSON presets save its enabled state and amount; AutoEQ text only saves the EQ filters and preamp, so importing text leaves Fixed Spatial off. The main bypass switch also disables Fixed Spatial while retaining the configured amount. DSP changes are smoothed over 20 ms and processing uses fixed buffers without realtime allocation.

## AutoEQ Files

Use **Import AutoEQ…** or **Export AutoEQ…** beneath the preset controls. Import saves a uniquely named user preset and loads it into the editor, respecting the global EQ bypass switch. Export uses the configured values even while EQ is bypassed.

Supported text includes `Preamp` and up to 32 `Filter` entries, with peak, shelf, pass, notch, and band-pass filters. Files must be UTF-8. Frequency must be 20–20,000 Hz, gain/preamp −12 to +12 dB, and Q 0.1–10. Unsupported filters, GraphicEQ curves, and out-of-range values show an error instead of silently changing the curve. AutoEQ text does not contain Radioform limiter settings; imports leave the limiter and Fixed Spatial off.

Longer presets scroll horizontally. Use **Add Filter** to insert a neutral filter; double-click a filter to edit its settings or use **Remove Filter**. The preamp remains a separate control. Existing presets retain their original filter counts and values.

The 32-filter capacity changes the DSP preset structure. Rebuild the DSP library, host, and app together before running the updated version; the installed app will not gain this support until replaced with the rebuilt app and host.

## Output Selection

Open **Settings… → Audio Outputs** to choose which physical outputs get a `(Radioform)` device. Preferences are saved by device UID in `~/Library/Application Support/Radioform/output-devices.json`, so excluded outputs stay excluded after reconnecting or restarting. New outputs default to enabled. Changes apply while the host is running without a driver restart; disabling the active EQ output restores its physical device before removing the proxy. All outputs can be disabled.

Run `bash tools/test_features.sh` from the repository root to test text round trips, invalid input, preset editor mapping, control-file filtering, and saved preferences. The tests disable Keychain and netrc credential lookup.

## Prerequisites

- macOS 13 or newer.
- Xcode command line tools (`xcode-select --install`).
- Built host binary at one of the expected host paths (recommended: `packages/host/.build/release/RadioformHost`).
- Driver bundle available for install/update flows (`RadioformDriver.driver` from `packages/driver`).

## Build

```bash
cd apps/mac/RadioformApp
swift build
```

Release build:

```bash
cd apps/mac/RadioformApp
swift build -c release
```

## Run (Development)

Recommended flow from repo root:

```bash
cd packages/host
swift build -c release

cd ../../apps/mac/RadioformApp
swift run
```

If host discovery fails, the app prompts with:

```bash
cd packages/host && swift build -c release
```

## Runtime Behavior

- On first launch, onboarding is shown until completed.
- On normal launch after onboarding, the app runs as a menu bar accessory app.
- The app launches `RadioformHost` if it is not already running.
- On app termination, cleanup runs and host processes are terminated.

## Data and State Paths

- IPC preset file: `~/Library/Application Support/Radioform/preset.json`
- User presets directory: `~/Library/Application Support/Radioform/Presets/`
- App log: `~/Library/Logs/Radioform/app.log`
- Driver install target: `/Library/Audio/Plug-Ins/HAL/RadioformDriver.driver`

## Developer Flags and Environment

- `--reset-onboarding`: clears onboarding state before app startup.
- `RADIOFORM_ROOT`: optional root path used during host binary discovery.
- `ENABLE_LIQUID_GLASS=1`: forces `LIQUID_GLASS_AVAILABLE` compile define in `Package.swift`.

## Test Utility

`test-presets.sh` cycles bundled presets by writing each one to:

`~/Library/Application Support/Radioform/preset.json`

Run:

```bash
cd apps/mac/RadioformApp
./test-presets.sh
```

## Troubleshooting

- Host not found:
  - Build host in `packages/host` and relaunch app.
- Driver install/update fails:
  - Ensure the driver bundle exists and grant admin privileges when prompted.
- Presets not loading:
  - Verify bundled JSON files exist under `Sources/Resources/Presets`.
  - Check user preset JSON validity in `~/Library/Application Support/Radioform/Presets/`.
