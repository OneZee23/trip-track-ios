# App Store Connect — 0.6.1

Всё, что нужно вставить при выкладке билда **0.6.1 (52)**. Заметки для ревьюера —
отдельно, в [app-review-notes.md](app-review-notes.md), секция «current submission».

0.6.0 добавил функциональность — 0.6.1 добавляет **языки**: с двух до тринадцати. Это значит, что в
App Store Connect надо не просто вписать «What's New», а **завести одиннадцать новых
локализаций** приложения: German, Spanish (Spain), French, Italian, Polish,
Turkish, Indonesian, Ukrainian, Portuguese (Brazil), Kazakh, Filipino.
Каждая — это отдельная вкладка с названием, подзаголовком, описанием,
ключевыми словами и скриншотами.

Лимиты: «What's New» — 4000, промо-текст — 170, подзаголовок — 30, ключевые
слова — 100. Всё ниже в них укладывается.

---

## 1. Новые локализации приложения

В App Store Connect → App Information → Localizations добавить:

| Локаль | Название приложения | Подзаголовок (≤30) |
|---|---|---|
| German (DE) | TripTrack | Die Fahrt, erinnert |
| Spanish (Spain) | TripTrack | El viaje, recordado |
| French (FR) | TripTrack | Le trajet, gardé |
| Italian (IT) | TripTrack | Il viaggio, ricordato |
| Polish (PL) | TripTrack | Trasa, zapamiętana |
| Turkish | TripTrack | Yol, hatırlanan |
| Indonesian | TripTrack | Perjalanan yang diingat |
| Ukrainian | TripTrack | Щоденник ваших доріг |
| Portuguese (Brazil) | TripTrack | A viagem, lembrada |
| Kazakh | TripTrack | Жолдарыңыз есте қалады |
| Filipino | TripTrack | Ang biyahe, natatandaan |

Название везде остаётся **TripTrack** — оно и есть бренд, переводить нечего.

### Ключевые слова (≤100 символов, через запятую, без пробелов после запятой)

```
DE: fahrtenbuch,route,gps,tacho,kilometer,fahrtenschreiber,strecke,autofahrt,tagebuch,reise
```
```
ES: diario de viaje,ruta,gps,kilometros,velocidad,coche,carretera,viajes,trayecto,mapa
```
```
FR: carnet de route,trajet,gps,kilometres,vitesse,voiture,itineraire,journal,carte,route
```
```
IT: diario di viaggio,percorso,gps,chilometri,velocita,auto,strada,viaggi,mappa,tragitto
```
```
PL: dziennik tras,trasa,gps,kilometry,predkosc,samochod,droga,podroze,mapa,przejazd
```
```
TR: yol defteri,rota,gps,kilometre,hiz,araba,seyahat,gunluk,harita,gezi
```
```
ID: catatan perjalanan,rute,gps,kilometer,kecepatan,mobil,jalan,perjalanan,peta,otomotif
```
```
UK: щоденник доріг,маршрут,gps,кілометри,швидкість,авто,дорога,подорожі,карта,поїздка
```
```
PT: diario de viagem,rota,gps,quilometros,velocidade,carro,estrada,viagens,mapa,trajeto
```
```
KK: жол күнделігі,бағыт,gps,километр,жылдамдық,көлік,жол,саяхат,карта,сапар
```
```
FIL: talaarawan ng biyahe,ruta,gps,kilometro,bilis,kotse,kalsada,biyahe,mapa,drive
```

---

## 2. What's New

Одна тема на весь релиз, поэтому текст короткий. В каждую локализацию — свой.

### English
```
TripTrack now speaks eleven more languages. Thirteen in total: English,
Russian, German, Spanish, French, Italian, Polish, Turkish, Indonesian,
Ukrainian, Brazilian Portuguese, Kazakh and Filipino.

Everything is translated — screens, empty states, errors, notifications, all 53
achievements, and the card on your lock screen.

Pick yours in Settings → Language. On a fresh install the app follows your
phone's language list, so it usually picks the right one by itself.

Dates, numbers and units follow the language you chose, and counted words get
their plural right in every one of the thirteen — including the awkward ones.
```

