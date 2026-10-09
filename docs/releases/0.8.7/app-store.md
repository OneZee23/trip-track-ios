# App Store Connect — 0.8.7 (76)

Подготовлено 9 октября 2026. Статус отправки будет указан после проверки ASC.
Ручной выпуск, существующие IAP и оценки. Сохранить 8 RU + 8 EN карточек и
прочие утверждённые наборы. 12 локалей; `fi` остаётся слотом Filipino.

## en-US

You can now help improve TripTrack with optional usage counters in Settings → Privacy. This is off by default and does not send routes, coordinates, photos or notes. Turning it off requests deletion of the counters.

## ru

Теперь можно помочь улучшить TripTrack: в настройках приватности появились добровольные счётчики использования. По умолчанию выключены. Маршруты, координаты, фото и заметки не отправляются; отключение запрашивает удаление счётчиков.

## de-DE

In den Datenschutzeinstellungen können Sie jetzt freiwillige Nutzungszähler aktivieren, um TripTrack zu verbessern. Standardmäßig deaktiviert. Routen, Koordinaten, Fotos und Notizen werden nicht gesendet. Beim Ausschalten wird die Löschung der Zähler angefordert.

## es-ES

Ahora puedes ayudar a mejorar TripTrack activando contadores de uso opcionales en Ajustes → Privacidad. Están desactivados por defecto y no envían rutas, coordenadas, fotos ni notas. Al desactivarlos, se solicita su eliminación.

## fr-FR

Vous pouvez aider à améliorer TripTrack avec des compteurs d’utilisation facultatifs dans Réglages → Confidentialité. Désactivés par défaut, ils n’envoient ni itinéraires, ni coordonnées, ni photos, ni notes. Les désactiver demande leur suppression.

## it

Puoi aiutare a migliorare TripTrack con contatori di utilizzo facoltativi in Impostazioni → Privacy. Sono disattivati per impostazione predefinita e non inviano percorsi, coordinate, foto o note. Disattivandoli, ne viene richiesta l’eliminazione.

## pl

Możesz pomóc ulepszać TripTrack, włączając opcjonalne liczniki użycia w Ustawienia → Prywatność. Domyślnie są wyłączone i nie wysyłają tras, współrzędnych, zdjęć ani notatek. Wyłączenie zleca usunięcie liczników.

## id

Kini Anda dapat membantu meningkatkan TripTrack dengan penghitung penggunaan opsional di Pengaturan → Privasi. Nonaktif secara default dan tidak mengirim rute, koordinat, foto, atau catatan. Menonaktifkannya meminta penghapusan penghitung.

## tr

Ayarlar → Gizlilik bölümündeki isteğe bağlı kullanım sayaçlarıyla TripTrack’in gelişmesine yardım edebilirsiniz. Varsayılan olarak kapalıdır; rota, koordinat, fotoğraf veya not göndermez. Kapatıldığında sayaçların silinmesi istenir.

## fi

Maaari ka nang tumulong na pagandahin ang TripTrack gamit ang opsyonal na mga bilang ng paggamit sa Settings → Privacy. Naka-off bilang default at hindi nagpapadala ng ruta, coordinate, larawan o tala. Ang pag-off ay humihiling ng pagbura ng mga bilang.

## uk

Тепер можна допомогти покращити TripTrack: у налаштуваннях приватності з’явилися добровільні лічильники використання. За замовчуванням вимкнені. Маршрути, координати, фото й нотатки не надсилаються; вимкнення запитує видалення лічильників.

## pt-BR

Agora você pode ajudar a melhorar o TripTrack com contadores de uso opcionais em Ajustes → Privacidade. Desativados por padrão, eles não enviam rotas, coordenadas, fotos ou notas. Ao desativá-los, a exclusão dos contadores é solicitada.

## Review Notes

TripTrack 0.8.7 (76) adds optional first-party usage counters to measure local recording success and Atlas use, including users who do not sign in or enable Cloud Sync. No new SDK, IAP, background mode or permission is introduced. The recording slider fix from 0.8.6 is retained.

HOW TO CHECK
1. Complete onboarding or skip optional permissions. No account is required.
2. Open Me → the settings gear → Privacy. "Help improve TripTrack" is OFF by default. Read the explanation and optionally turn it on.
3. Open Atlas. Recording starts and non-junk local saves are also counted if you choose to record a trip. Core recording and cloud-sync settings are independent of this choice.
4. Turn the option off. Collection stops immediately, local counters are cleared, and deletion of server counters is queued for the next connection. App functionality remains available.

DATA HANDLING
A random consent-period token (stored only as a SHA-256 hash on our server) groups cumulative counters and makes retries idempotent. Payloads contain counts of starts, successful local saves, save failures, Atlas screen appearances, save-speed buckets, whether the local library already contained trips, and UTC calendar days of consent, delivery and the first two saves since consent. No account ID, trip ID, advertising ID, route, coordinates, distance, notes, photos or vehicle details are included. The transport is separate from authenticated sync and works for guests. This is not advertising tracking. Inactive records and deletion markers expire after 90 days.

The privacy policies explain this optional processing. Existing App Privacy categories already include Device ID, Product Interaction and Performance Data for Analytics. Linked-to-user declarations for other existing app functions remain conservative; no existing category is removed.

The approved screenshot sets and existing PRO/tip products are unchanged. Local recording remains free and works without sign-in. Only location is enabled as a background mode. TripTrack does not request microphone access or record audio.
