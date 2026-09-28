# App Store Connect — 0.8.2

Всё, что нужно вставить при выкладке билда **0.8.2 (65)**. Заметки для
ревьюера — в [app-review-notes.md](../app-review-notes.md), секция «current
submission».

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
  него ФИЛИППИНСКИЙ текст — так делали в 0.6.3–0.8.1.
- **Казахского в карточке нет вовсе.** В приложении он есть, в списке локалей
  между Italian и Polish пусто.

**Монетизации в этом релизе по-прежнему НЕТ.** `PlusAvailability.isEnabled`
остаётся `false`: ни подписки, ни доната, ни вписанной вручную поездки не
видит никто ни в одном регионе. В App Store Connect для 0.8.2 **не идёт ни
один In-App Purchase** — товары заводить не нужно.

**Приватная зона — целиком на клиенте.** Ни колонок, ни эндпоинтов на сервере
она не заводит, деплоя перед сабмитом нет. Это важно и для ревью: приложение
не просит новых разрешений и не шлёт наружу ничего нового — наоборот, шлёт
меньше.

Ключевые слова, подзаголовок и описание карточки не меняются — только «What's
New». Лимиты: «What's New» — 4000, промо-текст — 170.

---

## 1. What's New


### English (U.S.)

```
YOUR HOME STAYS YOURS

Place your home on the map by hand and pick a private zone around it — 200, 500
or 1000 metres. Inside that circle nothing leaves your phone: not the track,
not the route preview, not the coordinates of a photo. Trips you have already
published are sent again, trimmed. The home marker itself is visible only to
you and never syncs anywhere.

DRAFTS HAVE THEIR OWN PLACE

Trips recorded automatically no longer fill up the "Me" tab. One row leads to
their own list: swipe right for "Mine", left to delete, or pick several at
once. The "Not confirmed" chip is gone — what a trip is, the screen says, not a
badge on the card.

THE ATLAS AND PLACES, REDRAWN

One sheet at the bottom of the Atlas instead of two, a region opens inside it,
and your home has a card of its own. In Places, search now takes over the
screen with results on every letter and an honest "Nothing found". Without a
network the map shows paper instead of empty squares. Both tabs still carry the
"Beta" chip: work on them continues.

CELLS — A THIRD MAP STYLE

Explored ground quantised into squares: a cell is either open or closed. Fog
and Night are left exactly as they were.

BADGES ARE DRAWN

58 engravings instead of icons on a coloured plate.

FIXED
• The map style switch now actually switches
• "Where am I" no longer claims your location is unavailable when it is not
• Tapping the strip of map above the open list collapses it instead of opening
  a region
• The region header no longer sits on top of the clock
```

### Russian

```
ДОМ ОСТАЁТСЯ ДОМА

Дом ставится пальцем по карте, вокруг него круг — 200, 500 или 1000 метров.
Внутри этого круга с телефона не уезжает ничего: ни трек, ни превью маршрута,
ни координата снимка. Уже опубликованные поездки отправляются заново,
обрезанными. Саму метку дома видите только вы, и она никуда не
синхронизируется.

У ЧЕРНОВИКОВ ПОЯВИЛОСЬ СВОЁ МЕСТО

Поездки, записанные автотрекингом, больше не занимают собой вкладку «Я». Одна
строка ведёт в их список: свайп вправо «Моя», влево — удалить, есть режим
выбора для нескольких сразу. Чип «Не подтверждена» убран совсем: что это за
поездка, говорит экран, а не подпись на карточке.

«АТЛАС» И «МЕСТА» ПЕРЕРИСОВАНЫ

На «Атласе» одна шторка внизу вместо двух, регион открывается внутри неё, а у
дома есть своя карточка. В «Местах» поиск стал полноценным состоянием экрана —
результаты на каждую букву и честное «Ничего не нашлось». Без сети карта
показывает бумагу, а не пустые квадраты. Обе вкладки по-прежнему со значком
«Бета»: работа над ними продолжается.

«КЛЕТКИ» — ТРЕТИЙ ВИД КАРТЫ

Открытое квантовано квадратами: клетка либо открыта целиком, либо закрыта.
«Туман» и «Ночь» остались ровно такими, какими были.

ЗНАЧКИ НАРИСОВАНЫ

58 гравюр вместо иконок на цветной плашке.

ЧТО ПОЧИНИЛИ
• Переключение вида карты наконец переключает
• Кнопка «где я» больше не говорит, что геопозиция недоступна, когда она
  доступна
• Нажатие на полоску карты над раскрытым списком сворачивает его, а не
  открывает регион
• Шапка экрана региона больше не наезжает на часы
```

