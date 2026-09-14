# App Store Connect — 0.6.8

Всё, что нужно вставить при выкладке билда **0.6.8 (60)**. Заметки для ревьюера —
в [app-review-notes.md](../app-review-notes.md), секция «current submission».

**«What's New» обязателен в КАЖДОЙ локализации карточки.** Сабмит 0.6.2
отклонили ровно за одну пропущенную.

**В карточке ДВЕНАДЦАТЬ локалей, и это НЕ языки приложения.** Заполнять ровно
их, ничего больше:

> English (генеральная) · Russian · German · Spanish (Spain) · French ·
> Italian · Polish · Indonesian · Turkish · **Finnish** · Ukrainian ·
> Portuguese (Brazil)

Два расхождения с приложением — старые и намеренно не чинятся:

- **Слот «Finnish» — это филиппинский.** Финского языка в приложении нет; при
  заведении локалей `fil` спутали с `fi`. Слот НЕ переименовываем, кладём в
  него ФИЛИППИНСКИЙ текст — так делали в 0.6.3, 0.6.4, 0.6.6 и 0.6.7.
- **Казахского в карточке нет вовсе.** В приложении он есть, в списке локалей
  между Italian и Polish пусто. Блок ниже оставлен для полноты, но вставлять
  его НЕКУДА.

Релиз **не чисто клиентский**: бэкенд деплоится первым — публичное путешествие
(таблица-страница `/j/<код>`, список `GET /users/:id/journeys`, поле `journey`
на карточке ленты) и колонка отрезков `trip.segments`. Без бэкенда «Опубликовать
путешествие» приведёт в никуда, а отрезок не переживёт первый пул. И до пуша
бэкенда владелец обязан добавить `/j/*` в то же правило Cloudflare, которым
`/s/*` и `/u/*` уходят на api-хост, — иначе ссылка на путешествие умрёт на edge.

Ключевые слова, подзаголовок и описание не меняются. Лимиты: «What's New» —
4000, промо-текст — 170.

---

## 1. What's New

### English (U.S.)

```
PLACES

Mark a spot during a trip and the app remembers it. Every later drive that
passes within about 100 m counts as a pass, so the place knows «Here 4 times»
and «usually 2:14 from the start». The new Places tab holds them all: a map of
pins and a card per place; inside, the threads of your passes, the best and the
worst one, and every pass as a row that opens the trip right at that
checkpoint. On the trip screen each checkpoint now carries a chip with the same
numbers. Places are worked out on the phone and never leave it.

A JOURNEY CAN BE PUBLISHED

The publish sheet lists the private trips inside by name, so you see exactly
what opens together with it. After that the journey has its own screen for
other people, a card in your public profile and a link trip-track.app/j/…, and
a trip that belongs to it shows «Part of …» in the feed, with a way inside.
Hiding works the same way: the journey disappears from other people's feeds and
profiles, and the trips inside stay exactly as they are.

LEGS

Two checkpoints of one trip make a leg with its own name, time and distance —
«from the petrol station to the pass». Once both ends have become places, the
leg also shows your own history: «You drove this leg 3 times: 4:58 · 5:12 ·
5:31».

CHANGED

The Groups tab is now Places; clubs did not go anywhere — they moved into the
profile, under the garage. The floating tab bar no longer sits on the home
indicator.
```

### Russian

