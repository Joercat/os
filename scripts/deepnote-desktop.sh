#!/usr/bin/env bash
set -Eeuo pipefail

# Runtime setup for Deepnote's free/basic machines.
# Deepnote's free tier cannot use this repository's Dockerfile as a custom
# environment, so this script installs and starts a lightweight XFCE + noVNC
# desktop directly inside the running Deepnote machine.

PORT="${PORT:-${DEEPNOTE_PORT:-8080}}"
VNC_DISPLAY="${VNC_DISPLAY:-1}"
VNC_GEOMETRY="${VNC_GEOMETRY:-1280x720}"
VNC_DEPTH="${VNC_DEPTH:-24}"
VNC_PORT=$((5900 + VNC_DISPLAY))
PASSWORD_FILE="${VNC_PASSWORD_FILE:-$HOME/.vnc/deepnote-password}"
NOVNC_WEBROOT="${NOVNC_WEBROOT:-/tmp/deepnote-novnc-web}"

log() {
  printf '\033[1;34m[deepnote-desktop]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[deepnote-desktop warning]\033[0m %s\n' "$*" >&2
}

fail() {
  printf '\033[1;31m[deepnote-desktop error]\033[0m %s\n' "$*" >&2
  exit 1
}

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    fail "This script needs root or passwordless sudo to install desktop packages."
  fi
}

have_desktop_stack() {
  (command -v vncserver >/dev/null 2>&1 || command -v tigervncserver >/dev/null 2>&1) && \
  (command -v vncpasswd >/dev/null 2>&1 || command -v tigervncpasswd >/dev/null 2>&1) && \
  command -v websockify >/dev/null 2>&1 && \
  command -v startxfce4 >/dev/null 2>&1 && \
  [[ -d /usr/share/novnc || -d /usr/share/novnc/app ]]
}

