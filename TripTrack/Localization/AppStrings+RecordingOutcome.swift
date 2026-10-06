import Foundation

extension AppStrings {
    static func recordingDiscardTitle(_ lang: LanguageManager.Language) -> String {
        switch lang {
        case .ru: return "Завершить без сохранения?"
        case .en: return "Finish without saving?"
        case .de: return "Ohne Speichern beenden?"
        case .es: return "¿Finalizar sin guardar?"
        case .fr: return "Terminer sans enregistrer ?"
        case .it: return "Terminare senza salvare?"
        case .pl: return "Zakończyć bez zapisywania?"
        case .id: return "Selesaikan tanpa menyimpan?"
        case .tr: return "Kaydetmeden bitirilsin mi?"
        case .fil: return "Tapusin nang hindi sine-save?"
        case .uk: return "Завершити без збереження?"
        case .kk: return "Сақтамай аяқтау керек пе?"
        case .pt: return "Terminar sem guardar?"
        }
    }

    static func recordingDiscardAction(_ lang: LanguageManager.Language) -> String {
        switch lang {
        case .ru: return "Завершить без сохранения"
        case .en: return "Finish without saving"
        case .de: return "Ohne Speichern beenden"
        case .es: return "Finalizar sin guardar"
        case .fr: return "Terminer sans enregistrer"
        case .it: return "Termina senza salvare"
        case .pl: return "Zakończ bez zapisywania"
        case .id: return "Selesaikan tanpa menyimpan"
        case .tr: return "Kaydetmeden bitir"
        case .fil: return "Tapusin nang hindi sine-save"
        case .uk: return "Завершити без збереження"
        case .kk: return "Сақтамай аяқтау"
        case .pt: return "Terminar sem guardar"
        }
    }

    /// Returning preserves a paused recording too: it is not a Resume action.
    static func recordingReturn(_ lang: LanguageManager.Language) -> String {
        switch lang {
        case .ru: return "Вернуться к записи"
        case .en: return "Back to recording"
        case .de: return "Zurück zur Aufzeichnung"
        case .es: return "Volver a la grabación"
        case .fr: return "Revenir à l’enregistrement"
        case .it: return "Torna alla registrazione"
        case .pl: return "Wróć do nagrywania"
        case .id: return "Kembali ke perekaman"
        case .tr: return "Kayda dön"
        case .fil: return "Bumalik sa pag-record"
        case .uk: return "Повернутися до запису"
        case .kk: return "Жазуға оралу"
        case .pt: return "Voltar à gravação"
        }
    }

    static func recordingDiscardReason(_ reason: TripJunkClassifier.Reason, _ lang: LanguageManager.Language) -> String {
        switch reason {
        case .tooShort:
            switch lang {
            case .ru: return "Поездка слишком короткая и не попадёт в историю."
            case .en: return "This trip is too short and won’t be added to your history."
            case .de: return "Diese Fahrt ist zu kurz und wird nicht im Verlauf gespeichert."
            case .es: return "Este viaje es demasiado corto y no se añadirá a tu historial."
            case .fr: return "Ce trajet est trop court et ne sera pas ajouté à votre historique."
            case .it: return "Questo viaggio è troppo breve e non verrà aggiunto alla cronologia."
            case .pl: return "Ta trasa jest zbyt krótka i nie zostanie dodana do historii."
            case .id: return "Perjalanan ini terlalu singkat dan tidak akan ditambahkan ke riwayat."
            case .tr: return "Bu yolculuk çok kısa olduğu için geçmişe eklenmeyecek."
            case .fil: return "Masyadong maikli ang biyaheng ito at hindi ito idaragdag sa history."
            case .uk: return "Поїздка надто коротка й не потрапить до історії."
            case .kk: return "Бұл сапар тым қысқа, сондықтан тарихқа қосылмайды."
            case .pt: return "Esta viagem é demasiado curta e não será adicionada ao histórico."
            }
        case .noDrivingSpeed:
            switch lang {
            case .ru: return "Скорость всё время была слишком низкой для поездки. Запись не попадёт в историю."
            case .en: return "The speed stayed too low for a drive. This recording won’t be added to your history."
            case .de: return "Die Geschwindigkeit war durchgehend zu niedrig für eine Fahrt. Die Aufzeichnung wird nicht im Verlauf gespeichert."
            case .es: return "La velocidad fue demasiado baja durante toda la grabación. No se añadirá al historial."
            case .fr: return "La vitesse est restée trop faible pour un trajet en voiture. Cet enregistrement ne sera pas ajouté à l’historique."
            case .it: return "La velocità è rimasta troppo bassa per un viaggio in auto. La registrazione non verrà aggiunta alla cronologia."
            case .pl: return "Prędkość przez cały czas była zbyt niska jak na jazdę. Nagranie nie zostanie dodane do historii."
            case .id: return "Kecepatan terlalu rendah sepanjang perekaman untuk dianggap berkendara. Rekaman ini tidak akan ditambahkan ke riwayat."
            case .tr: return "Hız tüm kayıt boyunca bir araç yolculuğu için çok düşüktü. Bu kayıt geçmişe eklenmeyecek."
            case .fil: return "Masyadong mababa ang bilis sa buong pag-record para maituring na biyahe sa sasakyan. Hindi ito idaragdag sa history."
            case .uk: return "Швидкість увесь час була надто низькою для поїздки. Запис не потрапить до історії."
            case .kk: return "Жылдамдық бүкіл жазба бойы көлік сапары үшін тым төмен болды. Жазба тарихқа қосылмайды."
            case .pt: return "A velocidade foi sempre demasiado baixa para uma viagem de carro. A gravação não será adicionada ao histórico."
            }
        }
    }

    static func recordingDiscardedSlow(_ lang: LanguageManager.Language) -> String {
        switch lang {
        case .ru: return "Поездка не сохранена — скорость была слишком низкой"
        case .en: return "Trip not saved — the speed stayed too low"
        case .de: return "Fahrt nicht gespeichert — die Geschwindigkeit war zu niedrig"
        case .es: return "Viaje no guardado: la velocidad fue demasiado baja"
        case .fr: return "Trajet non enregistré — la vitesse est restée trop faible"
        case .it: return "Viaggio non salvato: la velocità era troppo bassa"
        case .pl: return "Trasa niezapisana — prędkość była zbyt niska"
        case .id: return "Perjalanan tidak disimpan — kecepatan terlalu rendah"
        case .tr: return "Yolculuk kaydedilmedi — hız çok düşüktü"
        case .fil: return "Hindi na-save ang biyahe — masyadong mababa ang bilis"
        case .uk: return "Поїздку не збережено — швидкість була надто низькою"
        case .kk: return "Сапар сақталмады — жылдамдық тым төмен болды"
        case .pt: return "Viagem não guardada — a velocidade foi demasiado baixa"
        }
    }
}
