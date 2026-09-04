# App Store Connect — 0.6.4

Всё, что нужно вставить при выкладке билда **0.6.4 (55)**. Заметки для ревьюера —
отдельно, в [app-review-notes.md](app-review-notes.md), секция «current submission».

**В карточке ДВЕНАДЦАТЬ локализаций, и «What's New» обязателен в каждой.**
Сабмит 0.6.2 был отклонён ровно из-за этого. Тексты ниже покрывают все двенадцать.

Релиз **не чисто клиентский**. Серверная половина деплоится **первой**, до сабмита:
таблица `vehicle_photo`, маршруты `/vehicles/photos/*` и `/users/:id/garage`,
плюс миграция паспорта. Порядок безопасен в обе стороны: старый клиент со свежим
бэкендом ничего не замечает, новый клиент со старым бэкендом получает 404 на
гараж и показывает состояние «не удалось загрузить» вместо пустого гаража —
но именно поэтому сабмит без деплоя недопустим: у КАЖДОГО чужого профиля
кнопка «Гараж» вела бы в вечную ошибку.

Ключевые слова, подзаголовок и описание не меняются — ASO этот релиз не трогает.
Лимиты: «What's New» — 4000, промо-текст — 170.

---

## 1. What's New

### English (U.S.)

```
YOUR CAR NOW HAS A PASSPORT

The garage used to be a list of names. Open a vehicle now and you get its
biography: make, model and year, its plate, its level, and three numbers that
matter — trips, regions, days on the road. Below them, a map of everywhere that
car has been, its own records, and its trips as a screen of their own.

Add photos: the pinned one becomes the car's face, in your garage and in
anyone else's view of it. They sync, so they survive a new phone.

I'M A PASSENGER

Taxi, bus, someone else's car — say so before you start recording, in one tap.
The kilometres count toward your statistics and stay off your car's odometer.
It used to be something you could only fix afterwards.

ARCHIVE IS NOW A REAL STATE

A car goes to the archive by your hand, and nothing records onto it after that —
not the trip you start, not Bluetooth auto-record, not a Shortcut. Trips already
recorded stay with their car. Bringing it back is one tap.

YOU DECIDE WHAT OTHERS SEE

Each vehicle has four switches: the car itself, its map, its photos, its plate.
All of them are enforced on the server, so what you hide never reaches anyone
else's phone. Route maps for cars you already owned start switched OFF — a car's
map is, in effect, where its owner lives, and that is not something to turn on
for you.

FIXED

- After selling a car, the next trip was recorded onto it anyway.
- «Un-sell» never reached the server, so the sale came back.
- Connecting to an archived car's stereo made it active again, with no tap.
- Deleting your account left vehicle photos behind; erasing server data left
  your garage public.
```

### Русский

```
У МАШИНЫ ТЕПЕРЬ ЕСТЬ ПАСПОРТ

Гараж был списком названий. Теперь машина открывается: марка, модель и год,
номер, уровень и три числа, которые что-то значат, — поездки, регионы, дни в
дороге. Ниже — карта всего, что эта машина проехала, её собственные рекорды и
её поездки отдельным экраном.

Добавьте фотографии: закреплённая становится лицом машины — и в вашем гараже,
и у тех, кто на неё смотрит. Снимки синхронизируются, поэтому переживают смену
телефона.

Я ПАССАЖИР

Такси, автобус, чужая машина — скажите об этом до начала записи, одним тапом.
Километры пойдут в вашу статистику и не намотаются на одометр вашей машины.
Раньше это можно было поправить только задним числом.

АРХИВ СТАЛ НАСТОЯЩИМ СОСТОЯНИЕМ

Машина уезжает в архив вашей рукой, и после этого на неё не записывается
ничего: ни поездка, которую вы начали, ни автозапись по магнитоле, ни
«Команды». Уже записанные поездки остаются при ней. Вернуть — один тап.

ВЫ РЕШАЕТЕ, ЧТО ВИДНО ДРУГИМ

У каждой машины четыре переключателя: сама машина, её карта, её фотографии и
номер. Всё решается на сервере — скрытое не доезжает до чужого телефона вовсе.
У машин, которые у вас уже были, карта маршрутов ВЫКЛЮЧЕНА: карта машины — это,
по сути, где живёт её владелец, и включать её за вас мы не стали.

ИСПРАВЛЕНО

- После продажи машины следующая поездка уезжала на неё же.
- «Вернуть из проданных» не доезжало до сервера, и продажа возвращалась.
- Подключение к магнитоле архивной машины снова делало её активной.
- «Удалить аккаунт» не стирал фотографии машин, а «стереть данные с сервера»
  оставляло гараж публичным.
```

