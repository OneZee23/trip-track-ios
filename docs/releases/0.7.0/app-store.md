# App Store Connect — 0.7.0

Всё, что нужно вставить при выкладке билда **0.7.0 (61)**. Заметки для ревьюера —
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
  него ФИЛИППИНСКИЙ текст — так делали в 0.6.3, 0.6.4, 0.6.6, 0.6.7 и 0.6.8.
- **Казахского в карточке нет вовсе.** В приложении он есть, в списке локалей
  между Italian и Polish пусто. Блок ниже оставлен для полноты, но вставлять
  его НЕКУДА.

Релиз **не чисто клиентский**: бэкенд деплоится первым — каталог секретов
(`GET /secrets/catalog`), раскрытие (`POST /secrets/reveal`), стирание
(`POST /secrets/forget-all`) и пуш админу о новой регистрации. Без бэкенда
приложение не ломается (каталог берётся из бандла, находки считаются на
телефоне), но у карточки секрета не будет ни истории, ни «нашли N человек», а
находки не приедут на второй телефон. Правило Cloudflare в этот раз **не
нужно**: новых публичных веб-путей вида `/s/`, `/u/`, `/j/` версия не заводит.

Ключевые слова, подзаголовок и описание не меняются. Лимиты: «What's New» —
4000, промо-текст — 170.

---

## 1. What's New

### English (U.S.)

```
THE ATLAS

The Map tab is now the Atlas, and the world on it starts closed. Solid fog, and
your own roads burned through it as
a living map: streets, names, the sea. Everything you have ever recorded is in
there from the first launch; the app rebuilds it in the background. The sheet
says how much you have opened, and "1,910 km opened" is the length of the
opened corridors rather than the sum of your trips — the hundredth drive down
your own street opens nothing.

FINDS

After a trip ends, the phone reads the recorded track and tells you what you
drove past: authored secrets, riddles built from open data (a lighthouse, a pass,
a ferry, a dam, a border post) and milestones of your own
geography — a first region, your easternmost point, high in the mountains,
below sea level, three regions in one day, a border, a pass at night. Each one
puts a seal on the Atlas. Nothing is computed and nothing is shown while you
are driving: chasing a find belongs off the road.

THE EXPLORER'S JOURNAL

Pull the Atlas sheet up and it holds how much you have opened and the regions
with the date you first entered them, plus all your seals in one grid. Tap a
seal for its card: the story of a secret with "found by N, first
was ..."; the line and the circle of a riddle; the place and the date of a
milestone.

The trip summary gained an "Opened" block — "42 km of new road · 1 riddle · 1
milestone" — and the fog burns off the trip's own map along the road you have
just driven. Your finds also show in your public profile under the
achievements, each with a word for how rare it is, behind the same visibility
switch. And "Share the Atlas" now hands over a picture of your map: the same
fog, the same corridors, your seals. What you have not found is not on it.
```

### Russian

```
АТЛАС

Вкладка «Карта» стала «Атласом», и мир на ней закрыт. Непрозрачная мгла — и
ваши собственные дороги, прожжённые в ней
живой картой: улицы, названия, море. Всё, что вы когда-либо записали, уже
внутри с первого запуска: приложение разбирает библиотеку фоном. В листе видно,
сколько открыто, и «1 910 км открыто» — это длина открытых коридоров, а не
сумма поездок: сотый проезд по своей улице не открывает ничего.

НАХОДКИ

После финиша телефон сам разбирает записанный трек и говорит, мимо чего вы
проехали: авторские секреты, загадки по открытым данным (маяк, перевал, паром,
плотина, погранпост) и вехи собственной географии — первый регион, самая
восточная точка, высоко в горах, ниже уровня моря, три региона за день,
граница, ночной перевал. Каждая находка ставит на «Атлас» печать. На ходу не
считается и не показывается ничего: гнаться за находкой на дороге не надо.

ЖУРНАЛ ПЕРВООТКРЫВАТЕЛЯ

Потяните лист «Атласа» вверх — в нём сколько открыто и регионы с датой первого
въезда, и все ваши печати сеткой. Тап по печати открывает карточку:
история секрета и «нашли N человек, первым — имя»; строка и круг загадки; место
и дата вехи.

На экране итогов появился блок «Открыто» — «42 км нового пути · 1 загадка · 1
веха», — и туман выгорает с карты самой поездки по только что проеханному пути.
Находки видны и в публичном профиле, под достижениями, с подписью редкости и
под тем же переключателем видимости. А «Поделиться Атласом» отдаёт картинку
вашей карты: тот же туман, те же коридоры, ваши печати. Ненайденного на ней
нет.
```

