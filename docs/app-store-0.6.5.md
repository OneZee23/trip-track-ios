# App Store Connect — 0.6.5

Всё, что нужно вставить при выкладке билда **0.6.5 (57)**. Заметки для ревьюера —
в [app-review-notes.md](app-review-notes.md), секция «current submission».

**В карточке ДВЕНАДЦАТЬ локализаций, и «What's New» обязателен в каждой.**
Сабмит 0.6.2 отклонили ровно за одну пропущенную.

Релиз **не чисто клиентский**: бэкенд деплоится первым (таблица `trip_checkpoint`,
три колонки у `trip_photo`). Порядок безопасен в обе стороны: старый сервер
молча игнорирует новые ключи, новый клиент без них не падает — но отметки не
доедут до второго телефона, пока сервер не выкачен.

Ключевые слова, подзаголовок и описание не меняются. Лимиты: «What's New» — 4000,
промо-текст — 170.

---

## 1. What's New

### English (U.S.)

```
HOW LONG TO THE SEA?

Mark points on a drive and see how long — and how far — it took to reach them.
Tap the flag on the Lock Screen while you drive; no need to pick up the phone.
On a recorded trip, tap the route on the full-screen map. Each checkpoint
shows time from the start and the leg from the previous one, and names itself
after the place: "Dzhubga · 1:30". Drove the same road there and back? You
choose which pass you meant.

PHOTOS LAND ON THE ROUTE

Take a photo on the way and it appears on the map right where you took it —
as the photo, with a caption. Nothing to arrange by hand.

THE TRACK SHOWS WHAT HAPPENED

Turns, loops, U-turns and courtyard manoeuvres, without cut corners. The
odometer has not changed by a metre — that is covered by tests, not promises.

PAUSE MEANS PAUSE

A stop at a shop no longer splits a trip in two. Reminder mode now asks and
waits instead of ending the trip on its own. Long drives also run cooler.

MOMENTS

Every trip now tells its road in order: start, checkpoints with the photos taken there, finish — with the time of day on the left and "from start" under each. Tap a checkpoint on the map and the page scrolls to it; the replay pauses at every checkpoint for a moment.
```

### Russian

```
ДО МОРЯ — ЗА СКОЛЬКО?

Ставьте отметки на маршруте и смотрите, сколько времени и километров до них.
На ходу — флажок на экране блокировки, телефон доставать не нужно. На
записанной поездке — нажатие по маршруту на полноэкранной карте. У каждой
отметки два числа: от старта и отрезок от предыдущей, а имя она узнаёт сама:
«Джубга · 1:30». Проехали одной дорогой туда и обратно? Выберете, какой проезд
имели в виду.

ФОТОГРАФИИ ВСТАЮТ НА МАРШРУТ

Сняли по дороге — снимок появился на карте там, где вы его сделали. Снимком,
с подписью. Ничего не нужно расставлять руками.

ТРЕК ПОКАЗЫВАЕТ ТО, ЧТО БЫЛО

Повороты, круги, развороты, заезды по дворам — без срезанных углов. Одометр
не изменился ни на метр: это проверено тестами, а не обещанием.

ПАУЗА — ЭТО ПАУЗА

Остановка у магазина больше не рвёт поездку надвое. Режим «напоминания»
спрашивает и ждёт, а не завершает сам. Долгие поездки греют телефон меньше.

МОМЕНТЫ

Каждая поездка теперь рассказывает дорогу по порядку: старт, отметки со снимками, снятыми там же, финиш — время суток слева, «от старта» под каждой. Нажали на отметку на карте — страница прокрутится к ней; реплей у каждой отметки на пару секунд останавливается.
```

### German

