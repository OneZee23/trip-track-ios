# App Store Connect — 0.8.1

Всё, что нужно вставить при выкладке билда **0.8.1 (64)**. Заметки для
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
  него ФИЛИППИНСКИЙ текст — так делали в 0.6.3–0.8.0.
- **Казахского в карточке нет вовсе.** В приложении он есть, в списке локалей
  между Italian и Polish пусто.

**Монетизации в этом релизе по-прежнему НЕТ.** `PlusAvailability.isEnabled`
остаётся `false`: ни подписки, ни доната, ни вписанной вручную поездки не
видит никто ни в одном регионе. В App Store Connect для 0.8.1 **не идёт ни
один In-App Purchase** — товары заводить не нужно.

Ключевые слова, подзаголовок и описание карточки не меняются — только «What's
New». Лимиты: «What's New» — 4000, промо-текст — 170.

---

## 1. What's New

### English (U.S.)

```
A TRACK WITHOUT GAPS

An evening city, a tunnel, an underground car park — a weak signal used to
break the route into separate pieces. Now a rougher fix still draws the shape
of the road, and a gap that remains is filled in along real roads and shown as
a grey dashed line. Your distance does not change: only good fixes count
towards it.

REMINDERS NOW ASK

In "Reminders" mode the app no longer decides for you. It saves a draft and
asks "Is this yours?" — on the trip itself, in the summary, in the "Me" tab,
and in a notification if you did not answer straight away. An unconfirmed
draft stays out of the Atlas and out of your statistics.

A NEW LOOK — STILL IN BETA

The Atlas and Places are redrawn: a light paper map, period filters, your
places as pins on it, search and sorting in the list. Both tabs carry a "Beta"
chip — they are still being worked on, and the chip says so.

A NEW ICON

FIXED
• Opening someone else's trip from the feed no longer freezes the app
• Your level no longer resets to 1 while syncing
• Opening a journey from a trip and coming back no longer leaves a black
  rectangle where the map was
• Tapping a region on the Atlas moves the camera to it, not to the whole world
```

### Russian

```
ТРЕК БЕЗ ДЫР

Вечерний город, тоннель, подземный паркинг — слабый сигнал раньше рвал
маршрут на отдельные куски. Теперь фикс похуже всё равно рисует форму дороги,
а оставшийся разрыв достраивается по настоящим дорогам и показан серым
пунктиром. Километры при этом не меняются: в них идут только хорошие точки.

«НАПОМИНАНИЯ» ТЕПЕРЬ СПРАШИВАЮТ

В этом режиме приложение больше не решает за вас. Оно пишет черновик и
спрашивает «Это твоя поездка?» — на самой поездке, в итогах, в «Я» и
уведомлением, если ответа не было сразу. Неподтверждённый черновик не попадает
ни в «Атлас», ни в статистику.

НОВЫЙ ОБЛИК — ПОКА В БЕТЕ

«Атлас» и «Места» перерисованы: светлая бумажная карта, фильтры по периоду,
свои места булавками на ней, поиск и порядок в списке. У обеих вкладок стоит
значок «Бета» — их ещё дорабатывают, и значок об этом говорит.

НОВАЯ ИКОНКА

ИСПРАВЛЕНО
• Чужая поездка из ленты больше не вешает приложение
• Уровень больше не сбрасывается на 1 при синхронизации
• Открыть из поездки путешествие и вернуться больше не оставляет чёрный
  прямоугольник на месте карты
• Нажатие на регион в «Атласе» переводит камеру на него, а не на весь мир
```

### German