### German

```
DER ATLAS

Aus dem Tab „Karte“ wurde „Atlas“, und die Welt darauf ist zu. Undurchsichtiger
Nebel — und mittendrin Ihre eigenen
Straßen, als lebendige Karte hineingebrannt: Straßennamen, Orte, das Meer.
Alles, was Sie je aufgezeichnet haben, ist vom ersten Start an dabei; die App
baut es im Hintergrund auf. Das Blatt zeigt, wie viel offen ist, und „1 910 km
geöffnet“ ist die Länge der geöffneten Korridore und nicht die Summe Ihrer
Fahrten — die hundertste Fahrt durch die eigene Straße öffnet nichts mehr.

FUNDE

Nach dem Ende einer Fahrt liest das Telefon die Aufzeichnung und sagt Ihnen,
woran Sie vorbeigekommen sind: Geheimnisse von uns, Rätsel aus offenen Daten
(Leuchtturm, Pass, Fähre, Staudamm, Grenzposten) und Meilensteine
Ihrer eigenen Geografie — die erste Region, Ihr östlichster Punkt, hoch in den
Bergen, unter dem Meeresspiegel, drei Regionen an einem Tag, eine Grenze, ein
Pass bei Nacht. Jeder Fund setzt ein Siegel auf den Atlas. Während der Fahrt
wird nichts berechnet und nichts angezeigt: Einem Fund hinterherzujagen gehört
nicht auf die Straße.

DAS ENTDECKERTAGEBUCH

Ziehen Sie das Atlas-Blatt nach oben, dann stehen dort wie viel
offen ist und die Regionen mit dem Datum der ersten Einfahrt, sowie alle Ihre
Siegel als Raster. Ein Tippen auf ein Siegel öffnet seine Karte: die
Geschichte eines Geheimnisses mit „von N gefunden, als Erstes von …“; Zeile und
Kreis eines Rätsels; Ort und Datum eines Meilensteins.

Die Fahrtübersicht hat einen Block „Geöffnet“ bekommen — „42 km neuer Weg · 1
Rätsel · 1 Meilenstein“ —, und der Nebel brennt auf der Karte der Fahrt selbst
entlang des eben gefahrenen Weges weg. Ihre Funde stehen auch im öffentlichen
Profil unter den Erfolgen, jeder mit einem Wort für seine Seltenheit und hinter
demselben Schalter. Und „Atlas teilen“ gibt jetzt ein Bild Ihrer Karte heraus:
derselbe Nebel, dieselben Korridore, Ihre Siegel. Was Sie nicht gefunden haben,
ist darauf nicht zu sehen.
```

### Spanish (Spain)

