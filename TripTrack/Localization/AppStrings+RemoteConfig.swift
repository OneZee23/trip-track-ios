import Foundation

/// Карточка «Обновите приложение» (0.9.0). Сервер может прислать свой текст
/// (`RemoteConfig.UpdatePolicy.message`); без него — этот.
extension AppStrings {
    static func remoteUpdateTitle(_ l: LanguageManager.Language) -> String {
        switch l {
        case .ru: return "Доступна новая версия"
        case .en: return "A new version is available"
        case .de: return "Eine neue Version ist verfügbar"
        case .es: return "Hay una nueva versión disponible"
        case .fr: return "Une nouvelle version est disponible"
        case .it: return "È disponibile una nuova versione"
        case .pl: return "Dostępna jest nowa wersja"
        case .id: return "Versi baru tersedia"
        case .tr: return "Yeni bir sürüm mevcut"
        case .fil: return "May bagong bersyon na"
        case .uk: return "Доступна нова версія"
        case .kk: return "Жаңа нұсқа қолжетімді"
        case .pt: return "Uma nova versão está disponível"
        }
    }

    static func remoteUpdateBody(_ l: LanguageManager.Language) -> String {
        switch l {
        case .ru: return "Обновите TripTrack в App Store: в новой версии исправления и улучшения."
        case .en: return "Update TripTrack in the App Store to get the latest fixes and improvements."
        case .de: return "Aktualisieren Sie TripTrack im App Store, um die neuesten Korrekturen und Verbesserungen zu erhalten."
        case .es: return "Actualice TripTrack en la App Store para obtener las últimas correcciones y mejoras."
        case .fr: return "Mettez à jour TripTrack dans l’App Store pour profiter des dernières corrections et améliorations."
        case .it: return "Aggiorni TripTrack dall’App Store per ricevere le ultime correzioni e migliorie."
        case .pl: return "Zaktualizuj TripTrack w App Store, aby otrzymać najnowsze poprawki i ulepszenia."
        case .id: return "Perbarui TripTrack di App Store untuk mendapatkan perbaikan dan peningkatan terbaru."
        case .tr: return "En son düzeltmeler ve iyileştirmeler için TripTrack’i App Store’dan güncelleyin."
        case .fil: return "I-update po ang TripTrack sa App Store para sa mga pinakabagong ayos at pagpapabuti."
        case .uk: return "Оновіть TripTrack в App Store: у новій версії виправлення та покращення."
        case .kk: return "TripTrack-ті App Store-да жаңартыңыз: жаңа нұсқада түзетулер мен жақсартулар бар."
        case .pt: return "Atualize o TripTrack na App Store para ter as últimas correções e melhorias."
        }
    }

    static func remoteUpdateAction(_ l: LanguageManager.Language) -> String {
        switch l {
        case .ru: return "Обновить"
        case .en: return "Update"
        case .de: return "Aktualisieren"
        case .es: return "Actualizar"
        case .fr: return "Mettre à jour"
        case .it: return "Aggiorna"
        case .pl: return "Aktualizuj"
        case .id: return "Perbarui"
        case .tr: return "Güncelle"
        case .fil: return "I-update"
        case .uk: return "Оновити"
        case .kk: return "Жаңарту"
        case .pt: return "Atualizar"
        }
    }
}
