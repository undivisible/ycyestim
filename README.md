# YCYEStim

A comprehensive SwiftUI iOS app for controlling YCY-YOKONEX Gen 2 electrostimulation devices.

## Features

- **Liquid Glass UI** — Full iOS 26 glass material support with fallbacks
- **Multi-Channel Control** — Independent Channel A/B with sync mode
- **Waveform Engine** — 11 built-in waveforms + custom waveform drawing editor
- **Presets & Programs** — 8 built-in presets, 2 programs, full custom creation
- **Safety System** — Emergency stop, strength ceilings, session timers, ramp rate limits
- **Adaptive Biometrics** — Optional HealthKit and Apple Watch heart-rate monitoring reduces output during elevated load and can emergency stop at critical thresholds
- **Watch Companion** — Starts a watchOS workout session so Apple Watch can stream fresh heart-rate samples to Edge Mode
- **Local-First Connections** — Bluetooth BLE and user-owned HTTP/WebSocket bridge control
- **Comprehensive Settings** — 8 categories with 60+ configurable options

## Requirements

- iOS 18.0+ deployment target
- watchOS 11.0+ for continuous Apple Watch heart-rate streaming
- Xcode 16+ baseline; Xcode 26 enables native Liquid Glass surfaces where available
- Swift 6
- HealthKit-capable device for adaptive heart-rate safety; Apple Watch or an external HR sensor is recommended for continuous Edge Mode

## Architecture

```
YCYEStim/
├── Models/          # Data types (Channel, Waveform, Preset, Program, etc.)
├── Services/        # Connection layers (BLE, HTTP) + stores
├── ViewModels/      # MVVM view models (Control, Settings, Device)
├── Views/
│   ├── Control/     # Dashboard, waveforms, presets
│   ├── Session/     # Programs, history
│   └── Settings/    # Settings, device pairing
├── WatchApp/         # Apple Watch workout session + heart-rate streaming
├── Extensions/      # Color, View, String helpers
└── Resources/       # Default presets JSON
```

## Connection Modes

### Bluetooth BLE
1. Settings → Connection → Bluetooth
2. Scan for YCY devices
3. Connect and control directly
4. No internet needed

### HTTP/WebSocket
1. Self-host the [API-bridge](https://github.com/YCY-YOKONEX/API-bridge)
2. Set server URL in Settings
3. Commands sent via HTTP POST / WebSocket

## Protocol

Commands are JSON-encoded and sent through BLE or a user-owned API bridge:

```json
// Channel control
{ "code": "game_opts", "actions": [{ "type": "estim", "action": "control_channel", "data": { "channel": "A", "strength": 60, "duration_ms": 5000 } }] }

// Trigger preset
{ "code": "game_cmd", "id": "preset_id" }

// Emergency stop
{ "code": "game_cmd", "id": "_stop_all" }
```

## Safety

⚠️ Always follow device manufacturer guidelines for safe use.

- Global max strength limit (default 80%)
- Session timeout (default 60 min)
- Ramp rate limiting (5 units/sec)
- Confirmation required above threshold (default 60%)
- Emergency stop always visible
- Shake-to-stop gesture option
- Auto-shutdown on disconnect
- Optional HealthKit heart-rate safety caps output at elevated/high thresholds
- Apple Watch companion can run a workout session for continuous heart-rate updates
- Optional critical heart-rate emergency stop

## Open Source Protocol Coverage

The upstream [YCY-YOKONEX OpenSource](https://github.com/YCY-YOKONEX/YCY-YOKONEX-OpenSource) repository documents multiple protocol paths. YCYEStim intentionally supports only owner-controlled device paths: direct BLE and user-owned HTTP/WebSocket bridge control. Smart lock support is listed upstream as beta and is not implemented here yet.

## Building

Open `YCYEStim` folder in Xcode and build for your device.

No dependencies required — pure Swift + SwiftUI + CoreBluetooth.

## Apple Watch

The watch companion is embedded in the iPhone app and can also run independently.
After installing to iPhone, check the Watch app on iPhone under Available Apps if
automatic watch app installation is disabled. The watch app starts a workout
session and streams fresh heart-rate samples back to Edge Mode.

## License

MIT
