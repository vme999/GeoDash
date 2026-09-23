# GeoDash

A single-screen iOS app that shows where you are and how you’re moving: reverse-geocoded address, coordinates, altitude (with vertical accuracy), barometric pressure, speed, course, and a read-only map preview. Built with **SwiftUI**, **Core Location**, **MapKit**, and **Core Motion** (barometer).

## Features

- **Address** — `MKReverseGeocodingRequest` reverse geocoding (throttled), English-formatted when possible.
- **Coordinates** — latitude / longitude to three decimal degrees with cardinal directions.
- **Altitude** — meters plus ± vertical accuracy when available.
- **Pressure** — hPa from the device barometer when supported.
- **Speed** — km/h from GPS speed when valid.
- **Course** — degrees with compass-style label (N, NE, …).
- **Map** — hybrid (satellite + labels), flat elevation; follows MapKit’s user annotation; non-interactive preview.

## Requirements

- Xcode with an iOS SDK matching the project’s deployment target (see **Build Settings → iOS Deployment Target** in `GeoDash.xcodeproj`; currently **26.2**).
- A physical device is recommended for barometric pressure and the most reliable GPS; the Simulator can still exercise parts of the UI.

## Permissions

Declared in the target’s generated Info.plist keys:

| Key | Purpose |
| --- | --- |
| **Location When In Use** | Coordinates, altitude, speed, course, map camera, and reverse geocoding. |
| **Motion & Fitness** | Barometric pressure via `CMAltimeter`. |

## Run

1. Open `GeoDash.xcodeproj` in Xcode.
2. Select an iPhone (or Simulator) destination.
3. **Product → Run** (⌘R).

## Project layout

```
GeoDash/
├── README.md                 # This file
├── LICENSE                   # MIT
├── .gitignore
├── GeoDash.xcodeproj/
│   ├── project.pbxproj
│   └── project.xcworkspace/
└── GeoDash/
    ├── GeoDashApp.swift      # @main entry, UIApplicationDelegate adaptor
    ├── AppDelegate.swift     # Portrait-only supported orientations
    ├── ContentView.swift     # UI and map preview
    ├── LocationManager.swift # Core Location, geocoding, barometer
    └── Assets.xcassets/      # App icon, accent color
```

Licensed under the [MIT License](LICENSE).
