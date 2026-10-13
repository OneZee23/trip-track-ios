import CarPlay
import Combine
import Foundation

/// Собирает шаблон CarPlay из `CarPlayScreen.Model` и обновляет его, пока
/// человек ведёт.
///
/// Здесь только сборка: ЧТО показать, решает чистая функция, и проверяется она
/// тестом. Этот слой нельзя проверить ничем, кроме симулятора CarPlay, —
/// сказано вслух, а не спрятано.
@MainActor
final class CarPlayController {
    private let interface: CPInterfaceController
    private var template: CPInformationTemplate?
    private var watch: AnyCancellable?
    /// Что нарисовано прямо сейчас. Экран автомобиля не переписывается, пока
    /// картинка та же: `objectWillChange` у `MapViewModel` стреляет на каждый
    /// фикс GPS, а строки меняются раз в несколько секунд.
    private var shown: CarPlayScreen.Model?
    private var link: CarPlayLink { .shared }

    init(interface: CPInterfaceController) {
        self.interface = interface
    }

    // MARK: - Жизненный цикл сцены

    func start() {
        let template = makeTemplate(for: model())
        self.template = template
        interface.setRootTemplate(template, animated: false, completion: nil)
        subscribe()
        // Сцена умеет подключиться РАНЬШЕ, чем соберётся экран телефона.
        // Тогда модели ещё нет, и экран честно говорит «откройте приложение»;
        // как только она появится — пересобираемся и подписываемся.
        link.whenAttached { [weak self] in
            self?.subscribe()
            self?.refresh()
        }
    }

    func stop() {
        watch?.cancel()
        watch = nil
        link.stopWaiting()
        template = nil
        shown = nil
    }

    // MARK: - Обновление

    private func subscribe() {
        guard let publisher = link.publisher else { return }
        watch?.cancel()
        // Раз в секунду, и не чаще: расстояние в машине меняется медленно, а
        // `objectWillChange` приходит на каждый фикс. Шестьдесят перерисовок
        // шаблона в минуту экран автомобиля не просил.
        //
        // И `RunLoop.main` здесь ОБЯЗАТЕЛЕН, а не «чтобы на главном потоке»:
        // `objectWillChange` приходит ДО записи значения (та же ловушка, что
        // у подписки карты «Атласа»), а доставка через runloop случается
        // следующим витком — то есть `refresh()` читает УЖЕ новые числа.
        // Уберёшь окно «ради отзывчивости» — экран автомобиля станет
        // показывать предыдущий фикс.
        watch = publisher
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        let next = model()
        guard next != shown else { return }
        shown = next
        guard let template else { return }
        // Заголовок ОБНОВЛЯЕТСЯ вместе со строками, и это не формальность: он
        // и есть ответ на «пишется или стоит» («Записывается» → «На паузе»).
        // Забыв его здесь, экран автомобиля показывал бы «Записывается» над
        // остановленной записью — то есть врал бы о единственном, что человеку
        // за рулём от него нужно. `layout` при этом задаётся только при
        // создании (в заголовках SDK он `readonly`), а `title` — `copy`.
        template.title = next.title
        template.items = next.items.map {
            CPInformationItem(title: $0.title, detail: $0.detail)
        }
        template.actions = next.actions.map(button(for:))
    }

    private func model() -> CarPlayScreen.Model {
        CarPlayScreen.model(link.state,
                            unit: DistanceUnit.current,
                            lang: LanguageManager.currentLanguage)
    }

    // MARK: - Сборка

    private func makeTemplate(for model: CarPlayScreen.Model) -> CPInformationTemplate {
        shown = model
        return CPInformationTemplate(
            title: model.title,
            layout: .leading,
            items: model.items.map { CPInformationItem(title: $0.title, detail: $0.detail) },
            actions: model.actions.map(button(for:)))
    }

    private func button(for action: CarPlayScreen.Action) -> CPTextButton {
        // `.confirm` у «Завершить» — это УТВЕРЖДАЮЩИЙ стиль, а не красный:
        // завершение сохраняет поездку, то есть это тот исход, за которым
        // человек и ехал. Разрушительного действия на экране автомобиля нет
        // ни одного, поэтому `.cancel` здесь не используется вовсе.
        let style: CPTextButtonStyle = action == .finish ? .confirm : .normal
        return CPTextButton(
            title: CarPlayScreen.title(action, lang: LanguageManager.currentLanguage),
            textStyle: style
        ) { [weak self] _ in
            self?.link.perform(action)
            self?.refresh()
        }
    }
}
