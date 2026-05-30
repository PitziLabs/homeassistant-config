#!/bin/bash
xrandr --output HDMI-2 --mode 2560x1440 --rate 60
xset s off
xset -dpms
xset s noblank
unclutter -idle 3 -root &
chromium \
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
  "http://192.168.139.172:8123/dashboard-kiosk/home"
