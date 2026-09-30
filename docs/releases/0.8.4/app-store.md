# App Store Connect — 0.8.4

Всё, что нужно вставить при выкладке билда **0.8.4 (67)**. Заметки для
ревьюера — в [app-review-notes.md](../app-review-notes.md), секция «current
submission». Товары и цены — в
[app-store-connect-setup.md](app-store-connect-setup.md).

**ЭТОТ ТЕКСТ ОБЕЩАЕТ PRO. Значит до сабмита обязаны сойтись ТРИ вещи:**

1. Товары заведены в App Store Connect и в состоянии «Ready to Submit»
   (шаги 1–2 в `app-store-connect-setup.md`).
2. `PlusAvailability.isEnabled` переключён в `true` (шаг 4 там же) — иначе
   карточка рассказывает про экран, которого в сборке нет вовсе.
3. Билд собран ПОСЛЕ переключения флага.

Порядок именно такой. Промахнёшься флагом — получишь отказ ревью за то, что
описанного в «What's New» в приложении не найти, и это самый дорогой вид
отказа: он стоит цикла ревью, а не правки текста.

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
  него ФИЛИППИНСКИЙ текст — так делали в 0.6.3–0.8.3.
- **Казахского в карточке нет вовсе.** В приложении он есть, в списке локалей
  между Italian и Polish пусто.

**БЭКЕНД ДЕПЛОИТЬ НЕ НАДО.** Обратного порядка 0.8.3 здесь нет: миграций в
этой версии ноль, а всё серверное для подписки (`PlusModule`, привязка
покупки, whitelist косметики в `plus-view.ts`) стоит в проде с 0.8.0. Сабмит
идёт обычным путём.

**ЦЕНЫ В ТЕКСТЕ НЕТ, И ЭТО РЕШЕНИЕ.** В карточке США «19,99 €» было бы
неправдой — там платят в долларах, и Apple показывает местную цену сама.
Поэтому во всех локалях стоит «цена показана до оплаты», а числа живут ровно
там, где их подставляет App Store. Ставить их в «What's New» — заводить
тринадцатое место показа цены, которое разойдётся с первым же изменением
тарифа в любой одной стране.

**ПРО РЕГИОНЫ СКАЗАНО ВСЛУХ, в каждой локали.** `PlusGate` прячет PRO
целиком на витрине РФ (ни пейвола, ни замков, ни чаевых, ни вписанной
поездки), а платежи App Store там мертвы с 01.04.2026. Строка «PRO доступен
не во всех регионах» стоит последней в каждом тексте — без неё карточка
обещает человеку то, чего он у себя не найдёт.

**CARPLAY НЕ УПОМИНАЕТСЯ НИГДЕ.** Экран автомобиля в этой сборке есть в коде,
но entitlement `com.apple.developer.carplay-driving-task` Apple ещё не
выдавала, и его нет ни в одном файле прав (см. `EntitlementsWiringTests`). То есть
у человека из App Store CarPlay не заработает. Анонсировать его — обещать
неработающее; он уезжает в ту версию, которая выйдет после ответа Apple.

Ключевые слова, подзаголовок и описание карточки не меняются — только
«What's New». Лимиты: «What's New» — 4000, промо-текст — 170.

---

## What's New по локалям

### English (U.S.)

```
PRO — AND TRIPTRACK STAYS FREE

Everything you have today stays free: recording, the atlas, places, journeys,
photos, statistics. PRO adds extras, not essentials — nothing you already use
moved behind it.

MAKE IT YOURS

Eight backgrounds for your profile, six frames for your avatar, eight styles
for your vehicle card, and styles for the route line on your trips. A PRO mark
next to your name if you want one — and off if you don't.

TRIPS FROM BEFORE

Add a drive you made before you had the app: say where you went, pick the day,
and the route is drawn along real roads. It counts toward your distance, your
atlas and your garage. It does not count toward XP, levels or badges — those
stay for what the app recorded itself.

TIPS

If you just want to support the work, you can leave a tip. No subscription,
nothing to unlock, nothing expected in return.

PRO starts with 7 days free; the price is shown before you pay, and you can
cancel any time. PRO is not available in every region.
```

