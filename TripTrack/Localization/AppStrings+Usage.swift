import Foundation

extension AppStrings {
    static func usageTitle(_ l: LanguageManager.Language) -> String {
        switch l {
        case .ru: return "Помогать улучшать TripTrack"
        case .en: return "Help improve TripTrack"
        case .de: return "TripTrack verbessern helfen"
        case .es: return "Ayudar a mejorar TripTrack"
        case .fr: return "Aider à améliorer TripTrack"
        case .it: return "Aiuta a migliorare TripTrack"
        case .pl: return "Pomóż ulepszać TripTrack"
        case .id: return "Bantu meningkatkan TripTrack"
        case .tr: return "TripTrack’in gelişmesine yardım et"
        case .fil: return "Tumulong na pagandahin ang TripTrack"
        case .uk: return "Допомагати покращувати TripTrack"
        case .kk: return "TripTrack-ті жақсартуға көмектесу"
        case .pt: return "Ajudar a melhorar o TripTrack"
        }
    }

    static func usageDetail(_ l: LanguageManager.Language) -> String {
        switch l {
        case .ru: return "Отправлять счётчики запусков и сохранений записи, дней первой и повторной поездки, открытий Атласа и скорости сохранения. Без маршрутов, координат, фото и аккаунта; со случайным кодом для объединения счётчиков. Работает и без облачной синхронизации. Отключение удалит эти данные с сервера при подключении к сети."
        case .en: return "Send counts of recording starts and saves, first and repeat trip days, Atlas opens and save speed. No routes, coordinates, photos or account; a random code groups the counters. Works with Cloud Sync off. Turning this off deletes these data from the server when connected."
        case .de: return "Anzahlen von Aufzeichnungsstarts und Speicherungen, Tage der ersten und wiederholten Fahrt, Atlas-Aufrufe und Speichergeschwindigkeit senden. Ohne Routen, Koordinaten, Fotos oder Konto; ein Zufallscode ordnet die Zähler zu. Auch ohne Cloud-Sync. Beim Ausschalten werden die Daten bei Verbindung vom Server gelöscht."
        case .es: return "Enviar recuentos de inicios y guardados, días del primer viaje y del siguiente, aperturas del Atlas y velocidad de guardado. Sin rutas, coordenadas, fotos ni cuenta; un código aleatorio agrupa los datos. Funciona sin sincronización. Al desactivarlo, se borran del servidor cuando hay conexión."
        case .fr: return "Envoyer les nombres de démarrages et de sauvegardes, les jours du premier trajet et du suivant, les ouvertures de l’Atlas et la vitesse de sauvegarde. Sans itinéraires, coordonnées, photos ni compte ; un code aléatoire regroupe les compteurs. Fonctionne sans synchronisation. La désactivation efface ces données du serveur à la prochaine connexion."
        case .it: return "Invia i conteggi di avvii e salvataggi, i giorni del primo viaggio e del successivo, le aperture dell’Atlante e la velocità di salvataggio. Senza percorsi, coordinate, foto o account; un codice casuale raggruppa i contatori. Funziona senza sincronizzazione. Disattivando, i dati vengono eliminati dal server alla connessione."
        case .pl: return "Wysyłaj liczby rozpoczętych i zapisanych nagrań, dni pierwszej i kolejnej podróży, otwarcia Atlasu i szybkość zapisu. Bez tras, współrzędnych, zdjęć i konta; losowy kod łączy liczniki. Działa bez synchronizacji. Wyłączenie usuwa te dane z serwera po połączeniu z siecią."
        case .id: return "Kirim jumlah mulai dan simpan rekaman, hari perjalanan pertama dan berikutnya, pembukaan Atlas, serta kecepatan penyimpanan. Tanpa rute, koordinat, foto, atau akun; kode acak mengelompokkan penghitung. Berfungsi tanpa sinkronisasi. Menonaktifkannya menghapus data ini dari server saat tersambung."
        case .tr: return "Kayıt başlatma ve kaydetme sayıları, ilk ve sonraki yolculuk günleri, Atlas açılışları ve kaydetme hızını gönder. Rota, koordinat, fotoğraf veya hesap içermez; rastgele bir kod sayaçları gruplar. Bulut eşitleme kapalıyken de çalışır. Kapatınca bağlantı kurulduğunda bu veriler sunucudan silinir."
        case .fil: return "Ipadala ang bilang ng pagsisimula at pag-save ng recording, mga araw ng una at kasunod na biyahe, pagbukas ng Atlas at bilis ng pag-save. Walang ruta, coordinate, larawan o account; random na code ang nag-uugnay sa mga bilang. Gumagana kahit walang Cloud Sync. Kapag pinatay, mabubura ang datos sa server kapag nakakonekta."
        case .uk: return "Надсилати лічильники запусків і збережень запису, днів першої та повторної поїздки, відкриттів Атласу й швидкості збереження. Без маршрутів, координат, фото й акаунта; з випадковим кодом для об’єднання лічильників. Працює без хмарної синхронізації. Вимкнення видалить ці дані із сервера після підключення до мережі."
        case .kk: return "Жазуды бастау және сақтау санын, алғашқы және келесі сапар күндерін, Атласты ашу санын және сақтау жылдамдығын жіберу. Маршруттар, координаттар, фотолар және аккаунт жіберілмейді; санауыштар кездейсоқ кодпен біріктіріледі. Бұлттық синхрондаусыз жұмыс істейді. Өшіргенде, желіге қосылған соң бұл деректер серверден жойылады."
        case .pt: return "Enviar contagens de início e gravação, dias da primeira viagem e da seguinte, aberturas do Atlas e velocidade ao guardar. Sem rotas, coordenadas, fotos ou conta; um código aleatório agrupa as contagens. Funciona sem sincronização. Ao desativar, os dados são apagados do servidor quando houver ligação."
        }
    }
}