### Русский
```
TripTrack заговорил ещё на одиннадцати языках. Тринадцать всего: русский,
английский, немецкий, испанский, французский, итальянский, польский, турецкий,
индонезийский, украинский, португальский, казахский и филиппинский.

Переведено всё — экраны, пустые состояния, ошибки, уведомления, 53 достижения
и карточка на экране блокировки.

Свой выбирается в «Настройки → Язык». На свежей установке приложение смотрит на
список языков телефона и обычно угадывает само.

Даты, числа и единицы следуют выбранному языку, а счётные слова склоняются
правильно во всех тринадцати — включая неудобные.
```

### Deutsch
```
TripTrack spricht jetzt elf Sprachen mehr — dreizehn insgesamt.

Übersetzt ist alles: Bildschirme, leere Zustände, Fehlermeldungen,
Mitteilungen, alle 53 Erfolge und die Karte auf dem Sperrbildschirm.

Deine wählst du unter Einstellungen → Sprache. Bei einer frischen Installation
richtet sich die App nach der Sprachliste deines iPhones.

Datum, Zahlen und Einheiten folgen der gewählten Sprache, und gezählte Wörter
stehen in allen dreizehn in der richtigen Form.
```

### Español
```
TripTrack ya habla once idiomas más: trece en total.

Está todo traducido: pantallas, estados vacíos, errores, notificaciones, los 53
logros y la tarjeta de la pantalla de bloqueo.

Elige el tuyo en Ajustes → Idioma. En una instalación nueva la app sigue la
lista de idiomas del teléfono.

Las fechas, los números y las unidades siguen el idioma elegido, y las palabras
contadas van en el plural correcto en los trece.
```

### Français
```
TripTrack parle maintenant onze langues de plus — treize au total.

Tout est traduit : écrans, états vides, erreurs, notifications, les 53 succès
et la carte de l'écran verrouillé.

Choisissez la vôtre dans Réglages → Langue. Sur une installation neuve, l'app
suit la liste de langues de votre iPhone.

Les dates, les nombres et les unités suivent la langue choisie, et les mots
comptés prennent le bon pluriel dans les treize.
```

### Italiano
```
TripTrack ora parla undici lingue in più: tredici in tutto.

È tradotto tutto: schermate, stati vuoti, errori, notifiche, tutti i 53
traguardi e la scheda sulla schermata di blocco.

Scegli la tua da Impostazioni → Lingua. Su un'installazione nuova l'app segue
l'elenco delle lingue del telefono.

Date, numeri e unità seguono la lingua scelta, e le parole contate prendono il
plurale giusto in tutte e tredici.
```

### Polski
```
TripTrack mówi teraz w jedenastu kolejnych językach — trzynaście łącznie.

Przetłumaczone jest wszystko: ekrany, stany puste, komunikaty błędów,
powiadomienia, wszystkie 53 osiągnięcia i karta na ekranie blokady.

Swój wybierzesz w Ustawieniach → Język. Przy świeżej instalacji aplikacja
patrzy na listę języków telefonu.

Daty, liczby i jednostki idą za wybranym językiem, a liczone słowa odmieniają
się poprawnie we wszystkich trzynastu.
```

### Türkçe
```
TripTrack artık on bir dil daha konuşuyor — toplam on üç.

Her şey çevrildi: ekranlar, boş durumlar, hatalar, bildirimler, 53 başarımın
tamamı ve kilit ekranındaki kart.

Kendi dilini Ayarlar → Dil'den seç. Yeni kurulumda uygulama telefonunun dil
listesine bakar.

Ve evet: büyük «i» artık her yerde İ olarak yazılıyor.
```

### Bahasa Indonesia
```
TripTrack kini bicara sebelas bahasa lagi — total tiga belas.

Semuanya diterjemahkan: layar, keadaan kosong, pesan galat, notifikasi, semua
53 pencapaian, dan kartu di layar kunci.

Pilih bahasamu di Pengaturan → Bahasa. Pada pemasangan baru, aplikasi mengikuti
daftar bahasa di ponselmu.
```

### Українська
```
TripTrack заговорив ще одинадцятьма мовами — тринадцять усього.

Перекладено все: екрани, порожні стани, помилки, сповіщення, усі 53 досягнення
і картка на екрані блокування.

Свою обирайте в «Налаштування → Мова». На свіжій установці застосунок дивиться
на список мов телефона.
```