```
EINE SPUR OHNE LÜCKEN

Abendliche Stadt, Tunnel, Tiefgarage — ein schwaches Signal zerriss die Route
bisher in einzelne Stücke. Jetzt zeichnet auch ein gröberer Fix die Form der
Straße, und eine verbleibende Lücke wird entlang echter Straßen ergänzt und
als graue gestrichelte Linie gezeigt. Deine Distanz ändert sich nicht: dafür
zählen weiterhin nur gute Fixes.

ERINNERUNGEN FRAGEN JETZT NACH

Im Modus „Erinnerungen“ entscheidet die App nicht mehr für dich. Sie speichert
einen Entwurf und fragt „Ist das deine Fahrt?“ — auf der Fahrt selbst, in der
Zusammenfassung, im Tab „Ich“ und per Mitteilung, falls du nicht sofort
geantwortet hast. Ein unbestätigter Entwurf bleibt aus dem Atlas und aus
deiner Statistik heraus.

NEUES AUSSEHEN — NOCH IN DER BETA

Atlas und Orte wurden neu gezeichnet: helle Papierkarte, Zeitraumfilter, deine
Orte als Nadeln darauf, Suche und Sortierung in der Liste. Beide Tabs tragen
ein „Beta“-Abzeichen — sie werden noch überarbeitet, und das Abzeichen sagt es.

NEUES SYMBOL

BEHOBEN
• Die Fahrt einer anderen Person aus dem Feed friert die App nicht mehr ein
• Dein Level wird beim Synchronisieren nicht mehr auf 1 zurückgesetzt
• Eine Reise aus einer Fahrt öffnen und zurückkehren hinterlässt kein
  schwarzes Rechteck mehr an der Stelle der Karte
• Ein Tippen auf eine Region im Atlas bewegt die Kamera dorthin, nicht auf die
  ganze Welt
```

### Spanish (Spain)

```
UNA RUTA SIN HUECOS

Una ciudad al anochecer, un túnel, un aparcamiento subterráneo: una señal
débil rompía antes la ruta en trozos sueltos. Ahora una posición menos precisa
sigue dibujando la forma de la carretera, y el hueco que quede se completa por
carreteras reales y se muestra con una línea gris discontinua. Tu distancia no
cambia: para ella siguen contando solo las posiciones buenas.

LOS RECORDATORIOS AHORA PREGUNTAN

En el modo «Recordatorios» la app ya no decide por ti. Guarda un borrador y
pregunta «¿Es tuyo este viaje?»: en el propio viaje, en el resumen, en la
pestaña «Yo» y con una notificación si no respondiste enseguida. Un borrador
sin confirmar no entra ni en el Atlas ni en tus estadísticas.

NUEVO ASPECTO, TODAVÍA EN BETA

El Atlas y Lugares están redibujados: mapa claro de papel, filtros por
periodo, tus lugares como chinchetas, búsqueda y orden en la lista. Ambas
pestañas llevan la etiqueta «Beta»: se siguen trabajando, y la etiqueta lo dice.

NUEVO ICONO

CORREGIDO
• Abrir el viaje de otra persona desde el feed ya no bloquea la app
• Tu nivel ya no se reinicia a 1 al sincronizar
• Abrir un viaje largo desde un trayecto y volver ya no deja un rectángulo
  negro donde estaba el mapa
• Tocar una región en el Atlas mueve la cámara hasta ella, no a todo el mundo
```

### French

```
UN TRACÉ SANS TROUS

Une ville le soir, un tunnel, un parking souterrain : un signal faible
coupait jusqu'ici l'itinéraire en morceaux séparés. Désormais, un point moins
précis dessine quand même la forme de la route, et le trou qui subsiste est
complété le long des vraies routes et affiché en pointillés gris. Ta distance
ne change pas : seuls les bons points y comptent toujours.

LES RAPPELS POSENT MAINTENANT LA QUESTION

En mode « Rappels », l'app ne décide plus à ta place. Elle enregistre un
brouillon et demande « C'est ton trajet ? » — sur le trajet, dans le résumé,
dans l'onglet « Moi » et par notification si tu n'as pas répondu tout de
suite. Un brouillon non confirmé reste hors de l'Atlas et hors de tes
statistiques.

UNE NOUVELLE ALLURE, ENCORE EN BÊTA

L'Atlas et Lieux sont redessinés : carte papier claire, filtres par période,
tes lieux en épingles, recherche et tri dans la liste. Les deux onglets
portent une pastille « Bêta » — ils évoluent encore, et la pastille le dit.

UNE NOUVELLE ICÔNE

CORRIGÉ
• Ouvrir le trajet de quelqu'un d'autre depuis le fil ne fige plus l'app
• Ton niveau ne retombe plus à 1 lors de la synchronisation
• Ouvrir un voyage depuis un trajet puis revenir ne laisse plus un rectangle
  noir à la place de la carte
• Toucher une région dans l'Atlas amène la caméra dessus, pas sur le monde
  entier
```