```
EL ATLAS

La pestaña «Mapa» ahora es el «Atlas», y el mundo empieza cerrado. Niebla
opaca, y dentro tus carreteras,
quemadas en ella como un mapa vivo: calles, nombres, el mar. Todo lo que has
grabado alguna vez está ahí desde el primer arranque; la app lo reconstruye en
segundo plano. La hoja dice cuánto has abierto, y «1 910 km abiertos» es la
longitud de los corredores abiertos, no la suma de tus viajes: el centésimo
paso por tu propia calle no abre nada.

HALLAZGOS

Al terminar un trayecto, el teléfono lee la grabación y te cuenta por delante
de qué has pasado: secretos nuestros, enigmas hechos con datos abiertos (un faro,
un puerto de montaña, un ferri, una presa, un puesto fronterizo) e hitos
de tu propia geografía: la primera región, tu punto más al este, alto en la
montaña, bajo el nivel del mar, tres regiones en un día, una frontera, un
puerto de noche. Cada hallazgo pone un sello en el Atlas. En marcha no se
calcula ni se muestra nada: perseguir un hallazgo no es cosa de la carretera.

EL DIARIO DEL EXPLORADOR

Tira de la hoja del Atlas hacia arriba y verás cuánto has abierto
y las regiones con la fecha en que entraste por primera vez, y todos tus sellos
en una cuadrícula. Al tocar un sello se abre su ficha: la historia de un
secreto con «lo han encontrado N, el primero fue …»; la línea y el círculo de
un enigma; el lugar y la fecha de un hito.

La pantalla de resumen estrena un bloque «Abierto» — «42 km de camino nuevo · 1
enigma · 1 hito» — y la niebla se quema en el mapa del propio trayecto por la
carretera que acabas de hacer. Tus hallazgos también salen en tu perfil
público, bajo los logros, cada uno con una palabra para su rareza y tras el
mismo interruptor. Y «Compartir el Atlas» entrega ahora una imagen de tu mapa:
la misma niebla, los mismos corredores, tus sellos. Lo que no has encontrado no
aparece.
```

### French

```
L'ATLAS

L'onglet « Carte » devient « Atlas », et le monde y est fermé. Un brouillard
opaque — et vos propres routes
brûlées dedans comme une carte vivante : les rues, les noms, la mer. Tout ce
que vous avez enregistré un jour s'y trouve dès le premier lancement ; l'app le
reconstruit en arrière-plan. La feuille dit ce que vous avez ouvert, et
« 1 910 km ouverts » est la longueur des couloirs ouverts, pas la somme de vos
trajets : le centième passage dans votre rue n'ouvre plus rien.

DÉCOUVERTES

Une fois le trajet terminé, le téléphone lit l'enregistrement et vous dit
devant quoi vous êtes passé : des secrets signés, des énigmes bâties sur des
données ouvertes (un phare, un col, un bac, un barrage, un
poste-frontière) et des jalons de votre propre géographie — une première région,
votre point le plus à l'est, haut en montagne, sous le niveau de la mer, trois
régions en un jour, une frontière, un col de nuit. Chaque découverte pose un
sceau sur l'Atlas. En roulant, rien n'est calculé et rien n'est affiché :
courir après une découverte n'a pas sa place sur la route.

LE JOURNAL DE L'EXPLORATEUR

Tirez la feuille de l'Atlas vers le haut : ce que vous avez
ouvert et les régions avec la date de votre première entrée, et tous vos sceaux
en grille. Touchez un sceau pour sa fiche : l'histoire d'un secret
avec « trouvé par N, le premier était … » ; la ligne et le cercle d'une
énigme ; le lieu et la date d'un jalon.

L'écran de bilan gagne un bloc « Ouvert » — « 42 km de route neuve · 1 énigme ·
1 jalon » — et le brouillard brûle sur la carte du trajet lui-même, le long de
la route que vous venez de faire. Vos découvertes apparaissent aussi dans votre
profil public, sous les succès, chacune avec un mot pour sa rareté et derrière
le même interrupteur. Et « Partager l'Atlas » donne maintenant une image de
votre carte : le même brouillard, les mêmes couloirs, vos sceaux. Ce que vous
n'avez pas trouvé n'y est pas.
```

### Italian

