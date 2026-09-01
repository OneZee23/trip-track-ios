# What's New 0.6.2 — остальные локализации

App Store Connect требует «What's New» **в каждой локализации карточки**, а их
двенадцать, не две. English (U.S.) и Russian лежат в
[app-store-0.6.2.md](app-store-0.6.2.md) — здесь остальные десять, в том
порядке, в каком их перечислила ошибка сабмита.

Терминология сверена с самим приложением (`Translations+XX.swift`): типы
кузовов, «гараж», «транспорт» — те же слова, что видит пользователь в
интерфейсе. Лимит поля — 4000 символов; самый длинный текст ниже ~2 500.

> ⚠️ **Finnish.** В приложении финского языка НЕТ — тринадцатый язык у нас
> Filipino (`fil`). Похоже, при заведении локализаций в App Store Connect
> `fil` спутали с `fi`. Текст ниже написан, чтобы не блокировать релиз, но
> финский пользователь получит финскую карточку и англоязычное приложение.
> Решение — либо удалить Finnish из карточки, либо завести Filipino вместо
> него. Отдельно: казахского (`kk`) в карточке нет вовсе, хотя в приложении
> он есть.

---

## German

```
WÄHLE, WOMIT DU FÄHRST

In der Garage stand ein Auto in acht Farben. Jetzt sind es zehn Formen: Limousine, Schrägheck, Crossover, Pick-up, Transporter, Cabrio, Sportwagen, Motorrad, Moped und Fahrrad — jede in neun Farben. Form und Farbe wählst du getrennt, die Kombination gehört also dir.

Motorräder, Mopeds und Fahrräder sehen endlich aus wie sie selbst. Die App bot diese Typen schon länger an und zeichnete alle drei als Auto.

Dein Fahrzeug fährt jetzt auf der Fahrtkarte mit — du siehst ohne einen einzigen Tap, womit du unterwegs warst.

DEINE EIGENE GESCHICHTE, NACHGELESEN

Deine Fahrten stellen dich nicht länger dir selbst vor: Name und Avatar sind von deinen eigenen Karten verschwunden — du weißt ja, wer du bist. Das Level ist geblieben, und es ist jetzt das Level von damals. Eine Fahrt von vor zwei Jahren zeigt LVL 3, die von gestern LVL 9 — beim Scrollen durch deine Historie siehst du die Strecke, die du zurückgelegt hast.

GEZEICHNET, NICHT GELIEHEN

Jeder leere Bildschirm, jeder Fehler und jede Onboarding-Seite hat jetzt ein Bild, das für diese App gezeichnet wurde, statt eines Systemsymbols. Listen laden als Umriss der Liste statt als Ladekreis: Der Bildschirm, auf den du wartest, ist der Bildschirm, den du schon siehst.

BEHOBEN

Ein Verbindungsabbruch zu Fahrtbeginn konnte dich über Nacht abmelden und die fertige Fahrt auf dem Telefon zurücklassen. Die App repariert ihre Sitzung jetzt selbst — und wenn das wirklich nicht geht, behält sie deine Fahrten, deinen Namen und deine Einstellungen und bittet dich einfach, dich neu anzumelden. Nichts wird gelöscht.

Der Kilometerstand eines Fahrzeugs wird jetzt aus deinen Fahrten berechnet, statt einmalig hochgezählt zu werden. Eine Fahrt auf ein anderes Fahrzeug umzubuchen, eine Fahrt zu löschen oder deine Bibliothek vom Server wiederherzustellen ließ die Zahl früher unverändert.

Dein Auto in der Garage ist wieder scharf — es war die einzige Stelle in der App, die die Pixel geglättet hat.
```

---

## Indonesian

