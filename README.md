# BWOC macOS Control Center (`bwoc-mcc`)

A lightweight macOS **menu-bar** app that gives you, at a glance, the live state
of your BWOC agent fleet — and lets you drive the most common `bwoc` CLI
actions without opening a terminal.

> See also: [TH](./README.th.md) — บันทึกภาษาไทยฉบับคู่ขนาน

## Scope

Focused on **BWOC fleet operations only**:

- List incarnated agents with `STATUS` / `BACKEND` / `UPTIME` / `INBOX` count.
- Surface running vs idle sessions (mirrors `bwoc sessions`).
- Quick actions: spawn / chat / stop / start / supervise.
- Inbox preview + "open in terminal" jump-off.
- Workspace summary (path, agent count, total inbox).

**Out of scope** — provider auth/quota tracking. That belongs to
[LLMProviderMonitor](https://github.com/bemindlabs/LLMProviderMonitor); the two
apps are meant to sit side-by-side in the menu bar, not overlap.

## How it works

- Shells out to the `bwoc` CLI (resolved off `PATH`, including
  `/opt/homebrew/bin`). The app does **not** link the BWOC Rust core directly —
  all reads go through `bwoc <cmd> --json` for stability across releases.
- Auto-refreshes every 5 seconds; manual ↻ forces an immediate poll.
- Interactive sessions (`bwoc spawn` / `bwoc chat`) open **Terminal.app** —
  those flows need a real TTY and can't run inside the app.

The roster of supported CLI commands lives in one place:
[`BwocCli`](Sources/BwocMccCore/BwocCli.swift).

## Status

**Alpha scaffold** — Package.swift + minimal SwiftUI shell + one working
`bwoc list --json` call. Not yet on the App Store; install from source:

```bash
git clone https://github.com/bemindlabs/bwoc-mcc.git
cd bwoc-mcc
swift build -c release
.build/release/BwocMcc
```

## Sibling Project

If you also want to monitor your LLM provider CLIs (Claude, Codex, Kimi,
Antigravity) — auth status and credit-used — install
[LLMProviderMonitor](https://github.com/bemindlabs/LLMProviderMonitor)
alongside this app.

## License

TBD — to match the rest of the `bemindlabs` BWOC ecosystem.