```
L'ATLANTE

La scheda «Mappa» ora è «Atlante», e il mondo lì dentro parte chiuso. Nebbia
opaca — e le tue strade bruciate
dentro come una mappa viva: vie, nomi, il mare. Tutto quello che hai registrato
c'è già dal primo avvio; l'app lo ricostruisce in background. Il foglio dice
quanto hai aperto, e «1 910 km aperti» è la lunghezza dei corridoi aperti, non
la somma dei tuoi viaggi: il centesimo passaggio nella tua via non apre nulla.

SCOPERTE

Finito il viaggio, il telefono legge la traccia registrata e ti dice davanti a
cosa sei passato: segreti d'autore, enigmi costruiti su dati aperti (un faro,
un passo, un traghetto, una diga, un valico di frontiera) e traguardi della tua
geografia — la prima regione, il tuo punto più a est, in alta montagna, sotto
il livello del mare, tre regioni in un giorno, un confine, un passo di notte.
Ogni scoperta mette un sigillo sull'Atlante. In marcia non si calcola e non si
mostra niente: rincorrere una scoperta non è roba da strada.

IL DIARIO DELL'ESPLORATORE

Tira su il foglio dell'Atlante: quanto hai aperto e le regioni con
la data della prima volta che ci sei entrato, e tutti i tuoi sigilli in
griglia. Tocca
un sigillo per la sua scheda: la storia di un segreto con «trovato da N, il
primo è stato …»; la riga e il cerchio di un enigma; il luogo e la data di un
traguardo.

La schermata di riepilogo guadagna il blocco «Aperto» — «42 km di strada nuova
· 1 enigma · 1 traguardo» — e la nebbia brucia sulla mappa del viaggio stesso
lungo la strada appena fatta. Le scoperte si vedono anche nel profilo pubblico,
sotto i risultati, ognuna con una parola per la sua rarità e dietro lo stesso
interruttore. E «Condividi l'Atlante» ora consegna un'immagine della tua mappa:
la stessa nebbia, gli stessi corridoi, i tuoi sigilli. Ciò che non hai trovato
non c'è.
```

### Polish

```
ATLAS

Zakładka „Mapa” to teraz „Atlas”, a świat na niej jest zamknięty.
Nieprzezroczysta mgła — i twoje
własne drogi wypalone w niej jak żywa mapa: ulice, nazwy, morze. Wszystko, co
kiedykolwiek nagrałeś, jest tam od pierwszego uruchomienia; aplikacja składa to
w tle. Arkusz mówi, ile odkryłeś, a „1 910 km odkrytych” to długość odkrytych
korytarzy, nie suma przejazdów: setny przejazd twoją ulicą nie odkrywa już nic.

ZNALEZISKA

Po zakończeniu trasy telefon czyta nagrany ślad i mówi, obok czego
przejechałeś: autorskie sekrety, zagadki zbudowane z danych otwartych
(latarnia, przełęcz, prom, zapora, przejście graniczne) oraz kamienie milowe
własnej geografii — pierwszy region, najdalszy punkt na wschodzie, wysoko w
górach, poniżej poziomu morza, trzy regiony jednego dnia, granica, nocna
przełęcz. Każde znalezisko stawia na Atlasie pieczęć. W trakcie jazdy nic się
nie liczy i nic nie pokazuje: gonienie za znaleziskiem nie należy do drogi.

DZIENNIK ODKRYWCY

Pociągnij arkusz Atlasu w górę — jest tam ile odkryłeś i regiony z
datą pierwszego wjazdu, oraz wszystkie twoje pieczęcie w siatce.
Dotknięcie pieczęci otwiera jej kartę: historia sekretu i „znalazło N osób,
pierwszy był …”; linijka i okrąg zagadki; miejsce i data kamienia milowego.

Na ekranie podsumowania pojawił się blok „Odkryte” — „42 km nowej drogi · 1
zagadka · 1 kamień milowy” — a mgła wypala się z mapy samej trasy wzdłuż
przejechanej właśnie drogi. Znaleziska widać też w profilu publicznym, pod
osiągnięciami, każde ze słowem opisującym rzadkość i pod tym samym
przełącznikiem. A „Udostępnij Atlas” oddaje teraz obrazek twojej mapy: ta sama
mgła, te same korytarze, twoje pieczęcie. Tego, czego nie znalazłeś, tam nie ma.
```

### Indonesian