```
PILIH APA YANG KAMU KENDARAI

Dulu garasi hanya memuat satu mobil dalam delapan warna. Sekarang ada sepuluh bentuk: sedan, hatchback, crossover, pikap, van, konvertibel, mobil sport, motor, motor bebek, dan sepeda — masing-masing dalam sembilan warna. Bentuk dan warna dipilih terpisah, jadi kombinasinya milikmu.

Motor, motor bebek, dan sepeda akhirnya terlihat seperti dirinya sendiri. Aplikasi sudah lama menyediakan tipe-tipe itu dan menggambar ketiganya sebagai mobil.

Kendaraanmu kini ikut tampil di kartu perjalanan: kamu bisa melihat naik apa tanpa membuka apa pun.

RIWAYATMU SENDIRI, DIBACA ULANG

Perjalananmu tidak lagi memperkenalkan dirimu kepada dirimu sendiri: nama dan avatar hilang dari kartumu sendiri — kamu tahu siapa kamu. Levelnya tetap ada, dan sekarang itu level yang kamu punya saat itu. Perjalanan dua tahun lalu tertulis LVL 3 dan yang kemarin LVL 9, jadi menggulir riwayat memperlihatkan jarak yang sudah kamu tempuh.

DIGAMBAR, BUKAN DIPINJAM

Setiap layar kosong, setiap galat, dan setiap halaman perkenalan kini punya gambar yang dibuat khusus untuk aplikasi ini, bukan ikon sistem. Daftar dimuat sebagai kerangka daftar, bukan lingkaran berputar: layar yang kamu tunggu sudah ada di depanmu.

DIPERBAIKI

Koneksi yang putus di awal perjalanan bisa membuatmu keluar dari akun semalaman dan meninggalkan perjalanan yang sudah selesai terjebak di ponsel. Kini aplikasi memperbaiki sesinya sendiri — dan kalau benar-benar tidak bisa, ia menyimpan perjalanan, nama, dan pengaturanmu, lalu cukup memintamu masuk lagi. Tidak ada yang dihapus.

Jarak tempuh kendaraan kini dihitung dari perjalananmu, bukan dijumlahkan sekali saja. Memindahkan perjalanan ke kendaraan lain, menghapus perjalanan, atau memulihkan pustaka dari server dulu membuat angkanya tidak berubah.

Mobilmu di garasi kembali tajam — itu satu-satunya tempat di aplikasi yang menghaluskan pikselnya.
```

---

## Turkish

```
NEYLE SÜRDÜĞÜNÜ SEÇ

Garajda sekiz renkte tek bir araba vardı. Artık on gövde var: sedan, hatchback, crossover, pikap, panelvan, üstü açık, spor araba, motosiklet, moped ve bisiklet — her biri dokuz renkte. Gövde ve renk ayrı ayrı seçiliyor, yani kombinasyon senin.

Motosikletler, mopedler ve bisikletler nihayet kendilerine benziyor. Uygulama bu türleri bir süredir sunuyordu ve üçünü de araba olarak çiziyordu.

Aracın artık gezi kartının üzerinde yol alıyor: hiçbir şey açmadan neyle gittiğini görüyorsun.

KENDİ GEÇMİŞİN, YENİDEN OKUNMUŞ

Gezilerin artık seni sana tanıtmıyor: kendi kartlarından isim ve avatar kalktı — kim olduğunu zaten biliyorsun. Seviye kaldı ve artık o günkü seviyen. İki yıl önceki bir sürüş LVL 3, dünkü LVL 9 diyor; geçmişini kaydırdıkça kat ettiğin yolu görüyorsun.

ÇİZİLDİ, ÖDÜNÇ ALINMADI

Her boş ekranın, her hatanın ve her tanıtım sayfasının artık sistem simgesi yerine bu uygulama için çizilmiş bir resmi var. Listeler dönen çember yerine listenin kendi hatlarıyla yükleniyor: beklediğin ekran zaten önünde.

DÜZELTİLDİ

Sürüşün başındaki bir bağlantı kopması, gece boyunca oturumunu kapatıp biten geziyi telefonda mahsur bırakabiliyordu. Uygulama artık oturumunu kendi onarıyor; gerçekten onaramazsa gezilerini, adını ve ayarlarını koruyor ve yalnızca yeniden giriş yapmanı istiyor. Hiçbir şey silinmiyor.

Aracın kilometresi bir kez toplanmak yerine artık gezilerinden hesaplanıyor. Bir geziyi başka bir araca taşımak, bir geziyi silmek ya da kitaplığını sunucudan geri yüklemek eskiden sayıyı olduğu yerde bırakıyordu.

Garajdaki araban yeniden net — uygulamada pikselleri yumuşatan tek yer orasıydı.
```

