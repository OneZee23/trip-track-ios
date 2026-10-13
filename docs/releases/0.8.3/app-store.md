# App Store Connect — 0.8.3

Всё, что нужно вставить при выкладке билда **0.8.3 (66)**. Заметки для
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
  него ФИЛИППИНСКИЙ текст — так делали в 0.6.3–0.8.2.
- **Казахского в карточке нет вовсе.** В приложении он есть, в списке локалей
  между Italian и Polish пусто.

**БЭКЕНД ДЕПЛОИТСЯ РАНЬШЕ ПРИЛОЖЕНИЯ.** Две миграции —
`AddVehiclePowertrain` и `RelaxCheckpointCoordinates`. Старый сервер про тип
двигателя не знает и вернёт машину без него, а обязательные координаты отметки
отобьют апсерт поездки у того, у кого включена приватная зона. Порядок
обратный обычному: сначала прод, потом сабмит.

**Монетизации в этом релизе по-прежнему НЕТ.** `PlusAvailability.isEnabled`
остаётся `false`: ни подписки, ни доната, ни вписанной вручную поездки не
видит никто ни в одном регионе. В App Store Connect для 0.8.3 **не идёт ни
один In-App Purchase**. Строки «Плюс» переименованы в «PRO» и идентификаторы
товаров заведены заранее — на экране это ничего не меняет, потому что экрана
нет.

Ключевые слова, подзаголовок и описание карточки не меняются — только «What's
New». Лимиты: «What's New» — 4000, промо-текст — 170.

---

## 1. What's New


### English (U.S.)

```
ELECTRIC AND HYBRIDS

Your car now has an engine type: petrol or diesel, electric, or both at once.
An electric car counts kilowatt-hours and a price per kWh instead of litres; a
plug-in hybrid counts both halves. Every trip is broken down honestly — how far
you went on the battery, how far on fuel, and what it cost. The battery range
is spent day by day: the first kilometres of each day come off the night's
charge. And you can correct any trip by hand — Auto, Electric, Fuel.

A CHECKPOINT IN YOUR YARD NO LONGER GIVES THE YARD AWAY

If you have a private zone around your home, a checkpoint placed inside it is
now sent without its coordinates — the name, the time and the distance from the
start still travel. The track, the route preview and photos have been trimmed
since 0.8.2; now the checkpoint is too.

RECORDING STARTS UNDER A BAD SKY

The start slider no longer refuses to move in an underground car park, in a
courtyard or between tower blocks. Signal quality is reported honestly, and
kilometres are still counted only from good fixes.

FIXED
• Edits to a car — consumption, fuel price, currency, name, visibility — no
  longer roll back after a sync with your second phone
```

### Russian

```
ЭЛЕКТРО И ГИБРИДЫ

У машины появился тип двигателя: бензин или дизель, электро, или и то и другое
сразу. Электрическая считает киловатт-часы и цену за кВт·ч вместо литров,
плагин-гибрид считает обе половины. Каждая поездка раскладывается честно:
сколько прошло на батарее, сколько на топливе и во сколько это обошлось. Запас
хода тратится по дням — первые километры каждого дня идут с ночного заряда. А
режим можно поправить руками на любой поездке: «Авто», «Электро», «Топливо».

ОТМЕТКА ВО ДВОРЕ БОЛЬШЕ НЕ ВЫДАЁТ ДВОР

Если у вас включена приватная зона вокруг дома, отметка, поставленная внутри
круга, теперь уезжает без координаты — имя, время и километры от старта едут
как раньше. Трек, превью маршрута и снимки обрезались с 0.8.2, теперь и она.

ЗАПИСЬ НАЧИНАЕТСЯ ПОД ПЛОХИМ НЕБОМ

Слайдер старта больше не блокируется в подземном паркинге, во дворе и между
высотками. Качество сигнала показывается честно, а километры по-прежнему
считаются только по хорошим точкам.

ЧТО ПОЧИНИЛИ
• Правки машины — расход, цена топлива, валюта, название, видимость — больше
  не откатываются назад после синхронизации со вторым телефоном
```

### German

