# App Store Connect — 0.8.0

Всё, что нужно вставить при выкладке билда **0.8.0 (63)**. Заметки для ревьюера —
в [app-review-notes.md](../app-review-notes.md), секция «current submission»:
там же — как проверить подписку и донат в песочнице.

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
  него ФИЛИППИНСКИЙ текст — так делали в 0.6.3–0.6.8 и 0.7.0.
- **Казахского в карточке нет вовсе.** В приложении он есть, в списке локалей
  между Italian и Polish пусто. Блок ниже оставлен для полноты, но вставлять
  его НЕКУДА.

**Релиз не чисто клиентский, и в этот раз порядок особенно строгий.**
Продукты (подписка + три доната) обязаны стоять «Ready to Submit» в App Store
Connect ДО сборки билда — Apple связывает In-App Purchase со сборкой при
ревью, и подписка, заведённая после отправки, ревью не пройдёт. Бэкенд
(модуль `plus`, приём App Store Server Notifications) деплоится тоже до
сабмита — без него подписка на устройстве работает (источник правды —
StoreKit), но чужие профили не увидят купленную косметику, а сервер не
подтвердит покупку. Порядок целиком — `checklist.md`.

Ключевые слова, подзаголовок и описание карточки не меняются — только «What's
New». Лимиты: «What's New» — 4000, промо-текст — 170.

---

## 1. What's New

### English (U.S.)

```
PLUS

TripTrack now has a subscription. Plus unlocks four ways to make the app your
own — premium profile backgrounds, a frame around your avatar with a small
badge next to your name, a background for your car's card in the garage, and a
colour for your own route line on the map — plus one feature: writing in a
drive you did not record, point to point along real roads. Start it from the
Me tab — the plus button in the History header, or tap an empty day on the
calendar. A written-in trip still counts toward your distance, your regions,
the Atlas and your car's odometer; it earns no experience, no level, no badges
and no finds — those stay for a drive recorded live.

Plus is a yearly subscription with a 7-day free trial, or monthly without one.
Restore Purchases is one tap away wherever Plus is offered.

TIP JAR

Three one-time tips for the people who like the app enough to say so — nothing
is unlocked by them, and the app says exactly that before you pay.

PLACES

Places now suggests spots you seem to visit, guessed from where your trips
start and end — save one with a tap, right from the map where all the
suggestions show up together.

EXPORT

Export your own trip as GPX or CSV from its ••• menu — free, no subscription
needed.

FIXED

The first launch after updating no longer freezes. The Apple Maps attribution
on the Atlas no longer looks like a bright plate. Car photos sync again.
```

### Russian

```
ПЛЮС

В TripTrack появилась подписка. «Плюс» открывает четыре способа сделать
приложение своим — премиум-фоны профиля, рамку аватара со значком у имени, фон
карточки машины в гараже и цвет своей линии маршрута на карте — и одну
функцию: вписать поездку, которую вы не записывали, точка за точкой по
настоящим дорогам. Вписать её можно на вкладке «Я» — кнопкой в шапке «Истории»
или тапом по пустому дню в календаре. Вписанная поездка всё равно считается в
километры, регионы, «Атлас» и одометр машины; опыта, уровня, значков и находок
она не даёт — это остаётся за поездкой, записанной вживую.

«Плюс» — подписка на год с 7 днями бесплатно или на месяц без пробного
периода. «Восстановить покупки» — везде, где предлагают «Плюс».

ДОНАТ

Три разовых чаевых для тех, кому приложение нравится настолько, чтобы сказать
спасибо, — они ничего не открывают, и приложение говорит это прямо до оплаты.

МЕСТА

Вкладка «Места» теперь подсказывает: «Похоже, вы здесь бываете» — по тому,
откуда обычно начинаются и где заканчиваются ваши поездки. Сохранить место —
один тап, все подсказки видно на той же карте, что и уже сохранённые места.

ЭКСПОРТ

В «…» своей поездки — экспорт в GPX или CSV, бесплатно, без подписки.

ИСПРАВЛЕНО

Первый запуск после обновления больше не зависает. Подпись Apple на карте
«Атласа» больше не похожа на яркую плашку. Фото машины снова синхронизируются.
```

### German