```
WIE LANGE BIS ZUM MEER?

Setze Markierungen auf der Fahrt und sieh, wie lange – und wie weit – es bis
dorthin war. Unterwegs: die Flagge auf dem Sperrbildschirm, ohne das Handy in
die Hand zu nehmen. Bei einer aufgezeichneten Fahrt: auf die Route in der
Vollbildkarte tippen. Jede Markierung zeigt die Zeit ab Start und den Abschnitt
seit der vorigen und benennt sich selbst nach dem Ort: „Dschubga · 1:30“.
Dieselbe Straße hin und zurück? Du wählst, welche Fahrt gemeint war.

FOTOS LANDEN AUF DER ROUTE

Unterwegs fotografiert – das Bild erscheint auf der Karte genau dort, wo es
entstand. Als Foto, mit Beschriftung. Nichts von Hand anordnen.

DIE STRECKE ZEIGT, WAS WAR

Kurven, Kreisel, Wendemanöver, Hofeinfahrten – ohne abgeschnittene Ecken. Der
Kilometerstand hat sich um keinen Meter geändert: durch Tests abgesichert.

PAUSE HEISST PAUSE

Ein Halt am Laden teilt die Fahrt nicht mehr in zwei. Der Erinnerungsmodus
fragt und wartet, statt selbst zu beenden. Lange Fahrten laufen kühler.

MOMENTE

Jede Fahrt erzählt ihre Strecke jetzt der Reihe nach: Start, Markierungen mit den dort aufgenommenen Fotos, Ziel – links die Uhrzeit, darunter „ab Start“. Tippe eine Markierung auf der Karte an und die Seite springt dorthin; die Wiedergabe hält an jeder Markierung kurz an.
```

### Spanish (Spain)

```
¿CUÁNTO HASTA EL MAR?

Marca puntos en el viaje y mira cuánto tiempo —y cuántos kilómetros— tardaste
en llegar. En marcha: la bandera en la pantalla de bloqueo, sin coger el
teléfono. En un viaje grabado: toca la ruta en el mapa a pantalla completa.
Cada marca muestra el tiempo desde el inicio y el tramo desde la anterior, y
se nombra sola por el lugar: «Dzhubga · 1:30». ¿La misma carretera de ida y
vuelta? Tú eliges qué paso querías.

LAS FOTOS SE COLOCAN EN LA RUTA

Haz una foto por el camino y aparecerá en el mapa justo donde la tomaste. Como
foto, con pie. Nada que ordenar a mano.

EL TRACK MUESTRA LO QUE PASÓ

Curvas, rotondas, cambios de sentido, maniobras en patios: sin esquinas
recortadas. El cuentakilómetros no cambió ni un metro: lo cubren los tests.

PAUSA SIGNIFICA PAUSA

Parar en una tienda ya no parte el viaje en dos. El modo recordatorio pregunta
y espera en vez de terminar solo. Los viajes largos calientan menos.

MOMENTOS

Cada viaje cuenta ahora su camino en orden: salida, marcas con las fotos hechas allí, llegada; la hora a la izquierda y «desde la salida» debajo de cada una. Toca una marca en el mapa y la página baja hasta ella; la repetición se detiene un instante en cada marca.
```

### French

```
COMBIEN DE TEMPS JUSQU'À LA MER ?

Posez des repères sur le trajet et voyez combien de temps — et de kilomètres —
il a fallu pour les atteindre. En route : le drapeau sur l'écran verrouillé,
sans prendre le téléphone. Sur un trajet enregistré : touchez l'itinéraire sur
la carte plein écran. Chaque repère affiche le temps depuis le départ et le
segment depuis le précédent, et se nomme d'après le lieu : « Djoubga · 1:30 ».
Même route à l'aller et au retour ? Vous choisissez le passage voulu.

LES PHOTOS SE PLACENT SUR L'ITINÉRAIRE

Une photo en chemin apparaît sur la carte là où vous l'avez prise. En photo,
avec légende. Rien à ranger à la main.

LA TRACE MONTRE CE QUI S'EST PASSÉ

Virages, ronds-points, demi-tours, manœuvres dans les cours : sans angles
coupés. Le compteur n'a pas changé d'un mètre — les tests le garantissent.

PAUSE VEUT DIRE PAUSE

Un arrêt au magasin ne coupe plus le trajet en deux. Le mode rappel demande et
attend au lieu de terminer seul. Les longs trajets chauffent moins.

MOMENTS

Chaque trajet raconte désormais sa route dans l'ordre : départ, repères avec les photos prises sur place, arrivée — l'heure à gauche, « depuis le départ » sous chacun. Touchez un repère sur la carte et la page défile jusqu'à lui ; le replay marque une pause à chaque repère.
```

### Italian

