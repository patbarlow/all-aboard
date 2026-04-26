# Changelog

All notable changes to All Aboard will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-04-26

### Changed
- Switched from one-time license keys to a monthly subscription. Sign in with your email to get started — 7-day free trial included, no credit card required.
- Settings: License tab replaced with Account tab showing your email and subscription status.

## [Unreleased]

### Added
- Swap direction button on each trip section header in the menu bar popup.
- Live trip floating card now appears automatically when you pin a departure — no manual toggle needed.
- Settings tab in the trip management window for release channel and beta feature controls.
- Flick-to-corner gesture on the live trip floating card: flick quickly in any direction and it springs to the nearest corner with a bounce. Slow drags stay where you drop them.

### Changed
- Removed "All Aboard" text label from the menu bar icon — just the tram icon now, with a countdown shown when a departure is pinned.
- Live trip card redesigned: smaller and more compact (260 px wide), shows the current station name and time-until-departure prominently. Close button only appears on hover.
- Removed duplicate trip name from the live trip card.
- Removed green colouring from "On time" status in the live trip card — plain text only.
- Live trip card updates every 30 seconds while a departure is pinned and active.
- Live trip card automatically closes and the pin clears ~60 seconds after the pinned departure time.
- Removed the swap direction button from the saved trip cards in the management window — it now lives in the menu bar popup instead.
- Release channel and beta feature settings moved to a dedicated Settings tab, keeping the Trips view cleaner.
