# bwoc-mcc

> แอป menu-bar SwiftUI สำหรับควบคุมกองทัพเอเจนต์ BWOC บน macOS

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg?logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-13.0%2B-blue.svg)](https://www.apple.com/macos)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-alpha-red.svg)](#สถานะ)

แสดงสถานะกองทัพเอเจนต์ [BWOC](https://github.com/bemindlabs/BWOC-Framework)
แบบเรียลไทม์ — เอเจนต์, session, inbox — บน menu bar ของ macOS
พร้อม quick action ให้สั่ง spawn / chat / stop / supervise โดยไม่ต้องสลับไป
terminal เลยค่ะ

> 🇬🇧 English canonical: [README.md](./README.md)

## สารบัญ

- [คุณสมบัติ](#คุณสมบัติ)
- [Screenshot](#screenshot)
- [ความต้องการ](#ความต้องการ)
- [การติดตั้ง](#การติดตั้ง)
- [การใช้งาน](#การใช้งาน)
- [การพัฒนา](#การพัฒนา)
- [ขอบเขต](#ขอบเขต)
- [โปรเจกต์พี่น้อง](#โปรเจกต์พี่น้อง)
- [สถานะ](#สถานะ)
- [การร่วมพัฒนา](#การร่วมพัฒนา)
- [License](#license)

## คุณสมบัติ

- 👥 **เห็นกองทัพได้ในตาเดียว** — เอเจนต์ที่ incarnated ทุกตัว พร้อม status,
  backend, จำนวน inbox; รีเฟรชอัตโนมัติทุก 5 วินาที
- 🟢 **Running vs idle** — จุดสีต่อแถวสะท้อน `bwoc sessions`
- 📥 **Badge inbox** — แสดงจำนวนข้อความค้างเป็น badge inline; คลิกเพื่อดู
  พรีวิว *(วางแผน)*
- ⚡ **Quick action** *(วางแผน)* — spawn / chat / stop / start / supervise
  โดยไม่ต้องสลับไป terminal
- 🏠 **สรุป workspace** — path workspace + จำนวนเอเจนต์รวม, เห็นตลอด
- 🪶 **Native + เบา** — ใช้ SwiftUI `MenuBarExtra` ล้วน ๆ ไม่มี Electron
  ไม่มี daemon เพิ่มเติมนอกจาก `bwoc` เอง

## Screenshot

> 📸 รูปกำลังตามมาค่ะ — เปิดแอปแล้วคลิก menu bar ดูได้เลย

## ความต้องการ

- macOS **13.0** (Ventura) ขึ้นไป
- Swift **5.9** toolchain (Xcode 15+ หรือ Command Line Tools)
- ติดตั้ง CLI [`bwoc`](https://github.com/bemindlabs/BWOC-Framework)
  และอยู่บน `PATH` — แอปจะค้นตามลำดับ:
  1. `/opt/homebrew/bin/bwoc`
  2. `/usr/local/bin/bwoc`
  3. `~/.local/bin/bwoc`
  4. `~/.cargo/bin/bwoc`

## การติดตั้ง

```bash
git clone https://github.com/bemindlabs/bwoc-mcc.git
cd bwoc-mcc
swift build -c release
./.build/release/BwocMcc
```

แอปรันแบบ **accessory** (menu-bar เท่านั้น) — ไม่มี icon ใน Dock ไม่อยู่ใน
⌘-Tab ปิดด้วยปุ่ม **Quit** ในแอป หรือ `⌘Q`

## การใช้งาน

1. รัน `BwocMcc` (ดู [การติดตั้ง](#การติดตั้ง))
2. มอง menu bar — จะเห็น icon **`person.3.sequence`**
3. คลิก — หน้าต่างกว้าง 360 pixel เปิดขึ้น แสดงกองทัพแบบสด ๆ
4. รีเฟรชอัตโนมัติทุก 5 วินาที; กด **↻** เพื่อสั่งใหม่ได้

## การพัฒนา

```bash
# Debug build (iterate เร็ว)
swift build

# รันแอป menu bar
swift run BwocMcc

# รัน test runner ขั้นต่ำ (CoreChecks — ไม่ต้องมี XCTest)
swift run CoreChecks
```

Package มี 3 targets:

| Target | ชนิด | Path |
|---|---|---|
| `BwocMccCore` | library | `Sources/BwocMccCore/` |
| `BwocMcc` | executable (แอป SwiftUI) | `Sources/BwocMcc/` |
| `CoreChecks` | executable (test runner) | `Tests/CoreChecks/` |

ทุกการเรียก CLI ผ่าน `bwoc <cmd> --json` เพื่อให้แอปไม่ผูกกับ Rust internal
ของ BWOC ดูคำสั่งที่รองรับใน
[`BwocCli`](Sources/BwocMccCore/BwocCli.swift)

## ขอบเขต

`bwoc-mcc` โฟกัสที่ **BWOC fleet operations อย่างเดียว** — เอเจนต์, session,
inbox, และ (เร็ว ๆ นี้) สถานะ scrum สิ่งที่ **ไม่อยู่ในขอบเขต**:

- **การ auth / quota ของ LLM provider** — เป็นงานของ
  [LLMProviderMonitor](https://github.com/bemindlabs/LLMProviderMonitor)
  สองแอปออกแบบให้อยู่คู่กันบน menu bar
- **การแก้ไฟล์เอเจนต์** — ออกแบบเป็น read-only ใช้ `bwoc spawn`/`bwoc chat`
  สำหรับการแก้ไข

## โปรเจกต์พี่น้อง

- 🤖 [BWOC-Framework](https://github.com/bemindlabs/BWOC-Framework) — เฟรมเวิร์ก
  orchestration ภาษา Rust ที่แอปนี้อ่านข้อมูล
- 🔌 [LLMProviderMonitor](https://github.com/bemindlabs/LLMProviderMonitor) —
  แอป menu bar พี่น้องสำหรับ provider auth/quota

## สถานะ

**Alpha** — scaffold build ได้ รันได้ แสดง fleet สดจาก `bwoc list --json`
ส่วน quick action, sessions view, inbox preview, scrum integration อยู่ใน
`BWOC-EPIC-5` ใน BWOC workspace

## การร่วมพัฒนา

ยินดีรับ Issue และ PR ก่อนส่ง PR:

1. เปิด issue อธิบายการเปลี่ยนแปลงก่อน (เพื่อจูน scope ด้วยกัน)
2. รัน `swift build` กับ `swift run CoreChecks` — ต้องเขียวทั้งคู่
3. PR ให้โฟกัส — 1 เรื่องต่อ PR

## License

[MIT](./LICENSE) © 2026 BeMindLabs and contributors