install_desktop_stack() {
  log "Installing XFCE, TigerVNC, noVNC, and helper tools. This can take several minutes the first time."
  export DEBIAN_FRONTEND=noninteractive

  run_as_root apt-get update
  run_as_root apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    sudo \
    dbus-x11 \
    xfce4 \
    xfce4-terminal \
    x11-xserver-utils \
    xterm \
    tigervnc-standalone-server \
    tigervnc-common \
    novnc \
    websockify \
    procps \
    psmisc \
    htop \
    nano \
    git \
    zip \
    unzip \
    cpulimit

  run_as_root apt-get clean
  run_as_root rm -rf /var/lib/apt/lists/*
}

browser_cmd() {
  for candidate in firefox-esr firefox chromium chromium-browser; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

install_browser_if_possible() {
  if browser_cmd >/dev/null 2>&1; then
    return
  fi

  log "Trying to install a browser for the desktop session."
  export DEBIAN_FRONTEND=noninteractive
  run_as_root apt-get update || true

  for browser_pkg in firefox-esr chromium firefox chromium-browser; do
    if run_as_root apt-get install -y --no-install-recommends "$browser_pkg"; then
      log "Installed browser package: $browser_pkg"
      run_as_root apt-get clean || true
      run_as_root rm -rf /var/lib/apt/lists/* || true
      return
    fi
  done

  warn "Could not install Firefox/Chromium from this distro's apt repositories. The desktop will still start."
}

prepare_browser_launcher() {
  local detected_browser browser_name icon_name
  detected_browser="$(browser_cmd || true)"
  [[ -n "$detected_browser" ]] || return

  browser_name="$(basename "$detected_browser")"
  icon_name="$browser_name"

  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
  cat > "$HOME/.local/bin/deepnote-browser" <<EOF
#!/usr/bin/env bash
set -e
BROWSER_CMD="$detected_browser"
BROWSER_NAME="$browser_name"
CPU_LIMIT="\${BROWSER_CPU_LIMIT:-80}"

if command -v cpulimit >/dev/null 2>&1; then
  cpulimit -l "\$CPU_LIMIT" -e "\$BROWSER_NAME" >/dev/null 2>&1 &
fi

if [[ "\$(id -u)" -eq 0 && "\$BROWSER_NAME" == chromium* ]]; then
  exec "\$BROWSER_CMD" --no-sandbox "\$@"
else
  exec "\$BROWSER_CMD" "\$@"
fi
EOF
  chmod +x "$HOME/.local/bin/deepnote-browser"

  cat > "$HOME/.local/share/applications/deepnote-browser.desktop" <<EOF
[Desktop Entry]
Name=Web Browser (Deepnote)
Exec=$HOME/.local/bin/deepnote-browser %u
Icon=$icon_name
Type=Application
Categories=Network;WebBrowser;
EOF
}

find_novnc_root() {
  if [[ -d /usr/share/novnc ]]; then
    printf '%s\n' /usr/share/novnc
  elif [[ -d /usr/share/novnc/app ]]; then
    printf '%s\n' /usr/share/novnc/app
  else
    fail "noVNC web files were not found under /usr/share/novnc."
  fi
}

generate_password() {
  python3 - <<'PY'
import secrets
import string
alphabet = string.ascii_letters + string.digits
# VNC auth effectively uses up to 8 characters, so keep the displayed password
# at 8 chars to avoid confusion.
print(''.join(secrets.choice(alphabet) for _ in range(8)))
PY
}

vncserver_cmd() {
  if command -v vncserver >/dev/null 2>&1; then
    command -v vncserver
  elif command -v tigervncserver >/dev/null 2>&1; then
    command -v tigervncserver
  else
    fail "TigerVNC server command was not found after installation."
  fi
}

vncpasswd_cmd() {
  if command -v vncpasswd >/dev/null 2>&1; then
    command -v vncpasswd
  elif command -v tigervncpasswd >/dev/null 2>&1; then
    command -v tigervncpasswd
  else
    fail "TigerVNC password command was not found after installation."
  fi
}

prepare_vnc_password() {
  mkdir -p "$HOME/.vnc"
  chmod 700 "$HOME/.vnc"

  if [[ -n "${VNC_PASSWORD:-}" ]]; then
    printf '%s\n' "$VNC_PASSWORD" > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
  elif [[ ! -s "$PASSWORD_FILE" ]]; then
    generate_password > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
  fi

  local password passwd_cmd
  password="$(tr -d '\r\n' < "$PASSWORD_FILE")"
  [[ -n "$password" ]] || fail "VNC password is empty."
  if (( ${#password} > 8 )); then
    warn "VNC auth only uses the first 8 password characters; truncating the saved password to avoid login confusion."
    password="${password:0:8}"
    printf '%s\n' "$password" > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
  fi
  passwd_cmd="$(vncpasswd_cmd)"

  printf '%s\n' "$password" | "$passwd_cmd" -f > "$HOME/.vnc/passwd"
  chmod 600 "$HOME/.vnc/passwd"
}

prepare_xstartup() {
  mkdir -p "$HOME/.vnc"
  cat > "$HOME/.vnc/xstartup" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
export DESKTOP_SESSION=xfce

if command -v xrdb >/dev/null 2>&1 && [ -r "$HOME/.Xresources" ]; then
  xrdb "$HOME/.Xresources"
fi

exec dbus-launch --exit-with-session startxfce4
EOF
  chmod +x "$HOME/.vnc/xstartup"
}

prepare_novnc_webroot() {
  local novnc_source
  novnc_source="$(find_novnc_root)"

  rm -rf "$NOVNC_WEBROOT"
  mkdir -p "$NOVNC_WEBROOT"
  cp -a "$novnc_source"/. "$NOVNC_WEBROOT"/

  cat > "$NOVNC_WEBROOT/index.html" <<'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=true&resize=remote&path=websockify">
    <title>Deepnote Desktop</title>
  </head>
  <body>
    <p>Opening noVNC desktop… If nothing happens, <a href="vnc.html?autoconnect=true&resize=remote&path=websockify">click here</a>.</p>
  </body>
</html>
EOF
}

stop_previous_session() {
  local server_cmd
  server_cmd="$(vncserver_cmd)"

  log "Stopping any previous VNC/noVNC session on display :$VNC_DISPLAY and port $PORT."
  "$server_cmd" -kill ":$VNC_DISPLAY" >/dev/null 2>&1 || true
  if command -v fuser >/dev/null 2>&1; then
    fuser -k "${PORT}/tcp" >/dev/null 2>&1 || true
  fi
}

start_vnc() {
  local server_cmd
  server_cmd="$(vncserver_cmd)"

  log "Starting XFCE over VNC on display :$VNC_DISPLAY ($VNC_GEOMETRY, depth $VNC_DEPTH)."
  "$server_cmd" ":$VNC_DISPLAY" \
    -geometry "$VNC_GEOMETRY" \
    -depth "$VNC_DEPTH" \
    -xstartup "$HOME/.vnc/xstartup" \
    -localhost no \
    -SecurityTypes VncAuth
}

start_novnc() {
  local password
  password="$(tr -d '\r\n' < "$PASSWORD_FILE")"

  cat <<EOF

Deepnote desktop is ready to serve on port $PORT.

Next steps in Deepnote:
  1. In the right sidebar, open Environment and enable "Allow incoming connections".
  2. Open the project's incoming-connections URL.
  3. Use this VNC password when prompted: $password

Keep this terminal running. Press Ctrl+C here to stop the desktop.

EOF

  log "Starting noVNC on 0.0.0.0:$PORT -> localhost:$VNC_PORT"
  exec websockify --web="$NOVNC_WEBROOT" --heartbeat=30 "0.0.0.0:$PORT" "localhost:$VNC_PORT"
}

main() {
  if [[ "$PORT" != "8080" ]]; then
    warn "Deepnote incoming connections expose port 8080. You set PORT=$PORT; make sure you are forwarding 8080 to $PORT or set PORT=8080."
  fi

  if ! have_desktop_stack; then
    install_desktop_stack
  else
    log "Desktop stack is already installed."
  fi

  install_browser_if_possible
  prepare_browser_launcher
  prepare_vnc_password
  prepare_xstartup
  prepare_novnc_webroot
  stop_previous_session
  start_vnc
  start_novnc
}

main "$@"
