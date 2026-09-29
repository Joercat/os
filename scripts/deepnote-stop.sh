#!/usr/bin/env bash
set -Eeuo pipefail

PORT="${PORT:-${DEEPNOTE_PORT:-8080}}"
VNC_DISPLAY="${VNC_DISPLAY:-1}"
uid="$(id -u)"

displays=""
if command -v vncserver >/dev/null 2>&1; then
  displays="$(vncserver -list 2>/dev/null | grep -oE ':[0-9]+' | sort -u || true)"
  for display in $displays ":$VNC_DISPLAY"; do
    [[ -n "$display" ]] || continue
    vncserver -kill "$display" >/dev/null 2>&1 || true
  done
fi

pkill -u "$uid" -x Xvnc >/dev/null 2>&1 || true
pkill -u "$uid" -x Xkasmvnc >/dev/null 2>&1 || true
pkill -u "$uid" -x kasmxproxy >/dev/null 2>&1 || true
pkill -u "$uid" -f 'xfce4-session|xfwm4|xfce4-panel|xfdesktop|Thunar' >/dev/null 2>&1 || true
pkill -u "$uid" -f 'dbus-launch --exit-with-session xfce4-session' >/dev/null 2>&1 || true

if command -v fuser >/dev/null 2>&1; then
  fuser -k "${PORT}/tcp" >/dev/null 2>&1 || true
fi

for display in $displays ":$VNC_DISPLAY"; do
  number="${display#:}"
  [[ "$number" =~ ^[1-9][0-9]*$ ]] || continue
  rm -f "/tmp/.X${number}-lock" "/tmp/.X11-unix/X${number}" 2>/dev/null || true
  rm -f "$HOME/.vnc/"*":${number}.log" "$HOME/.vnc/"*":${number}.pid" "$HOME/.vnc/xfce-manual:${number}.log" 2>/dev/null || true
done

echo "Stopped all current-user KasmVNC/XFCE sessions and freed web port $PORT if they were running."
