# App Store Connect — 0.6.6

Всё, что нужно вставить при выкладке билда **0.6.6 (58)**. Заметки для ревьюера —
в [app-review-notes.md](../app-review-notes.md), секция «current submission».

**«What's New» обязателен в КАЖДОЙ локализации карточки.** Сабмит 0.6.2
отклонили ровно за одну пропущенную. Ниже тринадцать блоков — по числу языков
приложения; в файле 0.6.5 в этой строке стояло «двенадцать», а блоков было
тринадцать, так что считать надо по блокам, а не по слову.

Релиз **не чисто клиентский**: бэкенд деплоится первым — миграция `AddJourneys`,
таблица `journey`, секция `journeys` в `/sync/pull`. Порядок безопасен в обе
стороны (старый сервер молча игнорирует новые вызовы, клиент без них не падает),
но путешествие не доедет до второго телефона, пока сервер не выкачен.

Ключевые слова, подзаголовок и описание не меняются. Лимиты: «What's New» — 4000,
промо-текст — 170.

---

## 1. What's New

### English (U.S.)

```
ONE STORY, NOT FOUR RECORDINGS

Krasnodar → Vladikavkaz → Tbilisi and back is four recordings and one story.
Now they hold together: open a trip, tap "Combine into a journey" and pick
which of the neighbouring drives belong to it. Or press and hold a card in
"Mine" and choose them by hand.

THE JOURNEY SCREEN

One map with every leg on it, and the checkpoints of each leg still in place.
Below it the total — days, kilometres, drives, time on the road — and then the
road day by day: legs with their checkpoints and photos, with the local drives
around your destination folded into a single line.

IN "MINE" — ONE CARD

The legs stop crowding the list: they tuck under one journey card carrying the
map of the whole route. Everywhere else they stay exactly where they were.

IT NOTICES BY ITSELF

Slept somewhere other than home and drove back? The app offers to combine those
drives. A night away is what makes a journey — not distance — so a long daily
commute never counts. Home is worked out on the phone from your own trips and
asked about once: "Is this your home?"

NOTHING IS COPIED

A journey is a window of dates over trips you already have. Delete it and every
trip stays exactly where it was.
```

### Russian

```
ОДНА ИСТОРИЯ, А НЕ ЧЕТЫРЕ ЗАПИСИ

Краснодар → Владикавказ → Тбилиси и обратно — четыре записи и одна история.
Теперь они держатся вместе: откройте поездку, нажмите «Объединить в
путешествие» и отметьте, какие из соседних поездок в него входят. Или
задержите палец на карточке в «Моих» и выберите их руками.

ЭКРАН ПУТЕШЕСТВИЯ

Одна карта со всеми плечами, и отметки каждого плеча на своих местах. Под ней
итог — дни, километры, поездки, время в пути, — а дальше дорога по дням: плечи
со своими отметками и снимками, а поездки по городу назначения свёрнуты в одну
строку.

В «МОИХ» — ОДНА КАРТОЧКА

Плечи больше не забивают список: они убираются под одну карточку путешествия с
картой всего маршрута. Везде остальном они остаются там же, где были.

ЗАМЕЧАЕТ САМО

Ночевали не дома и вернулись? Приложение предложит объединить эти поездки.
Путешествие делает ночь не дома, а не расстояние, поэтому долгая дорога на
работу путешествием не станет никогда. Дом вычисляется на телефоне по вашим же
поездкам и спрашивается один раз: «Это твой дом?».

НИЧЕГО НЕ КОПИРУЕТСЯ

Путешествие — это окно дат поверх уже записанных поездок. Удалите его — каждая
поездка останется на своём месте.
```

### German