### German

```
DEIN AUTO HAT JETZT EINEN FAHRZEUGPASS

Die Garage war eine Liste von Namen. Jetzt öffnet sich ein Fahrzeug: Marke,
Modell und Baujahr, Kennzeichen, Level und drei Zahlen, die zählen — Fahrten,
Regionen, Tage unterwegs. Darunter eine Karte von allem, wo dieses Auto war,
seine eigenen Rekorde und seine Fahrten als eigener Bildschirm.

Füge Fotos hinzu: das angeheftete wird zum Gesicht des Autos. Sie werden
synchronisiert und überleben ein neues Telefon.

ICH BIN BEIFAHRER

Taxi, Bus, fremdes Auto — sag es mit einem Tippen, bevor die Aufzeichnung
startet. Die Kilometer zählen für deine Statistik und bleiben vom Tachostand
deines Autos fern.

DAS ARCHIV IST JETZT EIN ECHTER ZUSTAND

Ein Auto wandert von Hand ins Archiv, und danach wird nichts mehr darauf
aufgezeichnet — weder eine gestartete Fahrt noch die Bluetooth-Automatik noch
ein Kurzbefehl. Bereits aufgezeichnete Fahrten bleiben bei ihm.

DU ENTSCHEIDEST, WAS ANDERE SEHEN

Vier Schalter pro Fahrzeug: das Auto selbst, seine Karte, seine Fotos, sein
Kennzeichen. Alles wird auf dem Server durchgesetzt. Bei Autos, die du schon
hattest, ist die Routenkarte AUS — die Karte eines Autos zeigt praktisch, wo
sein Besitzer wohnt.

BEHOBEN: Verkauf setzte die nächste Fahrt trotzdem auf das verkaufte Auto;
«Verkauf zurücknehmen» erreichte den Server nie; das Radio eines archivierten
Autos machte es wieder aktiv.
```

### Spanish (Spain)

```
TU COCHE AHORA TIENE FICHA

El garaje era una lista de nombres. Ahora un vehículo se abre: marca, modelo y
año, matrícula, nivel y tres números que importan — viajes, regiones, días en
carretera. Debajo, un mapa de todo lo que ha recorrido, sus récords y sus
viajes en una pantalla propia.

Añade fotos: la fijada se convierte en la cara del coche. Se sincronizan, así
que sobreviven a un teléfono nuevo.

VOY DE PASAJERO

Taxi, autobús, coche de otro: dilo antes de empezar a grabar, con un toque. Los
kilómetros cuentan para tus estadísticas y no suben al cuentakilómetros de tu
coche.

EL ARCHIVO ES AHORA UN ESTADO REAL

Un coche va al archivo por tu mano y, después, no se graba nada en él: ni el
viaje que empiezas, ni la grabación automática por Bluetooth, ni un atajo. Los
viajes ya grabados se quedan con él.

TÚ DECIDES QUÉ SE VE

Cuatro interruptores por vehículo: el coche, su mapa, sus fotos, su matrícula.
Todo se aplica en el servidor. En los coches que ya tenías, el mapa de rutas
está APAGADO: el mapa de un coche dice, en la práctica, dónde vive su dueño.

CORREGIDO: tras vender, el siguiente viaje se grababa igualmente en ese coche;
«deshacer la venta» nunca llegaba al servidor.
```

### French

