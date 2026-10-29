import Foundation

/// Что начинает автозапись (0.9.3): движение или магнитола, как раньше, либо
/// только магнитола. `rawValue` — значение ключа `autoRecordTrigger` в
/// `UserDefaults`, менять его нельзя. Пустое или незнакомое значение — прежнее
/// поведение.
enum AutoRecordTrigger: String, CaseIterable, Codable {
    case motionOrStereo = "motionOrStereo"
    case stereoOnly = "stereoOnly"

    static func parse(_ rawValue: String?) -> AutoRecordTrigger {
        rawValue.flatMap(Self.init(rawValue:)) ?? .motionOrStereo
    }
}
