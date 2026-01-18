<p align="center">
  <img src="docs/assets/in-app.png" alt="Tunnelflare" width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9-orange?style=flat-square" alt="Swift">
  <img src="https://img.shields.io/badge/license-PolyForm%20Noncommercial-green?style=flat-square" alt="License">
</p>

---

If you've ever managed Cloudflare Tunnels, you know the drill: open terminal, type commands, check status, repeat. It works, but it's not exactly fun.

**Tunnelflare** is a macOS app that puts your tunnels in the menu bar. Start, stop, monitor — all without touching the terminal.

---

## What it does

- Lives in your menu bar, shows tunnel status at a glance
- Start/stop tunnels with a click
- Dashboard for when you need more details
- Streams logs in real-time
- Alerts you when something goes wrong

<p align="center">
  <img src="docs/assets/in-menubar.png" alt="Menu Bar" width="280">
</p>

---

## Installation

**Requirements:**
- macOS 14+ (Sonoma)
- A Cloudflare account

### Download

1. Download the latest `.zip` from [Releases](https://github.com/mberatsanli/tunnelflare/releases)
2. Extract and drag `Tunnelflare.app` to Applications
3. **First launch:** Right-click → Open → Open

> **Note:** macOS will show a warning because the app isn't notarized. This is normal for open-source apps. Click "Open" to proceed.

<details>
<summary>Alternative: System Settings method</summary>

If right-click doesn't work:
1. Try to open the app normally (it will be blocked)
2. Go to System Settings → Privacy & Security
3. Scroll down and click "Open Anyway"
</details>

### Build from Source

```bash
git clone https://github.com/mberatsanli/tunnelflare.git
cd Tunnelflare
open Tunnelflare.xcodeproj
# Hit ⌘R
```

### cloudflared

The app will prompt you to install `cloudflared` if it's not found. You can also install it manually:

```bash
brew install cloudflared
```

---

## Usage

1. Open the app
2. Enter your Cloudflare API token ([how to create one](HOWTO.md#1-getting-your-api-token))
3. Pick your account
4. Done — your tunnels show up in the menu bar

For detailed instructions, check out the [full guide](HOWTO.md).

Keyboard shortcuts:

| | |
|----------|--------|
| `⌘D` | Dashboard |
| `⌘R` | Refresh |
| `⌘N` | New Tunnel |
| `⌘⇧S` | Start All |
| `⌘⇧X` | Stop All |

---

## Config

Everything lives in `~/.tunnelflare/`. Credentials are in Keychain.

---

## Contributing

PRs welcome. Check out [CONTRIBUTING.md](CONTRIBUTING.md) for setup instructions.

```bash
git clone https://github.com/mberatsanli/tunnelflare.git
cd Tunnelflare
open Tunnelflare.xcodeproj
```

---

## License

[PolyForm Noncommercial 1.0.0](LICENSE) — free for personal use, not for commercial.

---

## Links

- [How to Use](HOWTO.md) — detailed usage guide
- [Roadmap](ROADMAP.md) — what's done, what's next
- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [cloudflared](https://github.com/cloudflare/cloudflared)