### Russian

```
PRO — И TRIPTRACK ОСТАЁТСЯ БЕСПЛАТНЫМ

Всё, что у вас есть сегодня, остаётся бесплатным: запись, атлас, места,
путешествия, фотографии, статистика. PRO добавляет приятное, а не нужное —
за него не ушло ничего из того, чем вы уже пользуетесь.

ПОД СЕБЯ

Восемь фонов профиля, шесть рамок аватара, восемь стилей карточки машины и
стили линии маршрута на поездках. Пометка PRO рядом с именем — если хочется;
и без неё, если не хочется.

ПОЕЗДКИ ЗАДНИМ ЧИСЛОМ

Впишите дорогу, которую проехали до того, как поставили приложение: откуда и
куда, какой был день — маршрут построится по настоящим дорогам. Километры
пойдут в общий счёт, в атлас и в гараж. В опыт, уровни и значки — нет: они
остаются за тем, что приложение видело своими глазами.

ЧАЕВЫЕ

Если хочется просто поддержать работу — можно оставить чаевые. Без подписки,
без разблокировки чего-либо и без ожиданий в ответ.

У PRO первые 7 дней бесплатно; цена показана до оплаты, отменить можно в
любой момент. PRO доступен не во всех регионах.
```

### German

```
PRO — UND TRIPTRACK BLEIBT KOSTENLOS

Alles, was du heute hast, bleibt kostenlos: Aufzeichnung, Atlas, Orte, Reisen,
Fotos, Statistik. PRO fügt Schönes hinzu, nichts Notwendiges — nichts, was du
schon nutzt, ist dahinter gewandert.

NACH DEINEM GESCHMACK

Acht Hintergründe für dein Profil, sechs Rahmen für dein Bild, acht Stile für
die Fahrzeugkarte und Stile für die Routenlinie deiner Fahrten. Ein
PRO-Zeichen neben deinem Namen, wenn du magst — und ohne, wenn nicht.

FAHRTEN VON FRÜHER

Trag eine Fahrt nach, die du vor der App gemacht hast: woher, wohin, welcher
Tag — die Route entsteht entlang echter Straßen. Die Kilometer zählen für
deine Strecke, deinen Atlas und deine Garage. Für XP, Level und Abzeichen
nicht: die bleiben dem, was die App selbst gesehen hat.

TRINKGELD

Wenn du die Arbeit einfach unterstützen willst, kannst du Trinkgeld geben.
Kein Abo, nichts wird freigeschaltet, nichts wird erwartet.

PRO beginnt mit 7 Tagen kostenlos; der Preis steht vor dem Kauf, kündbar
jederzeit. PRO ist nicht in allen Regionen verfügbar.
```

### Spanish (Spain)

```
PRO — Y TRIPTRACK SIGUE SIENDO GRATIS

Todo lo que tienes hoy sigue siendo gratis: la grabación, el atlas, los
lugares, los viajes, las fotos, las estadísticas. PRO añade cosas bonitas, no
necesarias: nada de lo que ya usas se ha movido detrás.

A TU GUSTO

Ocho fondos para tu perfil, seis marcos para tu avatar, ocho estilos para la
tarjeta del coche y estilos para la línea de la ruta en tus viajes. Una marca
PRO junto a tu nombre si te apetece, y sin ella si no.

VIAJES DE ANTES

Añade un trayecto que hiciste antes de tener la app: de dónde a dónde y qué
día, y la ruta se traza por carreteras reales. Los kilómetros cuentan para tu
distancia, tu atlas y tu garaje. Para la experiencia, los niveles y las
insignias no: esas quedan para lo que la app vio por sí misma.

PROPINAS

Si solo quieres apoyar el trabajo, puedes dejar una propina. Sin suscripción,
sin desbloquear nada y sin esperar nada a cambio.

PRO empieza con 7 días gratis; el precio se muestra antes de pagar y puedes
cancelar cuando quieras. PRO no está disponible en todas las regiones.
```

### French