### Italian

```
UNA TRACCIA SENZA BUCHI

Una città di sera, un tunnel, un parcheggio sotterraneo: un segnale debole
spezzava il percorso in pezzi separati. Ora anche una posizione meno precisa
disegna la forma della strada, e il buco che resta viene completato lungo
strade vere e mostrato con una linea grigia tratteggiata. La tua distanza non
cambia: per lei contano ancora solo le posizioni buone.

I PROMEMORIA ORA CHIEDONO

Nella modalità «Promemoria» l'app non decide più al posto tuo. Salva una bozza
e chiede «È tuo questo viaggio?» — sul viaggio stesso, nel riepilogo, nella
scheda «Io» e con una notifica se non hai risposto subito. Una bozza non
confermata resta fuori dall'Atlante e fuori dalle tue statistiche.

UN NUOVO ASPETTO, ANCORA IN BETA

Atlante e Luoghi sono ridisegnati: mappa chiara di carta, filtri per periodo,
i tuoi luoghi come spilli, ricerca e ordine nell'elenco. Entrambe le schede
hanno l'etichetta «Beta»: sono ancora in lavorazione, e l'etichetta lo dice.

UNA NUOVA ICONA

CORRETTO
• Aprire il viaggio di un'altra persona dal feed non blocca più l'app
• Il tuo livello non torna più a 1 durante la sincronizzazione
• Aprire un viaggio lungo da un percorso e tornare indietro non lascia più un
  rettangolo nero al posto della mappa
• Toccare una regione nell'Atlante porta la telecamera lì, non su tutto il
  mondo
```

### Polish

```
TRASA BEZ DZIUR

Wieczorne miasto, tunel, podziemny parking — słaby sygnał wcześniej rozrywał
trasę na osobne kawałki. Teraz gorszy pomiar i tak rysuje kształt drogi, a
pozostała dziura jest uzupełniana po prawdziwych drogach i pokazana szarą
linią przerywaną. Twój dystans się nie zmienia: liczą się do niego nadal tylko
dobre pomiary.

PRZYPOMNIENIA TERAZ PYTAJĄ

W trybie „Przypomnienia” aplikacja nie decyduje już za ciebie. Zapisuje
szkic i pyta „Czy to twój przejazd?” — na samym przejeździe, w podsumowaniu,
w zakładce „Ja” i powiadomieniem, jeśli nie odpowiedziałeś od razu.
Niepotwierdzony szkic nie trafia ani do Atlasu, ani do statystyk.

NOWY WYGLĄD — WCIĄŻ W BECIE

Atlas i Miejsca są przerysowane: jasna papierowa mapa, filtry okresu, twoje
miejsca jako pinezki, wyszukiwanie i sortowanie na liście. Obie zakładki mają
plakietkę „Beta” — wciąż nad nimi pracujemy, i plakietka to mówi.

NOWA IKONA

POPRAWIONO
• Otwarcie cudzego przejazdu z kanału nie zawiesza już aplikacji
• Twój poziom nie resetuje się już do 1 przy synchronizacji
• Otwarcie podróży z przejazdu i powrót nie zostawia już czarnego prostokąta
  w miejscu mapy
• Dotknięcie regionu w Atlasie przenosi kamerę na niego, a nie na cały świat
```

### Indonesian

