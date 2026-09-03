# App Store Connect — 0.6.3

Всё, что нужно вставить при выкладке билда **0.6.3 (54)**. Заметки для ревьюера —
отдельно, в [app-review-notes.md](app-review-notes.md), секция «current submission».

**В карточке ДВЕНАДЦАТЬ локализаций, и «What's New» обязателен в каждой.**
Сабмит 0.6.2 был отклонён ровно из-за этого. Тексты ниже покрывают все двенадцать.

Релиз **не чисто клиентский**: серверная половина (эндпоинт публичных поездок
и четыре колонки видимости) деплоится **первой**, до сабмита. Порядок безопасен
в обе стороны: старый клиент со свежим бэкендом ничего не замечает, новый клиент
со старым бэкендом получает 404 на `/users/:id/trips` и просто не показывает две
карточки-входа.

Ключевые слова, подзаголовок и описание не меняются — ASO этот релиз не трогает.
Лимиты: «What's New» — 4000, промо-текст — 170.

---

## 1. What's New

### English (U.S.)

```
SEE WHERE SOMEONE HAS ACTUALLY BEEN

A profile used to be three numbers. Now it opens: their full statistics — the
monthly rhythm, the records board, the new places they reached — and a map of
every route they made public.

Both are the same screens you have for yourself, drawn with their drives
instead of yours. The map says «public routes» under its title, because the
counters on a profile still count everything, private trips included, and the
map can only ever draw what was published.

YOU DECIDE WHAT SHOWS

A new «What others see» section in Privacy has four switches: basic counters,
full statistics, map, achievements. Everything starts on — nothing about your
profile changed the day you updated — and anything you switch off simply is
not there for other people. No «hidden» placeholder, and the data does not
leave the server at all.
```

### Русский

```
ВИДНО, ГДЕ ЧЕЛОВЕК ПРАВДА БЫЛ

Раньше профиль был тремя числами. Теперь он открывается: полная статистика —
ритм по месяцам, доска почёта, новые места — и карта всех маршрутов, которые
человек сделал публичными.

Это те же экраны, что у вас для себя, только с его поездками. Под заголовком
карты стоит «публичные маршруты»: счётчики профиля считают все поездки, включая
приватные, а карта может нарисовать только опубликованное.

ВЫ РЕШАЕТЕ, ЧТО ПОКАЗЫВАТЬ

В «Приватности» появился раздел «Кто что видит» с четырьмя тумблерами: базовые
счётчики, расширенная статистика, карта, достижения. Всё включено с самого
начала — в день обновления в вашем профиле ничего не изменилось, — а выключенный
блок у других просто отсутствует. Без плашки «скрыто», и данные вообще не
покидают сервер.
```

### German

```
SEHEN, WO JEMAND WIRKLICH WAR

Ein Profil waren bisher drei Zahlen. Jetzt lässt es sich öffnen: die vollständige Statistik — der Rhythmus über die Monate, die Bestenliste, die neuen Orte — und eine Karte aller Routen, die diese Person öffentlich gemacht hat.

Beides sind dieselben Bildschirme, die du für dich selbst hast, nur mit ihren Fahrten. Unter dem Kartentitel steht «öffentliche Routen»: die Zahlen im Profil zählen alle Fahrten, auch private, die Karte kann nur zeigen, was veröffentlicht wurde.

DU ENTSCHEIDEST, WAS SICHTBAR IST

In den Privatsphäre-Einstellungen gibt es jetzt «Was andere sehen» mit vier Schaltern: Grundzahlen, vollständige Statistik, Karte, Erfolge. Alles ist von Anfang an an — am Tag des Updates hat sich an deinem Profil nichts geändert — und was du abschaltest, ist für andere schlicht nicht da. Ohne Platzhalter, und die Daten verlassen den Server gar nicht erst.
```

### Spanish (Spain)