```
PLUS

TripTrack hat jetzt ein Abo. Plus schaltet vier Wege frei, die App zu Ihrer
eigenen zu machen — Premium-Profilhintergründe, einen Rahmen um Ihren Avatar
mit einem kleinen Abzeichen neben Ihrem Namen, einen Hintergrund für die Karte
Ihres Autos in der Garage und eine Farbe für Ihre eigene Routenlinie auf der
Karte — plus eine Funktion: eine Fahrt eintragen, die Sie nicht aufgezeichnet
haben, Punkt für Punkt entlang echter Straßen. Starten Sie es im Tab „Ich" —
über den Plus-Button in der Kopfzeile von „Verlauf" oder durch Tippen auf
einen leeren Tag im Kalender. Eine eingetragene Fahrt zählt weiterhin zu Ihrer
Distanz, Ihren Regionen, dem Atlas und dem Kilometerstand Ihres Autos; sie
bringt keine Erfahrung, keine Stufe, keine Abzeichen und keine Funde — die
bleiben einer live aufgezeichneten Fahrt vorbehalten.

Plus ist ein Jahresabo mit 7 Tagen kostenlos oder ein Monatsabo ohne
Testzeitraum. „Käufe wiederherstellen" ist überall verfügbar, wo Plus
angeboten wird.

TRINKGELD

Drei einmalige Trinkgelder für alle, denen die App gut genug gefällt, um es zu
sagen — sie schalten nichts frei, und die App sagt das genau so, bevor Sie
bezahlen.

ORTE

Orte schlägt jetzt Stellen vor, an denen Sie öfter sind — geschätzt danach, wo
Ihre Fahrten beginnen und enden. Einen Ort speichern Sie mit einem Antippen,
alle Vorschläge stehen zusammen mit den gespeicherten Orten auf derselben
Karte.

EXPORT

Exportieren Sie Ihre eigene Fahrt als GPX oder CSV über deren •••-Menü —
kostenlos, ohne Abo.

BEHOBEN

Der erste Start nach dem Update hängt sich nicht mehr auf. Der
Apple-Maps-Hinweis im Atlas sieht nicht mehr wie eine helle Platte aus.
Autofotos werden wieder synchronisiert.
```

### Spanish (Spain)

```
PLUS

TripTrack ahora tiene una suscripción. Plus desbloquea cuatro formas de hacer
la app tuya — fondos premium de perfil, un marco para tu avatar con una
pequeña insignia junto a tu nombre, un fondo para la tarjeta de tu coche en el
garaje y un color para tu propia línea de ruta en el mapa — más una función:
añadir a mano un trayecto que no grabaste, punto a punto por carreteras
reales. Empiézalo desde la pestaña «Yo» — con el botón más en la cabecera de
«Historial», o tocando un día vacío en el calendario. Un trayecto añadido a
mano sigue contando para tu distancia, tus regiones, el Atlas y el
cuentakilómetros de tu coche; no da experiencia, ni nivel, ni insignias, ni
hallazgos — eso queda para un trayecto grabado en directo.

Plus es una suscripción anual con 7 días de prueba gratis, o mensual sin
prueba. «Restaurar compras» está a un toque en cualquier sitio donde se
ofrezca Plus.

PROPINA

Tres propinas puntuales para quien le guste la app lo suficiente como para
decirlo — no desbloquean nada, y la app lo dice exactamente así antes de
pagar.

LUGARES

Lugares ahora sugiere sitios que pareces visitar a menudo, calculados a partir
de dónde empiezan y terminan tus trayectos. Guardar uno es un toque, y todas
las sugerencias aparecen en el mismo mapa junto a los lugares ya guardados.

EXPORTAR

Exporta tu propio trayecto como GPX o CSV desde su menú ••• — gratis, sin
suscripción.

SOLUCIONADO

El primer inicio tras la actualización ya no se congela. El aviso de Apple
Maps en el Atlas ya no parece una placa clara. Las fotos del coche vuelven a
sincronizarse.
```

### French