```
ELEKTRO UND HYBRIDE

Dein Auto hat jetzt eine Antriebsart: Benzin oder Diesel, Elektro oder beides
zugleich. Ein Elektroauto rechnet in Kilowattstunden und einem Preis pro kWh
statt in Litern, ein Plug-in-Hybrid in beiden Hälften. Jede Fahrt wird ehrlich
aufgeschlüsselt: wie weit du mit dem Akku gefahren bist, wie weit mit
Kraftstoff, und was das gekostet hat. Die elektrische Reichweite wird pro Tag
verbraucht — die ersten Kilometer jedes Tages kommen von der Nachtladung. Und
du kannst jede Fahrt von Hand korrigieren: Automatisch, Elektro, Kraftstoff.

EINE MARKIERUNG IM HOF VERRÄT DEN HOF NICHT MEHR

Wenn du eine private Zone um dein Zuhause hast, wird eine Markierung innerhalb
dieses Kreises jetzt ohne Koordinaten gesendet — Name, Uhrzeit und die Strecke
ab dem Start bleiben. Strecke, Routenvorschau und Fotos werden seit 0.8.2
gekürzt, jetzt auch die Markierung.

AUFZEICHNEN BEGINNT AUCH BEI SCHLECHTEM HIMMEL

Der Startregler blockiert nicht mehr in der Tiefgarage, im Innenhof oder
zwischen Hochhäusern. Die Signalqualität wird ehrlich angezeigt, und Kilometer
zählen weiterhin nur aus guten Positionen.

BEHOBEN
• Änderungen am Auto — Verbrauch, Kraftstoffpreis, Währung, Name, Sichtbarkeit
  — werden nach einer Synchronisierung mit dem zweiten Telefon nicht mehr
  zurückgesetzt
```

### Spanish (Spain)

```
ELÉCTRICOS E HÍBRIDOS

Tu coche ahora tiene un tipo de motor: gasolina o diésel, eléctrico, o ambos a
la vez. Un eléctrico cuenta kilovatios-hora y un precio por kWh en lugar de
litros; un híbrido enchufable cuenta las dos mitades. Cada viaje se desglosa
con honestidad: cuánto has hecho con la batería, cuánto con combustible y
cuánto ha costado. La autonomía eléctrica se gasta por días: los primeros
kilómetros de cada día salen de la carga de la noche. Y puedes corregir
cualquier viaje a mano: Automático, Eléctrico, Combustible.

UNA MARCA EN TU CALLE YA NO DELATA TU CALLE

Si tienes una zona privada alrededor de casa, una marca colocada dentro de ese
círculo se envía ahora sin coordenadas: el nombre, la hora y la distancia desde
la salida siguen viajando. El recorrido, la vista previa de la ruta y las fotos
se recortan desde la 0.8.2; ahora también la marca.

LA GRABACIÓN EMPIEZA CON MAL CIELO

El control de inicio ya no se bloquea en un aparcamiento subterráneo, en un
patio o entre edificios altos. La calidad de la señal se muestra con
honestidad, y los kilómetros se siguen contando solo con posiciones buenas.

CORREGIDO
• Los cambios en un coche —consumo, precio del combustible, moneda, nombre,
  visibilidad— ya no se revierten tras sincronizar con el segundo teléfono
```

### French

```
ÉLECTRIQUE ET HYBRIDES

Votre voiture a désormais un type de motorisation : essence ou diesel,
électrique, ou les deux à la fois. Une électrique compte des kilowattheures et
un prix au kWh au lieu des litres ; une hybride rechargeable compte les deux
moitiés. Chaque trajet est détaillé honnêtement : la distance parcourue sur
batterie, celle parcourue au carburant, et ce que cela a coûté. L'autonomie
électrique se consomme par journée — les premiers kilomètres de chaque journée
viennent de la charge de la nuit. Et vous pouvez corriger chaque trajet à la
main : Automatique, Électrique, Carburant.

UN REPÈRE DEVANT CHEZ VOUS NE TRAHIT PLUS VOTRE RUE

Si vous avez une zone privée autour de votre domicile, un repère placé dans ce
cercle part maintenant sans ses coordonnées : le nom, l'heure et la distance
depuis le départ, eux, continuent de voyager. La trace, l'aperçu de
l'itinéraire et les photos sont rognés depuis la 0.8.2 ; c'est maintenant le
tour du repère.

L'ENREGISTREMENT DÉMARRE SOUS UN MAUVAIS CIEL

Le curseur de départ ne se bloque plus dans un parking souterrain, dans une
cour ou entre des tours. La qualité du signal est annoncée honnêtement, et les
kilomètres ne sont toujours comptés qu'à partir de bons points.

CORRIGÉ
• Les modifications d'une voiture — consommation, prix du carburant, devise,
  nom, visibilité — ne reviennent plus en arrière après une synchronisation
  avec le second téléphone
```

