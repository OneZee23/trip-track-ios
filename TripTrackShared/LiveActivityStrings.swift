import Foundation

/// The handful of words the lock-screen card and the Dynamic Island say.
///
/// They cannot come from `AppStrings`: that file reaches into `MapViewModel`,
/// `BadgeRarity` and half the app, none of which exist inside a widget
/// extension. This file lives in `TripTrackShared`, which both targets
/// compile, and keys off the raw language code the app already ships in
/// `TripActivityAttributes.ContentState.language` — no new field, so an
/// activity started before an update still decodes.
///
/// Fifteen strings. If it grows much past that, move the app's translation
/// tables into the shared target instead of adding cases here.
enum LiveActivityStrings {
    /// Unknown codes fall back to English, the same rule `AppStrings.tr` uses.
    private static func pick(
        _ code: String,
        ru: String, en: String, de: String, es: String, fr: String, it: String, pl: String,
        id: String, tr: String, fil: String, uk: String, kk: String, pt: String
    ) -> String {
        switch code {
        case "ru": return ru
        case "de": return de
        case "es": return es
        case "fr": return fr
        case "it": return it
        case "pl": return pl
        case "id": return id
        case "tr": return tr
        case "fil": return fil
        case "uk": return uk
        case "kk": return kk
        case "pt": return pt
        default:   return en
        }
    }

    /// «СКОРОСТЬ» — caption over the speed readout. Upper-cased in the layout.
    static func speedCaption(_ c: String) -> String {
        pick(c, ru: "СКОРОСТЬ", en: "SPEED", de: "TEMPO", es: "VELOCIDAD",
             fr: "VITESSE", it: "VELOCITÀ", pl: "PRĘDKOŚĆ",
             id: "KECEPATAN", tr: "HIZ", fil: "BILIS", uk: "ШВИДКІСТЬ", kk: "ЖЫЛДАМДЫҚ", pt: "VELOCIDADE")
    }

    static func kmh(_ c: String) -> String {
        pick(c, ru: "км/ч", en: "km/h", de: "km/h", es: "km/h",
             fr: "km/h", it: "km/h", pl: "km/h",
             id: "km/j", tr: "km/s", fil: "km/h", uk: "км/год", kk: "км/сағ", pt: "km/h")
    }

    /// «ПРОЙДЕНО» — caption over the distance readout.
    static func distanceCaption(_ c: String) -> String {
        pick(c, ru: "ПРОЙДЕНО", en: "DISTANCE", de: "STRECKE", es: "DISTANCIA",
             fr: "DISTANCE", it: "DISTANZA", pl: "DYSTANS",
             id: "JARAK", tr: "MESAFE", fil: "DISTANSYA", uk: "ПРОЙДЕНО", kk: "ЖҮРІЛДІ", pt: "DISTÂNCIA")
    }

    /// The Dynamic Island's compact column is ~40pt wide, so this one has to
    /// be shorter than `distanceCaption` even where the full word would fit.
    static func distanceCaptionShort(_ c: String) -> String {
        pick(c, ru: "ПРОЙДЕНО", en: "DIST", de: "STRECKE", es: "DIST",
             fr: "DIST", it: "DIST", pl: "DYST",
             id: "JARAK", tr: "MESAFE", fil: "DIST", uk: "ПРОЙДЕНО", kk: "ЖҮРІЛДІ", pt: "DIST")
    }

    static func km(_ c: String) -> String {
        pick(c, ru: "км", en: "km", de: "km", es: "km", fr: "km", it: "km", pl: "km",
             id: "km", tr: "km", fil: "km", uk: "км", kk: "км", pt: "km")
    }

    static func resume(_ c: String) -> String {
        pick(c, ru: "Продолжить", en: "Resume", de: "Weiter", es: "Continuar",
             fr: "Reprendre", it: "Riprendi", pl: "Wznów",
             id: "Lanjut", tr: "Devam", fil: "Ituloy", uk: "Продовжити", kk: "Жалғастыру", pt: "Continuar")
    }

    static func pause(_ c: String) -> String {
        pick(c, ru: "Пауза", en: "Pause", de: "Pause", es: "Pausa",
             fr: "Pause", it: "Pausa", pl: "Pauza",
             id: "Jeda", tr: "Duraklat", fil: "I-pause", uk: "Пауза", kk: "Кідірту", pt: "Pausar")
    }

    static func finish(_ c: String) -> String {
        pick(c, ru: "Завершить", en: "Finish", de: "Beenden", es: "Terminar",
             fr: "Terminer", it: "Chiudi", pl: "Zakończ",
             id: "Akhiri", tr: "Bitir", fil: "Tapusin", uk: "Завершити", kk: "Аяқтау", pt: "Encerrar")
    }

    /// The Dynamic Island's version of `finish` — one word, tighter.
    static func end(_ c: String) -> String {
        pick(c, ru: "Завершить", en: "End", de: "Ende", es: "Fin",
             fr: "Fin", it: "Fine", pl: "Koniec",
             id: "Selesai", tr: "Bitir", fil: "Tapos", uk: "Кінець", kk: "Соңы", pt: "Fim")
    }

    static func paused(_ c: String) -> String {
        pick(c, ru: "На паузе", en: "Paused", de: "Pausiert", es: "En pausa",
             fr: "En pause", it: "In pausa", pl: "Wstrzymane",
             id: "Dijeda", tr: "Duraklatıldı", fil: "Naka-pause", uk: "На паузі", kk: "Кідіртілді", pt: "Pausado")
    }

    static func recording(_ c: String) -> String {
        pick(c, ru: "Запись маршрута", en: "Recording", de: "Aufnahme läuft",
             es: "Grabando", fr: "Enregistrement", it: "Registrazione", pl: "Nagrywanie",
             id: "Merekam", tr: "Kayıt sürüyor", fil: "Nagre-record", uk: "Запис маршруту", kk: "Жазып жатыр", pt: "Gravando")
    }

    /// «ВРЕМЯ В ПУТИ» — caption over the running clock.
    static func timeCaption(_ c: String) -> String {
        pick(c, ru: "ВРЕМЯ В ПУТИ", en: "TIME", de: "ZEIT", es: "TIEMPO",
             fr: "DURÉE", it: "TEMPO", pl: "CZAS",
             id: "WAKTU", tr: "SÜRE", fil: "ORAS", uk: "ЧАС У ДОРОЗІ", kk: "ЖОЛДАҒЫ УАҚЫТ", pt: "TEMPO")
    }

    static func routeSaved(_ c: String) -> String {
        pick(c, ru: "Маршрут сохранен", en: "Route saved", de: "Route gesichert",
             es: "Ruta guardada", fr: "Trajet enregistré", it: "Percorso salvato",
             pl: "Trasa zapisana",
             id: "Rute tersimpan", tr: "Rota kaydedildi", fil: "Na-save ang ruta", uk: "Маршрут збережено", kk: "Бағыт сақталды", pt: "Trajeto salvo")
    }

    static func openDiary(_ c: String) -> String {
        pick(c, ru: "Открыть автодневник", en: "Open trip diary",
             de: "Fahrtenbuch öffnen", es: "Abrir el diario de viajes",
             fr: "Ouvrir le journal", it: "Apri il diario di viaggio",
             pl: "Otwórz dziennik tras",
             id: "Buka buku harian", tr: "Yol günlüğünü aç", fil: "Buksan ang talaarawan", uk: "Відкрити автощоденник", kk: "Жол күнделігін ашу", pt: "Abrir o diário")
    }
}
