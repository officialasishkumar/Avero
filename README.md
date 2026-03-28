# Avero

Avero is a macOS-first screen recording app built in Swift. The current codebase is a native Swift package with a SwiftUI app shell, ScreenCaptureKit-based recording, click tracking for auto-zoom planning, and an export layer that composes the final video with a background image and soundtrack.

## What it is

Avero is being built to cover the core Screen Studio-style workflow on Mac:

- record the screen on macOS
- track clicks and interaction points
- generate automatic zoom timing
- export onto a custom background image
- mix in background music during export

## Setup

Requirements:

- macOS 15 or newer
- Swift 6.1+
- Xcode installed for full app development and signing

Local commands:

```bash
swift build
swift test
swift run
```

## Current Status

The repo currently contains:

- `AveroApp` for the SwiftUI app entry point
- `AveroCapture` for screen capture and interaction tracking
- `AveroCore` for shared models and auto-zoom planning
- `AveroExport` for the future composition/export pipeline

The current implementation compiles and includes:

- display discovery
- recording start/stop with `ScreenCaptureKit`
- global click tracking while recording
- an auto-zoom planner model with tests
- export controls for background image, music, zoom scale, and audio balance
- MP4 export with zoom ramps, background compositing, and music looping/mixing

## Near-Term Roadmap

- persist projects so captures can be edited after recording
- add a timeline/editor UI for fine-tuning zoom moments
- improve the app packaging/story outside Xcode so launch behavior is more app-like from the terminal

## Notes

This project is intentionally macOS-first. Cross-platform support can come later, after the core recording and export flow is stable.

For now, `swift build` and `swift test` are the reliable terminal workflows. For the best app-run experience, open the package in Xcode while the repo is still using Swift package app bootstrapping rather than a full `.app` project.
