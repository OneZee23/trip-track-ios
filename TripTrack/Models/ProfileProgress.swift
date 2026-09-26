import Foundation

/// A persisted reward snapshot, shared by the full profile push and its
/// progress-only retry. A fresh phone's defaults are not a request to reset
/// an existing account. In particular, an older `/auth/me` can return a
/// known level without XP: keep the level and leave the unknown XP alone.
struct ProfileProgress: Equatable {
    let level: Int?
    let xp: Int?
    let currentStreak: Int?
    let bestStreak: Int?

    init(entity: UserSettingsEntity) {
        let earnedXP = max(0, Int(entity.profileXP))
        let earnedLevel = max(Int(entity.profileLevel), LevelSystem.level(for: earnedXP))
        level = earnedXP > 0 || earnedLevel > 1 ? earnedLevel : nil
        xp = earnedXP > 0 ? earnedXP : nil
        currentStreak = entity.lastTripDate == nil ? nil : Int(entity.currentStreak)
        bestStreak = entity.bestStreak > 0 ? Int(entity.bestStreak) : nil
    }

    var hasProgress: Bool {
        level != nil || xp != nil || currentStreak != nil || bestStreak != nil
    }

    var request: ProfileUpdateRequest {
        ProfileUpdateRequest(
            displayName: nil, avatarEmoji: nil, profileBackground: nil,
            profileLevel: level, profileXp: xp, currentStreak: currentStreak,
            bestStreak: bestStreak, activeVehicleId: nil, language: nil,
            showOnPublicMap: nil)
    }
}