```
VER DÓNDE HA ESTADO ALGUIEN DE VERDAD

Un perfil eran tres cifras. Ahora se abre: sus estadísticas completas — el ritmo por meses, la tabla de récords, los lugares nuevos — y un mapa de todas las rutas que ha hecho públicas.

Son las mismas pantallas que tienes para ti, dibujadas con sus viajes. Bajo el título del mapa pone «rutas públicas»: las cifras del perfil cuentan todos los viajes, también los privados, y el mapa solo puede dibujar lo publicado.

TÚ DECIDES QUÉ SE VE

En Privacidad hay una sección nueva, «Qué ven los demás», con cuatro interruptores: cifras básicas, estadísticas completas, mapa y logros. Todo empieza activado — el día de la actualización tu perfil no cambió — y lo que desactives simplemente no está para los demás. Sin ningún cartel de «oculto», y los datos ni siquiera salen del servidor.
```

### French

```
VOIR OÙ QUELQU'UN EST VRAIMENT PASSÉ

Un profil, c'étaient trois chiffres. Il s'ouvre désormais : ses statistiques complètes — le rythme mois par mois, le tableau des records, les lieux inédits — et une carte de tous les trajets qu'il a rendus publics.

Ce sont les mêmes écrans que les vôtres, tracés avec ses trajets. Sous le titre de la carte, il est écrit « trajets publics » : les chiffres du profil comptent tous les trajets, y compris privés, et la carte ne peut montrer que ce qui a été publié.

C'EST VOUS QUI DÉCIDEZ

Une nouvelle section « Ce que voient les autres » dans Confidentialité propose quatre interrupteurs : chiffres de base, statistiques complètes, carte, succès. Tout est activé au départ — le jour de la mise à jour, rien n'a changé dans votre profil — et ce que vous désactivez n'existe tout simplement pas pour les autres. Sans mention « masqué », et les données ne quittent pas le serveur.
```

### Italian

```
VEDERE DOV'È STATO DAVVERO QUALCUNO

Un profilo erano tre numeri. Ora si apre: le sue statistiche complete — il ritmo mese per mese, l'albo d'oro, i posti nuovi — e una mappa di tutti i percorsi che ha reso pubblici.

Sono le stesse schermate che hai per te, disegnate con i suoi viaggi. Sotto il titolo della mappa c'è scritto «percorsi pubblici»: i numeri del profilo contano tutti i viaggi, anche quelli privati, e la mappa può mostrare solo ciò che è stato pubblicato.

DECIDI TU COSA SI VEDE

In Privacy c'è una nuova sezione «Cosa vedono gli altri» con quattro interruttori: numeri di base, statistiche complete, mappa, traguardi. Tutto parte acceso — il giorno dell'aggiornamento nel tuo profilo non è cambiato nulla — e ciò che spegni per gli altri semplicemente non c'è. Senza scritte «nascosto», e i dati non escono nemmeno dal server.
```

### Polish

```
WIDAĆ, GDZIE KTOŚ NAPRAWDĘ BYŁ

Profil był trzema liczbami. Teraz się otwiera: pełne statystyki — rytm miesiąc po miesiącu, tablica rekordów, nowe miejsca — i mapa wszystkich tras, które ktoś upublicznił.

To te same ekrany, które masz dla siebie, tylko z jego trasami. Pod tytułem mapy jest napis «trasy publiczne»: liczby w profilu liczą wszystkie trasy, także prywatne, a mapa może pokazać tylko to, co zostało opublikowane.

TY DECYDUJESZ, CO WIDAĆ

W Prywatności pojawiła się sekcja «Co widzą inni» z czterema przełącznikami: podstawowe liczby, pełne statystyki, mapa, osiągnięcia. Wszystko jest od początku włączone — w dniu aktualizacji nic się w Twoim profilu nie zmieniło — a to, co wyłączysz, dla innych po prostu nie istnieje. Bez plakietki «ukryte», a dane w ogóle nie opuszczają serwera.
```