```
PRO — ET TRIPTRACK RESTE GRATUIT

Tout ce que vous avez aujourd'hui reste gratuit : l'enregistrement, l'atlas,
les lieux, les voyages, les photos, les statistiques. PRO ajoute de l'agréable,
pas de l'indispensable — rien de ce que vous utilisez déjà n'est passé derrière.

À VOTRE GOÛT

Huit fonds pour votre profil, six cadres pour votre photo, huit styles pour la
carte du véhicule et des styles pour le tracé de vos trajets. Une marque PRO à
côté de votre nom si vous le souhaitez — et sans, sinon.

LES TRAJETS D'AVANT

Ajoutez un trajet fait avant d'avoir l'application : d'où à où, quel jour, et
l'itinéraire se dessine sur de vraies routes. Les kilomètres comptent pour
votre distance, votre atlas et votre garage. Pas pour l'expérience, les
niveaux ni les badges : ceux-là restent à ce que l'application a vu elle-même.

POURBOIRES

Si vous voulez simplement soutenir le travail, vous pouvez laisser un
pourboire. Sans abonnement, sans rien débloquer et sans rien attendre en retour.

PRO commence par 7 jours offerts ; le prix est indiqué avant le paiement et
vous pouvez résilier à tout moment. PRO n'est pas disponible dans toutes les
régions.
```

### Italian

```
PRO — E TRIPTRACK RESTA GRATUITO

Tutto quello che hai oggi resta gratuito: la registrazione, l'atlante, i
luoghi, i viaggi, le foto, le statistiche. PRO aggiunge cose belle, non
necessarie: nulla di ciò che già usi è finito dietro.

COME TI PIACE

Otto sfondi per il profilo, sei cornici per l'immagine, otto stili per la
scheda del veicolo e stili per la linea del percorso nei viaggi. Un segno PRO
accanto al tuo nome se ti va — e senza, se non ti va.

VIAGGI DI PRIMA

Aggiungi un viaggio fatto prima di avere l'app: da dove a dove e in che
giorno, e il percorso viene tracciato su strade reali. I chilometri contano
per la tua distanza, il tuo atlante e il tuo garage. Per esperienza, livelli e
distintivi no: quelli restano a ciò che l'app ha visto da sé.

MANCE

Se vuoi solo sostenere il lavoro, puoi lasciare una mancia. Senza abbonamento,
senza sbloccare nulla e senza attese in cambio.

PRO inizia con 7 giorni gratis; il prezzo è mostrato prima del pagamento e
puoi annullare quando vuoi. PRO non è disponibile in tutte le regioni.
```

### Polish

```
PRO — A TRIPTRACK POZOSTAJE DARMOWY

Wszystko, co masz dzisiaj, pozostaje darmowe: nagrywanie, atlas, miejsca,
podróże, zdjęcia, statystyki. PRO dodaje rzeczy przyjemne, nie niezbędne — nic
z tego, czego już używasz, nie przeszło za nie.

PO SWOJEMU

Osiem teł profilu, sześć ramek awatara, osiem styli karty pojazdu i style linii
trasy na przejazdach. Znak PRO obok imienia, jeśli chcesz — i bez niego, jeśli
nie.

PRZEJAZDY Z DAWNIEJ

Dopisz przejazd z czasów przed aplikacją: skąd i dokąd, jakiego dnia — trasa powstanie po prawdziwych drogach. Kilometry policzą się
do dystansu, atlasu i garażu. Do doświadczenia, poziomów i odznak nie: te
zostają dla tego, co aplikacja widziała sama.

NAPIWKI

Jeśli chcesz po prostu wesprzeć pracę, możesz zostawić napiwek. Bez subskrypcji,
bez odblokowywania czegokolwiek i bez oczekiwań w zamian.

PRO zaczyna się od 7 dni bezpłatnie; cena jest pokazana przed zapłatą, a
anulować można w każdej chwili. PRO nie jest dostępne we wszystkich regionach.
```

### Indonesian