```
МЕСТА

Поставьте отметку в поездке — и приложение запомнит это место. Каждая
следующая поездка, прошедшая в сотне метров от него, засчитывается проездом,
поэтому место знает: «Здесь 4 раза», «обычно 2:14 от старта». Новая вкладка
«Места» собирает их все: карта с булавками и карточка на каждое место, внутри
— нитки ваших проездов, лучший и худший, и список проездов с переходом в
поездку прямо к отметке. На странице поездки у каждой отметки появился чип с
теми же числами. Места считаются на телефоне и никуда с него не уходят.

ПУТЕШЕСТВИЕ МОЖНО ОПУБЛИКОВАТЬ

Лист публикации называет приватные поездки внутри поимённо — видно, что именно
откроется вместе с ним. Дальше у путешествия свой экран для других, карточка в
публичном профиле и ссылка trip-track.app/j/…, а у поездки-плеча в ленте
появляется строка «Часть путешествия…» с переходом внутрь. Скрыть можно так
же: путешествие пропадает из чужой ленты и профиля, а поездки внутри остаются
такими, какие они есть.

ОТРЕЗКИ

Две отметки одной поездки становятся отрезком со своим именем, временем и
расстоянием — «от заправки до перевала». Когда обе стали местами, под числами
появляется история по вашим же прошлым проездам: «Вы ехали этот отрезок 3
раза: 4:58 · 5:12 · 5:31».

ИЗМЕНИЛОСЬ

Вкладка «Группы» стала вкладкой «Места». Клубы никуда не делись — переехали в
профиль под гараж. Плавающий таб-бар больше не садится на индикатор «домой».
```

### German

```
ORTE

Setzen Sie unterwegs eine Markierung, und die App merkt sich diesen Ort. Jede
spätere Fahrt, die in etwa 100 m daran vorbeikommt, zählt als Vorbeifahrt — der
Ort weiß dann „4-mal hier" und „üblicherweise 2:14 ab Start". Der neue Tab
„Orte" sammelt sie alle: eine Karte mit Nadeln und eine Kachel je Ort, darin
die Spuren Ihrer Vorbeifahrten, die beste und die schlechteste, und jede
Vorbeifahrt öffnet die Fahrt direkt an der Markierung. Orte entstehen auf dem
Telefon und verlassen es nie.

EINE REISE LÄSST SICH VERÖFFENTLICHEN

Der Veröffentlichungsdialog nennt die privaten Fahrten darin beim Namen — Sie
sehen genau, was mit geöffnet wird. Danach hat die Reise einen eigenen
Bildschirm für andere, eine Kachel im öffentlichen Profil und einen Link
trip-track.app/j/…; bei einer Fahrt daraus steht im Feed „Teil von …" mit dem
Weg hinein. Verbergen geht genauso: Die Reise verschwindet aus fremden Feeds
und Profilen, die Fahrten darin bleiben, wie sie sind.

ETAPPEN

Zwei Markierungen einer Fahrt ergeben eine Etappe mit eigenem Namen, eigener
Zeit und Strecke — „von der Tankstelle bis zum Pass". Sind beide Enden zu Orten
geworden, zeigt die Etappe auch Ihre eigene Historie: „Sie sind diese Etappe
3-mal gefahren: 4:58 · 5:12 · 5:31".

GEÄNDERT

Aus dem Tab „Gruppen" wurde „Orte"; die Clubs sind ins Profil unter die Garage
gezogen. Die schwebende Tab-Leiste sitzt nicht mehr auf dem Home-Indikator.
```

### Spanish (Spain)

```
LUGARES

Marca un punto durante un viaje y la app se acuerda de él. Cada trayecto
posterior que pase a unos 100 m cuenta como paso, así que el lugar sabe «Aquí 4
veces» y «normalmente 2:14 desde la salida». La nueva pestaña «Lugares» los
reúne todos: un mapa con chinchetas y una tarjeta por lugar; dentro, los hilos
de tus pasos, el mejor y el peor, y cada paso abre el viaje justo en esa marca.
En la pantalla del viaje cada marca lleva ahora una etiqueta con esos mismos
números. Los lugares se calculan en el teléfono y nunca salen de él.

UN VIAJE SE PUEDE PUBLICAR

La hoja de publicación nombra uno a uno los trayectos privados que contiene:
ves exactamente qué se abre con él. Después el viaje tiene su propia pantalla
para los demás, una tarjeta en tu perfil público y un enlace trip-track.app/j/…;
en el feed, un trayecto suyo muestra «Parte de …» con acceso al interior.
Ocultarlo funciona igual: el viaje desaparece de los feeds y perfiles ajenos y
sus trayectos se quedan como están.

TRAMOS

Dos marcas de un mismo viaje forman un tramo con su nombre, su tiempo y su
distancia: «de la gasolinera al puerto». Cuando ambos extremos se han
convertido en lugares, el tramo muestra además tu propio historial: «Has hecho
este tramo 3 veces: 4:58 · 5:12 · 5:31».

CAMBIOS

La pestaña «Grupos» ahora es «Lugares»; los clubes se han mudado al perfil,
bajo el garaje. La barra flotante ya no se sienta sobre el indicador de inicio.
```