### German

```
DEIN ZUHAUSE BLEIBT DEINS

Setze dein Zuhause von Hand auf die Karte und wähle eine private Zone darum —
200, 500 oder 1000 Meter. Innerhalb dieses Kreises verlässt nichts dein Telefon:
weder die Strecke noch die Routenvorschau noch die Koordinaten eines Fotos.
Bereits veröffentlichte Fahrten werden erneut gesendet, gekürzt. Die Markierung
selbst siehst nur du, und sie wird nirgendwohin synchronisiert.

ENTWÜRFE HABEN JETZT IHREN PLATZ

Automatisch aufgezeichnete Fahrten füllen den Tab „Ich" nicht mehr. Eine Zeile
führt in ihre eigene Liste: nach rechts wischen für „Meine", nach links zum
Löschen, oder gleich mehrere auswählen. Der Chip „Nicht bestätigt" ist ganz
verschwunden — was eine Fahrt ist, sagt der Bildschirm, nicht ein Abzeichen auf
der Karte.

ATLAS UND ORTE, NEU GEZEICHNET

Im Atlas eine Leiste unten statt zwei, eine Region öffnet sich darin, und dein
Zuhause hat eine eigene Karte. In Orte übernimmt die Suche jetzt den Bildschirm,
mit Ergebnissen bei jedem Buchstaben und einem ehrlichen „Nichts gefunden". Ohne
Netz zeigt die Karte Papier statt leerer Quadrate. Beide Tabs tragen weiterhin
den „Beta"-Chip: die Arbeit daran geht weiter.

KACHELN — EIN DRITTER KARTENSTIL

Erkundetes Gelände in Quadrate gerastert: eine Kachel ist entweder offen oder
geschlossen. Nebel und Nacht bleiben genau so, wie sie waren.

ABZEICHEN SIND GEZEICHNET

58 Gravuren statt Symbole auf farbiger Fläche.

BEHOBEN
• Der Umschalter für den Kartenstil schaltet jetzt wirklich um
• „Wo bin ich" behauptet nicht mehr, dein Standort sei nicht verfügbar
• Ein Tippen auf den Kartenstreifen über der offenen Liste klappt sie zu, statt
  eine Region zu öffnen
• Die Kopfzeile der Region liegt nicht mehr über der Uhr
```

### Spanish (Spain)

```
TU CASA SIGUE SIENDO TUYA

Marca tu casa en el mapa a mano y elige una zona privada a su alrededor: 200,
500 o 1000 metros. Dentro de ese círculo nada sale de tu teléfono: ni la ruta,
ni su vista previa, ni las coordenadas de una foto. Los viajes ya publicados se
envían de nuevo, recortados. La marca de casa solo la ves tú y no se sincroniza
a ninguna parte.

LOS BORRADORES TIENEN SU SITIO

Los viajes grabados automáticamente ya no llenan la pestaña «Yo». Una fila lleva
a su propia lista: desliza a la derecha para «Mío», a la izquierda para
eliminar, o elige varios a la vez. La etiqueta «Sin confirmar» ha desaparecido:
lo que es un viaje lo dice la pantalla, no una etiqueta en la tarjeta.

ATLAS Y LUGARES, REDIBUJADOS

En el Atlas, una hoja abajo en lugar de dos, la región se abre dentro de ella y
tu casa tiene su propia tarjeta. En Lugares, la búsqueda ocupa ahora la pantalla
con resultados en cada letra y un honesto «No se encontró nada». Sin red el mapa
muestra papel en vez de cuadrados vacíos. Ambas pestañas siguen con la etiqueta
«Beta»: el trabajo continúa.

CASILLAS: UN TERCER ESTILO DE MAPA

Lo explorado se cuantiza en cuadrados: una casilla está abierta o cerrada. Niebla
y Noche quedan exactamente como estaban.

LAS INSIGNIAS ESTÁN DIBUJADAS

58 grabados en lugar de iconos sobre una placa de color.

CORREGIDO
• El cambio de estilo de mapa ahora cambia de verdad
• «Dónde estoy» ya no dice que tu ubicación no está disponible cuando sí lo está
• Tocar la franja de mapa sobre la lista abierta la pliega en vez de abrir una
  región
• La cabecera de la región ya no se monta sobre el reloj
```

