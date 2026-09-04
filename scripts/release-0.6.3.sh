#!/bin/bash
# ВНИМАНИЕ (сентябрь 2026): этот скрипт описывает 0.6.4 как «заготовку»
# (справочник марок, не подключённый ни к одному экрану). С тех пор 0.6.4 стала
# полноценным релизом — паспорт машины, фотографии, чужой гараж, CoreData v9,
# билд 55. Всё, что ниже про «исключить заготовку 0.6.4», к сегодняшнему дереву
# НЕ ОТНОСИТСЯ и повторять это нельзя. Скрипт оставлен как запись о том, как
# собирали 0.6.3.

#
# Релиз 0.6.3 — коммиты в обеих репах и тег на iOS.
#
# Скрипт НЕ пушит и ничего не выкладывает: он только раскладывает готовое
# дерево по коммитам и ставит тег. Пуш и отправка в стор — руками, ниже
# написано, в каком порядке.
#
# Отдельная забота скрипта: в дереве лежит заготовка 0.6.4 (справочник марок).
# Она не подключена ни к одному экрану, но в тег релиза ей попадать незачем,
# поэтому она уезжает СВОИМ коммитом уже после тега. Одна строка в project.yml
# принадлежит ей же — её приходится временно вынимать, иначе коммит релиза
# ссылался бы на файл, которого в нём нет, и `xcodegen` на свежем клоне упал бы.
#
# Запуск:  bash scripts/release-0.6.3.sh
set -euo pipefail

IOS=/Users/onezee/OneZeeProjects/trip-track
API=/Users/onezee/OneZeeProjects/trip-track-backend

GARAGE_064=(
  "TripTrack/Resources/VehicleCatalog.json"
  "TripTrack/Services/VehicleCatalog.swift"
  "TripTrackTests/VehicleCatalogTests.swift"
  "TripTrackTests/VehicleMapFeasibilityTests.swift"
  "scripts/gen_vehicle_catalog.py"
  "scripts/release-0.6.3.sh"
)

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ─────────────────────────────────────────────────────────── бэкенд
say "1/4  Бэкенд — коммит"
cd "$API"
git add -A
# Тега здесь нет намеренно: бэкенд-репу никогда не тегали, деплой едет с
# пуша в master, и заводить одну метку в пустом списке смысла нет.
git commit -m "feat: visibility gates"
git --no-pager log --oneline -1

# ─────────────────────────────────────────────────────────── iOS: релиз
say "2/4  iOS — коммит релиза (без заготовки 0.6.4)"
cd "$IOS"

# строка каталога 0.6.4 временно уезжает из project.yml
python3 - <<'PY'
p = 'project.yml'
s = open(p).read()
mark = "      # То же и с каталогом марок"
i = s.index(mark)
j = s.index("buildPhase: resources", i) + len("buildPhase: resources\n")
open('.catalog-line.tmp', 'w').write(s[i:j])
open(p, 'w').write(s[:i] + s[j:])
PY

git add -A
for f in "${GARAGE_064[@]}"; do git reset -q -- "$f" 2>/dev/null || true; done
git commit -m "feat: public profile"
# Без -f: если тег вдруг уже есть, пусть скрипт упадёт, а не перепишет чужую метку.
git tag v0.6.3
git --no-pager log --oneline -1

# ─────────────────────────────────────────────────────────── iOS: заготовка
say "3/4  iOS — заготовка гаража отдельным коммитом ПОСЛЕ тега"
python3 - <<'PY'
p = 'project.yml'
s = open(p).read()
line = open('.catalog-line.tmp').read()
anchor = "      - path: TripTrack/Resources/MapRegions.json\n        buildPhase: resources\n"
assert anchor in s
open(p, 'w').write(s.replace(anchor, anchor + line, 1))
PY
rm -f .catalog-line.tmp
xcodegen generate >/dev/null
git add -A
git commit -m "chore: vehicle catalog"
git --no-pager log --oneline -3

say "4/4  Готово. Дальше — руками, строго в этом порядке:"
cat <<'EOS'

  а) Бэкенд первым — CI задеплоит сам:
       cd /Users/onezee/OneZeeProjects/trip-track-backend
       git push origin master

     Дождаться деплоя и проверить:
       curl -s https://api.trip-track.app/health

  б) Только потом iOS:
       cd /Users/onezee/OneZeeProjects/trip-track
       git push -u origin release/0.6.3 && git push origin v0.6.3

  в) Xcode: Product → Archive (схема TripTrack, конфигурация Release,
     устройство «Any iOS Device»), затем Distribute App → App Store Connect.
     Версия 0.6.3, билд 54 — уже проставлены в project.yml.

  г) App Store Connect: «What's New» во ВСЕ ДВЕНАДЦАТЬ локалей из
     docs/app-store-0.6.3.md. Пустое поле хотя бы в одной = отказ (урок 0.6.2).

  д) Перед сабмитом пройти чек-лист в docs/app-store-0.6.3.md, раздел 3 —
     особенно пункт 6: открыть чужую карту, вернуться на свою, убедиться,
     что свой туман на месте. Это главный риск релиза.

EOS