### Indonesian

```
LIHAT KE MANA SESEORANG BENAR-BENAR PERGI

Dulu profil hanya tiga angka. Sekarang bisa dibuka: statistik lengkapnya — ritme per bulan, papan rekor, tempat-tempat baru — dan peta semua rute yang dia jadikan publik.

Keduanya layar yang sama seperti milikmu sendiri, hanya digambar dengan perjalanannya. Di bawah judul peta tertulis «rute publik»: angka di profil menghitung semua perjalanan, termasuk yang privat, sedangkan peta hanya bisa menggambar yang sudah dipublikasikan.

KAMU YANG MENENTUKAN APA YANG TAMPIL

Di Privasi ada bagian baru «Yang dilihat orang lain» dengan empat sakelar: angka dasar, statistik lengkap, peta, pencapaian. Semuanya menyala sejak awal — pada hari pembaruan tidak ada yang berubah di profilmu — dan yang kamu matikan memang tidak ada bagi orang lain. Tanpa label «disembunyikan», dan datanya sama sekali tidak keluar dari server.
```

### Turkish

```
BİRİNİN GERÇEKTEN NEREYE GİTTİĞİ GÖRÜNÜYOR

Profil eskiden üç sayıydı. Artık açılıyor: tüm istatistikleri — aylara göre ritim, rekorlar tablosu, yeni yerler — ve herkese açık yaptığı bütün rotaların haritası.

İkisi de kendin için kullandığın ekranların aynısı, sadece onun gezileriyle çizilmiş. Haritanın başlığının altında «herkese açık rotalar» yazıyor: profildeki sayılar özel geziler dahil hepsini sayar, harita ise yalnızca yayınlananı çizebilir.

NEYİN GÖRÜNECEĞİNE SEN KARAR VER

Gizlilik'te dört anahtarlı yeni bir «Başkaları ne görüyor» bölümü var: temel sayılar, tüm istatistikler, harita, başarımlar. Hepsi baştan açık — güncelleme günü profilinde hiçbir şey değişmedi — ve kapattığın şey başkaları için hiç yok. «Gizli» yazısı da çıkmaz, veri zaten sunucudan hiç ayrılmaz.
```

### Ukrainian

```
ВИДНО, ДЕ ЛЮДИНА СПРАВДІ БУЛА

Раніше профіль був трьома числами. Тепер він відкривається: повна статистика — ритм за місяцями, дошка пошани, нові місця — і карта всіх маршрутів, які людина зробила публічними.

Це ті самі екрани, що у вас для себе, тільки з її поїздками. Під заголовком карти стоїть «публічні маршрути»: лічильники профілю рахують усі поїздки, зокрема приватні, а карта може намалювати лише опубліковане.

ВИ ВИРІШУЄТЕ, ЩО ПОКАЗУВАТИ

У «Приватності» з'явився розділ «Хто що бачить» із чотирма перемикачами: базові лічильники, розширена статистика, карта, досягнення. Усе ввімкнено від початку — у день оновлення у вашому профілі нічого не змінилося, — а вимкнений блок в інших просто відсутній. Без плашки «приховано», і дані взагалі не покидають сервер.
```

### Finnish

> ⚠️ В приложении финского языка НЕТ — тринадцатый язык у нас Filipino (`fil`).
> Похоже на путаницу `fil`/`fi` при заведении локализаций (см.
> [app-store-0.6.2-locales.md](app-store-0.6.2-locales.md)). Текст написан,
> чтобы не блокировать сабмит; разобраться с локалью стоит отдельно.