### Italian

```
ELETTRICO E IBRIDI

La tua auto ora ha un tipo di motore: benzina o diesel, elettrico, o entrambi
insieme. Un'auto elettrica conta chilowattora e un prezzo al kWh invece dei
litri; un ibrido plug-in conta tutte e due le metà. Ogni viaggio viene
scomposto onestamente: quanto hai percorso a batteria, quanto a carburante e
quanto è costato. L'autonomia elettrica si consuma giorno per giorno — i primi
chilometri di ogni giornata vengono dalla carica della notte. E puoi correggere
a mano qualsiasi viaggio: Automatico, Elettrico, Carburante.

UN SEGNAPOSTO SOTTO CASA NON RIVELA PIÙ CASA TUA

Se hai una zona privata attorno a casa, un segnaposto messo dentro quel cerchio
ora parte senza coordinate: nome, ora e distanza dalla partenza continuano a
viaggiare. Il tracciato, l'anteprima del percorso e le foto vengono tagliati
dalla 0.8.2; ora anche il segnaposto.

LA REGISTRAZIONE PARTE ANCHE CON UN CIELO BRUTTO

Il cursore di avvio non si blocca più in un parcheggio sotterraneo, in un
cortile o tra i palazzi. La qualità del segnale è indicata onestamente e i
chilometri continuano a contarsi solo dai punti buoni.

CORRETTO
• Le modifiche a un'auto — consumo, prezzo del carburante, valuta, nome,
  visibilità — non tornano più indietro dopo una sincronizzazione con il
  secondo telefono
```

### Polish

```
ELEKTRYKI I HYBRYDY

Samochód ma teraz rodzaj napędu: benzyna lub diesel, elektryczny albo jedno i
drugie naraz. Elektryk liczy kilowatogodziny i cenę za kWh zamiast litrów,
hybryda plug-in — obie połowy naraz. Każda trasa jest rozpisana uczciwie: ile
przejechałeś na baterii, ile na paliwie i ile to kosztowało. Zasięg elektryczny
zużywa się dzień po dniu — pierwsze kilometry każdego dnia idą z nocnego
ładowania. Każdą trasę można też poprawić ręcznie: Automatycznie, Elektryk,
Paliwo.

ZNACZNIK POD DOMEM NIE ZDRADZA JUŻ DOMU

Jeśli masz strefę prywatną wokół domu, znacznik postawiony w tym okręgu
wyjeżdża teraz bez współrzędnych — nazwa, godzina i dystans od startu jadą jak
wcześniej. Ślad, podgląd trasy i zdjęcia są przycinane od 0.8.2; teraz także
znacznik.

NAGRYWANIE ZACZYNA SIĘ POD ZŁYM NIEBEM

Suwak startu nie blokuje się już w garażu podziemnym, na podwórku ani między
wieżowcami. Jakość sygnału pokazywana jest uczciwie, a kilometry nadal liczą
się tylko z dobrych punktów.

NAPRAWIONE
• Zmiany w samochodzie — spalanie, cena paliwa, waluta, nazwa, widoczność —
  nie cofają się już po synchronizacji z drugim telefonem
```

### Indonesian

