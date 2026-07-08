# Cloudflare Browser-RDP Tunnel

A lightweight, zero-client solution to access your Windows PC via Remote Desktop directly from any web browser. 

This tool installs `cloudflared` as a hidden Windows background service (`cloudflared-rdp`), enabling secure, browser-based RDP using Cloudflare Zero Trust. No VPN, no WARP client, and no RDP software is required on the connecting device.

## Features

- **Browser-based RDP:** Control your PC from Chrome, Edge, Safari, or Firefox.
- **Zero-Client:** Nothing to install on the device you are connecting *from*.
- **Zero Trust Security:** Protected by Cloudflare Access (e.g., OTP via email, Google Workspace, GitHub).
- **Network Agnostic:** Works on any network (WiFi, ethernet, mobile hotspot) without port forwarding.
- **Invisible & Resilient:** Runs as a hidden Windows service. Survives sleep, hibernation, lock screens, and logouts.
- **Auto-Recovery:** Built-in watchdog restarts the service automatically if it crashes.
- **Azure AD / Entra ID Support:** Detects Azure AD joined devices and offers interactive fixes for known RDP compatibility issues.
- **Power Management:** Built-in presets to keep the PC awake and reachable (MAX, High, Balanced, Low+, Low).
- **Safe:** Installs as a separate service (`cloudflared-rdp`) — will **not** interfere with any existing `cloudflared` installations.
- **Pre-configured Slots:** Optionally use a `slots.txt` file to offer a menu of pre-configured addresses.

## Requirements

- **Target PC:** Windows 10/11 Pro, Enterprise, or Education. (Windows Home does **not** support RDP).
- **Cloudflare Account:** A free Cloudflare account (Zero Trust is free for up to 50 users).
- **A Domain Name:** You must own a domain name (e.g., `example.com`) and have its DNS managed by Cloudflare.

---

## Step 1: Cloudflare Setup

Before running the script, you need to create a tunnel in your Cloudflare dashboard.

1. Log in to your [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/).
2. Navigate to **Networks** > **Tunnels**.
3. Click **Create a tunnel**.
4. Select **Cloudflared** and click Next.
5. Name your tunnel (e.g., `My-Laptop-RDP`) and click **Save tunnel**.
6. **Important:** On the installation screen, look at the command provided for Windows. Copy the long string of characters after `service install` (this is your **Tunnel Token**). Save this token, you will need it later.
7. Click **Next**.
8. Under **Public Hostname**, configure the following:
   - **Subdomain:** e.g., `rdp`
   - **Domain:** Select your domain (e.g., `example.com`)
   - **Service Type:** `RDP`
   - **URL:** `localhost:3389`
9. Click **Save tunnel**.

## Step 2: Cloudflare Access Setup (CRITICAL)

Now, protect the URL and enable Browser Rendering. **This step must be done correctly or you will only see a white screen.**

> **IMPORTANT:** The Access Application type MUST be `RDP` (Browser Rendering), NOT `Self-hosted`.
> If configured as Self-hosted, the tunnel will connect but you will only see a blank white page.

1. In the Zero Trust Dashboard, go to **Access** > **Applications**.
2. Click **Add an application**.
3. Select **Browser Rendering** (NOT "Self-hosted").
4. Select **RDP** as the protocol.
5. Configure:
   - **Application Name:** e.g., `My Laptop RDP`
   - **Application domain:** Enter the exact domain you configured earlier (e.g., `rdp.example.com`)
   - **Target criteria:** Hostname: any name, Port: `3389`, Protocol: `RDP`
   - **Session Duration:** 24h
   - **Skip interstitial:** Yes (recommended)
6. Click **Next**.
7. Create a Policy (e.g., Name: `Allow Me`, Action: `Allow`).
8. Under **Include**, select `Emails` and enter your email address.
9. Click **Next**, then **Add application**.

### Verifying correct configuration

If you only see a white screen after authenticating, your application is likely set to `Self-hosted` instead of `RDP`. You can verify via the API:

```bash
curl -s "https://api.cloudflare.com/client/v4/accounts/ACCOUNT_ID/access/apps" \
  -H "Authorization: Bearer TOKEN" | jq '.result[] | select(.domain=="rdp.example.com") | .type'
# Must return: "rdp" (not "self_hosted")
```

To fix: delete the application and recreate it using the steps above, making sure to select **Browser Rendering > RDP**.

## Step 3: Install on the Target PC

Now, go to the Windows PC you want to control remotely.

1. Download this repository (or just `setup.bat` and `script.ps1`).
2. Right-click `setup.bat` and select **Run as administrator**.
3. Press **[I]** to install.
4. When prompted, enter the **Tunnel Token** you copied in Step 1.
5. Enter the **Public Hostname** you configured (e.g., `rdp.example.com`).
6. The script will automatically:
   - Verify Windows compatibility (aborts on Windows Home)
   - Enable Remote Desktop
   - Detect Azure AD / Entra ID and offer fixes if needed
   - Download the latest `cloudflared` binary
   - Install it as a hidden service (`cloudflared-rdp`)
   - Configure the watchdog for auto-recovery
   - Start the service and verify the connection
   - Offer power management configuration
   - Show a checklist of all steps (OK/FAIL)