### French

```
VOTRE DOMICILE RESTE À VOUS

Placez votre domicile sur la carte à la main et choisissez une zone privée
autour : 200, 500 ou 1000 mètres. À l'intérieur de ce cercle, rien ne quitte
votre téléphone : ni le tracé, ni l'aperçu du trajet, ni les coordonnées d'une
photo. Les trajets déjà publiés sont renvoyés, rognés. Le repère du domicile
n'est visible que par vous et n'est synchronisé nulle part.

LES BROUILLONS ONT LEUR PLACE

Les trajets enregistrés automatiquement n'encombrent plus l'onglet « Moi ». Une
ligne mène à leur propre liste : balayez à droite pour « À moi », à gauche pour
supprimer, ou sélectionnez-en plusieurs. La pastille « Non confirmé » a disparu :
ce qu'est un trajet, c'est l'écran qui le dit, pas une étiquette sur la carte.

L'ATLAS ET LES LIEUX, REDESSINÉS

Dans l'Atlas, une seule feuille en bas au lieu de deux, une région s'ouvre à
l'intérieur, et votre domicile a sa propre carte. Dans Lieux, la recherche prend
désormais l'écran, avec des résultats à chaque lettre et un honnête « Rien
trouvé ». Sans réseau, la carte affiche du papier au lieu de carrés vides. Les
deux onglets gardent la pastille « Bêta » : le travail continue.

CASES — UN TROISIÈME STYLE DE CARTE

Le terrain exploré quantifié en carrés : une case est ouverte ou fermée. Brume et
Nuit restent exactement comme avant.

LES BADGES SONT DESSINÉS

58 gravures au lieu d'icônes sur une plaque colorée.

CORRIGÉ
• Le sélecteur de style de carte change vraiment de style
• « Où suis-je » ne prétend plus que votre position est indisponible
• Toucher la bande de carte au-dessus de la liste ouverte la referme au lieu
  d'ouvrir une région
• L'en-tête de la région ne chevauche plus l'horloge
```

### Italian

```
CASA TUA RESTA TUA

Metti casa sulla mappa a mano e scegli una zona privata attorno: 200, 500 o 1000
metri. Dentro quel cerchio non esce nulla dal telefono: né il percorso, né la
sua anteprima, né le coordinate di una foto. I viaggi già pubblicati vengono
inviati di nuovo, tagliati. Il segnaposto di casa lo vedi solo tu e non si
sincronizza da nessuna parte.

LE BOZZE HANNO IL LORO POSTO

I viaggi registrati automaticamente non riempiono più la scheda «Io». Una riga
porta al loro elenco: scorri a destra per «Mio», a sinistra per eliminare, o
selezionane più di uno. Il chip «Non confermato» è sparito del tutto: che cosa
sia un viaggio lo dice la schermata, non un'etichetta sulla scheda.

ATLANTE E LUOGHI, RIDISEGNATI

Nell'Atlante un solo foglio in basso invece di due, la regione si apre al suo
interno e casa tua ha una scheda propria. In Luoghi la ricerca ora prende la
schermata, con risultati a ogni lettera e un onesto «Nessun risultato». Senza
rete la mappa mostra carta invece di quadrati vuoti. Entrambe le schede restano
con il chip «Beta»: il lavoro continua.

CASELLE — UN TERZO STILE DI MAPPA

L'esplorato quantizzato in quadrati: una casella è aperta o chiusa. Nebbia e
Notte restano esattamente come erano.

I DISTINTIVI SONO DISEGNATI

58 incisioni invece di icone su una placca colorata.

CORRETTO
• Il selettore dello stile mappa ora cambia davvero
• «Dove sono» non dice più che la posizione non è disponibile quando lo è
• Toccare la striscia di mappa sopra l'elenco aperto lo richiude invece di
  aprire una regione
• L'intestazione della regione non finisce più sopra l'orologio
```

### Polish