```
VOTRE VOITURE A MAINTENANT UNE FICHE

Le garage était une liste de noms. Un véhicule s'ouvre désormais : marque,
modèle et année, plaque, niveau et trois nombres qui comptent — trajets,
régions, jours sur la route. En dessous, une carte de tout ce que cette voiture
a parcouru, ses records et ses trajets sur un écran à part.

Ajoutez des photos : celle qui est épinglée devient le visage de la voiture.
Elles se synchronisent et survivent à un changement de téléphone.

JE SUIS PASSAGER

Taxi, bus, voiture d'un autre : dites-le avant de lancer l'enregistrement, en
une touche. Les kilomètres comptent dans vos statistiques et n'entrent pas au
compteur de votre voiture.

L'ARCHIVE EST UN VRAI ÉTAT

Une voiture part à l'archive de votre main, et plus rien ne s'y enregistre : ni
le trajet que vous lancez, ni l'enregistrement automatique par Bluetooth, ni un
raccourci. Les trajets déjà enregistrés lui restent attachés.

VOUS DÉCIDEZ DE CE QUI EST VISIBLE

Quatre interrupteurs par véhicule : la voiture, sa carte, ses photos, sa
plaque. Tout est appliqué sur le serveur. Pour les voitures que vous aviez
déjà, la carte des trajets est DÉSACTIVÉE : la carte d'une voiture dit, en
pratique, où habite son propriétaire.

CORRIGÉ : après une vente, le trajet suivant s'enregistrait quand même sur
cette voiture ; « annuler la vente » n'atteignait jamais le serveur.
```

### Italian

```
LA TUA AUTO ORA HA UNA SCHEDA

Il garage era un elenco di nomi. Ora un veicolo si apre: marca, modello e anno,
targa, livello e tre numeri che contano — viaggi, regioni, giorni in strada.
Sotto, una mappa di tutto ciò che quest'auto ha percorso, i suoi record e i
suoi viaggi in una schermata dedicata.

Aggiungi foto: quella fissata diventa il volto dell'auto. Si sincronizzano,
quindi sopravvivono a un telefono nuovo.

SONO PASSEGGERO

Taxi, autobus, auto di qualcun altro: dillo prima di iniziare a registrare, con
un tocco. I chilometri contano nelle tue statistiche e non finiscono sul
contachilometri della tua auto.

L'ARCHIVIO È UNO STATO VERO

Un'auto va in archivio per tua mano e da quel momento non ci si registra più
nulla: né il viaggio che avvii, né la registrazione automatica via Bluetooth,
né un comando rapido. I viaggi già registrati restano con lei.

DECIDI TU COSA SI VEDE

Quattro interruttori per veicolo: l'auto, la sua mappa, le sue foto, la targa.
Tutto viene applicato sul server. Per le auto che avevi già, la mappa dei
percorsi è DISATTIVATA: la mappa di un'auto dice, in pratica, dove abita il suo
proprietario.

CORRETTO: dopo la vendita il viaggio successivo finiva comunque su quell'auto;
«annulla vendita» non arrivava mai al server.
```

### Polish

```
TWÓJ SAMOCHÓD MA TERAZ METRYKĘ

Garaż był listą nazw. Teraz pojazd się otwiera: marka, model i rok, tablica,
poziom i trzy liczby, które mają znaczenie — przejazdy, regiony, dni w drodze.
Niżej mapa wszystkiego, co ten samochód przejechał, jego rekordy i jego
przejazdy na osobnym ekranie.

Dodaj zdjęcia: przypięte staje się twarzą auta. Synchronizują się, więc
przetrwają zmianę telefonu.

JESTEM PASAŻEREM

Taksówka, autobus, cudze auto — powiedz to jednym dotknięciem przed startem
nagrywania. Kilometry liczą się do Twoich statystyk i nie trafiają na licznik
Twojego samochodu.

ARCHIWUM JEST TERAZ PRAWDZIWYM STANEM

Samochód trafia do archiwum Twoją ręką i od tej pory nic się na niego nie
zapisuje: ani rozpoczęty przejazd, ani automat po Bluetooth, ani skrót. Już
zapisane przejazdy zostają przy nim.

TY DECYDUJESZ, CO WIDAĆ

Cztery przełączniki na pojazd: samo auto, jego mapa, zdjęcia, tablica.
Wszystko egzekwuje serwer. W autach, które już miałeś, mapa tras jest
WYŁĄCZONA: mapa samochodu mówi w praktyce, gdzie mieszka jego właściciel.

NAPRAWIONO: po sprzedaży kolejny przejazd i tak lądował na tym aucie;
«cofnij sprzedaż» nigdy nie docierało do serwera.
```

### Indonesian