```
EINE GESCHICHTE STATT VIER AUFZEICHNUNGEN

Krasnodar → Wladikawkas → Tiflis und zurück: vier Aufzeichnungen, eine
Geschichte. Jetzt halten sie zusammen — Fahrt öffnen, „Zu einer Reise
zusammenfassen“ tippen und auswählen, welche der benachbarten Fahrten dazu
gehören. Oder in „Meine“ eine Karte gedrückt halten und von Hand wählen.

DER REISE-BILDSCHIRM

Eine Karte mit allen Etappen, die Markierungen jeder Etappe bleiben darauf.
Darunter die Summe — Tage, Kilometer, Fahrten, Zeit unterwegs — und dann die
Strecke Tag für Tag: Etappen mit ihren Markierungen und Fotos, die Fahrten vor
Ort am Ziel zu einer Zeile zusammengelegt.

IN „MEINE“ — EINE KARTE

Die Etappen verstopfen die Liste nicht mehr: Sie liegen unter einer einzigen
Reisekarte mit der Karte der ganzen Strecke. Überall sonst bleibt alles, wie es war.

SIE MERKT ES SELBST

Woanders übernachtet und zurückgefahren? Die App schlägt vor, diese Fahrten
zusammenzufassen. Eine Reise macht die Nacht außer Haus, nicht die Entfernung —
ein langer täglicher Arbeitsweg zählt nie. Das Zuhause wird auf dem Gerät aus
deinen eigenen Fahrten ermittelt und einmal erfragt: „Ist das dein Zuhause?“

NICHTS WIRD KOPIERT

Eine Reise ist ein Zeitfenster über bereits vorhandene Fahrten. Löschst du sie,
bleibt jede Fahrt an ihrem Platz.
```

### Spanish (Spain)

```
UNA HISTORIA, NO CUATRO GRABACIONES

Krasnodar → Vladikavkaz → Tbilisi y vuelta son cuatro grabaciones y una sola
historia. Ahora se mantienen juntas: abre un trayecto, toca «Combinar en un
viaje» y marca cuáles de los trayectos vecinos entran. O mantén pulsada una
tarjeta en «Míos» y elígelos a mano.

LA PANTALLA DEL VIAJE

Un mapa con todos los tramos y las marcas de cada uno en su sitio. Debajo, el
total —días, kilómetros, trayectos, tiempo en marcha— y luego el camino día a
día: tramos con sus marcas y fotos, con los trayectos por la ciudad de destino
plegados en una sola línea.

EN «MÍOS», UNA TARJETA

Los tramos dejan de llenar la lista: se recogen bajo una única tarjeta con el
mapa de todo el recorrido. En el resto de la app siguen donde estaban.

SE DA CUENTA SOLO

¿Dormiste fuera de casa y volviste? La app propone combinar esos trayectos. Lo
que hace un viaje es una noche fuera, no la distancia, así que un trayecto
diario largo nunca cuenta. La casa se deduce en el teléfono a partir de tus
propios trayectos y se pregunta una vez: «¿Esta es tu casa?».

NO SE COPIA NADA

Un viaje es una ventana de fechas sobre trayectos que ya tienes. Si lo borras,
cada uno sigue en su sitio.
```

### French

```
UNE HISTOIRE, PAS QUATRE ENREGISTREMENTS

Krasnodar → Vladikavkaz → Tbilissi et retour : quatre enregistrements, une
seule histoire. Ils tiennent désormais ensemble — ouvrez un trajet, touchez
« Regrouper en un voyage » et choisissez les trajets voisins qui en font
partie. Ou appuyez longuement sur une carte dans « Mes trajets » et
sélectionnez-les à la main.

L'ÉCRAN DU VOYAGE

Une carte avec toutes les étapes, les repères de chaque étape restent en place.
En dessous, le total — jours, kilomètres, trajets, temps de route — puis la
route jour après jour : les étapes avec leurs repères et leurs photos, les
trajets locaux à destination repliés en une seule ligne.

DANS « MES TRAJETS » : UNE CARTE

Les étapes n'encombrent plus la liste : elles se rangent sous une seule carte
de voyage portant la carte de tout l'itinéraire. Partout ailleurs, rien ne bouge.

IL LE REMARQUE TOUT SEUL

Vous avez dormi ailleurs qu'à la maison, puis vous êtes rentré ? L'app propose
de regrouper ces trajets. Ce qui fait un voyage, c'est une nuit hors de chez
soi, pas la distance : un long trajet quotidien ne comptera jamais. Le domicile
est déduit sur le téléphone à partir de vos propres trajets et demandé une
seule fois : « C'est chez toi ? »

RIEN N'EST COPIÉ

Un voyage est une fenêtre de dates posée sur des trajets déjà enregistrés.
Supprimez-le : chaque trajet reste à sa place.
```

### Italian

