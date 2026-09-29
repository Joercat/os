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
RESET_KASMVNC="${RESET_KASMVNC:-true}"
XFCE_LOG_FILE="$HOME/.vnc/xfce-manual:${VNC_DISPLAY}.log"

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
    x11-utils \
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
  cat > "$HOME/.vnc/xstartup" <<EOF_INNER
#!/bin/sh
set -eu

# KasmVNC sometimes starts xstartup with a sparse environment in notebook
# containers. Be explicit so XFCE never sees an empty DISPLAY.
export DISPLAY=":$VNC_DISPLAY"
export HOME="\${HOME:-$HOME}"
export USER="\${USER:-${USER:-$(id -un)}}"
export LOGNAME="\${LOGNAME:-\$USER}"
export SHELL="\${SHELL:-/bin/bash}"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$HOME/.local/bin"
export XAUTHORITY="\${XAUTHORITY:-\$HOME/.Xauthority}"
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
export DESKTOP_SESSION=xfce
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Wait briefly until the virtual X display is accepting clients.
i=0
while [ "\$i" -lt 75 ]; do
  if command -v xset >/dev/null 2>&1 && xset -display "\$DISPLAY" q >/dev/null 2>&1; then
    break
  fi
  if command -v xdpyinfo >/dev/null 2>&1 && xdpyinfo -display "\$DISPLAY" >/dev/null 2>&1; then
    break
  fi
  i=\$((i + 1))
  sleep 0.2
done

if command -v xset >/dev/null 2>&1 && ! xset -display "\$DISPLAY" q >/dev/null 2>&1; then
  echo "KasmVNC display \$DISPLAY is not ready; refusing to start XFCE with an empty/broken display." >&2
  exit 1
fi

if command -v xrdb >/dev/null 2>&1 && [ -r "\$HOME/.Xresources" ]; then
  xrdb -display "\$DISPLAY" "\$HOME/.Xresources" || true
fi

# Keep XFCE light for Deepnote's free/basic machines.
if command -v xfconf-query >/dev/null 2>&1; then
  xfconf-query -c xfwm4 -p /general/use_compositing -s false >/dev/null 2>&1 || true
fi

# Use xfce4-session directly instead of startxfce4; the wrapper is where the
# "xfce4-session: cannot open display:" message can happen if DISPLAY is lost.
exec env -i \
  HOME="\$HOME" \
  USER="\$USER" \
  LOGNAME="\$LOGNAME" \
  SHELL="\$SHELL" \
  PATH="\$PATH" \
  DISPLAY="\$DISPLAY" \
  XAUTHORITY="\$XAUTHORITY" \
  XDG_SESSION_TYPE=x11 \
  XDG_CURRENT_DESKTOP=XFCE \
  DESKTOP_SESSION=xfce \
  dbus-launch --exit-with-session xfce4-session
EOF_INNER
  chmod +x "$HOME/.vnc/xstartup"
}

stop_previous_session() {
  log "Resetting old KasmVNC/XFCE sessions and freeing port $PORT."

  local displays display number uid
  uid="$(id -u)"
  displays=""

  if command -v vncserver >/dev/null 2>&1; then
    if [[ "$RESET_KASMVNC" == "true" ]]; then
      displays="$(vncserver -list 2>/dev/null | grep -oE ':[0-9]+' | sort -u || true)"
    else
      displays=":$VNC_DISPLAY"
    fi

    for display in $displays ":$VNC_DISPLAY"; do
      [[ -n "$display" ]] || continue
      log "Stopping VNC display $display if present."
      vncserver -kill "$display" >/dev/null 2>&1 || true
    done
  fi

  if [[ "$RESET_KASMVNC" == "true" ]]; then
    # KasmVNC's vncserver -list can miss half-started sessions, so also kill
    # current-user Kasm/XFCE leftovers. This is intentionally scoped to the
    # current user so it does not disturb Deepnote system services.
    pkill -u "$uid" -x Xvnc >/dev/null 2>&1 || true
    pkill -u "$uid" -x Xkasmvnc >/dev/null 2>&1 || true
    pkill -u "$uid" -x kasmxproxy >/dev/null 2>&1 || true
    pkill -u "$uid" -f 'xfce4-session|xfwm4|xfce4-panel|xfdesktop|Thunar' >/dev/null 2>&1 || true
    pkill -u "$uid" -f 'dbus-launch --exit-with-session xfce4-session' >/dev/null 2>&1 || true
  fi

  if command -v fuser >/dev/null 2>&1; then
    fuser -k "${PORT}/tcp" >/dev/null 2>&1 || true
  fi

  # Remove stale display locks/logs from previous failed attempts. Do not touch
  # :0 because notebook platforms may use it internally.
  for display in $displays ":$VNC_DISPLAY"; do
    number="${display#:}"
    [[ "$number" =~ ^[1-9][0-9]*$ ]] || continue
    rm -f "/tmp/.X${number}-lock" "/tmp/.X11-unix/X${number}" 2>/dev/null || true
    rm -f "$HOME/.vnc/"*":${number}.log" "$HOME/.vnc/"*":${number}.pid" "$HOME/.vnc/xfce-manual:${number}.log" 2>/dev/null || true
  done

  sleep 1
}