```
PLUS

TripTrack a maintenant un abonnement. Plus débloque quatre façons de rendre
l'app vôtre — des fonds premium pour le profil, un cadre pour votre avatar
avec un petit badge à côté de votre nom, un fond pour la carte de votre
voiture dans le garage et une couleur pour votre propre ligne de trajet sur la
carte — plus une fonctionnalité : inscrire à la main un trajet que vous n'avez
pas enregistré, point par point le long de vraies routes. Créez-le depuis
l'onglet « Moi » — avec le bouton plus dans l'en-tête de « Historique », ou en
touchant un jour vide du calendrier. Un trajet inscrit à la main compte
toujours dans votre distance, vos régions, l'Atlas et le compteur de votre
voiture ; il ne rapporte ni expérience, ni niveau, ni badge, ni découverte —
cela reste réservé à un trajet enregistré en direct.

Plus est un abonnement annuel avec 7 jours d'essai gratuit, ou mensuel sans
essai. « Restaurer les achats » est disponible partout où Plus est proposé.

POURBOIRE

Trois pourboires ponctuels pour qui aime assez l'app pour le dire — ils ne
débloquent rien, et l'app le dit clairement avant le paiement.

LIEUX

Lieux suggère désormais des endroits que vous semblez fréquenter, déduits d'où
commencent et se terminent vos trajets. Enregistrer un lieu se fait d'un
geste, et toutes les suggestions apparaissent sur la même carte que les lieux
déjà enregistrés.

EXPORT

Exportez votre propre trajet en GPX ou CSV depuis son menu ••• — gratuit, sans
abonnement.

CORRIGÉ

Le premier lancement après la mise à jour ne se fige plus. La mention Apple
Plans sur l'Atlas ne ressemble plus à une plaque claire. Les photos de la
voiture se synchronisent à nouveau.
```

### Italian

```
PLUS

TripTrack ora ha un abbonamento. Plus sblocca quattro modi per rendere l'app
tua — sfondi premium per il profilo, una cornice per il tuo avatar con un
piccolo distintivo accanto al nome, uno sfondo per la scheda della tua auto in
garage e un colore per la tua linea di percorso sulla mappa — più una
funzione: inserire a mano un viaggio che non hai registrato, punto per punto
lungo strade vere. Iniziala dalla scheda «Io» — con il pulsante più
nell'intestazione di «Cronologia», oppure toccando un giorno vuoto nel
calendario. Un viaggio inserito a mano conta comunque per la tua distanza, le
tue regioni, l'Atlante e il contachilometri dell'auto; non dà esperienza,
livello, distintivi né scoperte — quelli restano per un viaggio registrato dal
vivo.

Plus è un abbonamento annuale con 7 giorni di prova gratuita, oppure mensile
senza prova. «Ripristina acquisti» è a portata di tocco ovunque Plus venga
offerto.

MANCIA

Tre mance una tantum per chi apprezza l'app abbastanza da dirlo — non
sbloccano nulla, e l'app lo dice chiaramente prima del pagamento.

LUOGHI

Luoghi ora suggerisce i posti che sembri frequentare, dedotti da dove iniziano
e finiscono i tuoi viaggi. Salvarne uno è un tocco, e tutti i suggerimenti
compaiono sulla stessa mappa dei luoghi già salvati.

ESPORTA

Esporta il tuo viaggio in GPX o CSV dal suo menu ••• — gratis, senza
abbonamento.

RISOLTO

Il primo avvio dopo l'aggiornamento non si blocca più. La dicitura Apple Mappe
sull'Atlante non sembra più una targhetta chiara. Le foto dell'auto tornano a
sincronizzarsi.
```

### Polish

```
PLUS

TripTrack ma teraz subskrypcję. Plus odblokowuje cztery sposoby, by aplikacja
była bardziej twoja — premium tła profilu, ramkę awatara z małą odznaką przy
imieniu, tło karty twojego samochodu w garażu oraz kolor własnej linii trasy
na mapie — a do tego jedną funkcję: wpisanie ręcznie przejazdu, którego nie
nagrałeś, punkt po punkcie prawdziwymi drogami. Zacznij od zakładki „Ja" —
przyciskiem plus w nagłówku „Historia" albo dotknięciem pustego dnia w
kalendarzu. Wpisany ręcznie przejazd nadal liczy się do dystansu, regionów,
Atlasu i przebiegu auta; nie daje doświadczenia, poziomu, odznak ani znalezisk
— te zostają dla przejazdu nagranego na żywo.

Plus to subskrypcja roczna z 7-dniowym darmowym okresem próbnym, albo
miesięczna bez próby. „Przywróć zakupy" jest o jedno dotknięcie wszędzie tam,
gdzie oferowany jest Plus.

NAPIWEK

Trzy jednorazowe napiwki dla tych, którym aplikacja podoba się na tyle, by to
powiedzieć — nie odblokowują niczego, a aplikacja mówi to wprost przed
płatnością.

MIEJSCA

Miejsca podpowiadają teraz miejsca, które chyba odwiedzasz często — na
podstawie tego, skąd zwykle zaczynają się i kończą twoje przejazdy. Zapisanie
miejsca to jedno dotknięcie, a wszystkie podpowiedzi widać na tej samej mapie
co już zapisane miejsca.

EKSPORT

Wyeksportuj swój przejazd do GPX lub CSV z jego menu ••• — za darmo, bez
subskrypcji.

NAPRAWIONE

Pierwsze uruchomienie po aktualizacji już się nie zawiesza. Podpis Apple Maps
na Atlasie nie wygląda już jak jasna płytka. Zdjęcia samochodu znów się
synchronizują.
```

