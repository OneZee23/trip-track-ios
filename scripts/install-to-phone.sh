#!/bin/bash
#
# Собрать и поставить TripTrack на подключённый iPhone.
#
# Единственное, чего скрипт не может сделать за тебя: РАЗБЛОКИРОВАТЬ телефон.
# Xcode отказывается готовить заблокированное устройство и говорит про это
# невнятно — «may need to be unlocked to recover from previously reported
# preparation errors», — поэтому скрипт проверяет состояние сам и говорит прямо.
#
# Запуск:  bash scripts/install-to-phone.sh
set -euo pipefail
cd "$(dirname "$0")/.."

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

say "1/3  Ищу телефон"
xcrun devicectl list devices --json-output /tmp/tt-devices.json >/dev/null 2>&1 || true
UDID=$(python3 - <<'PY'
import json
try:
    d = json.load(open('/tmp/tt-devices.json'))
except Exception:
    raise SystemExit
best = None
for dev in d.get('result', {}).get('devices', []):
    hw = dev.get('hardwareProperties', {})
    if hw.get('platform') != 'iOS':
        continue
    conn = dev.get('connectionProperties', {})
    if conn.get('tunnelState') == 'unavailable':
        continue
    # Кабель предпочтительнее сети: по сети установка бывает вдвое дольше и
    # чаще отваливается на середине.
    score = 0 if conn.get('transportType') == 'wired' else 1
    if best is None or score < best[0]:
        best = (score, dev.get('identifier'), dev.get('deviceProperties', {}).get('name', '?'))
if best:
    print(best[1])
PY
)

if [ -z "${UDID:-}" ]; then
  echo "Телефон не найден. Подключи его кабелем и разблокируй."
  exit 1
fi
echo "устройство: $UDID"

say "2/3  Сборка под устройство"
xcodebuild -scheme TripTrack -configuration Debug \
  -destination "id=$UDID" -allowProvisioningUpdates build >/tmp/tt-build.log 2>&1 || {
    echo "Сборка не прошла. Хвост лога:"
    grep -E "error:|may need to be unlocked" /tmp/tt-build.log | tail -5
    echo
    echo "Если написано «may need to be unlocked» — РАЗБЛОКИРУЙ телефон и запусти снова."
    exit 1
  }

APP=$(find ~/Library/Developer/Xcode/DerivedData -type d -name 'TripTrack.app' \
        -path '*Debug-iphoneos*' -print0 2>/dev/null | xargs -0 ls -td | head -1)
echo "собрано: $APP"

say "3/3  Установка"
xcrun devicectl device install app --device "$UDID" "$APP"
echo
echo "Готово. Приложение на телефоне."