```
TWÓJ DOM ZOSTAJE TWÓJ

Ustaw dom na mapie ręcznie i wybierz strefę prywatną wokół niego — 200, 500 lub
1000 metrów. Wewnątrz tego okręgu nic nie opuszcza telefonu: ani trasa, ani jej
podgląd, ani współrzędne zdjęcia. Już opublikowane przejazdy zostają wysłane
ponownie, przycięte. Sam znacznik domu widzisz tylko ty i nigdzie się nie
synchronizuje.

SZKICE MAJĄ SWOJE MIEJSCE

Przejazdy zapisane automatycznie nie zapychają już zakładki „Ja". Jeden wiersz
prowadzi do ich własnej listy: przesuń w prawo, by oznaczyć „Mój", w lewo, by
usunąć, albo wybierz kilka naraz. Plakietka „Niepotwierdzona" zniknęła zupełnie:
czym jest przejazd, mówi ekran, a nie etykieta na karcie.

ATLAS I MIEJSCA — NA NOWO

W Atlasie jeden panel na dole zamiast dwóch, region otwiera się w jego wnętrzu, a
dom ma własną kartę. W Miejscach wyszukiwanie przejmuje teraz ekran, z wynikami
przy każdej literze i uczciwym „Nic nie znaleziono". Bez sieci mapa pokazuje
papier zamiast pustych kwadratów. Obie zakładki nadal mają plakietkę „Beta":
prace trwają.

KRATKI — TRZECI STYL MAPY

Odkryty teren skwantowany w kwadraty: kratka jest albo otwarta, albo zamknięta.
Mgła i Noc zostają dokładnie takie, jakie były.

ODZNAKI SĄ NARYSOWANE

58 grafik zamiast ikon na kolorowej płytce.

NAPRAWIONE
• Przełącznik stylu mapy wreszcie przełącza
• „Gdzie jestem" nie twierdzi już, że lokalizacja jest niedostępna, gdy jest
• Dotknięcie paska mapy nad otwartą listą zwija ją zamiast otwierać region
• Nagłówek regionu nie nachodzi już na zegar
```

### Indonesian

```
RUMAHMU TETAP MILIKMU

Tandai rumahmu di peta secara manual dan pilih zona privat di sekelilingnya —
200, 500, atau 1000 meter. Di dalam lingkaran itu tidak ada yang keluar dari
ponselmu: bukan jalurnya, bukan pratinjau rutenya, bukan pula koordinat foto.
Perjalanan yang sudah dipublikasikan dikirim ulang dalam bentuk terpotong.
Penanda rumah hanya kamu yang melihatnya dan tidak disinkronkan ke mana pun.

DRAF PUNYA TEMPATNYA SENDIRI

Perjalanan yang direkam otomatis tidak lagi memenuhi tab «Saya». Satu baris
membawa ke daftarnya sendiri: geser ke kanan untuk «Milikku», ke kiri untuk
menghapus, atau pilih beberapa sekaligus. Label «Belum dikonfirmasi» hilang
sepenuhnya: apa itu perjalanan, layarnya yang bicara, bukan label di kartu.

ATLAS DAN TEMPAT, DIGAMBAR ULANG

Di Atlas satu panel di bawah, bukan dua; wilayah terbuka di dalamnya, dan rumahmu
punya kartu sendiri. Di Tempat, pencarian kini mengambil alih layar dengan hasil
di setiap huruf dan «Tidak ada yang ditemukan» yang jujur. Tanpa jaringan peta
menampilkan kertas, bukan kotak kosong. Kedua tab masih berlabel «Beta»:
pengerjaannya berlanjut.

KOTAK — GAYA PETA KETIGA

Wilayah terbuka dikuantisasi menjadi kotak: satu kotak terbuka penuh atau
tertutup penuh. Kabut dan Malam tetap persis seperti sebelumnya.

LENCANA SUDAH DIGAMBAR

58 ukiran menggantikan ikon di atas pelat berwarna.

DIPERBAIKI
• Pengalih gaya peta akhirnya benar-benar mengganti gaya
• «Di mana saya» tidak lagi mengatakan lokasi tidak tersedia padahal tersedia
• Mengetuk bidang peta di atas daftar yang terbuka menutup daftar, bukan membuka
  wilayah
• Judul wilayah tidak lagi menimpa jam
```

### Turkish