```
NÄET, MISSÄ JOKU ON OIKEASTI KÄYNYT

Profiili oli ennen kolme lukua. Nyt se aukeaa: koko tilasto — kuukausien rytmi, ennätystaulu, uudet paikat — ja kartta kaikista reiteistä, jotka hän on julkaissut.

Molemmat ovat samat näkymät kuin sinulla itselläsi, vain hänen ajoillaan piirrettyinä. Kartan otsikon alla lukee «julkiset reitit»: profiilin luvut laskevat kaikki ajot, myös yksityiset, ja kartta voi piirtää vain julkaistun.

SINÄ PÄÄTÄT, MITÄ NÄKYY

Yksityisyysasetuksiin tuli «Mitä muut näkevät» ja neljä kytkintä: perusluvut, koko tilasto, kartta, saavutukset. Kaikki on alusta asti päällä — päivityspäivänä profiilissasi ei muuttunut mitään — ja pois kytketty osa ei yksinkertaisesti ole muille olemassa. Ei «piilotettu»-merkintää, eivätkä tiedot lähde palvelimelta lainkaan.
```

### Portuguese (Brazil)

```
DÁ PARA VER ONDE ALGUÉM REALMENTE ESTEVE

Um perfil eram três números. Agora ele abre: as estatísticas completas — o ritmo mês a mês, o quadro de recordes, os lugares novos — e um mapa de todas as rotas que a pessoa tornou públicas.

São as mesmas telas que você tem para si, desenhadas com as viagens dela. Embaixo do título do mapa está escrito «rotas públicas»: os números do perfil contam todas as viagens, inclusive as privadas, e o mapa só consegue desenhar o que foi publicado.

VOCÊ DECIDE O QUE APARECE

Em Privacidade há uma seção nova, «O que os outros veem», com quatro chaves: números básicos, estatísticas completas, mapa e conquistas. Tudo começa ligado — no dia da atualização nada mudou no seu perfil — e o que você desliga simplesmente não existe para os outros. Sem aviso de «oculto», e os dados nem saem do servidor.
```

---

## 2. Промо-текст (≤170)

**EN:** Open a profile and see the whole road: full stats and a map of every public route. You choose what yours shows.

**RU:** Откройте профиль и увидите всю дорогу: полную статистику и карту публичных маршрутов. Что показывать у себя — решаете вы.

---

## 3. Что проверить перед отправкой

0. **Запушить бэкенд ПЕРВЫМ** (`trip-track-backend`, master → origin): CI
   задеплоит, `DB_SYNC=true` создаст новые колонки при старте; миграции
   guarded. Колонок теперь пять: четыре видимости профиля на `account` и
   `visible_to_others` на `vehicle`. После деплоя проверить, что
   `/users/<id>/trips` отвечает 200 и что `/auth/me` вернул четыре новых флага.
   Клиент без этого деплоя не сломается, но обе фичи видимости будут молчать.
1. Билд **0.6.3 (54)**. Сайт трогать не нужно.
2. «What's New» вставлен во **ВСЕ ДВЕНАДЦАТЬ** локалей. Пустое поле хотя бы в
   одной = отказ на сабмите (урок 0.6.2).
3. Промо-текст обновлён в обеих основных локалях (необязательно).
4. **Смоук чужого профиля** (10 минут, нужны два аккаунта): открыть чужой
   профиль → обе карточки-входа на месте → статистика открывается и показывает
   ЕГО числа, а не свои → карта показывает только его публичные маршруты и
   подписана «публичные маршруты».
5. **Смоук видимости:** выключить «Карту» у себя → со второго аккаунта карточка
   карты исчезла целиком, без плашки «скрыто» → включить обратно → вернулась.
5a. **Смоук машины:** выключить «Показывать машину другим» → со второго
   аккаунта машина пропала И из профиля, И с карточек в ленте. До этого релиза
   тумблер не делал ничего: колонки под него на сервере не было.
6. **Проверить, что своя карта не пострадала:** открыть чужую карту, вернуться
   на свою — туман и маршруты владельца на месте. Это главный риск релиза.
7. Демо-аккаунт в App Review Information всё ещё указан.