---

## Polish

```
WYBIERZ, CZYM JEŹDZISZ

W garażu stało jedno auto w ośmiu kolorach. Teraz jest dziesięć sylwetek: sedan, hatchback, crossover, pickup, furgon, kabriolet, sportowy, motocykl, motorower i rower — każda w dziewięciu kolorach. Kształt i kolor wybiera się osobno, więc zestawienie należy do Ciebie.

Motocykle, motorowery i rowery wreszcie wyglądają jak one same. Te typy były w aplikacji od dawna, a wszystkie trzy rysowane były jako samochód.

Twój pojazd jedzie teraz na karcie trasy — widzisz, czym jechałeś, bez otwierania czegokolwiek.

TWOJA WŁASNA HISTORIA, PRZECZYTANA NA NOWO

Twoje trasy nie przedstawiają Cię już Tobie samemu: imię i awatar zniknęły z Twoich kart — przecież wiesz, kim jesteś. Poziom został i jest teraz tym, który miałeś wtedy. Trasa sprzed dwóch lat pokazuje LVL 3, a wczorajsza LVL 9 — przewijając historię, widzisz dystans, który pokonałeś.

NARYSOWANE, NIE POŻYCZONE

Każdy pusty ekran, każdy błąd i każda strona powitania mają teraz obrazek narysowany dla tej aplikacji zamiast systemowej ikony. Listy ładują się jako zarys listy, a nie kręcące się kółko: ekran, na który czekasz, już jest przed Tobą.

NAPRAWIONE

Zerwane połączenie na początku trasy potrafiło w nocy wylogować konto i zostawić nagraną trasę na telefonie. Teraz aplikacja sama naprawia sesję, a jeśli naprawdę się nie da — zachowuje trasy, imię i ustawienia i po prostu prosi o ponowne zalogowanie. Nic nie znika.

Przebieg pojazdu liczy się z Twoich tras, zamiast być doliczanym raz. Przeniesienie trasy na inny pojazd, usunięcie trasy albo przywrócenie biblioteki z serwera zostawiały liczbę bez zmian.

Twoje auto w garażu znowu jest ostre — to było jedyne miejsce w aplikacji, w którym piksele były wygładzane.
```

---

## Italian

```
SCEGLI CON COSA GUIDI

In garage c'era un'auto in otto colori. Ora ci sono dieci forme: berlina, hatchback, crossover, pick-up, furgone, cabrio, sportiva, moto, ciclomotore e bici, ognuna in nove colori. Forma e colore si scelgono separatamente, così la combinazione è tua.

Moto, ciclomotori e bici finalmente hanno l'aspetto giusto. L'app offriva questi tipi già da un po' e li disegnava tutti e tre come un'auto.

Il tuo mezzo ora viaggia sulla scheda del viaggio: vedi con cosa sei andato senza aprire nulla.

LA TUA STORIA, RILETTA

I tuoi viaggi non ti presentano più a te stesso: nome e avatar sono spariti dalle tue schede — sai bene chi sei. Il livello è rimasto, ed è quello che avevi allora. Un viaggio di due anni fa dice LVL 3 e quello di ieri LVL 9: scorrendo la cronologia vedi la strada che hai fatto.

DISEGNATO, NON PRESO IN PRESTITO

Ogni schermata vuota, ogni errore e ogni pagina di benvenuto ha ora un'illustrazione disegnata per questa app invece di un'icona di sistema. Le liste si caricano come il contorno della lista e non come una rotella: la schermata che aspetti è già davanti a te.

CORRETTO

Un calo di connessione all'inizio di un viaggio poteva disconnetterti durante la notte e lasciare il viaggio finito bloccato sul telefono. Ora l'app ripara la sessione da sola e, se davvero non ci riesce, conserva viaggi, nome e impostazioni e ti chiede semplicemente di accedere di nuovo. Non viene cancellato nulla.

Il chilometraggio del mezzo si calcola dai tuoi viaggi invece di essere sommato una volta sola. Spostare un viaggio su un altro mezzo, eliminare un viaggio o ripristinare la libreria dal server lasciavano il numero dov'era.

La tua auto in garage è di nuovo nitida: era l'unico punto dell'app in cui i pixel venivano smussati.
```