```
EVİN SENİN KALIR

Evini haritaya elinle koy ve çevresinde özel bir bölge seç: 200, 500 ya da 1000
metre. O dairenin içinde telefonundan hiçbir şey çıkmaz: ne rota, ne rotanın
önizlemesi, ne de bir fotoğrafın konumu. Daha önce yayımladığın yolculuklar
kırpılmış olarak yeniden gönderilir. Ev işaretini yalnızca sen görürsün ve hiçbir
yere eşitlenmez.

TASLAKLARIN ARTIK KENDİ YERİ VAR

Otomatik kaydedilen yolculuklar artık «Ben» sekmesini doldurmuyor. Tek bir satır
kendi listelerine götürüyor: sağa kaydır «Benim», sola kaydır sil, ya da birkaçını
birden seç. «Onaylanmadı» etiketi tamamen kalktı: bir yolculuğun ne olduğunu
ekran söyler, karttaki rozet değil.

ATLAS VE YERLER YENİDEN ÇİZİLDİ

Atlas'ta altta iki yerine tek bir panel var, bölge onun içinde açılıyor ve evinin
kendi kartı var. Yerler'de arama artık ekranı devralıyor: her harfte sonuç ve
dürüst bir «Hiçbir şey bulunamadı». Ağ yokken harita boş kareler yerine kâğıt
gösteriyor. Her iki sekmede de «Beta» etiketi duruyor: çalışma sürüyor.

KARELER — ÜÇÜNCÜ HARİTA STİLİ

Keşfedilen alan karelere bölünür: bir kare ya tamamen açıktır ya da kapalı. Sis ve
Gece tam olarak eskisi gibi kaldı.

ROZETLER ÇİZİLDİ

Renkli zemin üzerindeki simgeler yerine 58 gravür.

DÜZELTİLDİ
• Harita stili değiştirici artık gerçekten değiştiriyor
• «Neredeyim» artık konumun kullanılabilir olduğu hâlde kullanılamıyor demiyor
• Açık listenin üstündeki harita şeridine dokunmak bölge açmak yerine listeyi
  kapatıyor
• Bölge başlığı artık saatin üzerine binmiyor
```

### Finnish

> Слот «Finnish» — филиппинский текст, см. оговорку выше.

```
ANG BAHAY MO AY SA IYO PA RIN

Ilagay ang bahay mo sa mapa nang manu-mano at pumili ng pribadong sona sa
paligid nito — 200, 500 o 1000 metro. Sa loob ng bilog na iyon, walang umaalis
sa telepono mo: hindi ang ruta, hindi ang preview nito, hindi rin ang koordinado
ng larawan. Ang mga biyaheng naipublish mo na ay ipapadala ulit nang pinaikli.
Ikaw lang ang nakakakita ng marka ng bahay, at hindi ito naka-sync kahit saan.

MAY SARILING LUGAR NA ANG MGA DRAFT

Ang mga biyaheng awtomatikong naitala ay hindi na pumupuno sa tab na «Ako». Isang
hilera ang magdadala sa sarili nilang listahan: i-swipe pakanan para «Akin»,
pakaliwa para burahin, o pumili ng ilan nang sabay. Tuluyan nang nawala ang chip
na «Hindi kumpirmado»: ang screen ang nagsasabi kung ano ang biyahe, hindi ang
tatak sa card.

BINAGO ANG ITSURA NG ATLAS AT MGA LUGAR

Sa Atlas, isang panel na lang sa ibaba imbes na dalawa, bumubukas ang rehiyon sa
loob nito, at may sariling card ang bahay mo. Sa Mga Lugar, kinukuha na ng paghahanap
ang buong screen, may resulta sa bawat letra at tapat na «Walang nahanap». Kapag
walang network, papel ang ipinapakita ng mapa imbes na blangkong kahon. May chip
pa ring «Beta» ang dalawang tab: tuloy ang pagtatrabaho.

MGA KAHON — IKATLONG ESTILO NG MAPA

Ang natuklasang lupa ay hinahati sa mga parisukat: bukas nang buo ang kahon o
sarado nang buo. Hindi ginalaw ang Hamog at Gabi.

IGINUHIT NA ANG MGA BADGE

58 ukit imbes na mga icon sa may kulay na plato.

INAYOS
• Gumagana na talaga ang pagpalit ng estilo ng mapa
• Hindi na sinasabi ng «Nasaan ako» na hindi available ang lokasyon kung available
• Ang pag-tap sa guhit ng mapa sa itaas ng bukas na listahan ay nagsasara nito
  imbes na magbukas ng rehiyon
• Hindi na sumasapaw sa orasan ang header ng rehiyon
```

### Ukrainian