```
ATLAS

Tab "Peta" kini menjadi "Atlas", dan dunianya dimulai dalam keadaan tertutup.
Kabut pekat — dan di
dalamnya jalan-jalan Anda sendiri, terbakar menembus kabut sebagai peta hidup:
nama jalan, nama tempat, laut. Semua yang pernah Anda rekam sudah ada sejak
peluncuran pertama; aplikasi menyusunnya di latar belakang. Lembarnya
menyebutkan berapa yang terbuka, dan "1.910 km terbuka" adalah panjang koridor
yang terbuka, bukan jumlah perjalanan: lintasan keseratus di jalan Anda sendiri
tidak membuka apa pun.

TEMUAN

Setelah perjalanan selesai, ponsel membaca rekaman jejak dan memberi tahu apa
saja yang Anda lewati: rahasia buatan kami, teka-teki dari data terbuka (mercu
suar, celah gunung, feri, bendungan, pos perbatasan) dan tonggak
geografi Anda sendiri — wilayah pertama, titik paling timur, tinggi di
pegunungan, di bawah permukaan laut, tiga wilayah dalam sehari, perbatasan,
celah gunung di malam hari. Setiap temuan menaruh satu segel di Atlas. Saat
berkendara tidak ada yang dihitung dan tidak ada yang ditampilkan: mengejar
temuan bukan urusan di jalan.

JURNAL PENJELAJAH

Tarik lembar Atlas ke atas — ada berapa yang terbuka dan daftar
wilayah dengan tanggal Anda pertama masuk, serta semua segel Anda dalam kisi.
Ketuk sebuah segel untuk membuka
kartunya: kisah sebuah rahasia dengan "ditemukan N orang, yang pertama …";
baris dan lingkaran sebuah teka-teki; tempat dan tanggal sebuah tonggak.

Layar ringkasan mendapat blok "Terbuka" — "42 km jalan baru · 1 teka-teki · 1
tonggak" — dan kabut terbakar dari peta perjalanan itu sendiri di sepanjang
jalan yang baru saja Anda tempuh. Temuan juga tampil di profil publik Anda, di
bawah pencapaian, masing-masing dengan satu kata tentang kelangkaannya dan di
balik sakelar yang sama. Dan "Bagikan Atlas" kini memberikan gambar peta Anda:
kabut yang sama, koridor yang sama, segel Anda. Yang belum ditemukan tidak ikut.
```

### Turkish

```
ATLAS

"Harita" sekmesi artık "Atlas" ve üzerindeki dünya kapalı başlıyor. Işık
geçirmeyen bir sis — ve sisin
içinde kendi yollarınız, canlı bir harita gibi yakılmış: sokaklar, adlar,
deniz. Bugüne kadar kaydettiğiniz her şey ilk açılıştan itibaren orada;
uygulama bunu arka planda toplar. Sayfa ne kadarını açtığınızı söyler ve
"1 910 km açıldı" açılan koridorların uzunluğudur, yolculuklarınızın toplamı
değil: kendi sokağınızdan yüzüncü geçiş hiçbir şey açmaz.

BULUNTULAR

Yolculuk bittikten sonra telefon kaydedilen izi okur ve neyin yanından
geçtiğinizi söyler: bizim gizemlerimiz, açık verilerden kurulmuş bilmeceler
(deniz feneri, geçit, feribot, baraj, sınır kapısı) ve kendi
coğrafyanızın dönüm noktaları — ilk bölge, en doğudaki noktanız, dağların
yükseğinde, deniz seviyesinin altında, bir günde üç bölge, bir sınır, gece
geçilen bir geçit. Her buluntu Atlas'a bir mühür basar. Yol giderken hiçbir şey
hesaplanmaz ve hiçbir şey gösterilmez: buluntunun peşine düşmek yolun işi
değildir.

KÂŞİF GÜNLÜĞÜ

Atlas sayfasını yukarı çekin: ne kadarını açtığınız ve ilk giriş
tarihleriyle bölgeler, ve tüm mühürleriniz bir ızgarada. Bir mühre
dokunun, kartı açılsın: bir gizemin hikâyesi ve "N kişi buldu, ilk bulan …";
bir bilmecenin satırı ve dairesi; bir dönüm noktasının yeri ve tarihi.

Özet ekranına "Açıldı" bloğu geldi — "42 km yeni yol · 1 bilmece · 1 dönüm
noktası" — ve sis, yolculuğun kendi haritasında az önce gittiğiniz yol boyunca
yanar. Buluntular herkese açık profilinizde de görünür, başarıların altında,
her biri ne kadar nadir olduğunu söyleyen bir kelimeyle ve aynı görünürlük
anahtarının arkasında. "Atlas'ı paylaş" ise artık haritanızın resmini verir:
aynı sis, aynı koridorlar, sizin mühürleriniz. Bulmadığınız şey resimde yok.
```

