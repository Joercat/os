#!/usr/bin/env bash
set -Eeuo pipefail

# Runtime setup for Deepnote's free/basic machines using KasmVNC.
# This does NOT use TigerVNC/noVNC. It either uses KasmVNC already present in
# the current image (for example linuxserver/webtop-based images), or installs
# the official KasmVNC .deb package for the running distro.

PORT="${PORT:-${DEEPNOTE_PORT:-8080}}"
VNC_DISPLAY="${VNC_DISPLAY:-1}"
VNC_GEOMETRY="${VNC_GEOMETRY:-1280x720}"
VNC_DEPTH="${VNC_DEPTH:-24}"
KASMVNC_VERSION="${KASMVNC_VERSION:-1.5.0}"
KASMVNC_USER="${KASMVNC_USER:-kasm}"
PASSWORD_FILE="${KASMVNC_PASSWORD_FILE:-$HOME/.vnc/deepnote-kasm-password}"

log() {
  printf '\033[1;34m[deepnote-kasm]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[deepnote-kasm warning]\033[0m %s\n' "$*" >&2
}

fail() {
  printf '\033[1;31m[deepnote-kasm error]\033[0m %s\n' "$*" >&2
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

have_kasmvnc() {
  command -v vncserver >/dev/null 2>&1 || return 1
  command -v vncpasswd >/dev/null 2>&1 || return 1
  command -v Xvnc >/dev/null 2>&1 || return 1

  local version_output
  version_output="$(Xvnc -version 2>&1 || true)"
  grep -qi 'KasmVNC' <<< "$version_output"
}

install_desktop_packages() {
  log "Installing XFCE and helper tools. This can take several minutes the first time."
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
    procps \
    psmisc \
    htop \
    nano \
    git \
    zip \
    unzip \
    cpulimit
}

detect_kasmvnc_codename() {
  local distro_id codename
  distro_id=""
  codename=""

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    distro_id="${ID:-}"
    codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  fi

  case "$codename" in
    bookworm|bullseye|trixie|focal|jammy|noble|kali-rolling)
      printf '%s\n' "$codename"
      return
      ;;
  esac

  case "$distro_id" in
    debian)
      printf '%s\n' "bookworm"
      ;;
    ubuntu)
      printf '%s\n' "jammy"
      ;;
    kali)
      printf '%s\n' "kali-rolling"
      ;;
    *)
      warn "Could not detect a KasmVNC package for this distro; trying Ubuntu Jammy package."
      printf '%s\n' "jammy"
      ;;
  esac
}

install_kasmvnc() {
  if have_kasmvnc; then
    log "KasmVNC is already installed in this environment."
    return
  fi

  log "Installing official KasmVNC ${KASMVNC_VERSION}."
  export DEBIAN_FRONTEND=noninteractive

  # If an older attempt installed TigerVNC, remove it so KasmVNC owns vncserver/Xvnc.
  run_as_root apt-get purge -y tigervnc-standalone-server tigervnc-common tigervnc-tools tightvncserver vnc4server >/dev/null 2>&1 || true
  run_as_root apt-get autoremove -y >/dev/null 2>&1 || true

  local codename deb_url deb_path
  codename="$(detect_kasmvnc_codename)"
  deb_url="https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_${codename}_${KASMVNC_VERSION}_amd64.deb"
  deb_path="/tmp/kasmvncserver_${codename}_${KASMVNC_VERSION}_amd64.deb"

  log "Downloading ${deb_url}"
  if command -v curl >/dev/null 2>&1; then
    curl -fL "$deb_url" -o "$deb_path"
  else
    wget -O "$deb_path" "$deb_url"
  fi

  run_as_root apt-get install -y "$deb_path"
  rm -f "$deb_path"

  if ! have_kasmvnc; then
    fail "KasmVNC did not install correctly."
  fi
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
  cat > "$HOME/.local/bin/deepnote-browser" <<EOF_INNER
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
EOF_INNER
  chmod +x "$HOME/.local/bin/deepnote-browser"

  cat > "$HOME/.local/share/applications/deepnote-browser.desktop" <<EOF_INNER
[Desktop Entry]
Name=Web Browser (Deepnote)
Exec=$HOME/.local/bin/deepnote-browser %u
Icon=$icon_name
Type=Application
Categories=Network;WebBrowser;
EOF_INNER
}

generate_password() {
  # 14 hex chars, simple to copy/paste, no dependency on Python or OpenSSL.
  od -An -N7 -tx1 /dev/urandom | tr -d ' \n'
  printf '\n'
}