### Português (Brasil)
```
O TripTrack agora fala mais onze idiomas — treze no total.

Está tudo traduzido: telas, estados vazios, erros, notificações, as 53
conquistas e o cartão da tela de bloqueio.

Escolha o seu em Ajustes → Idioma. Numa instalação nova, o app segue a lista de
idiomas do seu celular.
```

### Қазақша
```
TripTrack енді тағы он бір тілде сөйлейді — барлығы он үш.

Бәрі аударылды: экрандар, бос күйлер, қателер, хабарламалар, 53 жетістіктің
барлығы және құлыптау экранындағы карточка.

Өз тіліңізді «Параметрлер → Тіл» бөлімінен таңдаңыз. Жаңа орнатуда қолданба
телефонның тіл тізіміне қарайды.
```

### Filipino
```
Nagsasalita na ang TripTrack ng labing-isa pang wika — labintatlo lahat.

Isinalin ang lahat: mga screen, walang laman na estado, error, abiso, lahat ng
53 tagumpay, at ang card sa lock screen.

Piliin ang sa iyo sa Settings → Wika. Sa bagong install, sinusunod ng app ang
listahan ng wika sa telepono mo.
```

---

## 3. Описание (Description) для новых локалей

EN и RU остаются как в [app-store-0.6.0.md](app-store-0.6.0.md) — приложение с
0.6.0 не изменилось, изменился только его язык.

### Deutsch
```
TripTrack ist ein Tagebuch deiner Fahrten. Aufnahme starten, fahren, stoppen —
die App benennt die Fahrt nach den Orten, behält Route, Tempo und Höhenmeter und
legt sie in einen Feed, den du noch in einem Jahr öffnen kannst.

AUFNEHMEN, OHNE DARAN ZU DENKEN
Die Aufnahme übersteht einen gesperrten Bildschirm, ein Funkloch und einen
langen Tag. Die Live Activity hält die Fahrt auf dem Sperrbildschirm, und die
App kann von selbst starten, sobald du losfährst.

DIE FAHRT, DANACH
Sieh die Fahrt wie einen kleinen Film noch einmal. Die Route auf der Karte,
Tempo und Höhe auf Diagrammen zum Durchziehen, dazu die Fotos von unterwegs.

DIE, DIE DABEI WAREN
Lade die Mitfahrenden ein — die Fahrt wird gemeinsam, ihre Fotos landen darin,
und sie taucht auch in ihrer Historie auf. Veröffentlichte Fahrten kommen in den
Feed, wo sie Reaktionen und eine Diskussion bekommen.

DEINE KARTE
Jede Straße, die du gefahren bist, auf einer Karte — mit deinen Regionen und
deinen Zahlen dahinter.

GARAGE
Mehrere Fahrzeuge, jedes mit eigener Laufleistung, eigenem Level und eigener
Geschichte.

ZUERST DEINS
Alles funktioniert offline und ohne Account. Melde dich mit Apple an, nur wenn
du Cloud-Synchronisierung und die soziale Seite willst; deine Fahrten bleiben
privat, bis du sie selbst veröffentlichst, und der Account lässt sich jederzeit
in der App löschen.
```

### Español
```
TripTrack es un diario de tus viajes en coche. Dale a grabar, conduce, para: la
app pone nombre al viaje según por dónde fuiste, guarda la ruta, la velocidad y
el desnivel, y lo deja en un feed que podrás abrir dentro de un año.

GRABAR SIN PENSAR
La grabación aguanta la pantalla bloqueada, una zona sin cobertura y un día
largo. La Live Activity mantiene el viaje en la pantalla de bloqueo, y la app
puede empezar sola en cuanto te pones en marcha.

EL VIAJE, DESPUÉS
Revívelo como una pequeña película. La ruta en el mapa, la velocidad y la
altitud en gráficos que puedes recorrer, y las fotos que hiciste por el camino.

LOS QUE IBAN CONTIGO
Invita a tus acompañantes: el viaje pasa a ser común, sus fotos aparecen en él y
también se guarda en su historial. Un viaje publicado entra en el feed, donde
recibe reacciones y conversación.

TU MAPA
Todas las carreteras que has hecho, en un solo mapa, con tus regiones y tus
números detrás.

GARAJE
Varios vehículos, cada uno con su kilometraje, su nivel y su historia.

PRIMERO, LO TUYO
Todo funciona sin conexión y sin cuenta. Inicia sesión con Apple solo si quieres
sincronización en la nube y la parte social; tus viajes son privados hasta que
tú los publiques, y la cuenta se puede eliminar desde dentro de la app cuando
quieras.
```