### Filipino → вставлять в слот **Finnish**

```
ANG ATLAS

Ang tab na "Mapa" ay "Atlas" na, at nakasara ang mundo roon sa simula.
Makapal na hamog — at sa
loob nito ang sarili mong mga kalsada, nasunog papasok bilang buhay na mapa:
mga kalye, mga pangalan, ang dagat. Nandoon na mula sa unang buksan ang lahat
ng naitala mo kailanman; binubuo ito ng app sa likod. Sinasabi ng sheet kung
gaano na kalawak ang nabuksan, at ang "1,910 km ang bukas" ay haba ng mga
bukas na koridor, hindi kabuuan ng mga biyahe: ang ika-isang daang pagdaan sa
sarili mong kalye ay wala nang binubuksan.

MGA NATUKLASAN

Pagkatapos ng biyahe, binabasa ng telepono ang naitalang ruta at sinasabi kung
ano ang nadaanan mo: mga lihim na gawa namin, mga palaisipang hango sa bukas na
datos (parola, tuktok ng daan, lantsa, dam, hangganan) at mga hangganan ng
sarili mong heograpiya — unang rehiyon, pinakasilangang punto mo, mataas sa
bundok, mas mababa sa dagat, tatlong rehiyon sa isang araw, isang hangganan,
isang tuktok sa gabi. Bawat natuklasan ay naglalagay ng tatak sa Atlas. Habang
nagmamaneho, walang kinukuwenta at walang ipinapakita: hindi sa kalsada ang
paghahabol sa natuklasan.

TALAARAWAN NG MANANALIKSIK

Hilahin pataas ang sheet ng Atlas — kung gaano kalawak ang
nabuksan at ang mga rehiyon na may petsa ng unang pagpasok, at lahat ng tatak mo
sa isang grid. Pindutin ang tatak para sa
card nito: ang kuwento ng lihim at "N ang nakakita, una ay …"; ang linya at
bilog ng palaisipan; ang lugar at petsa ng hangganan.

May bagong bloke ang buod ng biyahe — "Nabuksan": "42 km na bagong daan · 1
palaisipan · 1 hangganan" — at nasusunog ang hamog sa mismong mapa ng biyahe sa
kahabaan ng kababiyahe mo lang. Lumalabas din ang mga natuklasan sa pampublikong
profile mo, sa ilalim ng mga tagumpay, bawat isa may salita para sa bihira nito
at nasa likod ng parehong switch. At ang "Ibahagi ang Atlas" ay nagbibigay na ng
larawan ng mapa mo: parehong hamog, parehong koridor, ang mga tatak mo. Wala
roon ang hindi mo pa natutuklasan.
```

### Ukrainian

```
АТЛАС

Вкладка «Карта» стала «Атласом», і світ на ній закритий. Непрозора мла — і ваші
власні дороги, пропалені в ній живою
картою: вулиці, назви, море. Усе, що ви коли-небудь записали, вже всередині з
першого запуску: застосунок розбирає бібліотеку у фоні. У аркуші видно, скільки
відкрито, і «1 910 км відкрито» — це довжина відкритих коридорів, а не сума
поїздок: сотий проїзд своєю вулицею не відкриває нічого.

ЗНАХІДКИ

Після фінішу телефон сам розбирає записаний трек і каже, повз що ви проїхали:
авторські секрети, загадки за відкритими даними (маяк, перевал, пором, гребля,
прикордонний пост) і віхи власної географії — перший регіон,
найсхідніша точка, високо в горах, нижче рівня моря, три регіони за день,
кордон, нічний перевал. Кожна знахідка ставить на «Атлас» печатку. На ходу
нічого не рахується й нічого не показується: гнатися за знахідкою на дорозі не
треба.

ЩОДЕННИК ПЕРШОВІДКРИВАЧА

Потягніть аркуш «Атласа» вгору — скільки відкрито й регіони з
датою першого в'їзду, та усі ваші печатки сіткою. Дотик до печатки відкриває
картку: історія секрету та «знайшли N людей, першим — ім'я»; рядок і коло загадки;
місце й дата віхи.

На екрані підсумків з'явився блок «Відкрито» — «42 км нового шляху · 1 загадка
· 1 віха», — а туман вигоряє з карти самої поїздки вздовж щойно проїханого
шляху. Знахідки видно й у публічному профілі, під досягненнями, з підписом
рідкісності та під тим самим перемикачем видимості. А «Поділитися Атласом»
віддає картинку вашої карти: той самий туман, ті самі коридори, ваші печатки.
Незнайденого на ній немає.
```