```
MOBILMU KINI PUNYA PASPOR

Garasi dulu hanya daftar nama. Sekarang kendaraan bisa dibuka: merek, model dan
tahun, pelat, level, dan tiga angka yang berarti — perjalanan, wilayah, hari di
jalan. Di bawahnya, peta semua yang pernah dilalui mobil itu, rekornya, dan
daftar perjalanannya di layar tersendiri.

Tambahkan foto: yang disematkan menjadi wajah mobil. Foto tersinkronisasi, jadi
tetap ada saat ganti ponsel.

SAYA PENUMPANG

Taksi, bus, mobil orang lain — katakan sebelum mulai merekam, satu ketukan.
Kilometernya masuk ke statistikmu dan tidak menambah odometer mobilmu.

ARSIP KINI STATUS SUNGGUHAN

Mobil masuk arsip karena tanganmu, dan setelah itu tidak ada yang direkam ke
sana: tidak perjalanan yang kamu mulai, tidak perekaman otomatis Bluetooth,
tidak pintasan. Perjalanan yang sudah tercatat tetap bersamanya.

KAMU YANG MENENTUKAN APA YANG TERLIHAT

Empat sakelar per kendaraan: mobilnya, petanya, fotonya, pelatnya. Semua
ditegakkan di server. Untuk mobil yang sudah kamu miliki, peta rute MATI: peta
sebuah mobil praktis menunjukkan di mana pemiliknya tinggal.

DIPERBAIKI: setelah dijual, perjalanan berikutnya tetap tercatat ke mobil itu;
«batalkan penjualan» tidak pernah sampai ke server.
```

### Turkish

```
ARABANIN ARTIK BİR PASAPORTU VAR

Garaj bir isim listesiydi. Artık araç açılıyor: marka, model ve yıl, plaka,
seviye ve önemli üç sayı — yolculuklar, bölgeler, yolda geçen günler. Altında
bu arabanın gittiği her yerin haritası, kendi rekorları ve yolculukları ayrı
bir ekranda.

Fotoğraf ekle: sabitlenen fotoğraf arabanın yüzü olur. Eşitlenir, yani yeni
telefonda da durur.

YOLCUYUM

Taksi, otobüs, başkasının arabası — kayda başlamadan önce tek dokunuşla söyle.
Kilometreler istatistiğine yazılır, arabanın kilometre sayacına yazılmaz.

ARŞİV ARTIK GERÇEK BİR DURUM

Araba arşive senin elinle gider ve ondan sonra ona hiçbir şey kaydedilmez: ne
başlattığın yolculuk, ne Bluetooth otomatiği, ne bir kısayol. Kayıtlı
yolculuklar onda kalır.

NEYİN GÖRÜNECEĞİNE SEN KARAR VER

Araç başına dört anahtar: arabanın kendisi, haritası, fotoğrafları, plakası.
Hepsi sunucuda uygulanır. Zaten sahip olduğun arabalarda rota haritası
KAPALI: bir arabanın haritası pratikte sahibinin nerede oturduğunu söyler.

DÜZELTİLDİ: satıştan sonra bir sonraki yolculuk yine o arabaya yazılıyordu;
«satışı geri al» sunucuya hiç ulaşmıyordu.
```

### Ukrainian

```
У МАШИНИ ТЕПЕР Є ПАСПОРТ

Гараж був списком назв. Тепер машина відкривається: марка, модель і рік, номер,
рівень і три числа, що мають значення — поїздки, регіони, дні в дорозі. Нижче —
карта всього, що ця машина проїхала, її рекорди та її поїздки окремим екраном.

Додайте фотографії: закріплена стає обличчям машини. Знімки синхронізуються,
тож переживають зміну телефона.

Я ПАСАЖИР

Таксі, автобус, чужа машина — скажіть про це до початку запису, одним дотиком.
Кілометри підуть у вашу статистику й не намотаються на одометр вашої машини.

АРХІВ СТАВ СПРАВЖНІМ СТАНОМ

Машина їде в архів вашою рукою, і після цього на неї не записується нічого: ні
поїздка, яку ви почали, ні автозапис по магнітолі, ні «Команди». Уже записані
поїздки залишаються при ній.

ВИ ВИРІШУЄТЕ, ЩО ВИДНО ІНШИМ

Чотири перемикачі на машину: сама машина, її карта, її фотографії та номер. Усе
вирішується на сервері. У машин, які у вас уже були, карта маршрутів ВИМКНЕНА:
карта машини — це, по суті, де живе її власник.

ВИПРАВЛЕНО: після продажу наступна поїздка все одно їхала на цю машину;
«повернути з проданих» ніколи не доїжджало до сервера.
```