```
QUANTO MANCA AL MARE?

Segna punti sul percorso e scopri quanto tempo — e quanti chilometri — ci sono
voluti per arrivarci. In marcia: la bandierina sulla schermata di blocco, senza
prendere il telefono. Su un viaggio registrato: tocca il percorso sulla mappa a
schermo intero. Ogni segnalibro mostra il tempo dalla partenza e il tratto dal
precedente, e prende il nome dal luogo: «Dzhubga · 1:30». Stessa strada
all'andata e al ritorno? Scegli tu quale passaggio intendevi.

LE FOTO SI POSANO SUL PERCORSO

Scatta lungo la strada e la foto appare sulla mappa dove l'hai fatta. Come
foto, con didascalia. Niente da sistemare a mano.

LA TRACCIA MOSTRA COM'È ANDATA

Curve, rotonde, inversioni, manovre nei cortili: senza angoli tagliati. Il
contachilometri non è cambiato di un metro: lo garantiscono i test.

PAUSA VUOL DIRE PAUSA

Una sosta al negozio non spezza più il viaggio in due. La modalità promemoria
chiede e aspetta invece di chiudere da sola. I viaggi lunghi scaldano meno.

MOMENTI

Ogni viaggio ora racconta la strada in ordine: partenza, punti con le foto scattate lì, arrivo — l'ora a sinistra e «dalla partenza» sotto ciascuno. Tocca un punto sulla mappa e la pagina scorre fino a lui; il replay si ferma un attimo a ogni punto.
```

### Polish

```
ILE DO MORZA?

Stawiaj znaczniki na trasie i sprawdzaj, ile czasu — i kilometrów — zajął
dojazd. W drodze: flaga na ekranie blokady, bez sięgania po telefon. Na
nagranej podróży: dotknij trasy na pełnoekranowej mapie. Każdy znacznik
pokazuje czas od startu i odcinek od poprzedniego, a nazwę nadaje sobie sam od
miejsca: „Dżubga · 1:30”. Ta sama droga tam i z powrotem? Wybierasz, który
przejazd miałeś na myśli.

ZDJĘCIA TRAFIAJĄ NA TRASĘ

Zrób zdjęcie po drodze, a pojawi się na mapie dokładnie tam, gdzie powstało.
Jako zdjęcie, z podpisem. Nic nie trzeba układać ręcznie.

ŚLAD POKAZUJE, JAK BYŁO

Zakręty, ronda, zawracanie, manewry na podwórkach — bez ściętych rogów.
Licznik nie zmienił się o metr: pilnują tego testy.

PAUZA TO PAUZA

Postój w sklepie nie dzieli już podróży na dwie. Tryb przypomnień pyta i czeka
zamiast kończyć sam. Długie trasy mniej grzeją telefon.

MOMENTY

Każda podróż opowiada teraz drogę po kolei: start, punkty ze zdjęciami zrobionymi na miejscu, meta — godzina po lewej, „od startu” pod każdym. Dotknij punktu na mapie, a strona przewinie się do niego; odtwarzanie zatrzymuje się na chwilę przy każdym punkcie.
```

### Indonesian

```
BERAPA LAMA KE LAUT?

Tandai titik di perjalanan dan lihat berapa lama — dan berapa jauh — untuk
sampai ke sana. Saat berkendara: bendera di Lock Screen, tanpa memegang
ponsel. Di perjalanan yang sudah terekam: ketuk rute di peta layar penuh.
Setiap penanda menunjukkan waktu sejak awal dan ruas dari penanda sebelumnya,
dan menamai dirinya dari tempatnya: «Dzhubga · 1:30». Jalan yang sama pergi
dan pulang? Kamu yang memilih lintasan mana.

FOTO TERPASANG DI RUTE

Ambil foto di jalan dan foto itu muncul di peta tepat di tempat kamu
mengambilnya. Sebagai foto, dengan keterangan. Tidak ada yang perlu diatur.

JALUR MENUNJUKKAN YANG SEBENARNYA

Belokan, bundaran, putar balik, manuver di halaman — tanpa sudut terpotong.
Odometer tidak berubah semeter pun: dijamin oleh pengujian.

JEDA BERARTI JEDA

Berhenti di toko tidak lagi membelah perjalanan jadi dua. Mode pengingat
bertanya dan menunggu, bukan mengakhiri sendiri. Perjalanan panjang lebih dingin.

MOMEN

Setiap perjalanan kini menceritakan jalannya secara berurutan: mulai, titik tanda dengan foto yang diambil di sana, selesai — jam di kiri, "dari awal" di bawah masing-masing. Ketuk titik di peta dan halaman bergulir ke sana; pemutaran ulang berhenti sejenak di setiap titik.
```