### Français
```
TripTrack est un journal de vos trajets. Lancez l'enregistrement, roulez,
arrêtez : l'app nomme le trajet d'après les lieux traversés, garde l'itinéraire,
la vitesse et le dénivelé, et le range dans un fil que vous pourrez rouvrir dans
un an.

ENREGISTRER SANS Y PENSER
L'enregistrement survit à un écran verrouillé, à une zone blanche et à une
longue journée. La Live Activity garde le trajet sur l'écran verrouillé, et
l'app peut démarrer d'elle-même dès que vous roulez.

LE TRAJET, APRÈS
Revivez-le comme un petit film. L'itinéraire sur la carte, la vitesse et
l'altitude sur des courbes que l'on parcourt du doigt, et les photos prises en
chemin.

CEUX QUI ÉTAIENT LÀ
Invitez vos compagnons de route : le trajet devient commun, leurs photos s'y
ajoutent, et il apparaît aussi dans leur historique. Un trajet publié rejoint le
fil, où il récolte des réactions et une discussion.

VOTRE CARTE
Toutes les routes que vous avez parcourues, sur une seule carte, avec vos
régions et vos chiffres derrière.

GARAGE
Plusieurs véhicules, chacun avec son kilométrage, son niveau et son histoire.

LE VÔTRE D'ABORD
Tout fonctionne hors ligne et sans compte. Connectez-vous avec Apple uniquement
si vous voulez la synchronisation cloud et le côté social ; vos trajets restent
privés tant que vous ne les publiez pas vous-même, et le compte se supprime
depuis l'app à tout moment.
```

### Italiano
```
TripTrack è un diario dei tuoi viaggi in auto. Avvia la registrazione, guida,
fermati: l'app dà un nome al viaggio in base ai posti attraversati, conserva
percorso, velocità e dislivello e lo mette in un feed che potrai riaprire fra un
anno.

REGISTRARE SENZA PENSARCI
La registrazione sopravvive allo schermo bloccato, a una zona senza campo e a
una giornata lunga. La Live Activity tiene il viaggio sulla schermata di blocco,
e l'app può partire da sola appena ti metti in marcia.

IL VIAGGIO, DOPO
Rivivilo come un piccolo film. Il percorso sulla mappa, velocità e quota su
grafici che scorri con il dito, e le foto scattate lungo la strada.

CHI ERA CON TE
Invita i compagni di viaggio: il viaggio diventa comune, le loro foto ci
finiscono dentro e compare anche nella loro cronologia. Un viaggio pubblicato
entra nel feed, dove raccoglie reazioni e discussione.

LA TUA MAPPA
Tutte le strade che hai percorso su un'unica mappa, con le tue regioni e i tuoi
numeri dietro.

GARAGE
Più veicoli, ognuno con il suo chilometraggio, il suo livello e la sua storia.

PRIMA IL TUO
Funziona tutto offline e senza account. Accedi con Apple solo se vuoi la
sincronizzazione cloud e la parte social; i tuoi viaggi restano privati finché
non li pubblichi tu, e l'account si può eliminare dall'app in qualsiasi momento.
```