### Indonesian

```
PLUS

TripTrack kini punya langganan. Plus membuka empat cara menjadikan aplikasi
ini milik Anda — latar belakang profil premium, bingkai avatar dengan lencana
kecil di samping nama Anda, latar belakang kartu mobil Anda di garasi, dan
warna untuk garis rute Anda sendiri di peta — plus satu fitur: menulis
perjalanan yang tidak Anda rekam, titik demi titik di sepanjang jalan
sungguhan. Mulai dari tab "Saya" — dengan tombol plus di header "Riwayat",
atau ketuk hari kosong di kalender. Perjalanan yang ditulis tangan tetap
dihitung dalam jarak, wilayah, Atlas, dan odometer mobil Anda; tidak
memberikan XP, level, lencana, atau temuan — itu tetap untuk perjalanan yang
direkam langsung.

Plus adalah langganan tahunan dengan uji coba gratis 7 hari, atau bulanan
tanpa uji coba. "Pulihkan Pembelian" ada satu ketukan di mana pun Plus
ditawarkan.

KOTAK TIP

Tiga tip sekali bayar untuk yang menyukai aplikasi ini cukup untuk
mengatakannya — tidak membuka apa pun, dan aplikasi mengatakan itu dengan
jelas sebelum Anda membayar.

TEMPAT

Tempat kini menyarankan lokasi yang sepertinya sering Anda kunjungi,
diperkirakan dari titik awal dan akhir perjalanan Anda. Menyimpan satu tempat
cukup satu ketukan, dan semua saran muncul di peta yang sama dengan tempat
yang sudah tersimpan.

EKSPOR

Ekspor perjalanan Anda sendiri sebagai GPX atau CSV dari menu ••• miliknya —
gratis, tanpa langganan.

DIPERBAIKI

Peluncuran pertama setelah pembaruan tidak lagi macet. Kredit Apple Maps di
Atlas tidak lagi terlihat seperti pelat terang. Foto mobil tersinkron lagi.
```

### Turkish

```
PLUS

TripTrack'te artık abonelik var. Plus, uygulamayı size özel kılan dört yol
açıyor — premium profil arka planları, adınızın yanında küçük bir rozetle
avatar çerçevesi, garajınızdaki aracınızın kartı için arka plan ve haritadaki
kendi rota çizginiz için bir renk — ve bir özellik daha: kaydetmediğiniz bir
yolculuğu, gerçek yollar boyunca nokta nokta elle girmek. "Ben" sekmesinden
başlatın — "Geçmiş" başlığındaki artı düğmesiyle ya da takvimde boş bir güne
dokunarak. Elle girilen yolculuk yine de mesafenize, bölgelerinize, Atlas'a ve
aracınızın kilometre sayacına eklenir; deneyim puanı, seviye, rozet veya
buluntu kazandırmaz — bunlar canlı kaydedilen bir yolculuğa özeldir.

Plus, 7 gün ücretsiz denemeli yıllık abonelik ya da denemesiz aylık abonelik
olarak sunulur. "Satın Alımları Geri Yükle" Plus'ın sunulduğu her yerde bir
dokunuş uzağınızda.

BAHŞİŞ

Uygulamayı bunu söyleyecek kadar sevenler için üç tek seferlik bahşiş — hiçbir
şeyin kilidini açmazlar, ve uygulama bunu ödemeden önce açıkça söyler.

YERLER

Yerler artık sık geldiğinizi tahmin ettiği noktaları öneriyor —
yolculuklarınızın nereden başlayıp nerede bittiğine bakarak. Bir yeri
kaydetmek tek dokunuş; tüm öneriler, kaydettiğiniz yerlerle aynı haritada
görünüyor.

DIŞA AKTARMA

Kendi yolculuğunuzu ••• menüsünden GPX ya da CSV olarak dışa aktarın —
ücretsiz, abonelik gerektirmez.

DÜZELTİLENLER

Güncellemeden sonraki ilk açılış artık donmuyor. Atlas'taki Apple Haritalar
imzası artık parlak bir levha gibi görünmüyor. Araç fotoğrafları yeniden
senkronize oluyor.
```

