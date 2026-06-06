# Codex Health Menu

A tiny macOS menu bar cockpit for Codex cloud usage and local machine health.

It combines the existing Codex usage meter with local thermal state and memory usage so the menu bar only needs one status item.

## Menu Bar Modes

Use the dropdown `Display` submenu to choose:

- `Both`: `59% (3h) 79% (5d) | OK | RAM 45%`
- `Codex Only`: `59% (3h) 79% (5d)`
- `Local Health Only`: `OK | RAM 45%`
- `Rotate`: alternates between Codex and Local Health

Use `Rotation Interval` to choose 5, 10, 15, 30, or 60 seconds.

## What It Shows

Codex:

- Short-window remaining usage and reset timer.
- Weekly remaining usage and reset timer.
- Local Codex token activity from `~/.codex/state_5.sqlite`.

Local Health:

- Exact temperature in C when a usable Apple Silicon HID temperature sensor is available.
- Otherwise, macOS thermal state: `OK`, `Warm`, `Hot`, or `Crit`.
- Memory used percentage from Mach VM stats.
- RAM used total.

## Color Rules

Codex remaining:

- Green: 50% or more remaining
- Yellow: 20-49% remaining
- Red: below 20% remaining

Temperature:

- Green: below 75 C, or thermal state `OK`
- Yellow: 75-89 C, or thermal state `Warm`
- Red: 90 C or hotter, or thermal state `Hot` / `Crit`

Thermal throttling warning:

- A `!` warning marker appears next to temperature only when thermal state is `Serious` or `Critical`
- This warning is temperature / thermal-state driven, not memory driven

Memory used:

- Green: below 70% used
- Yellow: 70-84% used
- Red: 85% used or higher

## Notes

- Refreshing Codex usage should not consume model tokens.
- Codex usage polls every five minutes.
- Local health refreshes every five seconds.
- It reads your local Codex auth token but never displays or logs it.
- While running, it sends that token as an `Authorization: Bearer ...` header to `https://chatgpt.com/backend-api/codex/usage`.
- Apple Silicon does not expose CPU die temperature through a stable public API, so this app tries an opportunistic HID temperature sensor first and falls back to macOS thermal state when no valid sensor reading is available.

## Requirements

- macOS 13 or newer.
- Apple Silicon Mac by default (`build.sh` targets `arm64-apple-macos13.0`).
- Xcode Command Line Tools with `swiftc`.
- An existing Codex login in `~/.codex/auth.json`.

## Build

```sh
./build.sh
```

The app bundle is created at:

```text
build/Codex Health.app
```

## Install

The intended app location is:

```text
/Applications/Codex Health.app
```

The app dropdown includes `Launch at Login`.

It also includes quick links for:

- `Open Codex Usage Page`
- `Open Activity Monitor`
