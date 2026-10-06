// Copy for the approved history and manual-trip improvements.
extension AppStrings {
    static func historySearch(_ lang: LanguageManager.Language) -> String {
        switch lang {
        case .ru: return "Название или регион"
        case .en: return "Trip name or region"
        case .de: return "Name oder Region"
        case .es: return "Nombre o región"
        case .fr: return "Nom ou région"
        case .it: return "Nome o regione"
        case .pl: return "Nazwa lub region"
        case .id: return "Nama atau wilayah"
        case .tr: return "Ad veya bölge"
        case .fil: return "Pangalan o rehiyon"
        case .uk: return "Назва або регіон"
        case .kk: return "Атауы немесе аймақ"
        case .pt: return "Nome ou região"
        }
    }

    static func historyNoMatches(_ lang: LanguageManager.Language) -> String {
        switch lang {
        case .ru: return "Поездки не найдены"
        case .en: return "No matching trips"
        case .de: return "Keine passenden Fahrten"
        case .es: return "No se encontraron viajes"
        case .fr: return "Aucun trajet trouvé"
        case .it: return "Nessun viaggio trovato"
        case .pl: return "Nie znaleziono tras"
        case .id: return "Perjalanan tidak ditemukan"
        case .tr: return "Yolculuk bulunamadı"
        case .fil: return "Walang nahanap na biyahe"
        case .uk: return "Поїздок не знайдено"
        case .kk: return "Сапарлар табылмады"
        case .pt: return "Nenhuma viagem encontrada"
        }
    }

    static func historyNoTripsInPeriod(_ lang: LanguageManager.Language) -> String {
        switch lang {
        case .ru: return "В эти дни поездок нет"
        case .en: return "No trips on these dates"
        case .de: return "Keine Fahrten an diesen Tagen"
        case .es: return "No hay viajes en estas fechas"
        case .fr: return "Aucun trajet à ces dates"
        case .it: return "Nessun viaggio in queste date"
        case .pl: return "Brak tras w tych dniach"
        case .id: return "Tidak ada perjalanan pada tanggal ini"
        case .tr: return "Bu tarihlerde yolculuk yok"
        case .fil: return "Walang biyahe sa mga petsang ito"
        case .uk: return "У ці дні поїздок немає"
        case .kk: return "Бұл күндері сапар жоқ"
        case .pt: return "Sem viagens nestas datas"
        }
    }

    static func historyClearFilters(_ lang: LanguageManager.Language) -> String {
        switch lang {
        case .ru: return "Сбросить поиск и даты"
        case .en: return "Clear search and dates"
        case .de: return "Suche und Datum zurücksetzen"
        case .es: return "Borrar búsqueda y fechas"
        case .fr: return "Effacer recherche et dates"
        case .it: return "Cancella ricerca e date"
        case .pl: return "Wyczyść wyszukiwanie i daty"
        case .id: return "Hapus pencarian dan tanggal"
        case .tr: return "Aramayı ve tarihleri temizle"
        case .fil: return "I-clear ang paghahanap at mga petsa"
        case .uk: return "Скинути пошук і дати"
        case .kk: return "Іздеу мен күндерді тазалау"
        case .pt: return "Limpar pesquisa e datas"
        }
    }

    static func historyClearSearch(_ lang: LanguageManager.Language) -> String {
        switch lang {
        case .ru: return "Очистить поиск"
        case .en: return "Clear search"
        case .de: return "Suche löschen"
        case .es: return "Borrar búsqueda"
        case .fr: return "Effacer la recherche"
        case .it: return "Cancella ricerca"
        case .pl: return "Wyczyść wyszukiwanie"
        case .id: return "Hapus pencarian"
        case .tr: return "Aramayı temizle"
        case .fil: return "I-clear ang paghahanap"
        case .uk: return "Очистити пошук"
        case .kk: return "Іздеуді тазалау"
        case .pt: return "Limpar pesquisa"
        }
    }

    static func historySectionsExpanded(_ lang: LanguageManager.Language) -> String {
        switch lang {
        case .ru: return "Развёрнуто"
        case .en: return "Expanded"
        case .de: return "Ausgeklappt"
        case .es: return "Expandido"
        case .fr: return "Développé"
        case .it: return "Espanso"
        case .pl: return "Rozwinięte"
        case .id: return "Diperluas"
        case .tr: return "Genişletildi"
        case .fil: return "Pinalawak"
        case .uk: return "Розгорнуто"
        case .kk: return "Ашылған"
        case .pt: return "Expandido"
        }
    }

    static func historySectionsCollapsed(_ lang: LanguageManager.Language) -> String {
        switch lang {
        case .ru: return "Свёрнуто"
        case .en: return "Collapsed"
        case .de: return "Eingeklappt"
        case .es: return "Contraído"
        case .fr: return "Réduit"
        case .it: return "Compresso"
        case .pl: return "Zwinięte"
        case .id: return "Diciutkan"
        case .tr: return "Daraltıldı"
        case .fil: return "Pinaliít"
        case .uk: return "Згорнуто"
        case .kk: return "Жиналған"
        case .pt: return "Recolhido"
        }
    }

    static func manualTripSwapPoints(_ lang: LanguageManager.Language) -> String {
        switch lang {
        case .ru: return "Поменять начало и конец"
        case .en: return "Swap start and destination"
        case .de: return "Start und Ziel tauschen"
        case .es: return "Intercambiar origen y destino"
        case .fr: return "Inverser le départ et l’arrivée"
        case .it: return "Scambia partenza e arrivo"
        case .pl: return "Zamień początek i koniec"
        case .id: return "Tukar awal dan tujuan"
        case .tr: return "Başlangıç ve varışı değiştir"
        case .fil: return "Pagpalitin ang simula at destinasyon"
        case .uk: return "Поміняти початок і кінець"
        case .kk: return "Басталу және аяқталу нүктелерін ауыстыру"
        case .pt: return "Trocar origem e destino"
        }
    }

    static func manualTripSave(_ lang: LanguageManager.Language) -> String {
        switch lang {
        case .ru: return "Сохранить поездку"
        case .en: return "Save trip"
        case .de: return "Fahrt speichern"
        case .es: return "Guardar viaje"
        case .fr: return "Enregistrer le trajet"
        case .it: return "Salva viaggio"
        case .pl: return "Zapisz trasę"
        case .id: return "Simpan perjalanan"
        case .tr: return "Yolculuğu kaydet"
        case .fil: return "I-save ang biyahe"
        case .uk: return "Зберегти поїздку"
        case .kk: return "Сапарды сақтау"
        case .pt: return "Salvar viagem"
        }
    }

}