### French

```
LIEUX

Posez un repère pendant un trajet et l'app s'en souvient. Chaque trajet
suivant qui passe à une centaine de mètres compte comme un passage : le lieu
sait « Ici 4 fois » et « d'habitude 2:14 depuis le départ ». Le nouvel onglet
« Lieux » les rassemble : une carte avec des épingles et une fiche par lieu ; à
l'intérieur, les tracés de vos passages, le meilleur et le pire, et chaque
passage ouvre le trajet exactement au repère. Sur l'écran du trajet, chaque
repère porte une pastille avec les mêmes chiffres. Les lieux sont
calculés sur le téléphone et n'en sortent jamais.

UN VOYAGE PEUT ÊTRE PUBLIÉ

La feuille de publication nomme un à un les trajets privés qu'il contient :
vous voyez ce qui s'ouvre avec lui. Ensuite le voyage a son propre
écran pour les autres, une fiche dans votre profil public et un lien
trip-track.app/j/… ; dans le fil, un trajet qui en fait partie affiche
« Fait partie de … ». Le masquer fonctionne pareil : le voyage disparaît des
fils et profils des autres, ses trajets restent tels quels.

TRONÇONS

Deux repères d'un même trajet forment un tronçon avec son nom, son temps et sa
distance : « de la station-service au col ». Quand les deux extrémités sont
devenues des lieux, le tronçon montre aussi votre historique : « Vous avez fait
ce tronçon 3 fois : 4:58 · 5:12 · 5:31 ».

CHANGÉ

L'onglet « Groupes » est devenu « Lieux » ; les clubs ont déménagé dans le
profil, sous le garage. La barre d'onglets flottante ne s'assoit plus sur
l'indicateur d'accueil.
```

### Italian

```
LUOGHI

Metti un segnaposto durante un viaggio e l'app se lo ricorda. Ogni tragitto
successivo che passa entro un centinaio di metri conta come passaggio, così il
luogo sa «Qui 4 volte» e «di solito 2:14 dalla partenza». La nuova scheda
«Luoghi» li raccoglie tutti: una mappa di spilli e una card per luogo; dentro,
le tracce dei tuoi passaggi, il migliore e il peggiore, e ogni passaggio apre il
viaggio proprio a quel segnaposto. Sulla schermata del viaggio ogni segnaposto
ha ora una pillola con gli stessi numeri. I luoghi si calcolano sul telefono e
non escono mai da lì.

UN VIAGGIO SI PUÒ PUBBLICARE

Il foglio di pubblicazione elenca per nome i tragitti privati che contiene: vedi
esattamente cosa si apre insieme a lui. Poi il viaggio ha la sua schermata per
gli altri, una card nel profilo pubblico e un link trip-track.app/j/…; nel feed
un tragitto che ne fa parte mostra «Parte di …» con l'accesso all'interno.
Nasconderlo funziona allo stesso modo: il viaggio sparisce dai feed e dai
profili altrui, i tragitti restano come sono.

TRATTI

Due segnaposti dello stesso viaggio formano un tratto con nome, tempo e
distanza propri: «dal distributore al passo». Quando entrambe le estremità sono
diventate luoghi, il tratto mostra anche la tua storia: «Hai percorso questo
tratto 3 volte: 4:58 · 5:12 · 5:31».

CAMBIATO

La scheda «Gruppi» ora è «Luoghi»; i club si sono trasferiti nel profilo, sotto
il garage. La barra a comparsa non si siede più sull'indicatore Home.
```

### Polish