```
UNA STORIA, NON QUATTRO REGISTRAZIONI

Krasnodar → Vladikavkaz → Tbilisi e ritorno: quattro registrazioni e una sola
storia. Ora stanno insieme — apri un viaggio, tocca «Unisci in un viaggio» e
scegli quali dei viaggi vicini ne fanno parte. Oppure tieni premuta una scheda
in «I miei» e selezionali a mano.

LA SCHERMATA DEL VIAGGIO

Una mappa con tutte le tratte, e i punti di ogni tratta restano al loro posto.
Sotto il totale — giorni, chilometri, viaggi, tempo in marcia — e poi la strada
giorno per giorno: tratte con i loro punti e le foto, con gli spostamenti in
loco a destinazione raccolti in una sola riga.

IN «I MIEI» UNA SOLA SCHEDA

Le tratte non intasano più l'elenco: finiscono sotto un'unica scheda con la
mappa dell'intero percorso. Altrove restano esattamente dov'erano.

SE NE ACCORGE DA SOLO

Hai dormito fuori casa e sei tornato? L'app propone di unire quei viaggi. È la
notte fuori a fare il viaggio, non la distanza: un lungo tragitto quotidiano
non conta mai. Casa viene dedotta sul telefono dai tuoi stessi viaggi e chiesta
una volta sola: «Questa è casa tua?».

NON SI COPIA NULLA

Un viaggio è una finestra di date sopra viaggi già registrati. Cancellalo e
ognuno resta al suo posto.
```

### Polish

```
JEDNA HISTORIA, A NIE CZTERY NAGRANIA

Krasnodar → Władykaukaz → Tbilisi i z powrotem to cztery nagrania i jedna
historia. Teraz trzymają się razem: otwórz przejazd, dotknij „Połącz w podróż”
i zaznacz, które z sąsiednich przejazdów do niej należą. Albo przytrzymaj
kartę w „Moje” i wybierz je ręcznie.

EKRAN PODRÓŻY

Jedna mapa ze wszystkimi odcinkami, znaczniki każdego odcinka zostają na
swoich miejscach. Pod nią podsumowanie — dni, kilometry, przejazdy, czas w
drodze — a dalej droga dzień po dniu: odcinki ze swoimi znacznikami i
zdjęciami, a jazdy po mieście docelowym zwinięte w jedną linijkę.

W „MOJE” JEDNA KARTA

Odcinki przestają zaśmiecać listę: chowają się pod jedną kartą podróży z mapą
całej trasy. Wszędzie indziej zostają tam, gdzie były.

ZAUWAŻA SAMA

Nocleg poza domem i powrót? Aplikacja zaproponuje połączenie tych przejazdów.
Podróż robi noc poza domem, a nie odległość — długi codzienny dojazd nigdy się
nie liczy. Dom jest wyliczany na telefonie z twoich własnych przejazdów i
pytany raz: „Czy to twój dom?”.

NIC NIE JEST KOPIOWANE

Podróż to okno dat nad już nagranymi przejazdami. Usuń ją, a każdy przejazd
zostanie na swoim miejscu.
```

### Indonesian

```
SATU CERITA, BUKAN EMPAT REKAMAN

Krasnodar → Vladikavkaz → Tbilisi dan kembali: empat rekaman, satu cerita.
Kini mereka menyatu — buka satu perjalanan, ketuk «Gabungkan menjadi
perjalanan», lalu pilih perjalanan tetangga mana yang termasuk. Atau tekan
lama sebuah kartu di «Milikku» dan pilih sendiri.

LAYAR PERJALANAN

Satu peta dengan semua ruas, dan penanda tiap ruas tetap di tempatnya. Di
bawahnya total — hari, kilometer, jumlah perjalanan, waktu di jalan — lalu
jalannya hari demi hari: ruas dengan penanda dan fotonya, sedangkan perjalanan
di sekitar kota tujuan dilipat menjadi satu baris.

DI «MILIKKU» — SATU KARTU

Ruas tidak lagi memenuhi daftar: semuanya masuk ke satu kartu perjalanan
dengan peta seluruh rute. Di tempat lain semuanya tetap seperti semula.

MENYADARI SENDIRI

Menginap di luar rumah lalu pulang? Aplikasi menawarkan untuk menggabungkan
perjalanan itu. Yang membuat sebuah perjalanan adalah malam di luar rumah,
bukan jaraknya — perjalanan harian yang jauh tidak pernah dihitung. Rumah
disimpulkan di ponsel dari perjalananmu sendiri dan ditanyakan sekali:
«Ini rumahmu?».

TIDAK ADA YANG DISALIN

Perjalanan adalah jendela tanggal di atas perjalanan yang sudah ada. Hapus, dan
setiap perjalanan tetap di tempatnya.
```

### Turkish