### Portuguese (Brazil)

```
O ATLAS

A aba “Mapa” agora é “Atlas”, e o mundo nela começa fechado. Névoa opaca —
e, dentro dela, as suas
estradas queimadas como um mapa vivo: ruas, nomes, o mar. Tudo o que você já
gravou está lá desde a primeira abertura; o app monta isso em segundo plano. A
folha diz quanto você abriu, e “1.910 km abertos” é o comprimento dos
corredores abertos, não a soma das viagens: a centésima passada pela sua
própria rua não abre mais nada.

DESCOBERTAS

Quando a viagem termina, o telefone lê o traçado gravado e conta por perto de
que você passou: segredos nossos, enigmas montados com dados abertos (farol,
passo de montanha, balsa, barragem, posto de fronteira) e marcos da sua própria
geografia — a primeira região, seu ponto mais a leste, alto na serra, abaixo do
nível do mar, três regiões num dia, uma fronteira, um passo à noite. Cada
descoberta põe um selo no Atlas. Em movimento nada é calculado e nada aparece:
correr atrás de uma descoberta não é assunto de estrada.

O DIÁRIO DO EXPLORADOR

Puxe a folha do Atlas para cima: quanto você abriu e as
regiões com a data em que entrou pela primeira vez, e todos os seus selos em uma
grade. Toque num selo para ver a ficha: a história de um segredo com
“N pessoas encontraram, o primeiro foi …”; a linha e o círculo de um enigma; o
lugar e a data de um marco.

A tela de resumo ganhou o bloco “Aberto” — “42 km de estrada nova · 1 enigma ·
1 marco” — e a névoa queima no mapa da própria viagem ao longo do caminho que
você acabou de fazer. As descobertas também aparecem no seu perfil público,
abaixo das conquistas, cada uma com uma palavra para a raridade e atrás do
mesmo botão de visibilidade. E “Compartilhar o Atlas” entrega agora uma imagem
do seu mapa: a mesma névoa, os mesmos corredores, os seus selos. O que você não
achou não está lá.
```

### Kazakh — В КАРТОЧКЕ ЭТОЙ ЛОКАЛИ НЕТ, вставлять некуда

```
АТЛАС

«Карта» қойындысы «Атлас» болды, ондағы әлем жабық тұрады. Мөлдір емес тұман,
үстінде тек аймақ шекаралары, ал ішінде — тірі карта болып күйдіріле
салынған өз жолдарыңыз. Бұрын жазғанның бәрі алғашқы іске қосудан бері сонда.

ОЛЖАЛАР

Сапар аяқталған соң телефон жазылған тректі өзі талдап, немен қатар өткеніңізді
айтады: авторлық құпиялар, ашық деректерден жасалған жұмбақтар (шамшырақ,
асу, паром, бөген, шекара бекеті) және өз географияңыздың белестері. Әр
олжа «Атласқа» мөр басады. Жол үстінде ештеңе есептелмейді және көрсетілмейді.

АШУШЫ КҮНДЕЛІГІ

«Атлас» парағын жоғары тартыңыз: қанша ашылғаны, барлық мөрлеріңіз торкөзде
және жақын маңдағы үшке дейін шешілмеген жұмбақ. Мөрді бассаңыз — карточкасы.
Қорытынды экранында «Ашылды» блогы пайда болды, ал «Атласпен бөлісу» енді
картаңыздың суретін береді.
```