```
MIEJSCA

Postaw znacznik podczas przejazdu, a aplikacja zapamięta to miejsce. Każdy
późniejszy przejazd w promieniu około 100 m liczy się jako przejazd obok, więc
miejsce wie: „Tu 4 razy" i „zwykle 2:14 od startu". Nowa zakładka „Miejsca"
zbiera je wszystkie: mapa z pinezkami i kafelek na każde miejsce, a w środku
nitki twoich przejazdów, najlepszy i najgorszy, oraz lista przejazdów z
przejściem do trasy dokładnie przy znaczniku. Na ekranie trasy każdy znacznik
ma teraz pastylkę z tymi samymi liczbami. Miejsca liczą się na telefonie i
nigdy go nie opuszczają.

PODRÓŻ MOŻNA OPUBLIKOWAĆ

Arkusz publikacji wymienia prywatne trasy w środku z nazwy — widzisz dokładnie,
co otworzy się razem z nią. Potem podróż ma własny ekran dla innych, kafelek w
publicznym profilu i link trip-track.app/j/…, a trasa należąca do niej pokazuje
w strumieniu wiersz „Część podróży …" z przejściem do środka. Ukrycie działa
tak samo: podróż znika z cudzych strumieni i profili, a trasy w środku zostają
takie, jakie są.

ODCINKI

Dwa znaczniki jednej trasy tworzą odcinek z własną nazwą, czasem i dystansem —
„od stacji do przełęczy". Gdy oba końce stały się miejscami, odcinek pokazuje
też twoją historię: „Przejechałeś ten odcinek 3 razy: 4:58 · 5:12 · 5:31".

ZMIENIŁO SIĘ

Zakładka „Grupy" stała się zakładką „Miejsca"; kluby przeniosły się do profilu,
pod garaż. Pływający pasek zakładek nie siada już na wskaźniku ekranu głównego.
```

### Indonesian

```
TEMPAT

Tandai satu titik saat perjalanan dan aplikasi akan mengingat tempat itu.
Setiap perjalanan berikutnya yang lewat dalam radius 100 m dihitung
sebagai lintasan, jadi tempat itu tahu «Di sini 4 kali» dan «biasanya 2:14 dari
start». Tab baru «Tempat» mengumpulkan semuanya: peta berisi pin dan satu kartu
per tempat; di dalamnya ada jalur lintasan Anda, yang tercepat dan
terlama, serta daftar lintasan yang membuka perjalanan tepat pada penanda itu.
Di layar perjalanan setiap penanda kini punya chip dengan angka yang sama.
Tempat dihitung di ponsel dan tidak pernah keluar dari sana.

PERJALANAN BISA DIPUBLIKASIKAN

Lembar publikasi menyebutkan satu per satu perjalanan privat di dalamnya —
Anda melihat persis apa yang ikut terbuka. Setelah itu perjalanan punya layar
sendiri untuk orang lain, kartu di profil publik Anda dan tautan
trip-track.app/j/…; di feed, perjalanan yang menjadi bagiannya menampilkan
«Bagian dari …» dengan jalan masuk. Menyembunyikan bekerja sama: perjalanan
hilang dari feed dan profil orang lain, sedangkan isinya tetap apa adanya.

ETAPE

Dua penanda dalam satu perjalanan membentuk etape dengan nama, waktu dan
jaraknya sendiri — «dari pom bensin sampai puncak». Ketika kedua ujungnya sudah
menjadi tempat, etape juga menampilkan riwayat Anda sendiri: «Anda menempuh
etape ini 3 kali: 4:58 · 5:12 · 5:31».

BERUBAH

Tab «Grup» kini menjadi «Tempat»; klub pindah ke profil, di bawah garasi. Bilah
tab mengambang tidak lagi duduk di atas indikator beranda.
```

### Turkish