```
LISTRIK DAN HIBRIDA

Mobil kini punya jenis penggerak: bensin atau diesel, listrik, atau keduanya
sekaligus. Mobil listrik menghitung kilowatt-jam dan harga per kWh, bukan
liter; hibrida plug-in menghitung kedua sisinya. Setiap perjalanan dirinci
dengan jujur: berapa jauh dengan baterai, berapa jauh dengan bahan bakar, dan
berapa biayanya. Jarak tempuh baterai terpakai per hari — kilometer pertama
setiap hari diambil dari pengisian semalam. Setiap perjalanan juga bisa
dikoreksi manual: Otomatis, Listrik, Bahan bakar.

PENANDA DI DEPAN RUMAH TIDAK LAGI MEMBOCORKAN RUMAH

Kalau kamu punya zona pribadi di sekitar rumah, penanda yang diletakkan di
dalam lingkaran itu kini dikirim tanpa koordinat — nama, waktu dan jarak dari
titik berangkat tetap terkirim. Jalur, pratinjau rute dan foto sudah dipangkas
sejak 0.8.2; sekarang penanda juga.

PEREKAMAN MULAI MESKI LANGIT BURUK

Penggeser mulai tidak lagi terkunci di parkir bawah tanah, di halaman dalam,
atau di antara gedung tinggi. Kualitas sinyal ditampilkan apa adanya, dan
kilometer tetap dihitung hanya dari titik yang bagus.

DIPERBAIKI
• Perubahan pada mobil — konsumsi, harga bahan bakar, mata uang, nama,
  visibilitas — tidak lagi kembali setelah sinkronisasi dengan ponsel kedua
```

### Turkish

```
ELEKTRİKLİ VE HİBRİT

Aracının artık bir motor tipi var: benzin ya da dizel, elektrikli veya ikisi
birden. Elektrikli araç litre yerine kilovatsaat ve kWh başına fiyat sayar;
şarj edilebilir hibrit iki yarımı da sayar. Her yolculuk dürüstçe ayrılır: ne
kadarı bataryayla, ne kadarı yakıtla gitti ve bu ne tuttu. Elektrikli menzil
günlere bölünerek harcanır — her günün ilk kilometreleri gece şarjından gelir.
Dilersen her yolculuğu elle de düzeltebilirsin: Otomatik, Elektrik, Yakıt.

EVİN ÖNÜNDEKİ İŞARET ARTIK EVİ ELE VERMİYOR

Evinin çevresinde özel bir bölgen varsa, o dairenin içine konan işaret artık
koordinatsız gönderiliyor — adı, saati ve başlangıçtan itibaren mesafesi
gitmeye devam ediyor. Rota, rota önizlemesi ve fotoğraflar 0.8.2'den beri
kırpılıyordu; şimdi işaret de.

KAYIT KÖTÜ GÖKYÜZÜNDE DE BAŞLIYOR

Başlatma kaydırıcısı artık yeraltı otoparkında, avluda veya yüksek binalar
arasında kilitlenmiyor. Sinyal kalitesi olduğu gibi gösteriliyor, kilometreler
ise yine sadece iyi konumlardan sayılıyor.

DÜZELTİLDİ
• Araçta yapılan değişiklikler — tüketim, yakıt fiyatı, para birimi, ad,
  görünürlük — ikinci telefonla eşitlemeden sonra artık geri alınmıyor
```

### Finnish (в слоте лежит ФИЛИППИНСКИЙ текст)

```
ELEKTRIKO AT HYBRID

May uri na ng makina ang sasakyan mo: gasolina o diesel, elektriko, o pareho
nang sabay. Kilowatt-hour at presyo kada kWh ang binibilang ng elektriko,
hindi litro; pareho namang kalahati ang binibilang ng plug-in hybrid. Bawat
biyahe ay hinahati nang tapat: gaano kalayo sa baterya, gaano kalayo sa
gasolina, at magkano ang nagastos. Araw-araw nauubos ang saklaw ng baterya —
ang unang mga kilometro ng bawat araw ay galing sa charge kagabi. Puwede mo
ring itama nang manu-mano ang alinmang biyahe: Awtomatiko, Elektriko, Gasolina.

ANG MARKA SA HARAP NG BAHAY AY HINDI NA NAGBUBUNYAG NG BAHAY

Kung may pribadong sona ka sa paligid ng bahay, ang markang inilagay sa loob
ng bilog na iyon ay ipinapadala na ngayon nang walang koordinado — nananatili
ang pangalan, oras at layo mula sa simula. Pinuputol na ang ruta, ang preview
ng ruta at ang mga larawan mula pa noong 0.8.2; ngayon pati ang marka.

NAGSISIMULA ANG PAG-RECORD KAHIT MASAMA ANG LANGIT

Hindi na naiipit ang slider ng pagsisimula sa underground parking, sa patyo, o
sa pagitan ng matataas na gusali. Tapat na ipinapakita ang lakas ng signal, at
ang mga kilometro ay binibilang pa rin mula lamang sa magagandang posisyon.

INAYOS
• Ang mga pagbabago sa sasakyan — konsumo, presyo ng gasolina, pera, pangalan,
  visibility — ay hindi na bumabalik pagkatapos mag-sync sa pangalawang telepono
```

