# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2] - 2026-04-04

### Added

- Speedometer
    - Live speed chart during recording and historical
      playback on past tracks (line or bar chart modes)
    - Configurable speed units (mph, kph, min/km) and
      time windows (All, 30s, 1m, 5m)
    - Bar chart colour-codes GPS accuracy: green (0-5m),
      yellow (5-20m), red (20m+)

## [0.1] - 2026-04-03

### Added

- GPS Tracking
    - Record / Pause / Resume / Stop with full state machine
    - GPS data capture: lat/long, accuracy, speed, altitude,
      heading
    - Pause/unpause events stored alongside point events
    - Time tracking relative to track start (ms since start)
    - 10s polling interval to conserve battery
    - Live GPS data debug panel (toggle via bug icon during
      recording)
- Permissions
    - Foreground and background location permission checks
    - Battery optimization exemption check
    - User-facing instructions when permissions are missing
- Track History
    - List of all recorded tracks, newest first
    - Rename and delete (with confirmation) per track
    - Distance covered (Haversine sum) and duration display
    - Approximate pace (min/km)
    - Copy GPX to clipboard
    - Save GPX to file (Downloads / app documents)
    - Navigate to Map or GPS Events view per track
- GPS Events Viewer
    - Table of all events with type, time, coordinates,
      accuracy, source
    - Source inference (GPS / Network / Fused / Mock),
      colour-coded
    - Accuracy breakdown summary: 0-5m, 5-20m, 20m+
    - Bulk removal of low-accuracy events (20m+ or 5m+)
      with confirmation
- Map Display
    - OpenStreetMap tile layer via flutter_map
    - Track drawn as polyline with border for visibility
    - Auto-centres and zooms to fit track bounding box
    - Pinch zoom and two-finger pan
    - Zoom level control (11-19) and Pan Reset button
    - Three line colour styles (blue / green / orange),
      persisted
    - Accuracy filter toggle (All / 20m / 10m / 5m),
      persisted
- Map Tile Caching
    - SQLite-backed cache, 50 MB max with LRU eviction
    - 7-day tile age policy; falls back to stale cache on
      network failure
    - Cache stats visible in Debug screen (hits, bytes
      loaded and served)
- Database and Debug
    - SQLite with auto-creation and migration
    - VACUUM at startup for space reclamation
    - Debug screen: track counts, point counts, DB file
      size, tile cache stats

[unreleased]: https://github.com/andywyatte17/andys-gps-collector/compare/v0.2...HEAD
[0.2]: https://github.com/andywyatte17/andys-gps-collector/compare/v0.1...v0.2
[0.1]: https://github.com/andywyatte17/andys-gps-collector/releases/tag/v0.1