prepare_kasm_password() {
  mkdir -p "$HOME/.vnc"
  chmod 700 "$HOME/.vnc"

  if [[ -n "${KASMVNC_PASSWORD:-}" ]]; then
    printf '%s\n' "$KASMVNC_PASSWORD" > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
  elif [[ ! -s "$PASSWORD_FILE" ]]; then
    generate_password > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
  fi

  local password
  password="$(tr -d '\r\n' < "$PASSWORD_FILE")"
  [[ ${#password} -ge 6 ]] || fail "KasmVNC password must be at least 6 characters."

  # KasmVNC's vncpasswd stores HTTP Basic Auth users in ~/.kasmpasswd.
  printf '%s\n%s\n' "$password" "$password" | vncpasswd -u "$KASMVNC_USER" -ow >/dev/null
  chmod 600 "$HOME/.kasmpasswd"
}

split_geometry() {
  local width height
  width="${VNC_GEOMETRY%x*}"
  height="${VNC_GEOMETRY#*x}"
  [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]] || fail "VNC_GEOMETRY must look like 1280x720."
  printf '%s %s\n' "$width" "$height"
}

prepare_kasm_config() {
  local width height
  read -r width height < <(split_geometry)

  mkdir -p "$HOME/.vnc"
  cat > "$HOME/.vnc/kasmvnc.yaml" <<EOF_INNER
desktop:
  resolution:
    width: $width
    height: $height
  allow_resize: true
  pixel_depth: $VNC_DEPTH

network:
  protocol: http
  interface: 0.0.0.0
  websocket_port: $PORT
  use_ipv4: true
  use_ipv6: false
  ssl:
    require_ssl: false

user_session:
  new_session_disconnects_existing_exclusive_session: false
  concurrent_connections_prompt: false
  concurrent_connections_prompt_timeout: 0
  idle_timeout: never

encoding:
  max_frame_rate: 20
  rect_encoding_mode:
    min_quality: 5
    max_quality: 7
  video_encoding_mode:
    jpeg_quality: 65
    webp_quality: 65

server:
  advanced:
    kasm_password_file: $HOME/.kasmpasswd
  auto_shutdown:
    no_user_session_timeout: never
    active_user_session_timeout: never
    inactive_user_session_timeout: never

command_line:
  prompt: false
EOF_INNER
}

prepare_xstartup() {
  mkdir -p "$HOME/.vnc"
  cat > "$HOME/.vnc/xstartup" <<'EOF_INNER'
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
EOF_INNER
  chmod +x "$HOME/.vnc/xstartup"
}

stop_previous_session() {
  log "Stopping any previous KasmVNC session on display :$VNC_DISPLAY and port $PORT."
  vncserver -kill ":$VNC_DISPLAY" >/dev/null 2>&1 || true
  if command -v fuser >/dev/null 2>&1; then
    fuser -k "${PORT}/tcp" >/dev/null 2>&1 || true
  fi
}

start_kasmvnc() {
  log "Starting XFCE over KasmVNC on display :$VNC_DISPLAY and web port $PORT."
  vncserver ":$VNC_DISPLAY" \
    -select-de xfce \
    -geometry "$VNC_GEOMETRY" \
    -depth "$VNC_DEPTH" \
    -xstartup "$HOME/.vnc/xstartup"
}

print_ready_message() {
  local password
  password="$(tr -d '\r\n' < "$PASSWORD_FILE")"

  cat <<EOF_INNER

KasmVNC desktop is ready on port $PORT.

Deepnote login for the Kasm page:
  Username: $KASMVNC_USER
  Password: $password

Next steps in Deepnote:
  1. Make sure incoming connections are enabled for the workspace.
  2. In this project, open Settings -> Machine -> More options next to Start machine.
  3. Toggle on Incoming connections and open the URL Deepnote shows you.

Keep this terminal running. Press Ctrl+C here to stop the desktop.

EOF_INNER
}

follow_logs_until_stopped() {
  local log_glob tail_pid

  # KasmVNC writes under ~/.vnc. Give the log file a moment to appear.
  sleep 2
  log_glob=("$HOME/.vnc"/*.log)

  cleanup() {
    log "Stopping KasmVNC."
    vncserver -kill ":$VNC_DISPLAY" >/dev/null 2>&1 || true
    [[ -n "${tail_pid:-}" ]] && kill "$tail_pid" >/dev/null 2>&1 || true
  }
  trap cleanup INT TERM EXIT

  if compgen -G "$HOME/.vnc/*.log" >/dev/null; then
    tail -n 80 -F "$HOME/.vnc"/*.log &
    tail_pid=$!
    wait "$tail_pid"
  else
    log "No KasmVNC log file found yet. Desktop is still running; press Ctrl+C to stop."
    while true; do sleep 3600; done
  fi
}

main() {
  if [[ "$PORT" != "8080" ]]; then
    warn "Deepnote incoming connections expose port 8080. You set PORT=$PORT; keep PORT=8080 unless you know you have a forwarder."
  fi

  install_desktop_packages
  install_kasmvnc
  install_browser_if_possible
  prepare_browser_launcher
  prepare_kasm_password
  prepare_kasm_config
  prepare_xstartup
  stop_previous_session
  start_kasmvnc
  print_ready_message
  follow_logs_until_stopped
}

main "$@"