### Ukrainian

```
ЕЛЕКТРО І ГІБРИДИ

У машини з'явився тип двигуна: бензин чи дизель, електро, або й те й те разом.
Електрична рахує кіловат-години й ціну за кВт·год замість літрів, плагін-гібрид
рахує обидві половини. Кожна поїздка розкладається чесно: скільки пройшло на
батареї, скільки на пальному і скільки це коштувало. Запас ходу витрачається
по днях — перші кілометри кожного дня йдуть із нічного заряду. А режим можна
виправити вручну на будь-якій поїздці: «Автоматично», «Електро», «Пальне».

ПОЗНАЧКА БІЛЯ ДОМУ БІЛЬШЕ НЕ ВИДАЄ ДІМ

Якщо у вас увімкнена приватна зона навколо дому, позначка, поставлена всередині
кола, тепер їде без координат — ім'я, час і кілометри від старту їдуть, як і
раніше. Трек, прев'ю маршруту і знімки обрізаються з 0.8.2, тепер і вона.

ЗАПИС ПОЧИНАЄТЬСЯ ПІД ПОГАНИМ НЕБОМ

Повзунок старту більше не блокується в підземному паркінгу, у дворі й між
висотками. Якість сигналу показується чесно, а кілометри так само рахуються
лише за добрими точками.

ЩО ПОЛАГОДИЛИ
• Правки машини — витрата, ціна пального, валюта, назва, видимість — більше
  не відкочуються назад після синхронізації з другим телефоном
```

### Portuguese (Brazil)

```
ELÉTRICOS E HÍBRIDOS

Seu carro agora tem um tipo de motor: gasolina ou diesel, elétrico, ou os dois
ao mesmo tempo. Um elétrico conta quilowatts-hora e um preço por kWh em vez de
litros; um híbrido plug-in conta as duas metades. Cada viagem é detalhada com
honestidade: quanto você rodou na bateria, quanto no combustível e quanto isso
custou. A autonomia elétrica é gasta dia a dia — os primeiros quilômetros de
cada dia saem da carga da noite. E dá para corrigir qualquer viagem na mão:
Automático, Elétrico, Combustível.

UMA MARCAÇÃO NA SUA RUA NÃO ENTREGA MAIS A SUA RUA

Se você tem uma zona privada em volta de casa, uma marcação feita dentro desse
círculo agora é enviada sem coordenadas — o nome, o horário e a distância desde
a largada continuam indo. O trajeto, a prévia da rota e as fotos são cortados
desde a 0.8.2; agora a marcação também.

A GRAVAÇÃO COMEÇA COM CÉU RUIM

O controle de início não trava mais em estacionamento subterrâneo, no pátio ou
entre prédios altos. A qualidade do sinal aparece com honestidade, e os
quilômetros continuam sendo contados só a partir de bons pontos.

CORRIGIDO
• As edições de um carro — consumo, preço do combustível, moeda, nome,
  visibilidade — não voltam mais atrás depois de sincronizar com o segundo
  telefone
```

---

## 2. Что НЕ меняется

- Подзаголовок, ключевые слова, описание, скриншоты — те же, что у 0.8.2.
- Возрастной рейтинг, категории, политика приватности — те же.
- Манифест приватности (`PrivacyInfo.xcprivacy`) не меняется: новых типов
  собираемых данных версия не заводит. Наоборот — координат отметки внутри
  приватной зоны сервер больше не получает.