### Filipino (Tagalog)

В карточке App Store этот язык исторически лежит в слоте «Finnish» — так же,
как в 0.6.3. Слот не переименовывается, текст кладётся филиппинский.

```
MAY PASAPORTE NA ANG SASAKYAN MO

Listahan lang ng pangalan ang garahe dati. Ngayon, bumubukas ang sasakyan:
marka, modelo at taon, plaka, level, at tatlong bilang na may saysay — biyahe,
rehiyon, araw sa daan. Sa ibaba, mapa ng lahat ng nalakbay nito, mga rekord
nito, at ang mga biyahe nito sa sariling screen.

Magdagdag ng larawan: ang naka-pin ang nagiging mukha ng sasakyan.
Nagsi-sync ito, kaya hindi nawawala kapag nagpalit ka ng telepono.

PASAHERO AKO

Taxi, bus, sasakyan ng iba — sabihin mo bago mag-record, isang tap lang. Bibilang
ang kilometro sa istatistika mo pero hindi sa odometer ng sasakyan mo.

TUNAY NANG ESTADO ANG ARCHIVE

Sa kamay mo napupunta sa archive ang sasakyan, at pagkatapos ay wala nang
naitatala rito: kahit biyaheng sinimulan mo, kahit auto-record sa Bluetooth,
kahit Shortcut. Nananatili rito ang mga naitalang biyahe.

IKAW ANG MAGPAPASYA KUNG ANO ANG NAKIKITA

Apat na switch bawat sasakyan: ang sasakyan, mapa nito, mga larawan, plaka.
Sa server ipinatutupad lahat. Sa mga sasakyang meron ka na, NAKA-OFF ang mapa
ng ruta: ang mapa ng sasakyan ay halos katumbas ng kung saan nakatira ang may-ari.

INAYOS: pagkatapos ibenta, sa sasakyang iyon pa rin naitatala ang susunod na
biyahe; hindi umaabot sa server ang «bawiin ang benta».
```

### Portuguese (Brazil)

```
SEU CARRO AGORA TEM UMA FICHA

A garagem era uma lista de nomes. Agora o veículo abre: marca, modelo e ano,
placa, nível e três números que importam — viagens, regiões, dias na estrada.
Abaixo, um mapa de tudo o que esse carro percorreu, seus recordes e suas
viagens em uma tela própria.

Adicione fotos: a fixada vira o rosto do carro. Elas sincronizam, então
sobrevivem à troca de telefone.

VOU DE PASSAGEIRO

Táxi, ônibus, carro de outra pessoa — diga isso antes de começar a gravar, com
um toque. Os quilômetros contam na sua estatística e não sobem no odômetro do
seu carro.

O ARQUIVO AGORA É UM ESTADO DE VERDADE

O carro vai para o arquivo pela sua mão e, depois disso, nada é gravado nele:
nem a viagem que você inicia, nem a gravação automática por Bluetooth, nem um
atalho. As viagens já gravadas continuam com ele.

VOCÊ DECIDE O QUE APARECE

Quatro chaves por veículo: o carro, o mapa dele, as fotos, a placa. Tudo é
aplicado no servidor. Nos carros que você já tinha, o mapa de rotas vem
DESLIGADO: o mapa de um carro diz, na prática, onde mora o dono.

CORRIGIDO: depois da venda, a viagem seguinte era gravada nesse carro mesmo
assim; «desfazer a venda» nunca chegava ao servidor.
```

---

## 2. Промо-текст

Не меняется — 0.6.4 не трогает ASO.

---

## 3. Порядок выкладки

1. Бэкенд: смёржить и задеплоить (миграции `AddVehiclePassport` и
   `AddVehiclePhotos`, маршруты гаража и фотографий машины).
2. Проверить на проде вручную: чужой профиль → «Гараж» → машина открывается;
   спрятанная машина по прямой ссылке отвечает как несуществующая; закрытый
   номер не приходит в ответе.
3. Только после этого — сабмит билда 55.
