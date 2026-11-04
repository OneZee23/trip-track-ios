extension Translations {
    private static let hiddenPartsKeys = [
        "hiddenAddSection", "hiddenAllTrip", "hiddenAlreadySeen", "hiddenChooseEdge", "hiddenDefault", "hiddenEditorTitle", "hiddenEnd",
        "hiddenLocalCardBody", "hiddenLocalCardTitle", "hiddenLocalOnlyNotice", "hiddenNone", "hiddenNumbersPreview", "hiddenNumbersTitle",
        "hiddenOption1000", "hiddenOption200", "hiddenOption500", "hiddenOvernightHint", "hiddenPrivacyIntro", "hiddenPrivacyModeFootnote",
        "hiddenPublishPreviewTitle", "hiddenPublishRow", "hiddenQuestionBody", "hiddenQuestionTitle", "hiddenQuickHide", "hiddenRouteLockAccessibility",
        "hiddenSave", "hiddenSectionEndHandle", "hiddenSectionStartHandle", "hiddenSectionTitle", "hiddenSettingsFootnote", "hiddenShowOwn",
        "hiddenShowPublic", "hiddenStart", "hiddenSummary", "hiddenTapEnd", "hiddenTapMapHint", "hiddenTapStart", "hiddenTitleHint", "hiddenWithoutHidden"
    ]

    private static func makeHiddenParts(_ values: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: zip(hiddenPartsKeys, values))
    }
    static let hiddenPrivacyDE: [String: String] = [
        "privacyEdgesTitle": "Start und Ende der Fahrten", "hiddenQuestionWholeTrips": "Die ganze Route von {count} veröffentlichten Fahrten wird verborgen",
        "hiddenTitleHintStart": "Der Titel „{title}“ nennt den Startort. Titel ändern",
        "hiddenHomeHint": "Anfang verbergen? Hier ist dein Zuhause",
        "privacyPlacesSection": "Orte, die andere nicht sehen",
        "privacyEdgeNever": "Nicht verbergen", "privacyEdge200": "200 m · Hof, Parkplatz",
        "privacyEdge500": "500 m · Viertel, Stellplatz", "privacyEdge1000": "1 km · sicherer beim Campen",
        "privacyEdgeFootnote": "Gilt für alle Fahrten, sofern keine eigene Entfernung festgelegt ist.",
        "filmingTitle": "Aufnahmemodus", "filmingSubtitle": "Verborgene Abschnitte sind auch auf deinen Bildschirmen nicht sichtbar",
        "filmingAutoTitle": "Bei Bildschirmaufnahme einschalten", "filmingAutoSubtitle": "Schaltet sich automatisch ein und aus",
        "filmingFootnote": "Im Aufnahmemodus zeigen Karten und Orte keine verborgenen Strecken, dein Zuhause oder den blauen Standortpunkt. Bei der Aufzeichnung bleibt der Punkt sichtbar.",
        "routeHiddenByAuthor": "Die Route wurde vom Autor verborgen"
    ]
    static let hiddenPrivacyES: [String: String] = [
        "privacyEdgesTitle": "Inicio y final de los viajes", "hiddenQuestionWholeTrips": "Se ocultará toda la ruta de {count} viajes publicados",
        "hiddenTitleHintStart": "El título «{title}» indica el lugar de inicio. Cambiar título",
        "hiddenHomeHint": "¿Ocultar el inicio? Aquí está tu casa",
        "privacyPlacesSection": "Lugares que otros no ven",
        "privacyEdgeNever": "No ocultar", "privacyEdge200": "200 m · patio, aparcamiento",
        "privacyEdge500": "500 m · barrio, campamento", "privacyEdge1000": "1 km · más seguro al acampar",
        "privacyEdgeFootnote": "Se aplica a todos los viajes, salvo que uno tenga una distancia propia.",
        "filmingTitle": "Modo de grabación", "filmingSubtitle": "Las partes ocultas tampoco aparecen en tus pantallas",
        "filmingAutoTitle": "Activar al grabar la pantalla", "filmingAutoSubtitle": "Se activa y desactiva automáticamente",
        "filmingFootnote": "En este modo, los mapas y Lugares ocultan los tramos ocultos, tu casa y el punto azul. La pantalla de grabación conserva el punto.",
        "routeHiddenByAuthor": "El autor ha ocultado la ruta"
    ]
    static let hiddenPrivacyFR: [String: String] = [
        "privacyEdgesTitle": "Début et fin des trajets", "hiddenQuestionWholeTrips": "Tout l’itinéraire de {count} trajets publiés sera masqué",
        "hiddenTitleHintStart": "Le titre « {title} » indique le lieu de départ. Modifier le titre",
        "hiddenHomeHint": "Masquer le début ? Votre domicile est ici",
        "privacyPlacesSection": "Lieux invisibles aux autres",
        "privacyEdgeNever": "Ne pas masquer", "privacyEdge200": "200 m · cour, parking",
        "privacyEdge500": "500 m · quartier, camping", "privacyEdge1000": "1 km · plus sûr en camping",
        "privacyEdgeFootnote": "S’applique à tous les trajets, sauf si une distance propre est définie.",
        "filmingTitle": "Mode vidéo", "filmingSubtitle": "Les parties masquées disparaissent aussi de vos écrans",
        "filmingAutoTitle": "Activer pendant l’enregistrement d’écran", "filmingAutoSubtitle": "S’active et se désactive automatiquement",
        "filmingFootnote": "Dans ce mode, les cartes et Lieux masquent les portions cachées, votre domicile et le point bleu. L’écran d’enregistrement garde le point.",
        "routeHiddenByAuthor": "L’auteur a masqué l’itinéraire"
    ]
    static let hiddenPrivacyIT: [String: String] = [
        "privacyEdgesTitle": "Inizio e fine dei viaggi", "hiddenQuestionWholeTrips": "L’intero percorso di {count} viaggi pubblicati verrà nascosto",
        "hiddenTitleHintStart": "Il titolo «{title}» indica il luogo di partenza. Cambia titolo",
        "hiddenHomeHint": "Nascondere l’inizio? Qui c’è casa tua",
        "privacyPlacesSection": "Luoghi che gli altri non vedono",
        "privacyEdgeNever": "Non nascondere", "privacyEdge200": "200 m · cortile, parcheggio",
        "privacyEdge500": "500 m · quartiere, campeggio", "privacyEdge1000": "1 km · più sicuro in campeggio",
        "privacyEdgeFootnote": "Si applica a tutti i viaggi, salvo quando ne imposti una distanza specifica.",
        "filmingTitle": "Modalità ripresa", "filmingSubtitle": "Le parti nascoste spariscono anche dai tuoi schermi",
        "filmingAutoTitle": "Attiva durante la registrazione dello schermo", "filmingAutoSubtitle": "Si attiva e disattiva da sola",
        "filmingFootnote": "In questa modalità, le mappe e Luoghi nascondono i tratti nascosti, casa tua e il punto blu. La schermata di registrazione mantiene il punto.",
        "routeHiddenByAuthor": "L’autore ha nascosto il percorso"
    ]
    static let hiddenPrivacyPL: [String: String] = [
        "privacyEdgesTitle": "Początek i koniec podróży", "hiddenQuestionWholeTrips": "Cała trasa {count} opublikowanych podróży zostanie ukryta",
        "hiddenTitleHintStart": "Tytuł „{title}” wskazuje miejsce startu. Zmień tytuł",
        "hiddenHomeHint": "Ukryć początek? Tu jest twój dom",
        "privacyPlacesSection": "Miejsca niewidoczne dla innych",
        "privacyEdgeNever": "Nie ukrywaj", "privacyEdge200": "200 m · podwórko, parking",
        "privacyEdge500": "500 m · okolica, kemping", "privacyEdge1000": "1 km · bezpieczniej na kempingu",
        "privacyEdgeFootnote": "Dotyczy wszystkich podróży, chyba że ustawisz dla danej własną odległość.",
        "filmingTitle": "Tryb nagrywania", "filmingSubtitle": "Ukryte odcinki znikają też z twoich ekranów",
        "filmingAutoTitle": "Włączaj podczas nagrywania ekranu", "filmingAutoSubtitle": "Włącza się i wyłącza automatycznie",
        "filmingFootnote": "W tym trybie mapy i Miejsca ukrywają ukryte odcinki, twój dom i niebieską kropkę. Ekran nagrywania zachowuje kropkę.",
        "routeHiddenByAuthor": "Autor ukrył trasę"
    ]
    static let hiddenPrivacyID: [String: String] = [
        "privacyEdgesTitle": "Awal dan akhir perjalanan", "hiddenQuestionWholeTrips": "Seluruh rute dari {count} perjalanan publik akan disembunyikan",
        "hiddenTitleHintStart": "Judul “{title}” menyebut tempat awal. Ubah judul",
        "hiddenHomeHint": "Sembunyikan awal? Rumah Anda di sini",
        "privacyPlacesSection": "Tempat yang tidak terlihat orang lain",
        "privacyEdgeNever": "Jangan sembunyikan", "privacyEdge200": "200 m · halaman, parkir",
        "privacyEdge500": "500 m · lingkungan, perkemahan", "privacyEdge1000": "1 km · lebih aman saat berkemah",
        "privacyEdgeFootnote": "Berlaku untuk semua perjalanan, kecuali jika jaraknya diatur khusus.",
        "filmingTitle": "Mode perekaman", "filmingSubtitle": "Bagian tersembunyi juga tidak terlihat di layar Anda",
        "filmingAutoTitle": "Aktifkan saat merekam layar", "filmingAutoSubtitle": "Akan aktif dan nonaktif sendiri",
        "filmingFootnote": "Dalam mode ini, peta dan Tempat menyembunyikan bagian rute tersembunyi, rumah, dan titik lokasi biru. Layar perekaman tetap menampilkan titik.",
        "routeHiddenByAuthor": "Rute disembunyikan oleh pemiliknya"
    ]
    static let hiddenPrivacyTR: [String: String] = [
        "privacyEdgesTitle": "Yolculukların başlangıcı ve sonu", "hiddenQuestionWholeTrips": "Yayınlanan {count} yolculuğun tüm rotası gizlenecek",
        "hiddenTitleHintStart": "“{title}” başlığı başlangıç yerini belirtiyor. Başlığı değiştir",
        "hiddenHomeHint": "Başlangıcı gizle? Eviniz burada",
        "privacyPlacesSection": "Başkalarının göremediği yerler",
        "privacyEdgeNever": "Gizleme", "privacyEdge200": "200 m · avlu, otopark",
        "privacyEdge500": "500 m · mahalle, kamp alanı", "privacyEdge1000": "1 km · kamp için daha güvenli",
        "privacyEdgeFootnote": "Yolculuk için ayrı bir mesafe belirlemediğiniz sürece tüm yolculuklarda geçerlidir.",
        "filmingTitle": "Kayıt modu", "filmingSubtitle": "Gizli bölümler kendi ekranlarınızda da görünmez",
        "filmingAutoTitle": "Ekran kaydı sırasında aç", "filmingAutoSubtitle": "Kendiliğinden açılır ve kapanır",
        "filmingFootnote": "Bu modda haritalar ve Yerler gizli bölümleri, evinizi ve mavi konum noktasını göstermez. Kayıt ekranında nokta görünür.",
        "routeHiddenByAuthor": "Rota sahibi tarafından gizlendi"
    ]
    static let hiddenPrivacyFIL: [String: String] = [
        "privacyEdgesTitle": "Simula at dulo ng mga biyahe", "hiddenQuestionWholeTrips": "Itatago ang buong ruta ng {count} pampublikong biyahe",
        "hiddenTitleHintStart": "Itinuturo ng pamagat na “{title}” ang pinagsimulan. Palitan ang pamagat",
        "hiddenHomeHint": "Itago ang simula? Nandito ang bahay mo",
        "privacyPlacesSection": "Mga lugar na hindi nakikita ng iba",
        "privacyEdgeNever": "Huwag itago", "privacyEdge200": "200 m · bakuran, paradahan",
        "privacyEdge500": "500 m · kapitbahayan, kampo", "privacyEdge1000": "1 km · mas ligtas sa pagkakamping",
        "privacyEdgeFootnote": "Para ito sa lahat ng biyahe maliban kung may sariling distansya ang isang biyahe.",
        "filmingTitle": "Mode ng pagkuha", "filmingSubtitle": "Hindi rin makikita sa sarili mong screen ang mga nakatagong bahagi",
        "filmingAutoTitle": "I-on kapag nagre-record ng screen", "filmingAutoSubtitle": "Awtomatikong magbubukas at magsasara",
        "filmingFootnote": "Sa mode na ito, itinatago ng mga mapa at Lugar ang mga nakatagong bahagi, bahay mo, at asul na tuldok. Nananatili ang tuldok sa screen ng recording.",
        "routeHiddenByAuthor": "Itinago ng may-akda ang ruta"
    ]
    static let hiddenPrivacyUK: [String: String] = [
        "privacyEdgesTitle": "Початок і кінець поїздок", "hiddenQuestionWholeTrips": "Маршрут {count} опублікованих поїздок буде приховано повністю",
        "hiddenTitleHintStart": "Назва «{title}» вказує на місце старту. Змінити назву",
        "hiddenHomeHint": "Приховати початок? Тут ваш дім",
        "privacyPlacesSection": "Місця, яких інші не бачать",
        "privacyEdgeNever": "Не приховувати", "privacyEdge200": "200 м · подвір’я, парковка",
        "privacyEdge500": "500 м · квартал, стоянка", "privacyEdge1000": "1 км · надійніше для кемпінгу",
        "privacyEdgeFootnote": "Діє для всіх поїздок, якщо для конкретної не задано власну відстань.",
        "filmingTitle": "Режим зйомки", "filmingSubtitle": "Прихованих ділянок не видно і на ваших екранах",
        "filmingAutoTitle": "Вмикати під час запису екрана", "filmingAutoSubtitle": "Вмикається та вимикається автоматично",
        "filmingFootnote": "У цьому режимі карти й «Місця» приховують ділянки маршруту, дім і синю точку. На екрані запису точка залишається.",
        "routeHiddenByAuthor": "Маршрут приховано автором"
    ]
    static let hiddenPrivacyKK: [String: String] = [
        "privacyEdgesTitle": "Сапардың басы мен соңы", "hiddenQuestionWholeTrips": "Жарияланған {count} сапардың бүкіл бағыты жасырын болады",
        "hiddenTitleHintStart": "«{title}» атауында басталған жер көрсетілген. Атауын өзгерту",
        "hiddenHomeHint": "Басын жасыру керек пе? Үйіңіз осында",
        "privacyPlacesSection": "Басқалар көрмейтін орындар",
        "privacyEdgeNever": "Жасырмау", "privacyEdge200": "200 м · аула, тұрақ",
        "privacyEdge500": "500 м · аудан, лагерь", "privacyEdge1000": "1 км · кемпинг үшін қауіпсіздеу",
        "privacyEdgeFootnote": "Сапарға жеке қашықтық қойылмаса, барлық сапарға қолданылады.",
        "filmingTitle": "Түсірілім режимі", "filmingSubtitle": "Жасырын бөліктер өз экрандарыңызда да көрінбейді",
        "filmingAutoTitle": "Экран жазылғанда қосу", "filmingAutoSubtitle": "Өзі қосылып, өзі сөнеді",
        "filmingFootnote": "Бұл режимде карталар мен «Орындар» жасырын бөліктерді, үйіңізді және көк нүктені көрсетпейді. Жазу экранында нүкте қалады.",
        "routeHiddenByAuthor": "Маршрут автор тарапынан жасырылған"
    ]
    static let hiddenPrivacyPT: [String: String] = [
        "privacyEdgesTitle": "Início e fim das viagens", "hiddenQuestionWholeTrips": "A rota completa de {count} viagens publicadas ficará oculta",
        "hiddenTitleHintStart": "O título “{title}” indica o local de partida. Alterar título",
        "hiddenHomeHint": "Ocultar o início? Sua casa fica aqui",
        "privacyPlacesSection": "Lugares que outras pessoas não veem",
        "privacyEdgeNever": "Não ocultar", "privacyEdge200": "200 m · quintal, estacionamento",
        "privacyEdge500": "500 m · bairro, camping", "privacyEdge1000": "1 km · mais seguro para acampar",
        "privacyEdgeFootnote": "Aplica-se a todas as viagens, exceto quando uma distância própria é definida.",
        "filmingTitle": "Modo de gravação", "filmingSubtitle": "As partes ocultas também somem das suas telas",
        "filmingAutoTitle": "Ativar ao gravar a tela", "filmingAutoSubtitle": "Liga e desliga automaticamente",
        "filmingFootnote": "Neste modo, mapas e Lugares ocultam trechos escondidos, sua casa e o ponto azul. A tela de gravação mantém o ponto.",
        "routeHiddenByAuthor": "O autor ocultou a rota"
    ]

    static let hiddenPartsDE: [String: String] = [
        "hiddenAddSection":"+ Mittelabschnitt verbergen", "hiddenAllTrip":"Ganze Fahrt", "hiddenAlreadySeen":"Wer die Fahrt schon gesehen hat, kann sich die ganze Route gemerkt haben.", "hiddenChooseEdge":"Entfernung verbergen", "hiddenDefault":"Standard", "hiddenEditorTitle":"Vor anderen verbergen", "hiddenEnd":"Ende", "hiddenLocalCardBody":"Verborgene Abschnitte: {pieces}; Fotos davon: {photos}. Sie erscheinen weder im Feed noch in der Cloud-Kopie.", "hiddenLocalCardTitle":"Bleibt auf diesem Telefon", "hiddenLocalOnlyNotice":"Verborgene Abschnitte gibt es nur auf dem Telefon, das die Fahrt aufgezeichnet hat.", "hiddenNone":"Keine", "hiddenNumbersPreview":"Andere sehen {distance} und {duration}", "hiddenNumbersTitle":"Zahlen für andere", "hiddenOption1000":"mehr Schutz beim Campen", "hiddenOption200":"Hof, Parkplatz", "hiddenOption500":"Viertel, Stellplatz", "hiddenOvernightHint":"Ende verbergen? Hier hast du übernachtet", "hiddenPrivacyIntro":"Gilt für Fahrten ohne eigene Einstellung. Verborgene Abschnitte werden weder in den Feed noch in die Cloud übertragen.", "hiddenPrivacyModeFootnote":"Im Aufnahmemodus verbergen Karten und Orte private Abschnitte, dein Zuhause und den blauen Standortpunkt. Auf dem Aufnahmebildschirm bleibt der Punkt sichtbar.", "hiddenPublishPreviewTitle":"So erscheint die Fahrt im Feed und Profil", "hiddenPublishRow":"Verborgene Abschnitte: {summary}", "hiddenQuestionBody":"Dein Zuhause und Übernachtungsorte erscheinen weder im Feed noch in der Cloud-Kopie. Du siehst die ganze Fahrt.", "hiddenQuestionTitle":"Anfang und Ende der Fahrten verbergen?", "hiddenQuickHide":"500 m verbergen", "hiddenRouteLockAccessibility":"Grenze eines verborgenen Abschnitts", "hiddenSave":"Speichern", "hiddenSectionEndHandle":"Ende des verborgenen Abschnitts", "hiddenSectionStartHandle":"Anfang des verborgenen Abschnitts", "hiddenSectionTitle":"Abschnitt {start} — {end}", "hiddenSettingsFootnote":"Ändern unter Einstellungen → Datenschutz", "hiddenShowOwn":"Deine Fahrt", "hiddenShowPublic":"So sehen es andere", "hiddenStart":"Anfang", "hiddenSummary":"Anfang {start} · Ende {end} · mittlere Abschnitte: {count}", "hiddenTapEnd":"Tippe auf das Routenende des Abschnitts", "hiddenTapMapHint":"Tippe auf die Route, um einen Abschnitt zu wählen", "hiddenTapStart":"Tippe auf den Routenanfang des Abschnitts", "hiddenTitleHint":"Der Titel „{title}“ nennt den Zielort. Titel ändern", "hiddenWithoutHidden":"Ohne verborgene Abschnitte"
    ]
    static let hiddenPartsES: [String: String] = [
        "hiddenAddSection":"+ Ocultar tramo intermedio", "hiddenAllTrip":"Viaje completo", "hiddenAlreadySeen":"Quien ya vio el viaje quizá recuerde la ruta completa.", "hiddenChooseEdge":"Distancia que ocultar", "hiddenDefault":"por defecto", "hiddenEditorTitle":"Ocultar a los demás", "hiddenEnd":"Final", "hiddenLocalCardBody":"Tramos ocultos: {pieces}; fotos: {photos}. No aparecerán en el feed ni en la copia en la nube.", "hiddenLocalCardTitle":"Solo en este teléfono", "hiddenLocalOnlyNotice":"Los tramos ocultos solo están en el teléfono que grabó el viaje.", "hiddenNone":"Ninguno", "hiddenNumbersPreview":"Los demás verán {distance} y {duration}", "hiddenNumbersTitle":"Cifras para los demás", "hiddenOption1000":"más privacidad al acampar", "hiddenOption200":"patio, aparcamiento", "hiddenOption500":"barrio, campamento", "hiddenOvernightHint":"¿Ocultar el final? Aquí pasaste la noche", "hiddenPrivacyIntro":"Se aplica a los viajes sin un ajuste propio. Los tramos ocultos no se envían al feed ni a la nube.", "hiddenPrivacyModeFootnote":"En este modo, los mapas y Lugares ocultan los tramos privados, tu casa y el punto azul. La pantalla de grabación conserva el punto.", "hiddenPublishPreviewTitle":"Así se verá en el feed y el perfil", "hiddenPublishRow":"Oculto: {summary}", "hiddenQuestionBody":"Tu casa y los lugares donde pasas la noche no aparecerán en el feed ni en la nube. Tú verás el viaje completo.", "hiddenQuestionTitle":"¿Ocultar el inicio y el final de los viajes?", "hiddenQuickHide":"Ocultar 500 m", "hiddenRouteLockAccessibility":"Límite del tramo oculto", "hiddenSave":"Guardar", "hiddenSectionEndHandle":"Final del tramo oculto", "hiddenSectionStartHandle":"Inicio del tramo oculto", "hiddenSectionTitle":"Tramo {start} — {end}", "hiddenSettingsFootnote":"Puedes cambiarlo en Ajustes → Privacidad", "hiddenShowOwn":"Tu viaje", "hiddenShowPublic":"Así lo verán los demás", "hiddenStart":"Inicio", "hiddenSummary":"Inicio {start} · final {end} · tramos intermedios: {count}", "hiddenTapEnd":"Toca donde termina el tramo", "hiddenTapMapHint":"Toca la ruta para elegir un tramo", "hiddenTapStart":"Toca donde empieza el tramo", "hiddenTitleHint":"El título «{title}» indica el destino. Cambiar título", "hiddenWithoutHidden":"Sin los tramos ocultos"
    ]
    static let hiddenPartsFR: [String: String] = [
        "hiddenAddSection":"+ Masquer un tronçon intermédiaire", "hiddenAllTrip":"Trajet entier", "hiddenAlreadySeen":"Les personnes qui ont déjà vu le trajet peuvent se souvenir de tout l’itinéraire.", "hiddenChooseEdge":"Distance à masquer", "hiddenDefault":"par défaut", "hiddenEditorTitle":"Masquer aux autres", "hiddenEnd":"Fin", "hiddenLocalCardBody":"Tronçons masqués : {pieces} ; photos : {photos}. Ils restent hors du fil et du cloud.", "hiddenLocalCardTitle":"Reste sur ce téléphone", "hiddenLocalOnlyNotice":"Les tronçons masqués restent uniquement sur le téléphone qui a enregistré le trajet.", "hiddenNone":"Aucun", "hiddenNumbersPreview":"Les autres verront {distance} et {duration}", "hiddenNumbersTitle":"Chiffres visibles par les autres", "hiddenOption1000":"plus sûr au camping", "hiddenOption200":"cour, parking", "hiddenOption500":"quartier, camping", "hiddenOvernightHint":"Masquer la fin ? Vous avez dormi ici", "hiddenPrivacyIntro":"S’applique aux trajets sans réglage propre. Les tronçons masqués ne partent ni dans le fil ni dans le cloud.", "hiddenPrivacyModeFootnote":"En mode vidéo, les cartes et Lieux masquent les tronçons privés, votre domicile et le point bleu. L’écran d’enregistrement garde le point.", "hiddenPublishPreviewTitle":"Aperçu dans le fil et le profil", "hiddenPublishRow":"Masqué : {summary}", "hiddenQuestionBody":"Votre domicile et les lieux de nuitée restent hors du fil et du cloud. Vous gardez le trajet complet.", "hiddenQuestionTitle":"Masquer le début et la fin des trajets ?", "hiddenQuickHide":"Masquer 500 m", "hiddenRouteLockAccessibility":"Limite du tronçon masqué", "hiddenSave":"Enregistrer", "hiddenSectionEndHandle":"Fin du tronçon masqué", "hiddenSectionStartHandle":"Début du tronçon masqué", "hiddenSectionTitle":"Tronçon {start} — {end}", "hiddenSettingsFootnote":"À modifier dans Réglages → Confidentialité", "hiddenShowOwn":"Votre trajet", "hiddenShowPublic":"Aperçu public", "hiddenStart":"Début", "hiddenSummary":"Début {start} · fin {end} · tronçons du milieu : {count}", "hiddenTapEnd":"Touchez l’endroit où le tronçon finit", "hiddenTapMapHint":"Touchez l’itinéraire pour choisir un tronçon", "hiddenTapStart":"Touchez l’endroit où le tronçon commence", "hiddenTitleHint":"Le titre « {title} » indique la destination. Modifier le titre", "hiddenWithoutHidden":"Sans les tronçons masqués"
    ]
    static let hiddenPartsIT: [String: String] = [
        "hiddenAddSection":"+ Nascondi un tratto centrale", "hiddenAllTrip":"Viaggio intero", "hiddenAlreadySeen":"Chi ha già visto il viaggio potrebbe ricordare tutto il percorso.", "hiddenChooseEdge":"Distanza da nascondere", "hiddenDefault":"predefinito", "hiddenEditorTitle":"Nascondi agli altri", "hiddenEnd":"Fine", "hiddenLocalCardBody":"Tratti nascosti: {pieces}; foto: {photos}. Non appariranno nel feed né nella copia cloud.", "hiddenLocalCardTitle":"Resta su questo telefono", "hiddenLocalOnlyNotice":"I tratti nascosti sono solo sul telefono che ha registrato il viaggio.", "hiddenNone":"Nessuno", "hiddenNumbersPreview":"Gli altri vedranno {distance} e {duration}", "hiddenNumbersTitle":"Numeri per gli altri", "hiddenOption1000":"più privacy in campeggio", "hiddenOption200":"cortile, parcheggio", "hiddenOption500":"quartiere, campeggio", "hiddenOvernightHint":"Nascondere la fine? Hai dormito qui", "hiddenPrivacyIntro":"Vale per i viaggi senza un’impostazione propria. I tratti nascosti restano fuori dal feed e dal cloud.", "hiddenPrivacyModeFootnote":"In modalità ripresa, mappe e Luoghi nascondono tratti privati, casa e punto blu. La schermata di registrazione mantiene il punto.", "hiddenPublishPreviewTitle":"Così apparirà nel feed e nel profilo", "hiddenPublishRow":"Nascosto: {summary}", "hiddenQuestionBody":"Casa e soste notturne restano fuori dal feed e dalla copia cloud. Tu vedrai il viaggio completo.", "hiddenQuestionTitle":"Nascondere l’inizio e la fine dei viaggi?", "hiddenQuickHide":"Nascondi 500 m", "hiddenRouteLockAccessibility":"Confine del tratto nascosto", "hiddenSave":"Salva", "hiddenSectionEndHandle":"Fine del tratto nascosto", "hiddenSectionStartHandle":"Inizio del tratto nascosto", "hiddenSectionTitle":"Tratto {start} — {end}", "hiddenSettingsFootnote":"Puoi cambiarlo in Impostazioni → Privacy", "hiddenShowOwn":"Il tuo viaggio", "hiddenShowPublic":"Anteprima pubblica", "hiddenStart":"Inizio", "hiddenSummary":"Inizio {start} · fine {end} · tratti centrali: {count}", "hiddenTapEnd":"Tocca dove finisce il tratto", "hiddenTapMapHint":"Tocca il percorso per scegliere un tratto", "hiddenTapStart":"Tocca dove inizia il tratto", "hiddenTitleHint":"Il titolo «{title}» indica la destinazione. Cambia titolo", "hiddenWithoutHidden":"Senza i tratti nascosti"
    ]
    static let hiddenPartsPL: [String: String] = [
        "hiddenAddSection":"+ Ukryj środkowy odcinek", "hiddenAllTrip":"Cała podróż", "hiddenAlreadySeen":"Osoby, które widziały podróż, mogą pamiętać całą trasę.", "hiddenChooseEdge":"Odległość do ukrycia", "hiddenDefault":"domyślnie", "hiddenEditorTitle":"Ukryj przed innymi", "hiddenEnd":"Koniec", "hiddenLocalCardBody":"Ukryte odcinki: {pieces}; zdjęcia: {photos}. Nie trafią do kanału ani kopii w chmurze.", "hiddenLocalCardTitle":"Zostaje na tym telefonie", "hiddenLocalOnlyNotice":"Ukryte odcinki są tylko na telefonie, który zapisał podróż.", "hiddenNone":"Brak", "hiddenNumbersPreview":"Inni zobaczą {distance} i {duration}", "hiddenNumbersTitle":"Dane dla innych", "hiddenOption1000":"bezpieczniej na kempingu", "hiddenOption200":"podwórko, parking", "hiddenOption500":"okolica, kemping", "hiddenOvernightHint":"Ukryć koniec? Tutaj nocowałeś", "hiddenPrivacyIntro":"Dotyczy podróży bez własnego ustawienia. Ukryte odcinki nie trafiają do kanału ani chmury.", "hiddenPrivacyModeFootnote":"W trybie nagrywania mapy i Miejsca ukrywają prywatne odcinki, dom i niebieską kropkę. Ekran nagrywania zachowuje kropkę.", "hiddenPublishPreviewTitle":"Tak będzie wyglądać w kanale i profilu", "hiddenPublishRow":"Ukryte: {summary}", "hiddenQuestionBody":"Dom i miejsca noclegu nie pojawią się w kanale ani kopii w chmurze. Ty zobaczysz całą podróż.", "hiddenQuestionTitle":"Ukrywać początek i koniec podróży?", "hiddenQuickHide":"Ukryj 500 m", "hiddenRouteLockAccessibility":"Granica ukrytego odcinka", "hiddenSave":"Zapisz", "hiddenSectionEndHandle":"Koniec ukrytego odcinka", "hiddenSectionStartHandle":"Początek ukrytego odcinka", "hiddenSectionTitle":"Odcinek {start} — {end}", "hiddenSettingsFootnote":"Zmienisz to w Ustawieniach → Prywatność", "hiddenShowOwn":"Twoja podróż", "hiddenShowPublic":"Podgląd publiczny", "hiddenStart":"Początek", "hiddenSummary":"Początek {start} · koniec {end} · środkowe odcinki: {count}", "hiddenTapEnd":"Dotknij miejsca, gdzie kończy się odcinek", "hiddenTapMapHint":"Dotknij trasy, aby wybrać odcinek", "hiddenTapStart":"Dotknij miejsca, gdzie zaczyna się odcinek", "hiddenTitleHint":"Tytuł „{title}” wskazuje miejsce końca. Zmień tytuł", "hiddenWithoutHidden":"Bez ukrytych odcinków"
    ]
    static let hiddenPartsID: [String: String] = [
        "hiddenAddSection":"+ Sembunyikan bagian tengah", "hiddenAllTrip":"Seluruh perjalanan", "hiddenAlreadySeen":"Orang yang sudah melihat perjalanan mungkin ingat seluruh rutenya.", "hiddenChooseEdge":"Jarak yang disembunyikan", "hiddenDefault":"default", "hiddenEditorTitle":"Sembunyikan dari orang lain", "hiddenEnd":"Akhir", "hiddenLocalCardBody":"Bagian tersembunyi: {pieces}; foto: {photos}. Tidak muncul di feed atau salinan cloud.", "hiddenLocalCardTitle":"Tersimpan di ponsel ini", "hiddenLocalOnlyNotice":"Bagian tersembunyi hanya ada di ponsel yang merekam perjalanan.", "hiddenNone":"Tidak ada", "hiddenNumbersPreview":"Orang lain melihat {distance} dan {duration}", "hiddenNumbersTitle":"Angka untuk orang lain", "hiddenOption1000":"lebih aman untuk berkemah", "hiddenOption200":"halaman, parkir", "hiddenOption500":"lingkungan, perkemahan", "hiddenOvernightHint":"Sembunyikan akhir? Anda bermalam di sini", "hiddenPrivacyIntro":"Berlaku untuk perjalanan tanpa pengaturan khusus. Bagian tersembunyi tidak dikirim ke feed atau cloud.", "hiddenPrivacyModeFootnote":"Mode rekaman menyembunyikan bagian privat, rumah, dan titik lokasi biru di peta dan Tempat. Layar rekaman tetap menampilkan titik.", "hiddenPublishPreviewTitle":"Tampilan di feed dan profil", "hiddenPublishRow":"Disembunyikan: {summary}", "hiddenQuestionBody":"Rumah dan tempat bermalam tidak masuk ke feed atau salinan cloud. Anda tetap melihat seluruh perjalanan.", "hiddenQuestionTitle":"Sembunyikan awal dan akhir perjalanan?", "hiddenQuickHide":"Sembunyikan 500 m", "hiddenRouteLockAccessibility":"Batas bagian tersembunyi", "hiddenSave":"Simpan", "hiddenSectionEndHandle":"Akhir bagian tersembunyi", "hiddenSectionStartHandle":"Awal bagian tersembunyi", "hiddenSectionTitle":"Bagian {start} — {end}", "hiddenSettingsFootnote":"Ubah di Pengaturan → Privasi", "hiddenShowOwn":"Perjalanan Anda", "hiddenShowPublic":"Pratinjau publik", "hiddenStart":"Awal", "hiddenSummary":"Awal {start} · akhir {end} · bagian tengah: {count}", "hiddenTapEnd":"Ketuk lokasi akhir bagian", "hiddenTapMapHint":"Ketuk rute untuk memilih bagian", "hiddenTapStart":"Ketuk lokasi awal bagian", "hiddenTitleHint":"Judul “{title}” menyebut tujuan. Ubah judul", "hiddenWithoutHidden":"Tanpa bagian tersembunyi"
    ]
    static let hiddenPartsTR = makeHiddenParts([
        "+ Orta bölümü gizle", "Tüm yolculuk", "Yolculuğu görenler tüm rotayı hatırlayabilir.", "Gizlenecek mesafe", "varsayılan", "Başkalarından gizle", "Bitiş",
        "Gizli bölümler: {pieces}; fotoğraflar: {photos}. Akışa veya bulut kopyasına eklenmez.", "Bu telefonda kalır", "Gizli bölümler yalnızca yolculuğun kaydedildiği telefondadır.", "Yok", "Diğerleri {distance} ve {duration} görür", "Başkalarına gösterilecek sayılar",
        "kamp için daha güvenli", "avlu, otopark", "mahalle, kamp alanı", "Bitişi gizle? Burada gecelediniz", "Kendi ayarı olmayan yolculuklarda geçerlidir. Gizli bölümler akışa veya buluta gönderilmez.", "Kayıt modunda haritalar ve Yerler özel bölümleri, evinizi ve mavi konum noktasını gizler. Kayıt ekranında nokta görünür.",
        "Akışta ve profilde böyle görünür", "Gizlenen: {summary}", "Eviniz ve gece konakladığınız yerler akışa veya bulut kopyasına gitmez. Yolculuğun tamamını siz görürsünüz.", "Yolculukların başlangıcı ve sonu gizlensin mi?", "500 m gizle", "Gizli bölüm sınırı",
        "Kaydet", "Gizli bölümün sonu", "Gizli bölümün başlangıcı", "Bölüm {start} — {end}", "Ayarlar → Gizlilik bölümünden değiştirebilirsiniz", "Yolculuğunuz", "Herkese açık önizleme", "Başlangıç", "Başlangıç {start} · bitiş {end} · orta bölümler: {count}", "Bölümün bittiği yere dokunun", "Bir bölüm seçmek için rotaya dokunun", "Bölümün başladığı yere dokunun", "“{title}” başlığı varış yerini belirtiyor. Başlığı değiştir", "Gizli bölümler olmadan"
    ])
    static let hiddenPartsFIL = makeHiddenParts([
        "+ Itago ang gitnang bahagi", "Buong biyahe", "Maaaring maalala ng nakakita na ang buong ruta.", "Distansyang itatago", "default", "Itago sa iba", "Dulo",
        "Mga nakatagong bahagi: {pieces}; mga larawan: {photos}. Wala ang mga ito sa feed o cloud copy.", "Mananatili sa teleponong ito", "Nasa teleponong nagrekord lang ng biyahe ang mga nakatagong bahagi.", "Wala", "Makikita ng iba ang {distance} at {duration}", "Mga bilang para sa iba",
        "mas ligtas sa kamping", "bakuran, paradahan", "kapitbahayan, kampo", "Itago ang dulo? Dito ka nagpalipas ng gabi", "Para ito sa biyahe na walang sariling setting. Hindi ipinapadala sa feed o cloud ang mga nakatagong bahagi.", "Itinatago ng mode ng pagkuha ang mga pribadong bahagi, bahay, at asul na tuldok sa mapa at Lugar. Nananatili ang tuldok sa screen ng recording.",
        "Ganito ito makikita sa feed at profile", "Nakatago: {summary}", "Hindi mapupunta sa feed o cloud copy ang bahay at mga tinuluyang lugar. Buong biyahe pa rin ang makikita mo.", "Itago ang simula at dulo ng biyahe?", "Itago ang 500 m", "Hangganan ng nakatagong bahagi",
        "I-save", "Dulo ng nakatagong bahagi", "Simula ng nakatagong bahagi", "Bahagi {start} — {end}", "Palitan sa Mga Setting → Privacy", "Iyong biyahe", "Pampublikong preview", "Simula", "Simula {start} · dulo {end} · gitnang bahagi: {count}", "I-tap kung saan nagtatapos ang bahagi", "I-tap ang ruta para pumili ng bahagi", "I-tap kung saan nagsisimula ang bahagi", "Itinuturo ng pamagat na “{title}” ang dulo. Palitan ang pamagat", "Walang mga nakatagong bahagi"
    ])
    static let hiddenPartsUK = makeHiddenParts([
        "+ Приховати середню ділянку", "Уся поїздка", "Ті, хто вже бачив поїздку, можуть пам’ятати весь маршрут.", "Відстань для приховування", "за замовчуванням", "Приховати від інших", "Кінець",
        "Приховані ділянки: {pieces}; фото: {photos}. Вони не потраплять у стрічку чи хмарну копію.", "Залишиться на цьому телефоні", "Приховані ділянки є лише на телефоні, де записано поїздку.", "Немає", "Інші побачать {distance} і {duration}", "Цифри для інших",
        "надійніше для кемпінгу", "подвір’я, парковка", "квартал, стоянка", "Приховати кінець? Тут ви ночували", "Діє для поїздок без власного налаштування. Приховані ділянки не надсилаються у стрічку чи хмару.", "У режимі зйомки карти й «Місця» приховують приватні ділянки, дім і синю точку. На екрані запису точка залишається.",
        "Так її побачать у стрічці й профілі", "Приховано: {summary}", "Дім і місця ночівлі не потраплять у стрічку чи хмарну копію. Ви побачите всю поїздку.", "Приховувати початок і кінець поїздок?", "Приховати 500 м", "Межа прихованої ділянки",
        "Зберегти", "Кінець прихованої ділянки", "Початок прихованої ділянки", "Ділянка {start} — {end}", "Змінити можна в Налаштуваннях → Приватність", "Ваша поїздка", "Публічний перегляд", "Початок", "Початок {start} · кінець {end} · середні ділянки: {count}", "Торкніться місця, де ділянка закінчується", "Торкніться маршруту, щоб вибрати ділянку", "Торкніться місця, де ділянка починається", "Назва «{title}» вказує на місце фінішу. Змінити назву", "Без прихованих ділянок"
    ])
    static let hiddenPartsKK = makeHiddenParts([
        "+ Орта бөлікті жасыру", "Бүкіл сапар", "Сапарды көргендер бүкіл бағытты есте сақтауы мүмкін.", "Жасырылатын қашықтық", "әдепкі", "Басқалардан жасыру", "Соңы",
        "Жасырын бөліктер: {pieces}; фотолар: {photos}. Олар таспаға да, бұлттағы көшірмеге де жіберілмейді.", "Осы телефонда қалады", "Жасырын бөліктер сапар жазылған телефонда ғана бар.", "Жоқ", "Басқалар {distance} және {duration} көреді", "Басқаларға арналған сандар",
        "кемпингке қауіпсіздеу", "аула, тұрақ", "аудан, тұрақ орны", "Соңын жасыру керек пе? Мұнда түнегенсіз", "Жеке баптауы жоқ сапарларға қолданылады. Жасырын бөліктер таспаға да, бұлтқа да жіберілмейді.", "Түсірілім режимінде карталар мен «Орындар» жасырын бөліктерді, үйді және көк нүктені көрсетпейді. Жазу экранында нүкте қалады.",
        "Таспада және профильде осылай көрінеді", "Жасырылғаны: {summary}", "Үй мен түнеген орындар таспаға не бұлттағы көшірмеге түспейді. Сапарды толық көресіз.", "Сапардың басы мен соңын жасыру керек пе?", "500 м жасыру", "Жасырын бөліктің шекарасы",
        "Сақтау", "Жасырын бөліктің соңы", "Жасырын бөліктің басы", "Бөлік {start} — {end}", "Баптаулар → Құпиялық бөлімінен өзгертуге болады", "Сапарыңыз", "Ашық алдын ала көрініс", "Басы", "Басы {start} · соңы {end} · орта бөліктер: {count}", "Бөлік аяқталатын жерді басыңыз", "Бөлікті таңдау үшін бағытты басыңыз", "Бөлік басталатын жерді басыңыз", "«{title}» атауында баратын жер көрсетілген. Атауын өзгерту", "Жасырын бөліктерсіз"
    ])
    static let hiddenPartsPT = makeHiddenParts([
        "+ Ocultar trecho intermediário", "Viagem inteira", "Quem já viu a viagem pode lembrar o percurso completo.", "Distância a ocultar", "padrão", "Ocultar dos outros", "Fim",
        "Trechos ocultos: {pieces}; fotos: {photos}. Não vão para o feed nem para a cópia na nuvem.", "Fica neste telefone", "Os trechos ocultos só ficam no telefone que gravou a viagem.", "Nenhum", "As outras pessoas verão {distance} e {duration}", "Números para outras pessoas",
        "mais seguro para camping", "quintal, estacionamento", "bairro, camping", "Ocultar o fim? Você passou a noite aqui", "Aplica-se às viagens sem uma configuração própria. Os trechos ocultos não vão para o feed nem para a nuvem.", "No modo de gravação, mapas e Lugares ocultam trechos privados, sua casa e o ponto azul. A tela de gravação mantém o ponto.",
        "Assim aparecerá no feed e no perfil", "Oculto: {summary}", "Sua casa e os locais onde passou a noite ficam fora do feed e da cópia na nuvem. Você vê a viagem inteira.", "Ocultar o início e o fim das viagens?", "Ocultar 500 m", "Limite do trecho oculto",
        "Salvar", "Fim do trecho oculto", "Início do trecho oculto", "Trecho {start} — {end}", "Altere em Ajustes → Privacidade", "Sua viagem", "Prévia pública", "Início", "Início {start} · fim {end} · trechos intermediários: {count}", "Toque onde o trecho termina", "Toque na rota para escolher um trecho", "Toque onde o trecho começa", "O título “{title}” indica o destino. Alterar título", "Sem os trechos ocultos"
    ])
}
