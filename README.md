# grok-phone-bridge

On-device helpers for **Termux on Android** (built on a Moto G 2025): search local storage, stage files into a Grok inbox, and inject prompts into a live [Grok Build](https://github.com/xai-org/grok-build) TUI.

No desktop PC required. Optional local `adb` on the same phone is supported when a device shows up in `adb devices`.

## Install

```bash
git clone https://github.com/justbecool87/grok-phone-bridge.git
cd grok-phone-bridge
mkdir -p ~/bin
cp bin/adb-to-grok bin/grok-phone ~/bin/
chmod 755 ~/bin/adb-to-grok ~/bin/grok-phone
export PATH="$HOME/bin:$PATH"
```

## Commands

```bash
grok-phone status
grok-phone search boarding
grok-phone stage "/sdcard/Download/some.pdf"
grok-phone upload-search boarding --say "Review these files in ~/grok-inbox"
grok-phone say "Ping from on-device bridge"
adb-to-grok status
```

| Command | Purpose |
|---|---|
| `grok-phone search <query>` | Find files under Download / DCIM / Pictures / Documents / Movies |
| `grok-phone stage <path…>` | Copy into `~/grok-inbox` (and `/sdcard/Download/grok-inbox`) |
| `grok-phone upload …` | Stage **and** inject a prompt into the live Grok TUI |
| `grok-phone upload-search …` | Search → stage → inject |
| `adb-to-grok say <text>` | Inject only |

## Requirements

- Termux on Android
- A running Grok Build session (so inject has a live TTY)
- `adb` optional (Termux `android-tools`) for `grok-phone adb-sh` / status

`adb-to-grok` matches binaries named `grok-*-linux-*` (plain `pidof grok` is not enough on current Grok Build builds).

## License

MIT
