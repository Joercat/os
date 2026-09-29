# Debian XFCE web desktop

This repo still contains the original Docker/Fly setup (`Dockerfile` + `fly.toml`), but Deepnote's free/basic plan is better handled without a custom Docker image. Use the runtime installer below inside a normal Deepnote project.

## Run on Deepnote for free

1. Create a free Deepnote project using the default Python environment.
2. Open **Terminal** in the Deepnote sidebar.
3. Paste this whole block into the Deepnote Terminal. It removes any old `os` folder that may have cloned the wrong branch, then clones this Arena branch specifically:

   ```bash
   cd ~/work 2>/dev/null || cd ~
   rm -rf os
   git clone --branch arena/01a0eb07-os --single-branch https://github.com/Joercat/os.git os
   cd os
   bash scripts/deepnote-desktop.sh
   ```

4. In Deepnote, open **Environment** and enable **Allow incoming connections**.
5. Open the incoming-connections URL Deepnote gives you.
6. Enter the VNC password printed by the script.

Keep the terminal running while you use the desktop. To stop it from another terminal:

```bash
cd os
bash scripts/deepnote-stop.sh
```

## What the Deepnote script does

`scripts/deepnote-desktop.sh` installs and starts:

- XFCE desktop
- TigerVNC server
- noVNC/websockify browser bridge
- common utilities (`curl`, `wget`, `git`, `nano`, `htop`, `zip`, `unzip`, `cpulimit`)
- Firefox ESR or Chromium when available from apt
- a desktop launcher named **Web Browser (Deepnote)** with a conservative CPU limit

It serves noVNC on port `8080`, which is the port Deepnote exposes for incoming connections.

## Configuration

You can override defaults with environment variables before running the script:

```bash
VNC_GEOMETRY=1366x768 VNC_PASSWORD='changeme' bash scripts/deepnote-desktop.sh
```

Supported variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `PORT` / `DEEPNOTE_PORT` | `8080` | noVNC listen port. Keep this at `8080` for Deepnote. |
| `VNC_DISPLAY` | `1` | VNC display number. Display `1` maps to VNC port `5901`. |
| `VNC_GEOMETRY` | `1280x720` | Desktop resolution. Lower values use less bandwidth/CPU. |
| `VNC_DEPTH` | `24` | Color depth. |
| `VNC_PASSWORD` | generated | Password shown by noVNC. VNC auth uses up to 8 characters. If omitted, one is generated and saved in `~/.vnc/deepnote-password`. |

## Notes and limitations

- The free Deepnote machine is not an always-on VPS. If Deepnote stops or restarts the machine, start the script again.
- Runtime apt installs can take a few minutes and may need to be repeated on a fresh machine.
- Avoid using this for sensitive browsing. Deepnote incoming connections can expose the desktop URL publicly if shared.
- If the browser package is unavailable in the default apt repositories, the desktop still starts; install a browser manually or use another tool inside the XFCE terminal.

## Existing Docker/Fly deployment

The original container deployment remains available:

```bash
docker build -t debian-xfce-webtop .
docker run --rm -p 7860:7860 debian-xfce-webtop
```

Fly.io is configured in `fly.toml` for port `7860` with a `/config` volume.