### Turkish

```
DENİZE NE KADAR SÜRDÜ?

Yolculukta noktalar işaretle; oraya ne kadar sürede ve kaç kilometrede
vardığını gör. Sürüşte: kilit ekranındaki bayrak, telefonu eline almadan.
Kayıtlı yolculukta: tam ekran haritada rotaya dokun. Her işaret başlangıçtan
geçen süreyi ve önceki işaretten bu yana bölümü gösterir, adını da yerden
alır: «Dzhubga · 1:30». Aynı yolu gidip geldin mi? Hangi geçişi kastettiğini
sen seçersin.

FOTOĞRAFLAR ROTAYA YERLEŞİR

Yolda çektiğin fotoğraf haritada tam çektiğin yerde belirir. Fotoğraf olarak,
açıklamasıyla. Elle düzenlenecek bir şey yok.

İZ, OLANI GÖSTERİR

Virajlar, dönel kavşaklar, U dönüşleri, avlu manevraları — köşeler kesilmeden.
Kilometre sayacı bir metre bile değişmedi; testlerle güvence altında.

DURAKLATMA DURAKLATMADIR

Markette mola artık yolculuğu ikiye bölmüyor. Hatırlatma modu kendi başına
bitirmek yerine sorup bekliyor. Uzun yolculuklar daha az ısınıyor.

ANLAR

Her yolculuk artık yolunu sırasıyla anlatıyor: başlangıç, orada çekilen fotoğraflarla işaretler, bitiş — solda saat, her birinin altında "başlangıçtan". Haritada bir işarete dokunun, sayfa ona kayar; tekrar oynatma her işarette kısa bir an durur.
```

### Filipino

```
GAANO KATAGAL PAPUNTANG DAGAT?

Maglagay ng mga marka sa biyahe at tingnan kung gaano katagal — at gaano
kalayo — bago ka nakarating. Habang nagmamaneho: ang bandila sa Lock Screen,
hindi na kailangang hawakan ang telepono. Sa naitalang biyahe: i-tap ang ruta
sa full-screen na mapa. Ipinapakita ng bawat marka ang oras mula sa simula at
ang bahagi mula sa nauna, at pinapangalanan ang sarili ayon sa lugar:
«Dzhubga · 1:30». Parehong daan pabalik? Ikaw ang pipili kung aling daan.

NAPUPUNTA ANG MGA LARAWAN SA RUTA

Kumuha ng litrato sa daan at lalabas ito sa mapa kung saan mo ito kinuha.
Bilang larawan, may caption. Walang aayusin nang mano-mano.

IPINAPAKITA NG TRACK ANG NANGYARI

Mga liko, rotonda, U-turn, maniobra sa mga bakuran — walang pinutol na sulok.
Hindi nagbago ang odometer kahit isang metro: sinisiguro ng mga test.

ANG PAUSE AY PAUSE

Ang paghinto sa tindahan ay hindi na naghahati ng biyahe. Ang reminder mode ay
nagtatanong at naghihintay sa halip na tapusin nang mag-isa. Mas malamig ang
mahahabang biyahe.

MGA SANDALI

Bawat biyahe ay nagkukuwento na ng daan nito nang sunud-sunod: simula, mga marka kasama ang mga larawang kinunan doon, dulo — oras sa kaliwa, "mula sa simula" sa ilalim ng bawat isa. I-tap ang marka sa mapa at dadalhin ka ng pahina roon; saglit na humihinto ang replay sa bawat marka.
```

### Ukrainian

```
ДО МОРЯ — ЗА СКІЛЬКИ?

Ставте позначки на маршруті й дивіться, скільки часу і кілометрів до них.
У дорозі — прапорець на екрані блокування, телефон діставати не треба. На
записаній поїздці — торкання маршруту на повноекранній карті. У кожної
позначки два числа: від старту та відрізок від попередньої, а ім'я вона
дізнається сама: «Джубга · 1:30». Проїхали однією дорогою туди й назад?
Оберете, який проїзд мали на увазі.

ФОТОГРАФІЇ СТАЮТЬ НА МАРШРУТ

Зняли дорогою — знімок з'явився на карті там, де ви його зробили. Знімком, з
підписом. Нічого не треба розставляти руками.

ТРЕК ПОКАЗУЄ ТЕ, ЩО БУЛО

Повороти, кола, розвороти, заїзди у двори — без зрізаних кутів. Одометр не
змінився ні на метр: це перевірено тестами.

ПАУЗА — ЦЕ ПАУЗА

Зупинка біля магазину більше не рве поїздку надвоє. Режим «нагадування»
запитує й чекає, а не завершує сам. Довгі поїздки менше гріють телефон.

МОМЕНТИ

Кожна поїздка тепер розповідає дорогу по порядку: старт, позначки зі знімками, зробленими там само, фініш — час ліворуч, «від старту» під кожною. Натисніть позначку на мапі — сторінка прокрутиться до неї; повтор на кожній позначці на мить зупиняється.
```