---

## 2. Промо-текст (170)

Один и тот же смысл в двенадцати локалях. Лимит — 170 знаков, проверено
`wc -m`.

**English (U.S.)**

```
Your map starts closed. Your own roads burn the fog away, and after the finish the phone says what you drove past: a lighthouse, a pass, your first region.
```

**Russian**

```
Карта закрыта мглой, и открывают её ваши дороги. А после финиша телефон говорит, мимо чего вы проехали: маяк, перевал, первый регион.
```

**German**

```
Ihre Karte ist zu. Ihre eigenen Straßen brennen den Nebel weg, und nach der Fahrt sagt das Telefon, woran Sie vorbeikamen: Leuchtturm, Pass, erste Region.
```

**Spanish (Spain)**

```
Tu mapa empieza cerrado. Tus carreteras queman la niebla y, al terminar, el teléfono dice por delante de qué pasaste: un faro, un puerto, tu primera región.
```

**French**

```
Votre carte est fermée. Vos routes brûlent le brouillard, et à l'arrivée le téléphone dit devant quoi vous êtes passé : un phare, un col, une première région.
```

**Italian**

```
La tua mappa parte chiusa. Le tue strade bruciano la nebbia e, a viaggio finito, il telefono dice davanti a cosa sei passato: un faro, un passo, la prima regione.
```

**Polish**

```
Twoja mapa jest zamknięta. Twoje drogi wypalają mgłę, a po trasie telefon mówi, obok czego przejechałeś: latarnia, przełęcz, pierwszy region.
```

**Indonesian**

```
Peta Anda mulai tertutup. Jalan Anda sendiri membakar kabutnya, dan setelah tiba ponsel menyebut apa yang Anda lewati: mercu suar, celah gunung, wilayah pertama.
```

**Turkish**

```
Haritanız kapalı başlar. Kendi yollarınız sisi yakar ve yolculuk bitince telefon neyin yanından geçtiğinizi söyler: deniz feneri, geçit, ilk bölgeniz.
```

**Filipino → слот Finnish**

```
Nakasara ang mapa mo sa simula. Ang mga kalsada mo ang sumusunog sa hamog, at pagkatapos ng biyahe sasabihin ng telepono ang nadaanan mo: parola, tuktok, rehiyon.
```

**Ukrainian**

```
Карта закрита млою, і відкривають її ваші дороги. А після фінішу телефон каже, повз що ви проїхали: маяк, перевал, перший регіон.
```

**Portuguese (Brazil)**

```
Seu mapa começa fechado. Suas estradas queimam a névoa e, no fim da viagem, o telefone diz por perto de que você passou: um farol, um passo, a primeira região.
```

---

## 3. Что проверить в карточке перед «Submit»

- [ ] «What's New» заполнен во **всех двенадцати** локалях карточки. Филиппинский
      текст — в слот **Finnish**. Казахский блок пропустить, локали нет.
- [ ] Рейтинг 13+ на месте (лента с реакциями = «Social Media»).
- [ ] **App Privacy** — без изменений с 0.6.7 (`docs/releases/app-privacy.md`).
      Новых типов данных версия не заводит: каталог секретов анонимен (только
      усечённые хеши, ни координат, ни имён), находки уезжают на сервер только
      при включённом Cloud Sync, слой открытого живёт на телефоне.
      `PrivacyInfo.xcprivacy` не меняется.
- [ ] Notes для ревьюера — блок v0.7.0 из `../app-review-notes.md`.
- [ ] Скриншоты: «Атлас» с туманом и карточка находки — **желательны, но не
      обязательны** (прежний набор остаётся валидным). Если снимать — снимать
      на телефоне с непустой библиотекой: на чистой базе «Атлас» это ровный
      туман, и кадр ничего не рассказывает.
- [ ] Бэкенд выкачен **до** сабмита — см. `checklist.md` §1. Правило Cloudflare
      в этот раз не нужно: новых публичных веб-путей нет.
