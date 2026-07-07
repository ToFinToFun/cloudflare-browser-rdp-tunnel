# Cloudflare RDP Tool

A lightweight, zero-client solution to access your Windows PC via Remote Desktop directly from any web browser. 

This tool installs `cloudflared` as a hidden Windows background service, enabling secure, browser-based RDP using Cloudflare Zero Trust. No VPN, no WARP client, and no RDP software is required on the connecting device.

## Features

- **Browser-based RDP:** Control your PC from Chrome, Edge, Safari, or Firefox.
- **Zero-Client:** Nothing to install on the device you are connecting *from*.
- **Zero Trust Security:** Protected by Cloudflare Access (e.g., OTP via email, Google Workspace, GitHub).
- **Network Agnostic:** Works on any network (WiFi, ethernet, mobile hotspot) without port forwarding.
- **Invisible & Resilient:** Runs as a hidden Windows service. Survives sleep, hibernation, lock screens, and logouts.
- **Auto-Recovery:** Built-in watchdog restarts the service automatically if it crashes.

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

## Step 2: Cloudflare Access Setup

Now, protect the URL so only you can access it.

1. In the Zero Trust Dashboard, go to **Access** > **Applications**.
2. Click **Add an application** and select **Self-hosted**.
3. **Application Name:** e.g., `My Laptop RDP`
4. **Session Duration:** 24h
5. **Application domain:** Enter the exact domain you configured earlier (e.g., `rdp.example.com`).
6. Scroll down to **Browser rendering settings** and select **RDP**.
7. Click **Next**.
8. Create a Policy (e.g., Name: `Allow Me`, Action: `Allow`).
9. Under **Include**, select `Emails` and enter your email address.
10. Click **Next**, then **Add application**.

## Step 3: Install on the Target PC

Now, go to the Windows PC you want to control remotely.

1. Download the `Cloudflare_RDP_Tool.bat` script from this repository.
2. Right-click the file and select **Run as administrator**.
3. When prompted, enter the **Tunnel Token** you copied in Step 1.
4. Enter the **Public Hostname** you configured (e.g., `rdp.example.com`).
5. The script will automatically:
   - Verify Windows compatibility
   - Enable Remote Desktop and Network Level Authentication (NLA)
   - Download the latest `cloudflared` binary
   - Install it as a hidden service
   - Configure the watchdog for auto-recovery
   - Start the service and verify the connection

## Step 4: Connect!

From any device (your phone, a hotel computer, a Mac):
1. Open a web browser and navigate to your public hostname (e.g., `https://rdp.example.com`).
2. Authenticate with Cloudflare Access (e.g., enter the pin sent to your email).
3. You will see the Windows login screen in your browser. Log in with your Windows username and password.

Done!

---

## Uninstallation

If you ever want to remove the tunnel from your PC:
1. Run `Cloudflare_RDP_Tool.bat` as administrator again.
2. The script will detect the existing installation.
3. Press `U` to uninstall completely.

## Credits

Created by **Japaasovaara**.

## License

MIT License. See `LICENSE` for details.