## Step 4: Connect!

From any device (your phone, a hotel computer, a Mac):
1. Open a web browser and navigate to your public hostname (e.g., `https://rdp.example.com`).
2. Authenticate with Cloudflare Access (e.g., enter the pin sent to your email).
3. You will see the Windows login screen in your browser. Log in with your Windows username and password.

Done!

---

## Power Management

After installation, the script offers to configure power settings to keep the PC awake and reachable. You can also change these later by running the script again and choosing **[P]** from the manage menu.

| Preset | Description |
|--------|-------------|
| **[1] MAX** | Never sleeps (AC + battery), lid does nothing, network always on, shutdown button hidden in Start menu (current user only) |
| **[2] High** | Never sleeps (AC + battery), lid does nothing, network always on |
| **[3] Balanced** (recommended) | Always awake/connected when charger is plugged in. Normal on battery |
| **[4] Low+** | Leaves sleep settings alone, but network never sleeps (requires Modern Standby / S0) |
| **[5] Low** | Resets to Windows defaults (acts as an undo button) |

The script automatically detects whether the PC supports Modern Standby (S0) and marks Low+ as unavailable on PCs with classic S3 sleep.

---

## Azure AD / Entra ID

If the target PC is joined to Azure AD (Microsoft Entra ID), browser-based RDP has known compatibility issues. The script detects this automatically and offers interactive fixes:

1. **NLA (Network Level Authentication)** — Disables NLA which blocks browser RDP clients
2. **PKU2U Protocol** — Enables Azure AD authentication for RDP
3. **Remote Desktop Users group** — Adds Authenticated Users to the RDP group
4. **CredSSP** (optional) — Allows fallback encryption for edge cases

Each fix explains what it changes, the risk level, and asks for confirmation before applying.

**Login format for Azure AD:** Use `AzureAD\YourName` as username (run `whoami` to check). Use your Microsoft account password (NOT your PIN).

---

## Pre-configured Slots (Optional)

If you manage multiple PCs, you can create a `slots.txt` file in the same folder as the script. This gives users a numbered menu to choose from instead of entering tokens manually.

**Format:** One entry per line: `hostname|token`

```
rdp1.example.com|eyJhIjoiYjkyNWM5NTkw...
rdp2.example.com|eyJhIjoiYzEyM2Q0NTY3...
office-pc.example.com|eyJhIjoiZGVmMTIz...
```

When `slots.txt` is present, the script shows:
```
Choose an address for this PC:

  [1] rdp1.example.com
  [2] rdp2.example.com
  [3] office-pc.example.com

  [C] Custom (enter your own token and address)
  [Q] Quit
```

When `slots.txt` is absent or empty, the script goes directly to manual token input.

See `slots.txt.example` for a template.

---

## Managing an Existing Installation

Run `setup.bat` as administrator on a PC that already has the tunnel installed. The script detects it and shows:

```
  [R] Reinstall / Change address
  [U] Uninstall completely
  [D] Run diagnostics (Azure AD check)
  [P] Power management settings
  [Q] Quit - do nothing
```

- **[R]** removes the current installation and starts a fresh install
- **[U]** uninstalls completely (optionally resets power settings)
- **[D]** runs Azure AD diagnostics without reinstalling
- **[P]** opens the power management preset menu

---

## Uninstallation

1. Run `setup.bat` as administrator.
2. The script will detect the existing installation.
3. Press **[U]** to uninstall completely.
4. You will be asked if you want to reset power settings to Windows defaults.

Other `cloudflared` services are never touched.

---

## How It Works

```
[Your Phone/Laptop]          [Cloudflare Edge]          [Target PC]
     Browser          --->   Zero Trust Access   <---   cloudflared-rdp
  (any device)               (OTP/SSO auth)             (outbound tunnel)
                                    |
                             Browser RDP Renderer
                             (IronRDP in browser)
```

1. The target PC runs `cloudflared-rdp` as a hidden service.
2. It maintains an **outbound** connection to Cloudflare (no open ports).
3. When you visit the URL, Cloudflare authenticates you (OTP/SSO).
4. Cloudflare renders the RDP session directly in your browser.
5. The PC's physical screen stays locked — nothing is visible locally.

---

## Files

| File | Description |
|------|-------------|
| `setup.bat` | Launcher — right-click > Run as Administrator |
| `script.ps1` | Main PowerShell script (all logic) |
| `slots.txt` | Pre-configured addresses (optional) |
| `slots.txt.example` | Template for slots.txt |

---

## Credits

Created by **JPaasovaara**.

## License

MIT License. See `LICENSE` for details.
