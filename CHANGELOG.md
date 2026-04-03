# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[unreleased]: https://github.com/andywyatte17/andys-gps-collector/compare/v0.1...HEAD
[0.1]: https://github.com/andywyatte17/andys-gps-collector/releases/tag/v0.1
