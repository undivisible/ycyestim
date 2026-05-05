# YCYEStim

A comprehensive SwiftUI iOS app for controlling YCY-YOKONEX Gen 2 electrostimulation devices.

## Features

- **Liquid Glass UI** — Full iOS 26 glass material support with fallbacks
- **Multi-Channel Control** — Independent Channel A/B with sync mode
- **Waveform Engine** — 11 built-in waveforms + custom waveform drawing editor
- **Presets & Programs** — 8 built-in presets, 2 programs, full custom creation
- **Safety System** — Emergency stop, strength ceilings, session timers, ramp rate limits
- **Three Connection Modes** — Tencent Cloud IM, Bluetooth BLE, HTTP/WebSocket
- **Comprehensive Settings** — 7 categories with 50+ configurable options

## Requirements

- iOS 26.0+ (for Liquid Glass — falls back to materials on older iOS)
- Xcode 26+
- Swift 6

## Architecture

```
YCYEStim/
├── Models/          # Data types (Channel, Waveform, Preset, Program, etc.)
├── Services/        # Connection layers (IM, BLE, HTTP) + stores
├── ViewModels/      # MVVM view models (Control, Settings, Device)
├── Views/
│   ├── Control/     # Dashboard, waveforms, presets
│   ├── Session/     # Programs, history
│   └── Settings/    # Settings, device pairing
├── Extensions/      # Color, View, String helpers
└── Resources/       # Default presets JSON
```

## Connection Modes

### Tencent Cloud IM (Recommended)
1. Open YCY app, start a game, copy the connect code
2. Paste into Settings → Connection
3. App authenticates via `suo.jiushu1234.com` API
4. Commands sent through Tencent IM SDK

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

Commands are JSON-encoded, sent via the chosen connection layer:

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

## Building

Open `YCYEStim` folder in Xcode and build for your device.

No dependencies required — pure Swift + SwiftUI + CoreBluetooth.
The Tencent Cloud IM SDK would need to be added via Swift Package Manager for production use.

## License

MIT
