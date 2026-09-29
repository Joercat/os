#!/usr/bin/env bash
set -Eeuo pipefail

PORT="${PORT:-${DEEPNOTE_PORT:-8080}}"
VNC_DISPLAY="${VNC_DISPLAY:-1}"

if command -v vncserver >/dev/null 2>&1; then
  vncserver -kill ":$VNC_DISPLAY" >/dev/null 2>&1 || true
fi

if command -v fuser >/dev/null 2>&1; then
  fuser -k "${PORT}/tcp" >/dev/null 2>&1 || true
fi

echo "Stopped Deepnote KasmVNC display :$VNC_DISPLAY and web port $PORT if they were running."