```
JEJAK TANPA CELAH

Kota di malam hari, terowongan, parkir bawah tanah — sinyal lemah dulu
memecah rute menjadi potongan terpisah. Kini posisi yang lebih kasar tetap
menggambar bentuk jalan, dan celah yang tersisa dilengkapi mengikuti jalan
sungguhan dan ditampilkan sebagai garis putus-putus abu-abu. Jarakmu tidak
berubah: yang dihitung tetap hanya posisi yang baik.

"PENGINGAT" KINI BERTANYA

Dalam mode "Pengingat" aplikasi tidak lagi memutuskan untukmu. Ia menyimpan
draf dan bertanya "Ini perjalananmu?" — pada perjalanannya, di ringkasan, di
tab "Saya", dan lewat notifikasi kalau kamu belum menjawab. Draf yang belum
dikonfirmasi tidak masuk ke Atlas maupun ke statistikmu.

TAMPILAN BARU — MASIH BETA

Atlas dan Tempat digambar ulang: peta kertas terang, filter periode,
tempat-tempatmu sebagai pin, pencarian dan urutan di daftar. Kedua tab
membawa label "Beta" — keduanya masih dikerjakan, dan label itu
mengatakannya.

IKON BARU

DIPERBAIKI
• Membuka perjalanan orang lain dari feed tidak lagi membuat aplikasi macet
• Levelmu tidak lagi kembali ke 1 saat sinkronisasi
• Membuka perjalanan panjang dari sebuah trip lalu kembali tidak lagi
  meninggalkan persegi hitam di tempat peta
• Mengetuk wilayah di Atlas memindahkan kamera ke sana, bukan ke seluruh dunia
```

### Turkish

```
BOŞLUKSUZ İZ

Akşam şehri, tünel, yeraltı otoparkı — zayıf sinyal rotayı eskiden ayrı
parçalara bölüyordu. Artık daha kaba bir konum da yolun şeklini çiziyor, kalan
boşluk gerçek yollar boyunca tamamlanıyor ve gri kesik çizgiyle gösteriliyor.
Mesafen değişmiyor: ona yine yalnızca iyi konumlar sayılıyor.

"HATIRLATMALAR" ARTIK SORUYOR

"Hatırlatmalar" modunda uygulama artık senin yerine karar vermiyor. Bir taslak
kaydediyor ve "Bu senin yolculuğun mu?" diye soruyor — yolculuğun kendisinde,
özette, "Ben" sekmesinde ve hemen yanıtlamadıysan bildirimle. Onaylanmamış bir
taslak ne Atlas'a ne de istatistiklerine girer.

YENİ GÖRÜNÜM — HENÜZ BETA

Atlas ve Yerler yeniden çizildi: açık kâğıt harita, dönem filtreleri, üzerinde
iğne olarak yerlerin, listede arama ve sıralama. Her iki sekmede de "Beta"
rozeti var — üzerlerinde hâlâ çalışılıyor, rozet de bunu söylüyor.

YENİ SİMGE

DÜZELTİLDİ
• Akıştan başkasının yolculuğunu açmak artık uygulamayı dondurmuyor
• Seviyen eşitleme sırasında artık 1'e düşmüyor
• Bir yolculuktan uzun bir seyahati açıp geri dönmek artık haritanın yerinde
  siyah dikdörtgen bırakmıyor
• Atlas'ta bir bölgeye dokunmak kamerayı oraya götürüyor, tüm dünyaya değil
```

### Finnish (слот = ФИЛИППИНСКИЙ текст)

```
TRACK NA WALANG PUWANG

Lungsod sa gabi, tunnel, underground parking — dati, pinuputol ng mahinang
signal ang ruta sa magkakahiwalay na piraso. Ngayon, kahit magaspang na fix ay
gumuguhit pa rin ng hugis ng daan, at ang natitirang puwang ay pinupunan
sunod sa totoong mga daan at ipinapakita bilang kulay-abong tuldok-tuldok na
linya. Hindi nagbabago ang distansya mo: mabubuting fix lang pa rin ang
binibilang doon.

NAGTATANONG NA ANG "MGA PAALALA"

Sa mode na "Mga Paalala", hindi na nagpapasya ang app para sa iyo. Nagse-save
ito ng draft at nagtatanong ng "Sa iyo ba ito?" — sa mismong biyahe, sa
buod, sa tab na "Ako", at sa notification kung hindi ka agad sumagot. Ang
draft na hindi pa nakumpirma ay hindi pumapasok sa Atlas o sa istatistika mo.

BAGONG ITSURA — BETA PA

Muling iginuhit ang Atlas at Mga Lugar: maliwanag na mapang papel, mga filter
ng panahon, ang mga lugar mo bilang pin, paghahanap at pag-aayos sa listahan.
May "Beta" chip ang dalawang tab — ginagawa pa ang mga ito, at sinasabi iyon
ng chip.

BAGONG ICON

INAYOS
• Ang pagbukas ng biyahe ng iba mula sa feed ay hindi na nagya-freeze sa app
• Hindi na bumabalik sa 1 ang level mo kapag nagsi-sync
• Ang pagbukas ng mahabang paglalakbay mula sa isang biyahe at pagbalik ay
  hindi na nag-iiwan ng itim na parisukat kung nasaan ang mapa
• Ang pag-tap sa isang rehiyon sa Atlas ay inilalapit ang kamera doon, hindi
  sa buong mundo
```