### Kazakh

```
ТЕҢІЗГЕ ДЕЙІН — ҚАНША УАҚЫТ?

Бағдарға белгілер қойып, оларға дейін қанша уақыт пен километр кеткенін
көріңіз. Жолда — құлып экранындағы жалауша, телефонды қолға алудың қажеті
жоқ. Жазылған сапарда — толық экрандық картада бағдарды түртіңіз. Әр белгіде
екі сан: стартан бері және алдыңғысынан бергі аралық, атын өзі табады:
«Джубга · 1:30». Бір жолмен барып-қайттыңыз ба? Қай өтуін меңзегеніңізді
өзіңіз таңдайсыз.

ФОТОЛАР БАҒДАРҒА ОРНАЛАСАДЫ

Жолда суретке түсірдіңіз — сурет картада дәл түсірген жеріңізде пайда
болады. Сурет күйінде, жазуымен. Қолмен реттейтін ештеңе жоқ.

ТРЕК БОЛҒАНЫН КӨРСЕТЕДІ

Бұрылыстар, айналмалар, кері бұрылу, аулаға кіру — бұрыштары кесілмеген.
Одометр бір метрге де өзгерген жоқ: бұл тесттермен тексерілген.

ПАУЗА — ПАУЗА

Дүкен жанындағы аялдама сапарды енді екіге бөлмейді. «Еске салу» режимі өзі
аяқтамай, сұрап күтеді. Ұзақ сапарлар телефонды азырақ қыздырады.

СӘТТЕР

Енді әр сапар жолын ретімен баяндайды: старт, сол жерде түсірілген фотолары бар белгілер, мәре — сол жақта уақыт, әрқайсысының астында «старттан». Картадағы белгіні басыңыз — бет соған жылжиды; қайта ойнату әр белгіде сәл тоқтайды.
```

### Portuguese (Brazil)

```
QUANTO TEMPO ATÉ O MAR?

Marque pontos na viagem e veja quanto tempo — e quantos quilômetros — levou
para chegar. Dirigindo: a bandeira na tela de bloqueio, sem pegar o telefone.
Numa viagem gravada: toque na rota no mapa em tela cheia. Cada marcação mostra
o tempo desde o início e o trecho desde a anterior, e se nomeia pelo lugar:
«Dzhubga · 1:30». Mesma estrada na ida e na volta? Você escolhe qual passagem.

AS FOTOS VÃO PARA A ROTA

Tire uma foto no caminho e ela aparece no mapa exatamente onde foi feita. Como
foto, com legenda. Nada para organizar à mão.

O TRAJETO MOSTRA O QUE ACONTECEU

Curvas, rotatórias, retornos, manobras em pátios — sem cantos cortados. O
odômetro não mudou um metro: garantido por testes.

PAUSA É PAUSA

Uma parada na loja não divide mais a viagem em duas. O modo lembrete pergunta
e espera em vez de encerrar sozinho. Viagens longas esquentam menos.

MOMENTOS

Cada viagem agora conta a estrada em ordem: partida, marcações com as fotos feitas ali, chegada — a hora à esquerda e «desde a partida» sob cada uma. Toque em uma marcação no mapa e a página rola até ela; o replay para um instante em cada marcação.
```

---

## 2. Промо-текст (170)

```
Отметки на маршруте: до моря — за сколько? Фото сами встают на карту. Трек без срезанных углов.
```

## 3. Что проверить в карточке перед «Submit»

- «What's New» вставлен во все 12 локализаций (см. выше).
- Билд 57, версия 0.6.5.
- Notes для ревьюера — из app-review-notes.md, блок 0.6.5.
- Бэкенд задеплоен (см. release-0.6.5-checklist.md, §1).