### Filipino → вставлять в слот **Finnish**

```
PLUS

May subscription na ngayon ang TripTrack. Binubuksan ng Plus ang apat na
paraan para gawing sarili mo ang app — premium na background ng profile, frame
ng avatar na may maliit na badge sa tabi ng pangalan mo, background para sa
card ng sasakyan mo sa garahe, at kulay para sa sarili mong linya ng ruta sa
mapa — at isang feature pa: ang pagsulat ng biyaheng hindi mo naitala, punto
por punto sa tunay na mga kalsada. Simulan ito mula sa tab na "Ako" — sa plus
button sa header ng "Kasaysayan", o i-tap ang walang laman na araw sa
kalendaryo. Ang biyaheng isinulat nang manu-mano ay bumibilang pa rin sa
distansya mo, mga rehiyon, Atlas, at odometer ng sasakyan mo; wala itong
ibinibigay na experience, level, badge, o natuklasan — nananatili iyon para sa
biyaheng direktang naitala.

Ang Plus ay taunang subscription na may 7 araw na libreng pagsubok, o buwanan
na walang pagsubok. Isang tap lang ang "Ibalik ang mga Binili" saan man
inaalok ang Plus.

TIP JAR

Tatlong beses-lang na tip para sa mga gustong-gusto ang app hanggang sabihin
ito — wala itong binubuksan, at malinaw na sinasabi ito ng app bago ka
magbayad.

MGA LUGAR

Nagmumungkahi na ngayon ang Mga Lugar ng mga lugar na mukhang madalas mong
puntahan, batay sa kung saan karaniwang nagsisimula at natatapos ang mga
biyahe mo. Isang tap lang para i-save ang isa, at lahat ng suhestiyon ay
makikita sa parehong mapa kasama ang mga nakasave nang lugar.

EXPORT

I-export ang sarili mong biyahe bilang GPX o CSV mula sa ••• menu nito —
libre, walang kailangang subscription.

NAAYOS

Hindi na humahang ang unang paglunsad pagkatapos mag-update. Ang credit ng
Apple Maps sa Atlas ay hindi na parang maliwanag na plaka. Muling nag-sync ang
mga larawan ng sasakyan.
```

### Ukrainian

```
ПЛЮС

У TripTrack з'явилася підписка. «Плюс» відкриває чотири способи зробити
застосунок своїм — преміум-фони профілю, рамку аватара з невеликим значком
біля імені, фон картки вашого авто в гаражі та колір власної лінії маршруту на
карті — і одну функцію: вписати поїздку, яку ви не записували, точка за точкою
справжніми дорогами. Вписати її можна на вкладці «Я» — кнопкою в шапці
«Історії» або тапом по порожньому дню в календарі. Вписана поїздка все одно
рахується в кілометри, регіони, «Атлас» і одометр авто; досвіду, рівня,
значків і знахідок вона не дає — це лишається за поїздкою, записаною наживо.

«Плюс» — річна підписка з 7 днями безкоштовно або місячна без пробного
періоду. «Відновити покупки» — скрізь, де пропонують «Плюс».

ЧАЙОВІ

Три одноразові чайові для тих, кому застосунок подобається настільки, щоб
сказати про це, — вони нічого не відкривають, і застосунок каже це прямо перед
оплатою.

МІСЦЯ

Вкладка «Місця» тепер підказує: «Схоже, ви тут буваєте» — за тим, звідки
зазвичай починаються і де закінчуються ваші поїздки. Зберегти місце — один
тап, усі підказки видно на тій самій карті, що й уже збережені місця.

ЕКСПОРТ

У «…» своєї поїздки — експорт у GPX або CSV, безкоштовно, без підписки.

ВИПРАВЛЕНО

Перший запуск після оновлення більше не зависає. Підпис Apple на карті
«Атласа» більше не схожий на яскраву табличку. Фото авто знову
синхронізуються.
```