```
DÖRT KAYIT DEĞİL, TEK BİR HİKÂYE

Krasnodar → Vladikavkaz → Tiflis ve dönüş: dört kayıt, tek hikâye. Artık bir
arada duruyorlar — bir yolculuğu aç, «Yolculukta birleştir»e dokun ve komşu
sürüşlerden hangilerinin dâhil olduğunu seç. Ya da «Benimkiler»de bir karta
uzun bas ve elle seç.

YOLCULUK EKRANI

Tüm etaplarıyla tek bir harita; her etabın işaretleri yerinde kalır. Altında
toplam — gün, kilometre, sürüş sayısı, yolda geçen süre — ve ardından gün gün
yol: işaretleri ve fotoğraflarıyla etaplar, varış şehrindeki kısa sürüşler ise
tek satıra katlanmış.

«BENİMKİLER»DE TEK KART

Etaplar listeyi doldurmuyor: hepsi, tüm rotanın haritasını taşıyan tek bir
yolculuk kartının altına giriyor. Diğer her yerde oldukları gibi kalıyorlar.

KENDİ FARK EDER

Ev dışında uyuyup geri döndün mü? Uygulama o sürüşleri birleştirmeyi önerir.
Yolculuğu yapan, mesafe değil, evden uzakta geçen gecedir — uzun bir günlük işe
gidiş geliş asla sayılmaz. Ev, kendi yolculuklarından telefonda çıkarılır ve
bir kez sorulur: «Burası evin mi?».

HİÇBİR ŞEY KOPYALANMAZ

Yolculuk, hâlihazırdaki sürüşlerin üzerine konmuş bir tarih penceresidir. Onu
silersen her sürüş yerinde kalır.
```

### Filipino

```
ISANG KUWENTO, HINDI APAT NA RECORDING

Krasnodar → Vladikavkaz → Tbilisi at pabalik: apat na recording, isang
kuwento. Magkasama na sila ngayon — buksan ang isang biyahe, i-tap ang
«Pagsamahin sa isang paglalakbay» at piliin kung alin sa mga katabing biyahe
ang kasama. O pindutin nang matagal ang isang card sa «Akin» at piliin sila
nang mano-mano.

ANG SCREEN NG PAGLALAKBAY

Isang mapa na may lahat ng bahagi, at nananatili ang mga marka ng bawat isa.
Sa ilalim ang kabuuan — araw, kilometro, biyahe, oras sa daan — at pagkatapos
ang daan araw-araw: mga bahagi kasama ang kanilang mga marka at larawan, habang
ang mga maiikling biyahe sa destinasyon ay tiniklop sa isang linya.

SA «AKIN» — ISANG CARD

Hindi na sumisikip ang listahan: pumapasok ang mga bahagi sa iisang card ng
paglalakbay na may mapa ng buong ruta. Sa ibang lugar, nananatili sila kung
saan sila dati.

NAPAPANSIN NIYA MAG-ISA

Natulog sa labas ng bahay at umuwi? Ipapanukala ng app na pagsamahin ang mga
biyaheng iyon. Ang gumagawa ng paglalakbay ay gabing wala ka sa bahay, hindi
ang layo — kaya hindi kailanman mabibilang ang mahabang araw-araw na biyahe sa
trabaho. Ang tahanan ay hinihinuha sa telepono mula sa sarili mong mga biyahe
at itinatanong nang isang beses: «Ito ba ang tahanan mo?».

WALANG KINOKOPYA

Ang paglalakbay ay isang bintana ng mga petsa sa ibabaw ng mga naitalang
biyahe. Burahin mo ito at mananatili sa lugar nito ang bawat biyahe.
```

### Ukrainian

```
ОДНА ІСТОРІЯ, А НЕ ЧОТИРИ ЗАПИСИ

Краснодар → Владикавказ → Тбілісі й назад — чотири записи й одна історія.
Тепер вони тримаються разом: відкрийте поїздку, натисніть «Об'єднати в
подорож» і позначте, які із сусідніх поїздок до неї входять. Або затримайте
палець на картці в «Моїх» і виберіть їх руками.

ЕКРАН ПОДОРОЖІ

Одна мапа з усіма плечима, і позначки кожного плеча на своїх місцях. Під нею
підсумок — дні, кілометри, поїздки, час у дорозі, — а далі дорога по днях:
плечі зі своїми позначками та знімками, а поїздки містом призначення згорнуті
в один рядок.

У «МОЇХ» — ОДНА КАРТКА

Плечі більше не забивають список: вони ховаються під одну картку подорожі з
мапою всього маршруту. У решті застосунку вони лишаються там само, де були.

ПОМІЧАЄ САМО

Ночували не вдома й повернулися? Застосунок запропонує об'єднати ці поїздки.
Подорож робить ніч не вдома, а не відстань, тож довга дорога на роботу
подорожжю не стане ніколи. Дім обчислюється на телефоні з ваших же поїздок і
запитується один раз: «Це твій дім?».

НІЧОГО НЕ КОПІЮЄТЬСЯ

Подорож — це вікно дат поверх уже записаних поїздок. Видаліть її — кожна
поїздка залишиться на своєму місці.
```

