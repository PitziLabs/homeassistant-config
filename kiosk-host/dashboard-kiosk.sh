#!/bin/bash
# Dashboard kiosk runner. Two modes, selected by KIOSK_MODE in
# /etc/default/dashboard-kiosk (sourced below if present):
#
#   kiosk    — fullscreen Chromium, no chrome, no WM. The default; renders
#              the household HA dashboard.
#   browser  — windowed Chromium with the normal UI (tabs, address bar),
#              under an openbox WM so the window is movable/resizable.
#              Use for ad-hoc "put this URL on the household monitor"
#              from SSH via /usr/local/bin/kiosk-show.
#
# The state file is NOT managed by the gitops loop — it's mutable runtime
# state owned by kiosk-show. Defaults below apply when the file is absent.
set -eu

KIOSK_MODE="kiosk"
KIOSK_URL="http://homeassistant.local:8123/dashboard-kiosk/home"

if [ -r /etc/default/dashboard-kiosk ]; then
  # shellcheck disable=SC1091
  . /etc/default/dashboard-kiosk
fi

xrandr --output HDMI-2 --mode 2560x1440 --rate 60
xset s off
xset -dpms
xset s noblank

case "${KIOSK_MODE}" in
  browser)
    openbox &
    exec chromium \
      --no-sandbox \
      --no-first-run \
      --disable-session-crashed-bubble \
      --disable-features=TranslateUI \
      --check-for-update-interval=31536000 \
      --force-device-scale-factor=1 \
      --start-maximized \
      "${KIOSK_URL}"
    ;;
  kiosk|*)
    unclutter -idle 3 -root &
    exec chromium \
      --no-sandbox \
      --kiosk \
      --noerrdialogs \
      --disable-infobars \
      --no-first-run \
      --disable-session-crashed-bubble \
      --disable-features=TranslateUI \
      --check-for-update-interval=31536000 \
      --force-device-scale-factor=1 \
      --window-size=2560,1440 \
      --window-position=0,0 \
      "${KIOSK_URL}"
    ;;
esac