```
YERLER

Yolculuk sırasında bir noktayı işaretleyin, uygulama o yeri hatırlasın. Sonraki
her yolculuk yaklaşık 100 m yakınından geçtiğinde bir geçiş sayılır; böylece
yer «Burada 4 kez» ve «genelde başlangıçtan 2:14» bilgisini edinir. Yeni
«Yerler» sekmesi hepsini toplar: iğnelerle bir harita ve her yer için bir kart;
içinde geçişlerinizin izleri, en iyisi ve en kötüsü, ve her geçiş yolculuğu tam
o işaretin üzerinde açar. Yolculuk ekranında her işaretin altında artık aynı
sayıları taşıyan bir rozet var. Yerler telefonda hesaplanır ve oradan hiç
çıkmaz.

BİR GEZİ YAYINLANABİLİR

Yayınlama sayfası içindeki özel yolculukları adıyla sayar — onunla birlikte
tam olarak neyin açılacağını görürsünüz. Ardından gezinin başkaları için kendi
ekranı, herkese açık profilinizde bir kartı ve trip-track.app/j/… bağlantısı
olur; akışta ona ait bir yolculukta «… gezisinin parçası» satırı görünür ve
içeri götürür. Gizlemek de aynı şekilde çalışır: gezi başkalarının akışından ve
profilinden kaybolur, içindeki yolculuklar olduğu gibi kalır.

ETAPLAR

Aynı yolculuktaki iki işaret, kendi adı, süresi ve mesafesiyle bir etap olur:
«benzinlikten geçide kadar». İki ucu da yere dönüştüğünde etap kendi geçmişinizi
de gösterir: «Bu etabı 3 kez sürdünüz: 4:58 · 5:12 · 5:31».

DEĞİŞENLER

«Gruplar» sekmesi «Yerler» oldu; kulüpler profile, garajın altına taşındı.
Yüzen sekme çubuğu artık ana ekran göstergesinin üzerine oturmuyor.
```

### Filipino → вставлять в слот **Finnish**

```
MGA LUGAR

Maglagay ng marka habang naglalakbay at tatandaan ito ng app. Bawat susunod na
biyaheng dumaan sa loob ng mga 100 m ay isang pagdaan, kaya alam ng lugar ang
«Dito 4 na beses» at «karaniwang 2:14 mula sa simula». Tinitipon silang lahat ng
bagong tab na «Mga lugar»: mapa ng mga pin at isang card bawat lugar; sa loob,
ang mga guhit ng iyong mga pagdaan, ang pinakamabilis at pinakamabagal, at
bubuksan ng bawat pagdaan ang biyahe mismo sa markang iyon. May chip na ang
bawat marka sa screen ng biyahe. Sa telepono kinukuwenta ang mga lugar at hindi
ito lumalabas doon.

PUWEDENG I-PUBLISH ANG PAGLALAKBAY

Pinapangalanan ng publish sheet ang mga pribadong biyahe sa loob: makikita mo
kung ano ang bubukas kasama nito. Pagkatapos, may sariling screen ang
paglalakbay para sa iba, card sa iyong pampublikong profile at link na
trip-track.app/j/…; sa feed, ang biyaheng kabilang dito ay may linyang «Bahagi
ng …». Ganoon din ang pagtatago: nawawala ang paglalakbay sa feed at profile ng
iba, nananatili ang mga biyahe sa loob.

MGA LEG

Dalawang marka sa iisang biyahe ang bumubuo ng leg na may sariling pangalan,
oras at distansya: «mula gasolinahan hanggang tuktok». Kapag naging lugar na
ang magkabilang dulo, ipinapakita rin ng leg ang sarili mong kasaysayan:
«Tatlong beses mo nang dinaanan ang leg na ito: 4:58 · 5:12 · 5:31».

NAGBAGO

Ang tab na «Mga grupo» ay «Mga lugar» na; lumipat ang mga club sa profile, sa
ilalim ng garahe. Hindi na nakadapo ang tab bar sa home indicator.
```

### Ukrainian

