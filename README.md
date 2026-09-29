# Debian XFCE web desktop

This repo contains a Deepnote-friendly launcher for a browser desktop. It uses **KasmVNC**, not TigerVNC/noVNC. If KasmVNC is already in your Deepnote image, the script uses it; otherwise it installs the official KasmVNC package at runtime.

The original container setup remains in `Dockerfile`; it is based on `lscr.io/linuxserver/webtop:debian-xfce`, which also uses KasmVNC.

## Run on Deepnote for free

1. Create a free Deepnote project using the default Python environment, or use your public Docker image environment if you already selected one.
2. Use either a **notebook block** or the **Terminal**.

### Option A: Notebook block, no Terminal needed

You can open `Deepnote_Kasm_Launcher.ipynb` and run its code cell, or create/open any notebook in Deepnote, add a **Code** block, paste this whole cell, then run it. The cell will keep running while the desktop is on.

```bash
%%bash
set -Eeuo pipefail
cd ~/work 2>/dev/null || cd ~
if [ -d os ]; then
  bash os/scripts/deepnote-stop.sh || true
fi
rm -rf os
git clone --branch arena/01a0eb07-os --single-branch https://github.com/Joercat/os.git os
cd os
bash scripts/deepnote-desktop.sh
```

### Option B: Terminal

Open **Terminal** in the Deepnote sidebar and paste this block. It removes any old `os` folder that may have cloned the wrong branch, then clones this Arena branch specifically:

```bash
cd ~/work 2>/dev/null || cd ~
if [ -d os ]; then
  bash os/scripts/deepnote-stop.sh || true
fi
rm -rf os
git clone --branch arena/01a0eb07-os --single-branch https://github.com/Joercat/os.git os
cd os
bash scripts/deepnote-desktop.sh
```

3. Enable incoming connections in Deepnote:

   **Workspace setting first**
   - Go back to the Deepnote home/workspace view.
   - Click **Settings & Members** in the left sidebar.
   - Open the **Project settings** tab.
   - Turn on **Allow incoming connections in projects**.

   **Then the project setting**
   - Open your project again.
   - Open the **Settings** panel from the top-right.
   - In the **Machine** section, click **More options** next to **Start machine**.
   - Turn on **Incoming connections**.
   - Open the URL Deepnote shows you.

4. Log in to the Kasm page using the username and password printed by the script. If the output shows a `https://...deepnoteproject.com` URL, use that after enabling incoming connections.

Keep the notebook cell/terminal running while you use the desktop. To stop it from another notebook block or terminal:

```bash
cd os
bash scripts/deepnote-stop.sh
```

## What the Deepnote script does

`scripts/deepnote-desktop.sh` installs and starts:

- XFCE desktop
- KasmVNC web desktop server
- common utilities (`curl`, `wget`, `git`, `nano`, `htop`, `zip`, `unzip`, `cpulimit`)
- Firefox ESR or Chromium when available from apt
- a desktop launcher named **Web Browser (Deepnote)** with a conservative CPU limit

It serves KasmVNC on port `8080`, which is the port Deepnote exposes for incoming connections.

## Configuration

You can override defaults with environment variables before running the script:

```bash
VNC_GEOMETRY=1366x768 KASMVNC_PASSWORD='changeme' bash scripts/deepnote-desktop.sh
```

Supported variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `PORT` / `DEEPNOTE_PORT` | `8080` | KasmVNC web listen port. Keep this at `8080` for Deepnote. |
| `VNC_DISPLAY` | `1` | KasmVNC display number. |
| `VNC_GEOMETRY` | `1280x720` | Desktop resolution. Lower values use less bandwidth/CPU. |
| `VNC_DEPTH` | `24` | Color depth. |
| `KASMVNC_USER` | `kasm` | Username for the KasmVNC login page. |
| `KASMVNC_PASSWORD` | generated | Password for the KasmVNC login page. If omitted, one is generated and saved in `~/.vnc/deepnote-kasm-password`. |
| `KASMVNC_VERSION` | `1.5.0` | Official KasmVNC release to install if KasmVNC is not already present. |
| `RESET_KASMVNC` | `true` | When `true`, the launcher cleans all stale current-user Kasm/XFCE sessions before starting. |

## Notes and limitations

- The free Deepnote machine is not an always-on VPS. If Deepnote stops or restarts the machine, start the script again.
- Runtime apt installs can take a few minutes and may need to be repeated on a fresh machine.
- Avoid using this for sensitive browsing. Deepnote incoming connections can expose the desktop URL publicly if shared.
- If the browser package is unavailable in the default apt repositories, the desktop still starts; install a browser manually or use another tool inside the XFCE terminal.
- Each launch resets old current-user KasmVNC/XFCE sessions, clears stale display locks/logs for non-zero displays, and frees port `8080` before starting.
- If you see `Unrecognized option: -WebpVideoQuality`, make sure you are on the latest branch version and rerun the setup block above. Newer commits avoid KasmVNC options that older Deepnote/webtop images do not support.
- If you see `xfce4-session: cannot open display`, make sure you are on the latest branch version and rerun the setup block above. The launcher starts KasmVNC with `-noxstartup`, then launches XFCE manually with `DISPLAY` forced and uses `xfce4-session` directly instead of the `startxfce4` wrapper.
- If you cannot find **Incoming connections**, make sure it is enabled at the workspace level first. You may need to be the workspace admin.

## Existing Docker/Fly-style deployment

The original container deployment remains available:

```bash
docker build -t debian-xfce-webtop .
docker run --rm -p 7860:7860 debian-xfce-webtop
```
