# On-phone Grok bridge (Moto G / Termux)

All traffic stays on the Android device. Desktop PC is not required.

## Install

```bash
cp platforms/phone-termux/executable/adb-to-grok ~/bin/
cp platforms/phone-termux/executable/grok-phone ~/bin/
chmod 755 ~/bin/adb-to-grok ~/bin/grok-phone
```

Or use the copies already in `~/bin` after a phone session installs them.

## Commands

```bash
grok-phone status
grok-phone search boarding
grok-phone stage "/sdcard/Download/some.pdf"
grok-phone upload-search boarding --say "Review these boarding passes"
grok-phone say "Ping from on-device bridge"
adb-to-grok status
```

- **search** — find files under `/sdcard/Download`, `DCIM`, `Pictures`, `Documents`, `Movies`
- **stage / upload** — copy into `~/grok-inbox` (+ mirror `/sdcard/Download/grok-inbox`)
- **say / upload** — inject text into the live Grok Build TUI via `/proc/<pid>/fd/0`
- Local **adb** (`emulator-5554` on this moto) is available for `grok-phone adb-sh …`

## Notes

- `adb-to-grok` matches `grok-*-linux-*` binaries (plain `pidof grok` is not enough).
- Keep a Grok Build session open in Termux so inject has a live TTY (`/dev/pts/N`).