```
ДІМ ЗАЛИШАЄТЬСЯ ВАШИМ

Дім ставиться пальцем на карті, навколо нього коло — 200, 500 або 1000 метрів.
Усередині цього кола з телефона не вирушає нічого: ні трек, ні прев'ю маршруту,
ні координата знімка. Уже опубліковані поїздки надсилаються знову, обрізаними.
Саму позначку дому бачите лише ви, і вона нікуди не синхронізується.

У ЧЕРНЕТОК З'ЯВИЛОСЯ СВОЄ МІСЦЕ

Поїздки, записані автотрекінгом, більше не заповнюють вкладку «Я». Один рядок
веде до їхнього списку: свайп праворуч «Моя», ліворуч — видалити, є режим вибору
кількох одразу. Чип «Не підтверджено» прибрано зовсім: що це за поїздка, каже
екран, а не підпис на картці.

«АТЛАС» І «МІСЦЯ» ПЕРЕМАЛЬОВАНО

В «Атласі» одна панель унизу замість двох, регіон відкривається всередині неї, а
дім має власну картку. У «Місцях» пошук став повноцінним станом екрана —
результати на кожну літеру й чесне «Нічого не знайшлося». Без мережі карта
показує папір, а не порожні квадрати. Обидві вкладки досі зі значком «Бета»:
робота над ними триває.

«КЛІТИНКИ» — ТРЕТІЙ ВИГЛЯД КАРТИ

Відкрите квантовано квадратами: клітинка або відкрита повністю, або закрита.
«Туман» і «Ніч» лишилися рівно такими, якими були.

ЗНАЧКИ НАМАЛЬОВАНО

58 гравюр замість іконок на кольоровій плашці.

ЩО ПОЛАГОДИЛИ
• Перемикання вигляду карти нарешті перемикає
• Кнопка «де я» більше не каже, що геопозиція недоступна, коли вона доступна
• Дотик до смужки карти над розкритим списком згортає його, а не відкриває
  регіон
• Шапка екрана регіону більше не наїжджає на годинник
```

### Portuguese (Brazil)

```
SUA CASA CONTINUA SUA

Marque sua casa no mapa manualmente e escolha uma zona privada ao redor: 200, 500
ou 1000 metros. Dentro desse círculo nada sai do seu telefone: nem o trajeto, nem
a prévia da rota, nem as coordenadas de uma foto. As viagens já publicadas são
enviadas de novo, recortadas. A marca da casa só você vê, e ela não é
sincronizada para lugar nenhum.

OS RASCUNHOS GANHARAM SEU LUGAR

As viagens gravadas automaticamente não ocupam mais a aba «Eu». Uma linha leva à
lista delas: deslize para a direita para «Minha», para a esquerda para excluir, ou
selecione várias de uma vez. O selo «Não confirmada» saiu de vez: o que é uma
viagem quem diz é a tela, não um rótulo no cartão.

ATLAS E LUGARES, REDESENHADOS

No Atlas, uma folha embaixo em vez de duas, a região abre dentro dela e sua casa
tem um cartão próprio. Em Lugares, a busca agora toma a tela, com resultados a
cada letra e um honesto «Nada encontrado». Sem rede o mapa mostra papel em vez de
quadrados vazios. As duas abas continuam com o selo «Beta»: o trabalho segue.

QUADROS — UM TERCEIRO ESTILO DE MAPA

O explorado quantizado em quadrados: um quadro está aberto ou fechado. Névoa e
Noite ficaram exatamente como estavam.

AS INSÍGNIAS ESTÃO DESENHADAS

58 gravuras em vez de ícones sobre uma placa colorida.

CORRIGIDO
• O seletor de estilo do mapa agora troca de verdade
• «Onde estou» não diz mais que sua localização está indisponível quando está
• Tocar na faixa de mapa acima da lista aberta recolhe a lista em vez de abrir
  uma região
• O cabeçalho da região não fica mais em cima do relógio
```

---

## 2. Что ещё проверить перед отправкой

- Билд **65**, версия **0.8.2**; `MARKETING_VERSION` и
  `CURRENT_PROJECT_VERSION` в `project.yml` уже стоят.
- Скриншоты карточки не меняются: экраны переделаны, но набор кадров в сторе
  остался с прошлой версии — обновлять их отдельным решением.
- Возрастной рейтинг, категория, ключевые слова, подзаголовок — без изменений.
- In-App Purchase не заводится (см. оговорку про «Плюс» выше).
- Экспорт-комплаенс: шифрование не добавлялось, ответ прежний.
