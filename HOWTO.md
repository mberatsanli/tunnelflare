# How to Use Tunnelflare

Tunnelflare supports two ways to sign in:

- **Sign in with Cloudflare (OAuth)** — browser-based login, no token to copy/paste. Recommended. See [section 1](#1-signing-in-with-cloudflare-oauth).
- **API Token** — paste a token you create manually. Good for headless/CI or as a fallback. See [section 2](#2-getting-your-api-token).

---

## 1. Signing in with Cloudflare (OAuth)

OAuth (PKCE) lets you authorize Tunnelflare in your browser without ever pasting a long-lived token.

### One-time setup: register the OAuth client

OAuth needs a **Client ID** that identifies the app. Register it once in the Cloudflare dashboard:

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com) → your account → **Manage Account** → **OAuth clients**
2. Click **Create client**
3. Fill in:
   - **Client name:** `Tunnelflare`
   - **Grant type:** Authorization Code
   - **Response type:** Code
   - **Token endpoint auth method:** **None** (public client — uses PKCE, no client secret)
   - **Redirect URI:** `http://127.0.0.1:8788/callback`
     > Cloudflare requires an `http`/`https` redirect and rejects custom schemes, so Tunnelflare uses a local loopback listener (RFC 8252). The port `8788` must match `OAuthConstants.loopbackPort` in the code.
4. Select the **scopes** below, then **Create client**
5. Copy the **Client ID** (there is no secret for a public client)

### Scopes to select

Select these scopes on the client (the exact scope tokens, shown in parentheses, are what the app requests):

| Group | Scope | Token |
|-------|-------|-------|
| Cloudflare One / Zero Trust | Cloudflare Tunnel Read | `argotunnel.read` |
| Cloudflare One / Zero Trust | Cloudflare Tunnel Write | `argotunnel.write` |
| DNS & Zones | DNS Read | `dns.read` |
| DNS & Zones | DNS Write | `dns.write` |
| DNS & Zones | Zone Read | `zone.read` |
| Account & Billing | Account Settings Read | `account-settings.read` |
| Account & Billing | User Details Read | `user-details.read` |
| Other | openid | `openid` |

> These exact tokens are pinned in `OAuthConstants.scopes` (`Constants.swift`). The scope selection on the OAuth client MUST include all of them, or Cloudflare returns `invalid_scope`. Omitting the scope grants 0 permissions, so the app always sends them explicitly.

### Endpoints

The app talks to Cloudflare's OAuth endpoints directly (Cloudflare does not publish a fetchable discovery document for third-party clients):

- Authorize: `https://dash.cloudflare.com/oauth2/auth`
- Token: `https://dash.cloudflare.com/oauth2/token`

### Configure the build

The Client ID is injected at build time from a local, gitignored xcconfig:

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
# then edit Config/Secrets.xcconfig:
#   CF_OAUTH_CLIENT_ID = your-client-id-here
```

`Config/Base.xcconfig` (tracked) optionally includes `Secrets.xcconfig`, so a
fresh clone builds fine without it — until you create the file, the
**Sign in with Cloudflare** button shows *"OAuth is not configured"* and you
can use an API token instead.

### Signing in

1. Open Tunnelflare → login screen
2. Click **Sign in with Cloudflare**
3. Your browser opens Cloudflare's consent page → approve
4. The browser redirects to the local listener and you can close the tab
5. Back in the app you're signed in (tokens are stored in Keychain and auto-refreshed)

---

## 2. Getting Your API Token

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

## 3. First Launch

1. Open Tunnelflare
2. You'll see the login screen
3. Either click **Sign in with Cloudflare** (OAuth) or expand **Or use an API token** and paste your token
4. If you have multiple accounts, pick one
5. Done — your tunnels will load

---

## 4. Creating a Tunnel

1. Click the **+** button in the dashboard (or `⌘N`)
2. Enter a name for your tunnel
   - Lowercase letters, numbers, and hyphens only
   - Must start with a letter
   - 3-63 characters
3. Click **Create**
4. The tunnel will appear in your list (inactive)

> **Note:** This creates the tunnel in Cloudflare. To actually route traffic, you'll need to configure ingress rules in the Cloudflare dashboard.

---

## 5. Starting a Tunnel

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

## 6. Viewing Logs

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

## 7. Stopping a Tunnel

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

## 8. Deleting a Tunnel

> **Warning:** This permanently deletes the tunnel from Cloudflare. Any DNS routes pointing to it will break.

1. Open dashboard
2. Select the tunnel
3. Make sure it's stopped
4. Click **Delete** (or right-click → Delete)
5. Confirm the deletion

---

## 9. Troubleshooting

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

### "OAuth is not configured"
The build's OAuth Client ID hasn't been set. Register an OAuth client (see [section 1](#1-signing-in-with-cloudflare-oauth)) and set `OAuthConstants.clientID` in `Constants.swift`. Or just use an API token instead.

### OAuth browser opens but sign-in never completes
The loopback listener on `127.0.0.1:8788` may be blocked or the port is in use. Make sure the redirect URI registered in Cloudflare is exactly `http://127.0.0.1:8788/callback` and nothing else is using port `8788`.

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