```
PRO — DAN TRIPTRACK TETAP GRATIS

Semua yang kamu miliki hari ini tetap gratis: perekaman, atlas, tempat,
perjalanan, foto, statistik. PRO menambahkan hal yang menyenangkan, bukan yang
diperlukan — tidak ada yang sudah kamu pakai berpindah ke belakangnya.

SESUAI SELERAMU

Delapan latar profil, enam bingkai avatar, delapan gaya kartu kendaraan, dan
gaya garis rute pada perjalanan. Tanda PRO di sebelah namamu kalau mau — dan
tanpa itu kalau tidak.

PERJALANAN DARI DULU

Tambahkan perjalanan yang kamu lakukan sebelum punya aplikasi ini: dari mana
ke mana dan hari apa, lalu rutenya digambar mengikuti jalan sebenarnya.
Kilometernya masuk ke total jarak, atlas, dan garasimu. Ke XP, level, dan
lencana tidak: itu tetap untuk apa yang direkam aplikasi sendiri.

TIP

Kalau kamu hanya ingin mendukung pekerjaan ini, kamu bisa memberi tip. Tanpa
langganan, tanpa membuka apa pun, dan tanpa harapan balasan.

PRO dimulai dengan 7 hari gratis; harganya ditampilkan sebelum pembayaran dan
bisa dibatalkan kapan saja. PRO tidak tersedia di semua wilayah.
```

### Turkish

```
PRO — VE TRIPTRACK ÜCRETSİZ KALIYOR

Bugün elinde olan her şey ücretsiz kalıyor: kayıt, atlas, yerler, yolculuklar,
fotoğraflar, istatistikler. PRO hoş olanı ekliyor, gerekli olanı değil —
hâlihazırda kullandığın hiçbir şey arkasına geçmedi.

KENDİNE GÖRE

Profil için sekiz arka plan, avatar için altı çerçeve, araç kartı için sekiz
stil ve yolculuklarda güzergâh çizgisi stilleri. İstersen adının yanında bir
PRO işareti — istemezsen olmadan.

ESKİ YOLCULUKLAR

Uygulamayı kurmadan önce yaptığın bir yolculuğu sonradan ekle: nereden nereye
ve hangi gün — güzergâh gerçek yollar üzerinden çizilir. Kilometreler toplam
mesafene, atlasına ve garajına sayılır. Deneyime, seviyelere ve nişanlara
sayılmaz: onlar uygulamanın kendi gördüğüne kalır.

BAHŞİŞ

Sadece bu işi desteklemek istiyorsan bahşiş bırakabilirsin. Abonelik yok, bir
şeyin kilidi açılmıyor ve karşılığında bir şey beklenmiyor.

PRO 7 gün ücretsiz başlar; fiyat ödemeden önce gösterilir ve dilediğin an iptal
edebilirsin. PRO her bölgede kullanılamaz.
```

### Finnish — СЛОТ ФИЛИППИНСКОГО (см. выше, кладём текст на Filipino)

```
PRO — AT MANANATILING LIBRE ANG TRIPTRACK

Lahat ng nasa iyo ngayon ay mananatiling libre: ang pag-record, ang atlas, ang
mga lugar, ang mga paglalakbay, ang mga larawan, ang estadistika. Nagdadagdag
ang PRO ng magaganda, hindi ng kailangan — walang ginagamit mo na lumipat sa
likod nito.

AYON SA GUSTO MO

Walong background para sa profile, anim na frame para sa avatar, walong estilo
para sa card ng sasakyan, at mga estilo ng linya ng ruta sa mga biyahe. May
markang PRO sa tabi ng pangalan mo kung gusto mo — at wala kung hindi.

MGA BIYAHE NOON

Idagdag ang biyaheng ginawa mo bago mo pa magkaroon ng app: saan galing at saan
patungo, at anong araw — iguguhit ang ruta sa tunay na mga kalsada. Bibilangin
ang kilometro sa kabuuang distansya, sa atlas at sa garahe mo. Sa XP, antas at
mga badge, hindi: para lang iyon sa nakita mismo ng app.

TIP

Kung gusto mo lang suportahan ang gawaing ito, maaari kang mag-iwan ng tip.
Walang subscription, walang bubuksan, at walang hinihintay kapalit.

Nagsisimula ang PRO sa 7 araw na libre; makikita ang presyo bago magbayad at
maaari kang mag-cancel anumang oras. Hindi available ang PRO sa lahat ng
rehiyon.
```