---

## Ukrainian

```
ОБЕРІТЬ, ЧИМ ВИ ЇЗДИТЕ

У гаражі стояло одне авто у восьми кольорах. Тепер їх десять: седан, хетчбек, кросовер, пікап, фургон, кабріолет, спорткар, мотоцикл, мопед і велосипед — кожен у дев'яти кольорах. Тип і колір обираються окремо, тож поєднання ваше.

Мотоцикли, мопеди та велосипеди нарешті виглядають собою. Ці типи були в застосунку давно, і всі три малювалися легковим авто.

Ваш транспорт тепер їде на картці поїздки — видно, чим ви їхали, не відкриваючи деталей.

ВЛАСНА ІСТОРІЯ, ПЕРЕЧИТАНА

Поїздки більше не представляють вас вам же: ім'я й аватар з ваших карток прибрано — ви й так знаєте, хто ви. Рівень залишився, і тепер він той, що був на момент запису. На поїздці дворічної давнини LVL 3, на вчорашній LVL 9 — гортаючи стрічку, ви бачите відстань, яку подолали.

НАМАЛЬОВАНО, А НЕ ПОЗИЧЕНО

У кожного порожнього екрана, кожної помилки та кожної сторінки онбордингу тепер власний малюнок, зроблений для цього застосунку, а не системний значок. Списки завантажуються контуром списку, а не кружальцем, що крутиться: екран, на який ви чекаєте, вже перед вами.

ВИПРАВЛЕНО

Обрив зв'язку на початку поїздки міг за ніч вийти з акаунта, а записану поїздку лишити на телефоні. Тепер застосунок сам відновлює сесію, а якщо це справді неможливо — зберігає поїздки, ім'я та налаштування і просто просить увійти ще раз. Нічого не стирається.

Пробіг транспорту рахується за поїздками, а не накопичується один раз. Перенесення поїздки на інше авто, видалення поїздки та відновлення бібліотеки із сервера раніше лишали число незмінним.

Ваше авто в гаражі знову чітке — це було єдине місце в застосунку, де пікселі згладжувалися.
```

---

## Finnish

> См. предупреждение вверху файла — этой локализации в приложении нет.