### Polski
```
TripTrack to dziennik Twoich tras. Włączasz nagrywanie, jedziesz, zatrzymujesz
się — aplikacja nazywa trasę po miejscach, zapisuje przebieg, prędkość i sumę
podjazdów i odkłada ją na tablicę, którą otworzysz jeszcze za rok.

NAGRYWANIE, O KTÓRYM SIĘ NIE MYŚLI
Nagrywanie przetrwa zgaszony ekran, brak zasięgu i długi dzień. Live Activity
trzyma trasę na ekranie blokady, a aplikacja potrafi ruszyć sama, gdy tylko
pojedziesz.

TRASA — POTEM
Obejrzyj ją jeszcze raz jak mały film. Przebieg na mapie, prędkość i wysokość na
wykresach, po których przesuwasz palcem, i zdjęcia zrobione po drodze.

CI, KTÓRZY BYLI OBOK
Zaproś pasażerów — trasa staje się wspólna, ich zdjęcia trafiają do środka, a
ona sama pojawia się też w ich historii. Opublikowana trasa idzie na tablicę,
gdzie zbiera reakcje i dyskusję.

TWOJA MAPA
Wszystkie przejechane drogi na jednej mapie — z Twoimi regionami i Twoimi
liczbami za nimi.

GARAŻ
Kilka pojazdów, każdy z własnym przebiegiem, poziomem i historią.

NAJPIERW TWOJE
Wszystko działa offline i bez konta. Zaloguj się przez Apple tylko wtedy, gdy
chcesz synchronizację w chmurze i część społecznościową; trasy są prywatne,
dopóki sam ich nie opublikujesz, a konto usuniesz z poziomu aplikacji w każdej
chwili.
```
### Описания для турецкого, индонезийского, украинского, португальского, казахского и филиппинского
Ещё не написаны. Структура та же — шесть блоков: запись, поездка потом,
попутчики, карта, гараж, приватность. Можно взять английский или немецкий выше
как образец. Если этих локалей нет описания, Apple покажет английское —
заявку это не завернёт.


---

## 4. Promotional text (≤170)

```
DE: Fahrt aufzeichnen, wie einen Film noch einmal ansehen und mit allen teilen, die im Auto saßen. Deine Straßen, erinnert.
```
```
ES: Graba el viaje, revívelo como una película y compártelo con quien iba contigo. Tus carreteras, recordadas.
```
```
FR: Enregistrez le trajet, revivez-le comme un film et partagez-le avec ceux qui étaient là. Vos routes, gardées.
```
```
IT: Registra il viaggio, rivivilo come un film e condividilo con chi era in auto con te. Le tue strade, ricordate.
```
```
PL: Nagraj trasę, obejrzyj ją jak film i podziel się z tymi, którzy jechali z Tobą. Twoje drogi, zapamiętane.
```
```
TR: Yolu kaydet, film gibi yeniden izle ve arabada seninle olanlarla paylaş. Yolların, hatırlanan.
```
```
ID: Rekam perjalanannya, tonton lagi seperti film, dan bagikan ke yang ikut bersamamu. Jalanmu, diingat.
```
```
UK: Запишіть дорогу, перегляньте її як кіно і розділіть із тими, хто їхав поруч. Ваші маршрути — запам'ятані.
```
```
PT: Grave o trajeto, reveja como um filme e compartilhe com quem estava no carro. Suas estradas, lembradas.
```
```
KK: Жолды жазып алыңыз, оны кино сияқты қайта көріңіз және қасыңызда жүргендермен бөлісіңіз.
```
```
FIL: I-record ang biyahe, panoorin ulit na parang pelikula, at ibahagi sa mga kasama mo. Ang mga daan mo, natatandaan.
```

---

## 5. Что проверить перед отправкой

1. Билд **0.6.1 (52)**. Бэкенд и сайт менять не нужно — релиз клиентский.
2. Одиннадцать локализаций заведены (DE / ES-ES / FR / IT / PL / TR / ID / UK /
   PT-BR / KK / FIL) и в каждой заполнены подзаголовок, ключевые слова,
   «What's New» и промо-текст. Описание — там, где написано (см. §3).
3. **Скриншоты для новых локалей.** Если их не загрузить, Apple покажет
   английские — заявку это не завернёт, но выглядит как недоделка. Снимать на
   том же устройстве, переключив язык в «Настройки → Язык».
4. На телефоне пройти по одному экрану каждого языка: Лента → Карта → Запись →
   Группы → Я. Ищем обрезанные надписи: немецкий, польский, турецкий и
   филиппинский длиннее русского, и кнопки в один ряд — первое, что ломается.
5. **Турецкий — глазами.** Пройти по заголовкам секций капсом и убедиться, что
   «BURADAKİ GEZİLER» пишется с точкой над İ. Это то, что чинилось в релизе, и
   проверяется только глазами.
6. Проверить экран блокировки (Live Activity) хотя бы на одном новом языке.
6. Демо-аккаунт в App Review Information всё ещё указан.