### Kazakh

```
ТӨРТ ЖАЗБА ЕМЕС, БІР ӘҢГІМЕ

Краснодар → Владикавказ → Тбилиси және кері — төрт жазба, бір әңгіме. Енді
олар бірге тұрады: сапарды ашыңыз, «Саяхатқа біріктіру» дегенді басып, көрші
сапарлардың қайсысы кіретінін белгілеңіз. Немесе «Менікі» бөлімінде картаны
басып ұстап, оларды қолмен таңдаңыз.

САЯХАТ ЭКРАНЫ

Барлық тіреуі бар бір карта, әр тіреудің белгілері өз орнында қалады. Астында
қорытынды — күндер, километр, сапар саны, жолдағы уақыт, — одан әрі жол күн
сайын: белгілері мен суреттері бар тіреулер, ал баратын қаладағы қысқа
сапарлар бір жолға жиналған.

«МЕНІКІ» БӨЛІМІНДЕ — БІР КАРТОЧКА

Тіреулер тізімді енді толтырмайды: олар бүкіл бағдардың картасы бар бір
саяхат карточкасының астына кіреді. Қалған жерде бәрі бұрынғы орнында.

ӨЗІ БАЙҚАЙДЫ

Үйден тыс қонып, қайтып оралдыңыз ба? Қолданба сол сапарларды біріктіруді
ұсынады. Саяхатты қашықтық емес, үйден тыс өткен түн жасайды — жұмысқа күнде
баратын ұзақ жол ешқашан саналмайды. Үй телефонда өз сапарларыңыз бойынша
анықталып, бір рет сұралады: «Бұл сенің үйің бе?».

ЕШТЕҢЕ КӨШІРІЛМЕЙДІ

Саяхат — жазылып қойған сапарлардың үстіндегі күндер терезесі. Оны өшірсеңіз,
әр сапар өз орнында қалады.
```

### Portuguese (Brazil)

```
UMA HISTÓRIA, NÃO QUATRO GRAVAÇÕES

Krasnodar → Vladikavkaz → Tbilisi e volta: quatro gravações e uma só história.
Agora elas ficam juntas — abra um percurso, toque em «Combinar em uma viagem»
e marque quais dos percursos vizinhos entram. Ou mantenha o dedo em um cartão
em «Meus» e escolha na mão.

A TELA DA VIAGEM

Um mapa com todos os trechos, e as marcações de cada trecho continuam no lugar.
Abaixo o total — dias, quilômetros, percursos, tempo na estrada — e depois a
estrada dia a dia: trechos com suas marcações e fotos, e os percursos pela
cidade de destino dobrados em uma única linha.

EM «MEUS» — UM CARTÃO

Os trechos param de entupir a lista: entram sob um único cartão de viagem com
o mapa de toda a rota. No resto do app eles ficam exatamente onde estavam.

ELE PERCEBE SOZINHO

Dormiu fora de casa e voltou? O app propõe combinar esses percursos. O que faz
uma viagem é a noite fora, não a distância — um trajeto diário longo nunca
conta. A casa é deduzida no telefone a partir dos seus próprios percursos e
perguntada uma vez: «Esta é a tua casa?».

NADA É COPIADO

Uma viagem é uma janela de datas sobre percursos já gravados. Apague-a e cada
percurso continua no seu lugar.
```

---

## 2. Промо-текст (170)

```
Четыре записи — одна история. Путешествие: общая карта, итог по дням, местные поездки свёрнуты. Ночевал не дома — приложение предложит объединить само.
```

## 3. Что проверить в карточке перед «Submit»

- «What's New» вставлен во ВСЕ локализации карточки (тринадцать блоков выше).
- Билд 58, версия 0.6.6.
- Notes для ревьюера — из app-review-notes.md, блок 0.6.6.
- Бэкенд задеплоен (см. [checklist.md](checklist.md), §1): без него путешествие
  не доедет до второго телефона.
- Скриншоты: экран путешествия — лучший кадр релиза, снимать с картой-склейкой
  и лентой по дням.
