import XCTest
@testable import TripTrack

/// Что показать, когда профиль не открылся (0.6.3).
///
/// Сервер отвечает `USER_NOT_FOUND` НА ВСЕ ТРИ случая сразу — профиля нет, он
/// закрыт, или между вами блокировка — и делает это намеренно: любой другой
/// ответ позволял бы по ссылке проверять, существует ли аккаунт. Клиент обязан
/// сохранить эту неразличимость.
///
/// Единственное исключение — когда личность УЖЕ приехала из публичной ленты
/// (`preloaded`). Там существование аккаунта и так публично, скрывать нечего, и
/// честнее сказать «закрытый профиль» с именем, чем сделать вид, что человека,
/// которого только что видели в ленте, не существует.
final class ProfileUnavailableTests: XCTestCase {

    private let notFound = APIError.unknownServer(code: "USER_NOT_FOUND", message: "User not found")
    private let author = SocialAuthor(
        id: UUID(), displayName: "Марина К.", avatarEmoji: "😎", profileLevel: 7)

    // MARK: - Личность уже публична

    func testClosedProfileKeepsTheIdentityThatCameFromTheFeed() {
        let state = ProfileUnavailableState.from(error: notFound, preloaded: author)

        guard case .closed(let name, let avatar) = state else {
            return XCTFail("ожидалось состояние закрытого профиля, получено \(state)")
        }
        XCTAssertEqual(name, "Марина К.")
        XCTAssertEqual(avatar, "😎")
    }

    // MARK: - Прямая ссылка

    func testColdLinkNeverImpliesTheAccountExists() {
        let state = ProfileUnavailableState.from(error: notFound, preloaded: nil)

        XCTAssertEqual(
            state, .unavailable,
            "по прямой ссылке нельзя подтверждать существование аккаунта — иначе ссылка станет инструментом проверки"
        )
    }

    func testColdLinkStaysAnonymousEvenWithABlankAuthor() {
        // Автор без имени и аватара не даёт ничего, что стоило бы показать:
        // «Закрытый профиль» под пустым кружком выглядит как сломанный экран.
        let blank = SocialAuthor(id: UUID(), displayName: "  ", avatarEmoji: nil, profileLevel: 1)

        let state = ProfileUnavailableState.from(error: notFound, preloaded: blank)

        XCTAssertEqual(state, .unavailable)
    }

    // MARK: - Прочие отказы остаются отказами

    func testNetworkFailureIsNotAClosedProfile() {
        let state = ProfileUnavailableState.from(
            error: .network(URLError(.notConnectedToInternet)), preloaded: author)

        guard case .transient = state else {
            return XCTFail("обрыв связи — это не «профиль закрыт», и предлагать он должен повтор, а не подписку")
        }
    }

    func testUnknownServerErrorIsTransient() {
        let state = ProfileUnavailableState.from(
            error: .unknownServer(code: "SOMETHING_NEW", message: "boom"), preloaded: nil)

        guard case .transient = state else {
            return XCTFail("незнакомый серверный код нельзя выдавать за закрытый профиль")
        }
    }

    func testBannedAccountIsNotDisguisedAsAClosedProfile() {
        let state = ProfileUnavailableState.from(error: .userBanned, preloaded: author)

        guard case .transient = state else {
            return XCTFail("бан — отдельный случай, и молча превращать его в «закрытый профиль» нечестно")
        }
    }
}