```
VALITSE, MILLÄ AJAT

Tallissa oli yksi auto kahdeksassa värissä. Nyt siellä on kymmenen muotoa: sedan, viistoperä, crossover, avolava, pakettiauto, avoauto, urheiluauto, moottoripyörä, mopo ja polkupyörä — jokainen yhdeksässä värissä. Muoto ja väri valitaan erikseen, joten yhdistelmä on sinun.

Moottoripyörät, mopot ja polkupyörät näyttävät vihdoin itseltään. Sovellus on tarjonnut näitä tyyppejä jo jonkin aikaa ja piirsi kaikki kolme autona.

Ajoneuvosi kulkee nyt matkakortin mukana: näet yhdellä silmäyksellä, millä liikuit.

OMA HISTORIASI, UUDELLEEN LUETTUNA

Matkasi eivät enää esittele sinua sinulle: nimi ja avatar ovat poissa omilta korteiltasi — tiedät kyllä, kuka olet. Taso jäi, ja se on nyt se taso, joka sinulla oli silloin. Kahden vuoden takainen ajo sanoo LVL 3 ja eilinen LVL 9, joten historiaa selatessasi näet matkan, jonka olet kulkenut.

PIIRRETTY, EI LAINATTU

Jokaisella tyhjällä näytöllä, jokaisella virheellä ja jokaisella esittelysivulla on nyt tätä sovellusta varten piirretty kuva järjestelmän kuvakkeen sijaan. Listat latautuvat listan ääriviivoina pyörivän ympyrän sijaan: näyttö, jota odotat, on jo edessäsi.

KORJATTU

Yhteyden katkeaminen ajon alussa saattoi kirjata sinut ulos yön aikana ja jättää valmiin matkan jumiin puhelimeen. Nyt sovellus korjaa istuntonsa itse — ja jos se ei todella onnistu, se säilyttää matkasi, nimesi ja asetuksesi ja pyytää vain kirjautumaan uudelleen. Mitään ei pyyhitä.

Ajoneuvon kilometrit lasketaan nyt matkoistasi sen sijaan, että ne laskettaisiin yhteen kerran. Matkan siirtäminen toiselle ajoneuvolle, matkan poistaminen tai kirjaston palauttaminen palvelimelta jätti luvun ennalleen.

Autosi tallissa on taas terävä — se oli sovelluksen ainoa paikka, jossa pikselit pehmennettiin.
```

---

## Portuguese (Brazil)

```
ESCOLHA O QUE VOCÊ DIRIGE

Na garagem havia um carro em oito cores. Agora são dez formas: sedã, hatchback, crossover, picape, van, conversível, esportivo, moto, ciclomotor e bicicleta — cada uma em nove cores. Forma e cor são escolhidas separadamente, então a combinação é sua.

Motos, ciclomotores e bicicletas finalmente têm a cara delas. O app já oferecia esses tipos havia um tempo e desenhava os três como carro.

Seu veículo agora anda no cartão da viagem: dá para ver com o que você foi sem abrir nada.

SUA PRÓPRIA HISTÓRIA, RELIDA

Suas viagens não apresentam mais você a você mesmo: o nome e o avatar saíram dos seus próprios cartões — você sabe quem é. O nível ficou, e agora é o nível que você tinha na época. Uma viagem de dois anos atrás mostra LVL 3 e a de ontem, LVL 9: percorrendo o histórico, você vê a distância que avançou.

DESENHADO, NÃO EMPRESTADO

Cada tela vazia, cada erro e cada página de boas-vindas agora tem uma ilustração desenhada para este app, em vez de um ícone do sistema. As listas carregam como o contorno da lista, e não como uma rodinha girando: a tela que você espera já está na sua frente.

CORRIGIDO

Uma queda de conexão no início de uma viagem podia desconectar sua conta durante a noite e deixar a viagem gravada presa no telefone. Agora o app conserta a sessão sozinho — e, se realmente não conseguir, mantém suas viagens, seu nome e seus ajustes e apenas pede que você entre de novo. Nada é apagado.

A quilometragem do veículo passa a ser calculada pelas suas viagens, em vez de somada uma única vez. Mover uma viagem para outro veículo, excluir uma viagem ou restaurar sua biblioteca do servidor deixavam o número onde estava.

Seu carro na garagem está nítido de novo — era o único lugar do app que suavizava os pixels.
```

---

## French

