import Foundation

extension AppStrings {
    /// The object and its saved variant are concrete: an avatar frame must not
    /// claim that an "ordinary background" is currently displayed. Retention of
    /// a replaced premium choice is local, so the promise names this iPhone.
    static func cosmeticRetainedChoice(_ lang: LanguageManager.Language,
                                       kind: ProShowcaseKind, name: String) -> String {
        let sentence: String
        switch lang {
        case .ru: sentence = "Сохранено: {kind} — {name}. После продления PRO этот выбор вернётся на этом iPhone."
        case .en: sentence = "Saved: {kind} — {name}. This choice will return on this iPhone when you renew PRO."
        case .de: sentence = "Gespeichert: {kind} — {name}. Nach der Verlängerung von PRO wird diese Auswahl auf diesem iPhone wiederhergestellt."
        case .es: sentence = "Guardado: {kind} — {name}. Esta opción volverá en este iPhone cuando renueves PRO."
        case .fr: sentence = "Choix conservé : {kind} — {name}. Il sera rétabli sur cet iPhone après le renouvellement de PRO."
        case .it: sentence = "Salvato: {kind} — {name}. Questa scelta tornerà su questo iPhone quando rinnovi PRO."
        case .pl: sentence = "Zapisano: {kind} — {name}. Ten wybór powróci na tym iPhonie po odnowieniu PRO."
        case .id: sentence = "Tersimpan: {kind} — {name}. Pilihan ini akan kembali di iPhone ini saat kamu memperpanjang PRO."
        case .tr: sentence = "Kaydedildi: {kind} — {name}. PRO’yu yenilediğinde bu seçim bu iPhone’da geri gelir."
        case .fil: sentence = "Naka-save: {kind} — {name}. Babalik ang pagpiling ito sa iPhone na ito kapag ni-renew mo ang PRO."
        case .uk: sentence = "Збережено: {kind} — {name}. Після поновлення PRO цей вибір повернеться на цьому iPhone."
        case .kk: sentence = "Сақталды: {kind} — {name}. PRO жазылымын ұзартқаннан кейін бұл таңдау осы iPhone құрылғысында қайта қолданылады."
        case .pt: sentence = "Salvo: {kind} — {name}. Esta escolha voltará neste iPhone quando você renovar o PRO."
        }
        return sentence.replacingOccurrences(of: "{kind}", with: kind.title(lang))
            .replacingOccurrences(of: "{name}", with: name)
    }
}