```
МІСЦЯ

Поставте позначку в поїздці — і застосунок запам'ятає це місце. Кожна наступна
поїздка, що пройшла за сотню метрів від нього, зараховується проїздом, тому
місце знає: «Тут 4 рази», «зазвичай 2:14 від старту». Нова вкладка «Місця»
збирає їх усі: карта з шпильками й картка на кожне місце, а всередині — нитки
ваших проїздів, найкращий і найгірший, та список проїздів з переходом у
поїздку просто до позначки. На сторінці поїздки біля кожної позначки з'явився
чип із тими самими числами. Місця рахуються на телефоні й нікуди з нього не
йдуть.

ПОДОРОЖ МОЖНА ОПУБЛІКУВАТИ

Аркуш публікації називає приватні поїздки всередині поіменно — видно, що саме
відкриється разом із нею. Далі в подорожі свій екран для інших, картка в
публічному профілі та посилання trip-track.app/j/…, а в поїздки-плеча у стрічці
з'являється рядок «Частина подорожі…» з переходом усередину. Сховати можна так
само: подорож зникає з чужої стрічки та профілю, а поїздки всередині лишаються
такими, які вони є.

ВІДРІЗКИ

Дві позначки однієї поїздки стають відрізком зі своїм іменем, часом і
відстанню — «від заправки до перевалу». Коли обидві стали місцями, під числами
з'являється історія за вашими ж минулими проїздами: «Ви їхали цей відрізок 3
рази: 4:58 · 5:12 · 5:31».

ЗМІНИЛОСЯ

Вкладка «Групи» стала вкладкою «Місця». Клуби нікуди не зникли — переїхали до
профілю під гараж. Плавальна панель вкладок більше не сідає на індикатор
«додому».
```

### Portuguese (Brazil)

```
LUGARES

Marque um ponto durante um trajeto e o app guarda esse lugar. Cada viagem
seguinte que passe a uns 100 m conta como uma passagem, então o lugar sabe
«Aqui 4 vezes» e «normalmente 2:14 desde a largada». A nova aba «Lugares» reúne
todos: um mapa de alfinetes e um cartão por lugar; dentro, os traços das suas
passagens, a melhor e a pior, e cada passagem abre o trajeto exatamente naquela
marca. Na tela do trajeto, cada marca agora tem uma pílula com os mesmos
números. Os lugares são calculados no telefone e nunca saem dele.

DÁ PARA PUBLICAR UMA VIAGEM

A folha de publicação nomeia um a um os trajetos privados que estão dentro —
você vê exatamente o que abre junto. Depois a viagem ganha a própria tela para
os outros, um cartão no seu perfil público e um link trip-track.app/j/…; no
feed, um trajeto que faz parte dela mostra «Parte de …» com caminho para
dentro. Esconder funciona igual: a viagem some do feed e do perfil dos outros,
e os trajetos de dentro ficam como estão.

TRECHOS

Duas marcas de um mesmo trajeto formam um trecho com nome, tempo e distância
próprios: «do posto até o passo». Quando as duas pontas viraram lugares, o
trecho mostra também o seu histórico: «Você fez este trecho 3 vezes: 4:58 ·
5:12 · 5:31».

MUDOU

A aba «Grupos» agora é «Lugares»; os clubes se mudaram para o perfil, embaixo
da garagem. A barra flutuante não senta mais no indicador de início.
```

### Kazakh — В КАРТОЧКЕ ЭТОЙ ЛОКАЛИ НЕТ, вставлять некуда

```
ОРЫНДАР

Сапар кезінде белгі қойыңыз — қолданба бұл орынды есте сақтайды. Одан кейінгі
әр сапар жүз метрдей жерден өтсе, өту болып саналады, сондықтан орын «Мұнда 4
рет» және «әдетте стартан 2:14» дегенді біледі. Жаңа «Орындар» қойындысы
олардың бәрін жинайды.

САЯХАТТЫ ЖАРИЯЛАУҒА БОЛАДЫ

Жариялау парағы ішіндегі жеке сапарларды атымен атайды. Содан кейін саяхаттың
өз экраны, ашық профильдегі картасы және trip-track.app/j/… сілтемесі болады.
Жасыру да солай: саяхат жоғалады, сапарлар сол күйінде қалады.

КЕСІНДІЛЕР

Бір сапардың екі белгісі өз атауы, уақыты мен қашықтығы бар кесіндіге
айналады. Екі ұшы да орынға айналса, кесінді сіздің тарихыңызды көрсетеді.

ӨЗГЕРДІ

«Топтар» қойындысы «Орындар» болды; клубтар профильге, гараждың астына көшті.
```