### Ukrainian

```
ТРЕК БЕЗ ДІРОК

Вечірнє місто, тунель, підземний паркінг — слабкий сигнал раніше рвав маршрут
на окремі шматки. Тепер гірша точка все одно малює форму дороги, а розрив, що
лишився, добудовується справжніми дорогами й показаний сірим пунктиром.
Кілометри при цьому не змінюються: до них ідуть лише хороші точки.

«НАГАДУВАННЯ» ТЕПЕР ПИТАЮТЬ

У цьому режимі застосунок більше не вирішує за тебе. Він пише чернетку й питає
«Це твоя поїздка?» — на самій поїздці, у підсумках, у «Я» та сповіщенням, якщо
відповіді не було одразу. Непідтверджена чернетка не потрапляє ні до «Атласу»,
ні до статистики.

НОВИЙ ВИГЛЯД — ПОКИ В БЕТІ

«Атлас» і «Місця» перемальовані: світла паперова карта, фільтри за періодом,
свої місця шпильками на ній, пошук і порядок у списку. Обидві вкладки мають
значок «Бета» — їх ще допрацьовують, і значок про це каже.

НОВА ІКОНКА

ВИПРАВЛЕНО
• Чужа поїздка зі стрічки більше не вішає застосунок
• Рівень більше не скидається на 1 під час синхронізації
• Відкрити з поїздки подорож і повернутися більше не лишає чорний прямокутник
  на місці карти
• Дотик до регіону в «Атласі» переводить камеру на нього, а не на весь світ
```

### Portuguese (Brazil)

```
UM TRAJETO SEM FALHAS

Cidade à noite, túnel, estacionamento subterrâneo — um sinal fraco antes
quebrava a rota em pedaços separados. Agora uma posição mais grosseira ainda
desenha o formato da via, e a falha que sobra é completada por ruas reais e
mostrada como uma linha cinza tracejada. Sua distância não muda: para ela
continuam contando só as posições boas.

OS "LEMBRETES" AGORA PERGUNTAM

No modo "Lembretes" o app não decide mais por você. Ele salva um rascunho e
pergunta "Esta viagem é sua?" — na própria viagem, no resumo, na aba "Eu" e
por notificação se você não respondeu na hora. Um rascunho não confirmado fica
de fora do Atlas e das suas estatísticas.

VISUAL NOVO — AINDA EM BETA

Atlas e Lugares foram redesenhados: mapa claro de papel, filtros por período,
seus lugares como alfinetes, busca e ordenação na lista. As duas abas têm o
selo "Beta" — ainda estão sendo trabalhadas, e o selo diz isso.

ÍCONE NOVO

CORRIGIDO
• Abrir a viagem de outra pessoa pelo feed não trava mais o app
• Seu nível não volta mais para 1 ao sincronizar
• Abrir uma jornada a partir de uma viagem e voltar não deixa mais um
  retângulo preto no lugar do mapa
• Tocar em uma região no Atlas leva a câmera até ela, não ao mundo inteiro
```

---

## 2. Промо-текст (170 знаков) — не меняется

Остаётся тот же, что в 0.8.0. Промо-текст не привязан к билду и правится в
любой момент.

---

## 3. Скриншоты

**Менять не обязательно.** Карточка 0.8.0 снята на «Атласе» и «Местах»
прежнего оформления, но оба экрана в 0.8.1 помечены «Бета» и будут
переделываться ещё раз — снимать их заново ради промежуточного вида смысла
нет.

Если всё же меняем, то ТОЛЬКО кадр с иконкой/главным экраном — новая иконка
D2 это единственное, что в карточке видно и не изменится в следующей версии.
