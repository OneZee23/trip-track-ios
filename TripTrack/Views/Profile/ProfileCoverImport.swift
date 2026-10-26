import OSLog
import PhotosUI
import SwiftUI

/// Выбор фото обложки и их импорт в `ProfilePhotoStore` — один на два входа:
/// приглашение на «Я» (`ProfileCoverPager`) и строку «Обложка» в
/// «Мой профиль». Второй вход нужен, потому что приглашение можно скрыть.
struct ProfileCoverImport: ViewModifier {
    @Binding var isPresented: Bool
    @ObservedObject private var store = ProfilePhotoStore.shared
    @EnvironmentObject private var lang: LanguageManager
    @State private var picking: [PhotosPickerItem] = []
    @State private var toastItem: ToastItem?
    private static let log = Logger(subsystem: "com.triptrack", category: "profile.photos.picker")

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $picking,
                          maxSelectionCount: max(1, 9 - store.photos.count), matching: .images)
            .onChange(of: picking) { _, items in
                guard !items.isEmpty else { return }
                Task { await save(items) }
            }
            .onChange(of: store.limitReached) { _, reached in
                guard reached else { return }
                toastItem = ToastItem(type: .info, message: AppStrings.profilePhotosLimit(lang.language))
                store.limitReached = false
            }
            .toast(item: $toastItem)
    }

    private func save(_ items: [PhotosPickerItem]) async {
        defer { picking = [] }
        let session = store.session
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                try await store.add(data, session: session)
            } catch is CancellationError {
                break
            } catch ProfilePhotoStore.StoreError.limitReached {
                toastItem = ToastItem(type: .info, message: AppStrings.profilePhotosLimit(lang.language))
                break
            } catch {
                Self.log.error("profile photo import failed: \(error.localizedDescription)")
            }
        }
    }
}

extension View {
    func profileCoverImport(isPresented: Binding<Bool>) -> some View {
        modifier(ProfileCoverImport(isPresented: isPresented))
    }
}

/// Приглашение «Добавить обложку» скрыто человеком. Хранится на телефоне:
/// это вопрос вида, а не данные профиля.
enum ProfileCoverPrompt {
    static let hiddenKey = "profileCoverPromptHidden"
}