### Portuguese (Brazil)

```
PLUS

O TripTrack agora tem uma assinatura. O Plus libera quatro jeitos de deixar o
app com a sua cara — fundos premium de perfil, uma moldura para o avatar com
um selo pequeno ao lado do seu nome, um fundo para o cartão do seu carro na
garagem e uma cor para a sua própria linha de rota no mapa — mais um recurso:
registrar à mão uma viagem que você não gravou, ponto a ponto por estradas de
verdade. Comece pela aba "Eu" — pelo botão de mais no cabeçalho de
"Histórico", ou tocando em um dia vazio no calendário. Uma viagem registrada à
mão continua contando para a sua distância, suas regiões, o Atlas e o odômetro
do carro; ela não dá experiência, nível, selos nem descobertas — isso fica
para uma viagem gravada ao vivo.

O Plus é uma assinatura anual com 7 dias de teste grátis, ou mensal sem teste.
"Restaurar Compras" fica a um toque em qualquer lugar onde o Plus é oferecido.

GORJETA

Três gorjetas avulsas para quem gosta do app o bastante para dizer isso — elas
não liberam nada, e o app diz exatamente isso antes do pagamento.

LUGARES

Lugares agora sugere pontos que você parece frequentar, deduzidos de onde suas
viagens costumam começar e terminar. Salvar um é um toque, e todas as
sugestões aparecem no mesmo mapa junto com os lugares já salvos.

EXPORTAR

Exporte sua própria viagem como GPX ou CSV pelo menu ••• dela — grátis, sem
assinatura.

CORRIGIDO

O primeiro início após a atualização não trava mais. O crédito da Apple Maps
no Atlas não parece mais uma placa clara. As fotos do carro voltam a
sincronizar.
```

### Kazakh — В КАРТОЧКЕ ЭТОЙ ЛОКАЛИ НЕТ, вставлять некуда

```
ПЛЮС

TripTrack-та енді жазылым бар. «Плюс» қолданбаны өзіңізге ыңғайлы ететін төрт
жол ашады — профильдің премиум фондары, аты жанындағы белгішесі бар аватар
жақтауы, гараждағы көлік картасының фоны және картадағы өз маршрут
сызығыңыздың түсі — әрі бір мүмкіндік: жазылмаған сапарды нақты жолмен
нүкте-нүктелеп қолмен жазу. Оны «Мен» қойындысынан бастаңыз — «Тарих»
тақырыбындағы плюс түймесімен немесе күнтізбедегі бос күнге түрту арқылы.
Қолмен жазылған сапар қашықтыққа, аймақтарға, «Атласқа» және одометрге бәрібір
қосылады; тәжірибе, деңгей, белгі және олжа бермейді — олар тікелей жазылған
сапарда қалады.

«Плюс» — 7 күн тегін сынақпен жылдық жазылым немесе сынақсыз айлық. «Сатып
алуларды қалпына келтіру» «Плюс» ұсынылған жерде әрқашан бір түртімде.

ОРЫНДАР

«Орындар» енді сіз жиі баратын жерлерді ұсынады — сапарларыңыздың әдетте
қайдан басталып, қайда аяқталатынына қарап. Орынды сақтау — бір түрту, ал
барлық ұсыныстар бұрыннан сақталған орындармен бір картада көрінеді.

ЭКСПОРТ

Өз сапарыңыздың «…» мәзірінен GPX немесе CSV форматында экспорттаңыз — тегін,
жазылымсыз.

ТҮЗЕТІЛДІ

Жаңартудан кейінгі алғашқы іске қосылу енді тоқтап қалмайды. «Атластағы» Apple
Maps жазбасы енді жарқын тақташаға ұқсамайды. Көлік фотосуреттері қайта
синхрондалады.
```

---

## 2. Промо-текст (170)

Один и тот же смысл в двенадцати локалях. Лимит — 170 знаков, проверено
`wc -m`.

**English (U.S.)**