```
CHOISISSEZ CE QUE VOUS CONDUISEZ

Le garage contenait une voiture en huit couleurs. Il en contient maintenant dix formes : berline, compacte, crossover, pick-up, fourgon, cabriolet, sportive, moto, scooter et vélo — chacune en neuf couleurs. La forme et la couleur se choisissent séparément : la combinaison est la vôtre.

Les motos, les scooters et les vélos se ressemblent enfin. L'app proposait ces types depuis un moment et les dessinait tous les trois en voiture.

Votre véhicule roule désormais sur la carte du trajet : vous voyez avec quoi vous étiez parti sans rien ouvrir.

VOTRE PROPRE HISTOIRE, RELUE

Vos trajets ne vous présentent plus à vous-même : le nom et l'avatar ont quitté vos propres cartes — vous savez qui vous êtes. Le niveau est resté, et c'est désormais celui que vous aviez à l'époque. Un trajet d'il y a deux ans affiche LVL 3, celui d'hier LVL 9 : en parcourant votre historique, vous voyez le chemin parcouru.

DESSINÉ, PAS EMPRUNTÉ

Chaque écran vide, chaque erreur et chaque page d'accueil a maintenant une image dessinée pour cette app, et non une icône système. Les listes se chargent sous la forme du contour de la liste plutôt qu'en roue qui tourne : l'écran que vous attendez est déjà devant vous.

CORRIGÉ

Une coupure de connexion au début d'un trajet pouvait vous déconnecter pendant la nuit et laisser le trajet terminé bloqué sur le téléphone. L'app répare maintenant sa session toute seule — et si elle n'y parvient vraiment pas, elle conserve vos trajets, votre nom et vos réglages et vous demande simplement de vous reconnecter. Rien n'est effacé.

Le kilométrage d'un véhicule est désormais calculé à partir de vos trajets au lieu d'être cumulé une seule fois. Déplacer un trajet vers un autre véhicule, supprimer un trajet ou restaurer votre bibliothèque depuis le serveur laissait le chiffre inchangé.

Votre voiture dans le garage est de nouveau nette — c'était le seul endroit de l'app où les pixels étaient lissés.
```

---

## Spanish (Spain)

```
ELIGE LO QUE CONDUCES

En el garaje había un coche en ocho colores. Ahora hay diez formas: sedán, hatchback, crossover, pickup, furgoneta, descapotable, deportivo, moto, ciclomotor y bici, cada una en nueve colores. La forma y el color se eligen por separado, así que la combinación es tuya.

Las motos, los ciclomotores y las bicis por fin se parecen a sí mismos. La app ofrecía esos tipos desde hace tiempo y dibujaba los tres como un coche.

Tu vehículo ahora viaja en la tarjeta del viaje: ves en qué fuiste sin abrir nada.

TU PROPIA HISTORIA, RELEÍDA

Tus viajes ya no te presentan a ti mismo: el nombre y el avatar han desaparecido de tus tarjetas, porque ya sabes quién eres. El nivel se queda, y ahora es el nivel que tenías entonces. Un viaje de hace dos años dice LVL 3 y el de ayer, LVL 9: al recorrer tu historial ves la distancia que has hecho.

DIBUJADO, NO PRESTADO

Cada pantalla vacía, cada error y cada página de bienvenida tiene ahora una ilustración dibujada para esta app en lugar de un icono del sistema. Las listas se cargan como el contorno de la lista y no como una ruedecita: la pantalla que esperas ya está delante de ti.

CORREGIDO

Un corte de conexión al empezar un viaje podía cerrarte la sesión durante la noche y dejar el viaje terminado atrapado en el teléfono. Ahora la app repara su sesión sola y, si de verdad no puede, conserva tus viajes, tu nombre y tus ajustes y simplemente te pide que vuelvas a iniciar sesión. No se borra nada.

El kilometraje del vehículo se calcula a partir de tus viajes en vez de sumarse una sola vez. Mover un viaje a otro vehículo, borrar un viaje o restaurar tu biblioteca desde el servidor dejaban el número donde estaba.

Tu coche del garaje vuelve a verse nítido: era el único sitio de la app donde se suavizaban los píxeles.
```
