# bwoc-mcc

> SwiftUI macOS menu-bar control center for the BWOC agent fleet.

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg?logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-13.0%2B-blue.svg)](https://www.apple.com/macos)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-alpha-red.svg)](#status)

Live status of your [BWOC](https://github.com/bemindlabs/BWOC-Framework) agent
fleet — agents, sessions, inboxes — surfaced from the macOS menu bar, with
quick actions to spawn, chat, stop, and supervise without leaving your
workflow.

> 🇹🇭 บันทึกภาษาไทย: [README.th.md](./README.th.md)

## Table of Contents

- [Features](#features)
- [Screenshot](#screenshot)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Development](#development)
- [Scope](#scope)
- [Related Projects](#related-projects)
- [Status](#status)
- [Contributing](#contributing)
- [License](#license)

## Features

- 👥 **Fleet at a glance** — every incarnated agent with status, backend, and
  inbox count, refreshed every 5 seconds.
- 🟢 **Running vs idle** — color dot per agent mirrors `bwoc sessions`.
- 📥 **Inbox badges** — pending message count surfaced inline; click through to
  preview *(planned)*.
- ⚡ **Quick actions** *(planned)* — spawn, chat, stop, start, supervise without
  switching to a terminal.
- 🏠 **Workspace summary** — workspace path + total agents, always visible.
- 🪶 **Native + lightweight** — pure SwiftUI `MenuBarExtra`, no Electron, no
  background daemons beyond `bwoc` itself.

## Screenshot

> 📸 Screenshots coming soon — open the menu bar after running and see the live
> fleet view.

## Requirements

- macOS **13.0** (Ventura) or later
- Swift **5.9** toolchain (Xcode 15+ or Command Line Tools)
- [`bwoc`](https://github.com/bemindlabs/BWOC-Framework) CLI installed and
  resolvable on `PATH` — checked in this order:
  1. `/opt/homebrew/bin/bwoc`
  2. `/usr/local/bin/bwoc`
  3. `~/.local/bin/bwoc`
  4. `~/.cargo/bin/bwoc`

## Installation

```bash
git clone https://github.com/bemindlabs/bwoc-mcc.git
cd bwoc-mcc
swift build -c release
./.build/release/BwocMcc
```

The app runs as an **accessory** (menu-bar only) — no Dock icon, no
⌘-Tab entry. Quit via the in-app **Quit** button or `⌘Q`.

## Usage

1. Launch `BwocMcc` (see [Installation](#installation)).
2. Look for the **`person.3.sequence`** icon in your menu bar.
3. Click it — a 360-pixel window opens with the live fleet.
4. The list auto-refreshes every 5 seconds; click **↻** to force a refresh.

## Development

```bash
# Debug build (faster iteration)
swift build

# Run the menu-bar app
swift run BwocMcc

# Run the headless test suite (CoreChecks — no XCTest required)
swift run CoreChecks
```

The package has three targets:

| Target | Kind | Path |
|---|---|---|
| `BwocMccCore` | library | `Sources/BwocMccCore/` |
| `BwocMcc` | executable (SwiftUI app) | `Sources/BwocMcc/` |
| `CoreChecks` | executable (test runner) | `Tests/CoreChecks/` |

All CLI shell-outs go through `bwoc <cmd> --json` so the app stays insulated
from BWOC's Rust internals. See
[`BwocCli`](Sources/BwocMccCore/BwocCli.swift) for the supported commands.

## Scope

`bwoc-mcc` is focused on **BWOC fleet operations only**: agents, sessions,
inboxes, and (soon) scrum state. Out of scope:

- **LLM provider auth & quota** — that's
  [LLMProviderMonitor](https://github.com/bemindlabs/LLMProviderMonitor)'s
  job. The two apps are designed to live side-by-side in the menu bar.
- **Editing agent files** — read-only by design. Use `bwoc spawn`/`bwoc chat`
  for that.

## Related Projects

- 🤖 [BWOC-Framework](https://github.com/bemindlabs/BWOC-Framework) — the Rust
  orchestration framework this app reads from.
- 🔌 [LLMProviderMonitor](https://github.com/bemindlabs/LLMProviderMonitor) —
  sibling menu-bar app for provider auth/quota.

## Status

**Alpha** — the scaffold builds, launches, and renders the live fleet from
`bwoc list --json`. Quick actions, sessions view, inbox preview, and scrum
integration are tracked under `BWOC-EPIC-5` in the BWOC workspace.

## Contributing

Issues and PRs welcome. Before submitting:

1. Open an issue describing the change (so we can scope it together).
2. Run `swift build` and `swift run CoreChecks` — both must be green.
3. Keep PRs focused — one concern per PR.

## License

[MIT](./LICENSE) © 2026 BeMindLabs and contributors.
