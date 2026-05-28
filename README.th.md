# BWOC macOS Control Center (`bwoc-mcc`)

แอป **menu bar** บน macOS ขนาดเล็ก ที่แสดงสถานะของกองทัพเอเจนต์ BWOC ของคุณ
แบบเรียลไทม์ — และทำให้คุณสั่งคำสั่ง `bwoc` CLI ที่ใช้บ่อยที่สุดได้โดยไม่ต้องเปิด
terminal เลยค่ะ

> ดูคู่ขนาน: [EN](./README.md) — English canonical

## ขอบเขต

โฟกัสที่ **BWOC fleet operations อย่างเดียว** ค่ะ:

- แสดงรายการเอเจนต์ที่ incarnated แล้ว พร้อม `STATUS` / `BACKEND` / `UPTIME` /
  จำนวน inbox
- บอกว่า session ไหน running ไหน idle (สะท้อน `bwoc sessions`)
- Quick action: spawn / chat / stop / start / supervise
- พรีวิว inbox + ปุ่ม "เปิดใน terminal"
- สรุป workspace (path, จำนวนเอเจนต์, inbox รวม)

**ไม่อยู่ในขอบเขต** — การติดตาม provider auth/quota เรื่องนั้นเป็นของ
[LLMProviderMonitor](https://github.com/bemindlabs/LLMProviderMonitor) ค่ะ
สองแอปนี้ออกแบบมาให้อยู่คู่กันบน menu bar ไม่ทับซ้อนกัน

## วิธีทำงาน

- เรียก `bwoc` CLI ผ่าน shell (หา binary จาก `PATH` รวมถึง `/opt/homebrew/bin`)
  แอปไม่ได้ link กับ BWOC Rust core ตรง ๆ — ทุกการอ่านผ่าน `bwoc <cmd> --json`
  เพื่อความเสถียรข้ามเวอร์ชัน
- รีเฟรชอัตโนมัติทุก 5 วินาที; ปุ่ม ↻ สั่งดึงข้อมูลใหม่ทันที
- Session แบบ interactive (`bwoc spawn` / `bwoc chat`) จะเปิดใน
  **Terminal.app** เพราะ flow พวกนั้นต้องการ TTY จริง รันในแอปไม่ได้ค่ะ

รายการคำสั่ง CLI ที่รองรับอยู่ที่เดียว:
[`BwocCli`](Sources/BwocMccCore/BwocCli.swift)

## สถานะ

**Alpha scaffold** — มี Package.swift + SwiftUI shell ขั้นต่ำ + การเรียก
`bwoc list --json` ที่ใช้งานได้ 1 ตัว ยังไม่ขึ้น App Store ติดตั้งจาก source:

```bash
git clone https://github.com/bemindlabs/bwoc-mcc.git
cd bwoc-mcc
swift build -c release
.build/release/BwocMcc
```

## โปรเจกต์พี่น้อง

ถ้าอยากดู provider CLI ด้วย (Claude, Codex, Kimi, Antigravity) — auth status
และ credit-used — ติดตั้ง
[LLMProviderMonitor](https://github.com/bemindlabs/LLMProviderMonitor)
ควบคู่ไปได้เลยค่ะ

## License

TBD — จะให้ตรงกับ ecosystem `bemindlabs` BWOC ตัวอื่น