```
Plus adds premium looks, your own route colour, and trips written in by hand — plus a tip jar for saying thanks. 7-day free trial on the yearly plan.
```

**Russian**

```
«Плюс» — премиум-фоны, свой цвет линии и поездки, вписанные вручную. Плюс донат — просто спасибо. 7 дней бесплатно на годовой подписке.
```

**German**

```
Plus bringt Premium-Optik, eine eigene Routenfarbe und handschriftlich eingetragene Fahrten — plus ein Trinkgeld als Dankeschön. 7 Tage kostenlos im Jahresabo.
```

**Spanish (Spain)**

```
Plus trae fondos premium, tu propio color de ruta y trayectos añadidos a mano — más una propina como agradecimiento. 7 días gratis en el plan anual.
```

**French**

```
Plus ajoute des fonds premium, votre couleur de trajet et des trajets inscrits à la main — plus un pourboire pour dire merci. Essai gratuit de 7 jours en annuel.
```

**Italian**

```
Plus porta sfondi premium, un colore di percorso tutto tuo e viaggi inseriti a mano — più una mancia per dire grazie. 7 giorni di prova nell'abbonamento annuale.
```

**Polish**

```
Plus to premium tła, własny kolor trasy i ręcznie wpisane przejazdy — a do tego napiwek jako podziękowanie. 7 dni za darmo w planie rocznym.
```

**Indonesian**

```
Plus: latar premium, warna rute sendiri, dan perjalanan yang ditulis tangan — plus kotak tip sebagai terima kasih. Uji coba gratis 7 hari di paket tahunan.
```

**Turkish**

```
Plus; premium görünüm, kendi rota renginiz ve elle girilen yolculuklar getiriyor — bahşiş kutusu da teşekkür için. Yıllık planda 7 gün ücretsiz deneme.
```

**Filipino → слот Finnish**

```
Dala ng Plus ang premium na itsura, sariling kulay ng ruta, at mga biyaheng manu-mano — at tip jar bilang pasasalamat. 7 araw libreng pagsubok, taunang plano.
```

**Ukrainian**

```
«Плюс» — преміум-фони, свій колір лінії й поїздки, вписані вручну. А ще чайові — просто подяка. 7 днів безкоштовно на річній підписці.
```

**Portuguese (Brazil)**

```
O Plus traz fundos premium, sua própria cor de rota e viagens registradas à mão — mais uma gorjeta para dizer obrigado. 7 dias grátis no plano anual.
```

---

## 3. Что проверить в карточке перед «Submit»

- [ ] «What's New» заполнен во **всех двенадцати** локалях карточки. Филиппинский
      текст — в слот **Finnish**. Казахский блок пропустить, локали нет.
- [ ] Оба продукта подписки и три доната — «Ready to Submit» или «Approved» в
      Monetization ДО прикрепления к билду (см. `checklist.md` §1). Пустой
      список товаров у ревьюера — типовая причина отказа 2.1.
- [ ] **App Privacy — ИЗМЕНЕНИЯ ЕСТЬ, в отличие от 0.6.8 и 0.7.0.** Новый тип
      данных: **Purchase History** (App Functionality, Linked to You, Tracking
      = No) — сервер хранит `product_id`/`status`/`expires_at`/`is_trial` по
      подтверждённой транзакции, привязанные к аккаунту. Текст ответа —
      `app-review-notes.md`, «Если спросят про приватность». Донат в это НЕ
      входит — про чаевые сервер не знает вовсе, они не идут дальше StoreKit.
      Обновить `docs/releases/app-privacy.md` (строка 24, «Purchases → Purchase
      History» — с ❌ на ✅) тем же ходом, что при любой смене анкеты.
- [ ] Notes для ревьюера — блок v0.8.0 из `../app-review-notes.md`, включая
      «How to test the subscription in sandbox».
- [ ] Скриншоты: пейвол и/или премиум-фон профиля — **желательны, но не
      обязательны** (прежний набор остаётся валидным, подписка не меняет
      ключевые экраны).
- [ ] Бэкенд выкачен **до** сабмита, включая `APPLE_APP_APPLE_ID` и URL
      уведомлений — см. `checklist.md` §1. Правило Cloudflare `/j/*` и т.п. в
      этот раз не нужно: новых публичных веб-путей версия не заводит.
