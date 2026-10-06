# App Store Connect — 0.8.5

Пакет для **0.8.5 (74)** от 6 октября 2026: компактная Live Activity,
читаемый текст в теме принимающего экрана и счётчик похожих поездок по
сохранённой истории. Публичная версия — 0.8.4 (73). Подготовка этих текстов
не подтверждает сборку, загрузку или отправку 74; результаты фиксируются
в [candidate-74.md](candidate-74.md). После одобрения — ручной выпуск.

Меняются What's New и Review Notes. Описание, ключевые слова, цены,
продукты PRO и чаевые сохраняются. Запись и остальные бесплатные функции
остаются бесплатными. Новых товаров на ревью нет.

В App Store Connect сохраняются прежние **12 локалей**. Как в
[0.8.4](../0.8.4/app-store.md), слот **Finnish (`fi`) содержит Filipino**;
его не переименовываем. Казахской локали ASC нет. Это отличается от
13 языков приложения, в которых обновлена подпись счётчика.

## What's New по локалям

### English (U.S.)

```text
Live Activity now has a compact recording summary with readable text in both light and dark appearance.

The similar-trip count now uses your saved history, including trips restored from the cloud.

Recording, the atlas and statistics remain free. PRO is unchanged.
```

### Russian

```text
В Live Activity появилась компактная сводка записи с читаемым текстом в светлой и тёмной теме.

Счётчик похожих поездок теперь учитывает сохранённую историю, включая поездки, восстановленные из облака.

Запись, атлас и статистика остаются бесплатными. PRO без изменений.
```

### German

```text
Die Live-Aktivität zeigt jetzt eine kompakte Übersicht der Aufzeichnung mit gut lesbarem Text im hellen und dunklen Modus.

Ähnliche Fahrten werden jetzt anhand deines gespeicherten Verlaufs gezählt, einschließlich der aus der Cloud wiederhergestellten Fahrten.

Aufzeichnung, Atlas und Statistiken bleiben kostenlos. PRO bleibt unverändert.
```

### Spanish (Spain)

```text
La actividad en directo ahora muestra un resumen compacto de la grabación, con texto legible tanto en modo claro como oscuro.

El contador de viajes similares ahora utiliza tu historial guardado, incluidos los viajes recuperados de la nube.

La grabación, el atlas y las estadísticas siguen siendo gratis. PRO no cambia.
```

### French

```text
L’activité en direct affiche désormais un résumé compact de l’enregistrement, avec un texte lisible en mode clair comme en mode sombre.

Le compteur de trajets similaires s’appuie désormais sur votre historique enregistré, y compris les trajets restaurés depuis le cloud.

L’enregistrement, l’atlas et les statistiques restent gratuits. PRO ne change pas.
```

### Italian

```text
L’attività in tempo reale ora mostra un riepilogo compatto della registrazione, con testo leggibile sia in modalità chiara che scura.

Il conteggio dei viaggi simili ora usa la cronologia salvata, inclusi i viaggi ripristinati dal cloud.

La registrazione, l’atlante e le statistiche restano gratuiti. PRO non cambia.
```

### Polish

```text
Aktywność na żywo pokazuje teraz zwięzłe podsumowanie nagrywania z czytelnym tekstem w jasnym i ciemnym trybie.

Licznik podobnych przejazdów korzysta teraz z zapisanej historii, także z przejazdów przywróconych z chmury.

Nagrywanie, atlas i statystyki pozostają bezpłatne. PRO bez zmian.
```

### Indonesian

```text
Live Activity kini menampilkan ringkasan perekaman yang ringkas, dengan teks yang mudah dibaca dalam mode terang maupun gelap.

Jumlah perjalanan serupa kini dihitung dari riwayat tersimpan, termasuk perjalanan yang dipulihkan dari cloud.

Perekaman, atlas, dan statistik tetap gratis. PRO tidak berubah.
```

### Turkish

```text
Canlı Etkinlik artık açık ve koyu modda okunaklı metinlerle kompakt bir kayıt özeti gösteriyor.

Benzer yolculuk sayısı artık buluttan geri yüklenen yolculuklar da dahil olmak üzere kayıtlı geçmişinize göre hesaplanıyor.

Kayıt, atlas ve istatistikler ücretsiz kalıyor. PRO değişmedi.
```

### Finnish — слот Filipino

```text
May maikling buod na ng pagrekord ang Live Activity, na may tekstong madaling basahin sa light at dark mode.

Ang bilang ng magkakatulad na biyahe ay batay na sa naka-save mong history, kasama ang mga biyaheng naibalik mula sa cloud.

Libre pa rin ang pagrekord, atlas, at mga istatistika. Walang pagbabago sa PRO.
```

### Ukrainian

```text
У Live Activity з’явився компактний підсумок запису з читабельним текстом у світлій і темній темі.

Лічильник схожих поїздок тепер враховує збережену історію, зокрема поїздки, відновлені з хмари.

Запис, атлас і статистика залишаються безкоштовними. PRO без змін.
```

### Portuguese (Brazil)

```text
A Atividade ao Vivo agora mostra um resumo compacto da gravação, com texto legível nos modos claro e escuro.

A contagem de viagens semelhantes agora usa o histórico salvo, incluindo viagens restauradas da nuvem.

A gravação, o atlas e as estatísticas continuam gratuitos. O PRO não mudou.
```

## Review Notes — English

Текст для поля App Review Information → Notes. Указать сборку 74 только
после проверки выбранного билда в App Store Connect.

```text
TripTrack 0.8.5 (74) fixes the recording Live Activity and the similar-trip count shown after a trip. Recording, the atlas, places, journeys, photos and statistics remain free. PRO subscriptions and tips are unchanged; no previously free feature became paid. No new in-app purchase products are included in this submission.

LIVE ACTIVITY
The compact presentation now shows recording status, elapsed time and distance. Text follows the appearance of the screen displaying the activity instead of the map theme selected on the phone. The regular iPhone presentation retains its pause/resume, finish and checkpoint actions.
This is a system-hosted Live Activity update, not a separate CarPlay app. It does not add or require a CarPlay app entitlement.

SIMILAR TRIPS
After finishing a recorded trip, the similar-trip count uses saved trip history, including synced route previews. The current trip is never counted twice. Similarity is approximate; it does not claim to count drives that were never recorded. Manually added, unconfirmed, unfinished and very short trips are excluded, as are trips with known recording gaps. Synced previews do not preserve every point-level gap or interpolation marker. XP, levels and road-collection totals are not recalculated. The count label is updated in all 13 app languages.

HOW TO CHECK
1. Start recording, lock the iPhone and view the Live Activity in light and dark appearance. Check pause/resume and finish on the iPhone Lock Screen. Where the system offers a compact Live Activity, it shows the summary rather than phone-sized controls.
2. Finish a recorded trip and check the similar-trip count against the saved history, including previously synced trips.

No special app account is required for local recording. Sign in with Apple is available for sync. No new permissions or background modes are requested. The permission flow approved in 0.8.4 is retained: users can deny access in the iOS dialogs, and denial is respected. The only background mode remains location for trip recording. TripTrack does not request microphone access or record audio.

Manual release is selected after approval.
```