start_kasmvnc() {
  log "Starting KasmVNC display :$VNC_DISPLAY on web port $PORT."
  # Start only the KasmVNC X/web server here. We launch XFCE ourselves below
  # with DISPLAY forced. That avoids KasmVNC/vncserver startup wrappers losing
  # DISPLAY and producing: "xfce4-session: cannot open display:".
  env -u DISPLAY -u SESSION_MANAGER -u DBUS_SESSION_BUS_ADDRESS \
    vncserver ":$VNC_DISPLAY" \
      -geometry "$VNC_GEOMETRY" \
      -depth "$VNC_DEPTH" \
      -noxstartup

  log "Starting XFCE manually on KasmVNC display :$VNC_DISPLAY."
  : > "$XFCE_LOG_FILE"
  nohup "$HOME/.vnc/xstartup" >> "$XFCE_LOG_FILE" 2>&1 &
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

current_log_file() {
  ls -t "$HOME/.vnc/"*":${VNC_DISPLAY}.log" 2>/dev/null | head -n 1 || true
}

print_recent_logs() {
  local log_file
  log_file="$(current_log_file)"

  if [[ -n "$log_file" ]]; then
    printf '\n--- KasmVNC log: %s ---\n' "$log_file" >&2
    tail -n 120 "$log_file" >&2 || true
  fi

  if [[ -f "$XFCE_LOG_FILE" ]]; then
    printf '\n--- XFCE startup log: %s ---\n' "$XFCE_LOG_FILE" >&2
    tail -n 120 "$XFCE_LOG_FILE" >&2 || true
  fi
}

wait_for_desktop() {
  local log_file uid
  uid="$(id -u)"

  for _ in {1..75}; do
    if pgrep -u "$uid" -f 'xfce4-session|xfwm4|xfce4-panel' >/dev/null 2>&1; then
      return 0
    fi

    log_file="$(current_log_file)"
    if { [[ -n "$log_file" ]] && grep -Eqi 'cannot open display|KasmVNC display .* is not ready|xstartup.*(failed|exited)' "$log_file"; } || \
       { [[ -f "$XFCE_LOG_FILE" ]] && grep -Eqi 'cannot open display|KasmVNC display .* is not ready|xfce4-session.*failed' "$XFCE_LOG_FILE"; }; then
      warn "XFCE did not start cleanly. Recent logs follow:"
      print_recent_logs
      return 1
    fi

    sleep 0.4
  done

  warn "KasmVNC started, but XFCE was not detected after 30 seconds. Recent logs follow:"
  print_recent_logs
  return 1
}

follow_logs_until_stopped() {
  local log_file tail_pid

  # KasmVNC writes under ~/.vnc. Give the log file a moment to appear.
  sleep 1
  log_file="$(current_log_file)"

  cleanup() {
    log "Stopping KasmVNC."
    vncserver -kill ":$VNC_DISPLAY" >/dev/null 2>&1 || true
    [[ -n "${tail_pid:-}" ]] && kill "$tail_pid" >/dev/null 2>&1 || true
  }
  trap cleanup INT TERM EXIT

  if [[ -n "$log_file" && -f "$XFCE_LOG_FILE" ]]; then
    tail -n 80 -F "$log_file" "$XFCE_LOG_FILE" &
    tail_pid=$!
    wait "$tail_pid"
  elif [[ -n "$log_file" ]]; then
    tail -n 80 -F "$log_file" &
    tail_pid=$!
    wait "$tail_pid"
  elif [[ -f "$XFCE_LOG_FILE" ]]; then
    tail -n 80 -F "$XFCE_LOG_FILE" &
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
  if ! wait_for_desktop; then
    stop_previous_session
    fail "KasmVNC started, but XFCE failed to attach to its display."
  fi
  print_ready_message
  follow_logs_until_stopped
}

main "$@"