---

## 2. Промо-текст (170)

Один и тот же смысл в двенадцати локалях. Лимит — 170 знаков, проверено
`wc -m`.

**English (U.S.)**

```
Mark a spot on a trip and the app knows the place next time: here 4 times, usually 2:14. Plus legs between checkpoints and journeys you can publish.
```

**Russian**

```
Поставьте отметку — приложение узнает место в следующий раз: здесь 4 раза, обычно 2:14. Плюс отрезки между отметками и путешествие, которое можно показать.
```

**German**

```
Markieren Sie einen Punkt — die App kennt den Ort beim nächsten Mal: 4-mal hier, meist 2:14. Dazu Etappen zwischen Markierungen und Reisen zum Veröffentlichen.
```

**Spanish (Spain)**

```
Marca un punto y la app reconocerá el lugar la próxima vez: aquí 4 veces, normalmente 2:14. Además, tramos entre marcas y viajes que puedes publicar.
```

**French**

```
Posez un repère : l'app reconnaît le lieu la fois suivante — ici 4 fois, d'habitude 2:14. Plus les tronçons entre repères et les voyages à publier.
```

**Italian**

```
Metti un segnaposto e l'app riconosce il luogo la volta dopo: qui 4 volte, di solito 2:14. In più i tratti tra i segnaposti e i viaggi da pubblicare.
```

**Polish**

```
Postaw znacznik, a aplikacja rozpozna miejsce następnym razem: tu 4 razy, zwykle 2:14. Do tego odcinki między znacznikami i podróże do opublikowania.
```

**Indonesian**

```
Tandai satu titik dan aplikasi mengenali tempat itu lain kali: di sini 4 kali, biasanya 2:14. Plus etape antar penanda dan perjalanan yang bisa dipublikasikan.
```

**Turkish**

```
Bir noktayı işaretleyin, uygulama o yeri bir dahaki sefere tanısın: burada 4 kez, genelde 2:14. Ayrıca işaretler arası etaplar ve yayınlanabilen geziler.
```

**Filipino → слот Finnish**

```
Markahan ang isang lugar at makikilala ito ng app sa susunod: dito 4 na beses, karaniwang 2:14. May mga leg at paglalakbay na puwedeng i-publish.
```

**Ukrainian**

```
Поставте позначку — застосунок упізнає місце наступного разу: тут 4 рази, зазвичай 2:14. Плюс відрізки між позначками та подорож, яку можна показати.
```

**Portuguese (Brazil)**

```
Marque um ponto e o app reconhece o lugar da próxima vez: aqui 4 vezes, normalmente 2:14. Além de trechos entre marcas e viagens que dá para publicar.
```

---

## 3. Что проверить в карточке перед «Submit»

- [ ] «What's New» заполнен во **всех двенадцати** локалях карточки. Филиппинский
      текст — в слот **Finnish**. Казахский блок пропустить, локали нет.
- [ ] Рейтинг 13+ на месте (лента с реакциями = «Social Media»).
- [ ] **App Privacy** — без изменений с 0.6.7 (`docs/releases/app-privacy.md`).
      Места на сервер не уходят вовсе, отрезки едут внутри уже описанной
      поездки, публичное путешествие — уже описанный пользовательский контент.
- [ ] Notes для ревьюера — блок 0.6.8 из `../app-review-notes.md`.
- [ ] Скриншоты: вкладка «Места» и экран путешествия — **желательны, но не
      обязательны** (решение владельца; прежний набор остаётся валидным).
- [ ] Бэкенд выкачен **до** сабмита, и правило Cloudflare на `/j/*` добавлено
      **до** пуша бэкенда — см. `checklist.md` §1.
