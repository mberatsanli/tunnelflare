# How to Use Tunnelflare

## 1. Getting Your API Token

Tunnelflare needs a Cloudflare API token to work. Here's how to create one:

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens)
2. Click **Create Token**
3. Use **Create Custom Token**
4. Set these permissions:

| Permission | Access |
|------------|--------|
| Account / Cloudflare Tunnel | Edit |
| Account / Account Settings | Read |
| Zone / Zone | Read |
| Zone / DNS | Edit |

5. Under **Account Resources**, select your account
6. Under **Zone Resources**, select "All zones" or specific zones
7. Click **Continue to summary** → **Create Token**
8. Copy the token — you won't see it again

> **Tip:** Store the token somewhere safe. If you lose it, you'll need to create a new one.

---

## 2. First Launch

1. Open Tunnelflare
2. You'll see the login screen
3. Paste your API token
4. Click **Sign In**
5. If you have multiple accounts, pick one
6. Done — your tunnels will load

---

## 3. Creating a Tunnel

1. Click the **+** button in the dashboard (or `⌘N`)
2. Enter a name for your tunnel
   - Lowercase letters, numbers, and hyphens only
   - Must start with a letter
   - 3-63 characters
3. Click **Create**
4. The tunnel will appear in your list (inactive)

> **Note:** This creates the tunnel in Cloudflare. To actually route traffic, you'll need to configure ingress rules in the Cloudflare dashboard.

---

## 4. Starting a Tunnel

### From Menu Bar
- Click the Tunnelflare icon in menu bar
- Find your tunnel
- Click the **▶** play button

### From Dashboard
- Open dashboard (`⌘D`)
- Find your tunnel in the list
- Click **Start**

The status indicator will turn:
- 🟡 Yellow — connecting
- 🟢 Green — connected
- 🔴 Red — failed

---

## 5. Viewing Logs

Real-time logs help you debug connection issues.

1. Open dashboard (`⌘D`)
2. Click on a tunnel
3. Go to the **Logs** tab

You can:
- **Filter by level** — Error, Warning, Info, Debug
- **Search** — Find specific messages
- **Export** — Save logs to a file

Logs are also saved to `~/.tunnelflare/logs/` if you enable persistent logging in Settings.

---

## 6. Stopping a Tunnel

### From Menu Bar
- Click the Tunnelflare icon
- Find the running tunnel
- Click the **■** stop button

### From Dashboard
- Select the tunnel
- Click **Stop**

### Stop All Tunnels
- Press `⌘⇧X`
- Or use the menu: **Tunnels → Stop All Tunnels**

---

## 7. Deleting a Tunnel

> **Warning:** This permanently deletes the tunnel from Cloudflare. Any DNS routes pointing to it will break.

1. Open dashboard
2. Select the tunnel
3. Make sure it's stopped
4. Click **Delete** (or right-click → Delete)
5. Confirm the deletion

---

## 8. Troubleshooting

### "cloudflared not found"
Install it with Homebrew:
```bash
brew install cloudflared
```

Or set a custom path in **Settings → cloudflared Path**

### Tunnel won't connect
1. Check your internet connection
2. Check the logs for errors
3. Make sure the tunnel has a valid config in Cloudflare dashboard
4. Try restarting the tunnel

### Token expired or invalid
1. Go to **Settings**
2. Click **Sign Out**
3. Create a new token in Cloudflare dashboard
4. Sign in again

### App not responding
Force quit (`⌘Q`) and reopen. If the problem persists, delete `~/.tunnelflare/` and sign in again.

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘D` | Open Dashboard |
| `⌘,` | Settings |
| `⌘R` | Refresh Tunnels |
| `⌘N` | New Tunnel |
| `⌘⇧S` | Start All |
| `⌘⇧X` | Stop All |
| `⌘Q` | Quit |

---

## Files & Data

| Location | What's there |
|----------|--------------|
| `~/.tunnelflare/logs/` | Tunnel log files |
| macOS Keychain | API token & credentials |
| `~/Library/Preferences/` | App settings |

To fully reset the app, delete `~/.tunnelflare/` and remove the Keychain entries for "com.tunnelflare".