### Ukrainian

```
PRO — І TRIPTRACK ЗАЛИШАЄТЬСЯ БЕЗКОШТОВНИМ

Усе, що у вас є сьогодні, залишається безкоштовним: запис, атлас, місця,
подорожі, фотографії, статистика. PRO додає приємне, а не потрібне — за нього
не пішло нічого з того, чим ви вже користуєтеся.

ПІД СЕБЕ

Вісім фонів профілю, шість рамок аватара, вісім стилів картки автомобіля та
стилі лінії маршруту на поїздках. Позначка PRO поруч з іменем — якщо хочеться;
і без неї, якщо ні.

ПОЇЗДКИ ЗАДНІМ ЧИСЛОМ

Впишіть дорогу, яку проїхали до того, як встановили застосунок: звідки й куди,
який був день — маршрут побудується справжніми дорогами. Кілометри підуть у
загальний підрахунок, в атлас і в гараж. У досвід, рівні та значки — ні: вони
залишаються за тим, що застосунок бачив на власні очі.

ЧАЙОВІ

Якщо хочеться просто підтримати роботу — можна залишити чайові. Без підписки,
без розблокування чогось і без очікувань у відповідь.

У PRO перші 7 днів безкоштовно; ціну показано до оплати, скасувати можна будь-
коли. PRO доступний не в усіх регіонах.
```

### Portuguese (Brazil)

```
PRO — E O TRIPTRACK CONTINUA GRATUITO

Tudo o que você tem hoje continua gratuito: a gravação, o atlas, os lugares,
as viagens, as fotos, as estatísticas. O PRO acrescenta o que é agradável, não
o que é necessário — nada do que você já usa foi para trás dele.

DO SEU JEITO

Oito fundos para o perfil, seis molduras para o avatar, oito estilos para o
cartão do veículo e estilos para a linha da rota nas viagens. Uma marca PRO ao
lado do seu nome, se quiser — e sem ela, se não quiser.

VIAGENS DE ANTES

Registre uma viagem que você fez antes de ter o aplicativo: de onde para onde
e em que dia — a rota é traçada por estradas reais. Os quilômetros contam para
a sua distância, o seu atlas e a sua garagem. Para experiência, níveis e
medalhas, não: essas ficam para o que o aplicativo viu por conta própria.

GORJETAS

Se você quiser apenas apoiar o trabalho, pode deixar uma gorjeta. Sem
assinatura, sem desbloquear nada e sem esperar nada em troca.

O PRO começa com 7 dias grátis; o preço é mostrado antes do pagamento e você
pode cancelar quando quiser. O PRO não está disponível em todas as regiões.
```

---

## Обязательные поля подписки в App Store Connect

Заполняются у ГРУППЫ подписок и у каждого тарифа, иначе сабмит не уйдёт.
Полностью — в `app-store-connect-setup.md`; здесь то, что относится к
карточке:

- **Localized display name** и **description** у каждого тарифа — минимум в
  генеральной локали. «PRO Yearly» / «PRO Monthly» как отображаемые имена
  годятся: слово PRO не переводится ни на один из тринадцати языков (решение
  0.8.4), переводится только то, что вокруг.
- **Review screenshot** у каждого тарифа — кадр пейвола. Годятся снимки из
  `TripTrackUITests/PlusShotTests` (`test_plus_row_paywall_and_tip_jar`).
- **Subscription Terms** в описании приложения и ссылки на Privacy Policy и
  Terms of Use — уже стоят в карточке с 0.8.0, менять не надо; проверить, что
  ссылка на Terms открывается (Apple проверяет её у подписок отдельно).

## Чего в сабмите НЕТ

- **CarPlay** — код в сборке есть, entitlement Apple не выдала, в Release его
  нет. Не упоминать ни в «What's New», ни в заметках ревьюеру.
- **Новых разрешений и новых ключей приватности** — ноль. Манифест приватности
  не меняется: подписка не собирает ничего нового, а привязка покупки уезжает
  тем же путём, что и в 0.8.0.
- **Миграций сервера** — ноль.
