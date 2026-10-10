# App Store — 0.8.9, черновик

Черновик, не загружен в App Store Connect. Пишется по тому, что УЖЕ есть
в ветке. Веб-редактор поездок здесь НЕ объявляется: он откроется флагом на
сервере только после сквозной проверки на устройстве, и обещать его в
описании версии раньше значило бы обещать то, чего у человека ещё нет.
Если к сборке редактор будет открыт — добавить один абзац, перевести на
все 12 локалей ASC (`fi` — это Filipino, не финский).

## ru

Поездки, добавленные на сайте, приходят на iPhone вписанными вручную: километры идут в статистику и пробег машины, но не в опыт и значки. Полный маршрут скачивается при первом открытии.

Если включена зона у дома, публичная поездка с сайта уходит на сервер только после того, как маршрут скачан и двор обрезан.

Точнее описали, что приложение делает с фото и геолокацией в фоне, и что запись начинается автоматически, только если включена автозапись.

## en-US

Trips added on the website arrive on your iPhone as hand-entered: the kilometres count towards your statistics and your car’s odometer, not towards XP or badges. The full route downloads the first time you open the trip.

With a home privacy zone on, a public trip from the website is sent to the server only after its route has been downloaded and your home trimmed.

Clearer wording about what happens to your photos and to background location, and about when recording starts automatically.

## Review Notes (черновик)

This update lets the app correctly import trips that a PRO subscriber added on our website (trip-track.app). Such trips are marked as hand-entered and never earn XP or badges. No new permission, SDK, background mode or in-app purchase. Permission descriptions were made more precise: the photo-library text now mentions that photos are uploaded when Cloud Sync is on, and the background-location text no longer promises that no part of a trip can be lost.
