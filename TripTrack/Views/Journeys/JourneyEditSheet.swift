import SwiftUI

/// Правка путешествия: имя, окно дат, обложка — и удаление.
///
/// Сдвиг дат здесь и ЕСТЬ слияние и разделение: плечи не выбираются списком,
/// они те, что попали в окно. Поэтому отказ «даты заняты» показывается прямо
/// под датами и лист остаётся открытым — человек пришёл двигать границу, а не
/// узнавать, что она не двинулась.
struct JourneyEditSheet: View {
    let journey: Journey
    /// Снимки всех плеч — из них выбирается обложка. Своих снимков у
    /// путешествия нет и не будет: обложка это кадр одной из поездок.
    let photos: [TripPhoto]

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = JourneyManager.shared

    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var coverPhotoId: UUID?
    @State private var error: String?
    @State private var confirmDelete = false
    /// Сколько поездок попадёт в окно с выбранными датами. Считается при
    /// каждой смене даты, а не в `body`: это выборка из базы.
    @State private var windowTripCount: Int = 0
    /// Убранные рукой плечи, которые лежат внутри выбранного окна, — полка
    /// возврата. Читается из базы вместе со счётом, а не в `body`.
    @State private var removedLegs: [Trip] = []
    /// Отмеченные к возврату. Применяются в `save()`, как обложка и имя: в
    /// этом листе до нажатия «Сохранить» не меняется НИЧЕГО, и возврат — не
    /// исключение из правила.
    @State private var returningIds: Set<UUID> = []
    /// Окно, которым лист ОТКРЫЛСЯ (после зажима). От него меряется
    /// `datesMoved` — см. её доку.
    @State private var openedStart: Date
    @State private var openedEnd: Date

    /// Имя длиннее этого не помещается ни в шапку, ни в карточку ленты, а
    /// обрезать его при показе значило бы принять то, что нельзя прочитать.
    ///
    /// Не `private`: тот же предел стоит в листе СОЗДАНИЯ
    /// (`JourneyComposerSheet`). Два разных предела на двух листах означали
    /// бы, что правка молча съедает хвост имени, которое приняло создание.
    static let titleLimit = 60

    /// «Сейчас» — снимок времени, взятый при сборке листа.
    ///
    /// Обещать «ровно один раз за открытие» здесь нельзя: лист приходит из
    /// вычисляемого свойства внутри `.sheet {}` (`JourneyDetailView.editSheet`),
    /// поэтому `init` переисполняется на каждом обновлении родителя, и `now`
    /// перечитывается вместе с ним. Держится это на двух вещах. Зажатие границ
    /// уходит в `State(initialValue:)`, который после первой сборки уже не
    /// применяется, — даты человека повторный `init` не двигает. А
    /// `startBounds`/`endBounds` монотонны по `now`: с ходом времени диапазоны
    /// только расширяются и по построению содержат уже выбранную дату, так что
    /// подъехавшая полночь не выкидывает выбор за границы и не переворачивает
    /// диапазон. Хранимое значение всё равно лучше вызова `Date()` прямо в
    /// `body`: одно и то же «сейчас» видят оба диапазона и `clampedWindow`.
    private let now: Date

    init(journey: Journey, photos: [TripPhoto], now: Date = Date()) {
        self.journey = journey
        self.photos = photos
        self.now = now
        // Обрезается ЗДЕСЬ, а не первым нажатием клавиши: длинное имя,
        // принятое прежней сборкой, иначе исчезало бы хвостом молча, посреди
        // правки одной буквы.
        _title = State(initialValue: String((journey.title ?? "").prefix(Self.titleLimit)))
        let window = Self.clampedWindow(start: journey.startDate, end: journey.endDate, now: now)
        _startDate = State(initialValue: window.start)
        _endDate = State(initialValue: window.end)
        _openedStart = State(initialValue: window.start)
        _openedEnd = State(initialValue: window.end)
        _coverPhotoId = State(initialValue: journey.coverPhotoId)
    }

    // MARK: - Окно, которым безопасно открыть пикеры

    /// Границы, приведённые к тому, что пикеры вообще могут показать.
    ///
    /// Путешествие — это то, что уже проехали, поэтому будущего в границах
    /// быть не должно. Но в базе оно БЫВАЕТ: окно «15–30 сентября» завёл
    /// прежней сборкой человек, которому будущее ещё не запрещали. Открывать
    /// такую запись надо чем-то валидным — зажатым в прошлое и в правильном
    /// порядке, — а не падать на построении диапазона `start...now`, у
    /// которого нижняя граница больше верхней.
    ///
    /// Открытое окно (`end == nil`) закрывается первой же правкой: два выбора
    /// дат — это две даты, и притворяться, будто вторая ещё не выбрана, некуда.
    /// Закрывается СЕГОДНЯШНИМ днём, а не собственным началом: по
    /// `Journey.contains` открытое окно тянется вперёд до конца времён, и
    /// свернуть его в одни сутки значило бы выбросить все плечи, кроме
    /// первого дня, — при сохранении одного лишь ИМЕНИ. Сегодня — ближайшая
    /// граница, которая не теряет ни одного уже записанного плеча: поездок из
    /// будущего не бывает.
    static func clampedWindow(start: Date, end: Date?, now: Date,
                              calendar: Calendar = .current) -> (start: Date, end: Date) {
        let cappedStart = notFuture(start, now: now, calendar: calendar)
        // Конец берётся от `now`, а тот всё равно проходит через зажим: у
        // будущего начала оба конца сходятся в сегодня.
        let cappedEnd = notFuture(end ?? now, now: now, calendar: calendar)
        // Перепутанные местами границы — не отказ, а описка: окно
        // разворачивается само, ровно как в `save()`.
        return (min(cappedStart, cappedEnd), max(cappedStart, cappedEnd))
    }

    /// «Не в будущем» с точностью до ДНЯ: пикер выбирает дни, и подрезать
    /// сегодняшние 23:59 до текущих 10:00 значит менять хранимое значение там,
    /// где человек не увидит разницы.
    static func notFuture(_ date: Date, now: Date, calendar: Calendar = .current) -> Date {
        calendar.isDate(date, inSameDayAs: now) ? date : min(date, now)
    }

    /// Последнее мгновение суток — календарём, а не `+ 86_400 - 1`.
    ///
    /// Ровно 24 часа — это не ровно сутки: в день перевода часов их 23 или 25,
    /// и арифметическая граница съезжала на час — то отрезая последний час
    /// суток от окна, то прихватывая первый час следующих. `HistoryFolding`
    /// на эти же грабли уже наступил (см. `dayRange`); правило одно на оба
    /// места — сутки считает календарь.
    static func endOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        return next.addingTimeInterval(-1)
    }

    /// Диапазоны, которые невозможно перевернуть.
    ///
    /// `a...b` из двух произвольных дат — не пустой диапазон, а падение
    /// («Range requires lowerBound <= upperBound»). Именно так лист и умирал:
    /// `startDate...Date()` при старте 15 сентября и «сегодня» 10-м. Поэтому
    /// верхняя граница всегда поднимается и до нижней, и до ТЕКУЩЕГО значения
    /// — диапазон валиден и содержит выбор при любых данных. Будущее при этом
    /// закрыто: выше `now` граница уходит только вслед за уже выбранным
    /// значением, которое пикер обязан уметь показать.
    ///
    /// Считаются чистыми функциями, чтобы «перевернуть нельзя» проверялось
    /// тестом, а не открытым листом на телефоне владельца.
    static func startBounds(start: Date, end: Date, now: Date) -> ClosedRange<Date> {
        Date.distantPast...max(start, min(end, now))
    }

    static func endBounds(start: Date, end: Date, now: Date) -> ClosedRange<Date> {
        min(start, end)...max(end, now)
    }

    private var startRange: ClosedRange<Date> {
        Self.startBounds(start: startDate, end: endDate, now: now)
    }

    private var endRange: ClosedRange<Date> {
        Self.endBounds(start: startDate, end: endDate, now: now)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 18) {
            header(c)
            nameField(c)
            datesBlock(c)
            removedShelf(c)
            coverShelf(c)
            saveButton(c)
            deleteButton(c)
        }
        .padding(20)
        .background(c.bg)
        .animation(.easeInOut(duration: 0.15), value: error)
        .animation(.easeInOut(duration: 0.15), value: windowTripCount)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: returningIds)
        .task { recountWindow() }
        .onChange(of: startDate) { _, new in adjustStart(new) }
        .onChange(of: endDate) { _, new in adjustEnd(new) }
        .appConfirm(
            isPresented: $confirmDelete,
            title: AppStrings.journeyDelete(lang.language),
            message: AppStrings.journeyDeleteHint(lang.language),
            actions: [
                AppDialogAction(AppStrings.delete(lang.language), kind: .destructive,
                                identifier: "journey_edit_delete_confirm") {
                    manager.delete(id: journey.id)
                    dismiss()
                }
            ]
        )
    }

    // MARK: - Куски

    private func header(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 10) {
            Text(AppStrings.journeyEdit(lang.language))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(c.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                NavCircleIcon(systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.close(lang.language))
        }
    }

    private func nameField(_ c: AppTheme.Colors) -> some View {
        TextField(AppStrings.journeyTitlePlaceholder(lang.language), text: $title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(c.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("journey_edit_title")
            .onChange(of: title) { _, new in
                if new.count > Self.titleLimit { title = String(new.prefix(Self.titleLimit)) }
            }
    }

    /// Две системные «компактные» даты — это КОНТРОЛ, а не системное окно:
    /// запрет на чужие модалки к ним не относится.
    private func datesBlock(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.journeyDates(lang.language))
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(c.textTertiary)
                .textCase(.uppercase)
            // Даты — только прошедшие и в порядке: путешествие это то, что
            // уже проехали, а «с 15 по 30 сентября» в будущем давало пустое
            // окно с картой-заглушкой. Границы сюда приходят готовыми
            // (`startRange`/`endRange`) — сырое `a...b` из двух дат здесь
            // однажды уже уронило лист.
            HStack(spacing: 10) {
                datePicker($startDate, in: startRange, id: "journey_edit_start")
                Text("\u{2013}")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.textTertiary)
                datePicker($endDate, in: endRange, id: "journey_edit_end")
                Spacer(minLength: 0)
            }
            // Живой счёт: сколько поездок окажется внутри. Ноль — сохранять
            // нечего, и кнопка это знает.
            Text(windowTripCount == 0
                 ? AppStrings.journeyDatesEmpty(lang.language)
                 : "\(windowTripCount) \(AppStrings.nounTrips(lang.language, windowTripCount)) \(AppStrings.journeyInDates(lang.language))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(windowTripCount == 0 ? AppTheme.red : c.textSecondary)
                .accessibilityIdentifier("journey_edit_window_count")
            if let error {
                Text(error)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.red)
                    .accessibilityIdentifier("journey_edit_error")
            }
        }
    }

    private func datePicker(_ value: Binding<Date>, in range: ClosedRange<Date>, id: String) -> some View {
        DatePicker("", selection: value, in: range, displayedComponents: .date)
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(AppTheme.accent)
            .accessibilityIdentifier(id)
    }

    /// Инвариант держится и при правке, а не только при открытии: пикер отдаёт
    /// значение из своего диапазона, но диапазоны у двух дат разные, и,
    /// уведя начало за конец, человек оставил бы конец по ту сторону.
    private func adjustStart(_ new: Date) {
        let fixed = Self.notFuture(new, now: now)
        if new != fixed { startDate = fixed }
        if endDate < fixed { endDate = fixed }
        error = nil
        recountWindow()
    }

    private func adjustEnd(_ new: Date) {
        let fixed = Self.notFuture(new, now: now)
        if new != fixed { endDate = fixed }
        if startDate > fixed { startDate = fixed }
        error = nil
        recountWindow()
    }

    /// Полка обложек — как у отметки: нажатие выбирает, подпись переезжает.
    /// Снимков нет вовсе — полки нет: пустая рамка с заголовком обещает выбор,
    /// которого не будет.
    @ViewBuilder
    private func coverShelf(_ c: AppTheme.Colors) -> some View {
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.journeyCover(lang.language))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(c.textTertiary)
                    .textCase(.uppercase)
                ScrollView(.horizontal, showsIndicators: false) {
                    // `LazyHStack`: снимки здесь — ВСЕ снимки всех плеч, а у
                    // месячного путешествия их сотни, и обычный стек читал бы
                    // с диска каждую миниатюру до первого кадра листа.
                    LazyHStack(spacing: 8) {
                        ForEach(photos) { coverChip($0, c) }
                    }
                    .padding(.vertical, 2)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: coverPhotoId)
        }
    }

    private func coverChip(_ photo: TripPhoto, _ c: AppTheme.Colors) -> some View {
        let isCover = coverPhotoId == photo.id
        return Button {
            Haptics.selection()
            // Второе нажатие снимает выбор: обложка — не обязанность, без неё
            // карточка берёт карту.
            coverPhotoId = isCover ? nil : photo.id
        } label: {
            AsyncThumbnailView(filename: photo.filename, maxSize: 180)
                .frame(width: 74, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottom) {
                    if isCover {
                        Text(AppStrings.journeyCover(lang.language))
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.accent, in: Capsule())
                            .padding(.bottom, 5)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isCover ? AppTheme.accent : c.border, lineWidth: isCover ? 3 : 1)
                }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel(isCover
            ? "\(AppStrings.nounPhotos(lang.language, 1)), \(AppStrings.journeyCover(lang.language))"
            : AppStrings.nounPhotos(lang.language, 1))
        .accessibilityAddTraits(isCover ? .isSelected : [])
    }

    // MARK: - Полка возврата

    /// Убранные плечи — и единственный способ вернуть их обратно.
    ///
    /// До этой правки `excludedTripIds` только рос: «Убрать из путешествия»
    /// спрашивало «точно?», зная, что назад хода нет. Сдвиг дат исключение не
    /// отменяет (оно сильнее окна), а собрать новое путешествие вокруг
    /// убранной поездки не даёт проверка пересечения окон — старое окно эти
    /// даты занимает. Оставалось удалить путешествие и собрать заново, потеряв
    /// имя и обложку.
    ///
    /// Полка стоит ЗДЕСЬ, а не отменой в тосте. Тост живёт три с половиной
    /// секунды: он закрывает промах пальцем, но не решение, о котором человек
    /// передумал назавтра, — а односторонней дверь остаётся и с ним. Своего
    /// экрана она не стоит: рядом уже правятся окно и обложка, то есть весь
    /// остальной состав путешествия, и живой счёт под датами уже отвечает на
    /// тот же вопрос — сколько поездок останется внутри.
    ///
    /// Карточка показывает ровно то же, что строка листа сборки: миниатюру
    /// маршрута, день и километры. «Владикавказ» и «Владикавказ» по имени не
    /// различить, а по нитке маршрута — сразу.
    @ViewBuilder
    private func removedShelf(_ c: AppTheme.Colors) -> some View {
        if !removedLegs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.journeyRemovedLegs(lang.language))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(c.textTertiary)
                    .textCase(.uppercase)
                ScrollView(.horizontal, showsIndicators: false) {
                    // `LazyHStack` и горизонтальная полка по той же причине,
                    // что у обложек: убранных бывает сколько угодно, а высота
                    // листа от их числа зависеть не должна — он без прокрутки,
                    // и «Сохранить» обязано остаться на экране.
                    LazyHStack(spacing: 8) {
                        ForEach(removedLegs) { removedCard($0, c) }
                    }
                    .padding(.vertical, 2)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func removedCard(_ trip: Trip, _ c: AppTheme.Colors) -> some View {
        let returning = returningIds.contains(trip.id)
        let l = lang.language
        return Button {
            Haptics.selection()
            if returning { returningIds.remove(trip.id) } else { returningIds.insert(trip.id) }
            // Счёт под датами отвечает сразу: возврат меняет состав окна
            // ровно так же, как сдвиг границы.
            recountWindow()
        } label: {
            HStack(spacing: 9) {
                legThumbnail(trip, c)
                VStack(alignment: .leading, spacing: 2) {
                    Text(JourneyFormat.dayDate(trip.startDate, language: l))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(Measure.distance(
                        metres: trip.distance, unit: distanceUnit, lang: l, style: .grouped))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                }
                returnPill(returning, l)
            }
            .padding(8)
            .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(returning ? AppTheme.accent : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("\(AppStrings.journeyReturnLeg(l)), \(JourneyFormat.tripTitle(trip, language: l))")
        .accessibilityAddTraits(returning ? .isSelected : [])
        .accessibilityIdentifier("journey_edit_return_leg")
    }

    /// Слово, а не одна иконка: «вернуть» — это то, что случится, и нажатие
    /// обязано сказать об этом до, а не после (CLAUDE.md, «Нажатие обязано
    /// отвечать»). Залитая пилюля означает «вернётся при сохранении».
    private func returnPill(_ on: Bool, _ l: LanguageManager.Language) -> some View {
        HStack(spacing: 4) {
            Image(systemName: on ? "checkmark" : "arrow.uturn.backward")
                .font(.system(size: 9, weight: .heavy))
            Text(AppStrings.journeyReturnLeg(l))
                .font(.system(size: 10.5, weight: .heavy))
                .lineLimit(1)
        }
        .foregroundStyle(on ? Color.white : AppTheme.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(on ? AppTheme.accent : AppTheme.accent.opacity(0.14), in: Capsule())
    }

    /// Меньше двух точек — `MapSnapshotPreview` мерцает вечно и читается как
    /// вечная загрузка; та же заглушка, что в листе сборки.
    @ViewBuilder
    private func legThumbnail(_ trip: Trip, _ c: AppTheme.Colors) -> some View {
        let coords = trip.previewCoordinates
        Group {
            if coords.count > 1 {
                MapSnapshotPreview(coordinates: coords, tripId: trip.id, height: 44, width: 56)
            } else {
                ZStack {
                    Rectangle().fill(c.card)
                    Image(systemName: "map.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
            }
        }
        .frame(width: 56, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Гейт сохранения

    /// Двигал ли даты ЧЕЛОВЕК. Не то же самое, что «поедут ли границы в базе»,
    /// на что отвечает `plannedWindow()`.
    ///
    /// Гейт сохранения спрашивал именно второе — сравнивал пикеры с ХРАНИМОЙ
    /// записью. Но границы к тому моменту уже подвинул `clampedWindow` в
    /// `init`: у окна с `endDate == nil` и у окна, залезающего в будущее,
    /// «даты тронуты» выходило истинным ещё до того, как человек коснулся
    /// экрана. Такая запись БЕЗ плеч оставалась с единственным действием
    /// «Удалить» — тот самый тупик, который для обычного пустого путешествия
    /// уже закрыли, просто с другого входа.
    ///
    /// Поэтому меряется от окна, которым лист ОТКРЫЛСЯ, а не от хранимой
    /// записи. Чистой функцией — чтобы это держал тест, а не открытый лист.
    static func datesMoved(start: Date, end: Date, opened: (start: Date, end: Date),
                           calendar: Calendar = .current) -> Bool {
        !calendar.isDate(min(start, end), inSameDayAs: opened.start)
            || !calendar.isDate(max(start, end), inSameDayAs: opened.end)
    }

    private var saveDisabled: Bool {
        Self.datesMoved(start: startDate, end: endDate, opened: (openedStart, openedEnd))
            && windowTripCount == 0
    }

    private func saveButton(_ c: AppTheme.Colors) -> some View {
        Button {
            save()
        } label: {
            Text(AppStrings.save(lang.language))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressableCardStyle())
        // Гаснет только когда ДАТЫ ТРОГАЛИ и в новом окне пусто: сдвинуть
        // границу в никуда нельзя. Путешествие БЕЗ плеч при этом остаётся
        // живой записью (CLAUDE.md, «Путешествие БЕЗ плеч — тоже строка») —
        // убрал последнее плечо, а переименовать и сменить обложку по-прежнему
        // можно. Прежняя проверка по одному счёту оставляла такому
        // путешествию единственное действие: удалить.
        .disabled(saveDisabled)
        .opacity(saveDisabled ? 0.5 : 1)
        .accessibilityIdentifier("journey_edit_save")
    }

    private func deleteButton(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            confirmDelete = true
        } label: {
            Text(AppStrings.journeyDelete(lang.language))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.red)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(AppTheme.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("journey_edit_delete")
    }

    // MARK: - Сохранение

    /// Окно, которое запишет `save()`, — и ровно его же меряет счёт под
    /// пикерами.
    ///
    /// Одна функция на оба вопроса нарочно. Раньше счёт всегда брал полные
    /// сутки, а `save()` при нетронутом дне оставлял хранимое время: «3
    /// поездки в этих датах» сохранялись двумя, потому что мерили разные окна.
    ///
    /// День НЕ трогали — граница остаётся ровно та, что в базе. Иначе
    /// переименование двигало бы даты: выборы дат отдают полночь, и сохранение
    /// имени растягивало окно на целые сутки в обе стороны. Оно могло
    /// прихватить чужую поездку или упереться в соседнее путешествие — то есть
    /// отказать в сохранении ИМЕНИ из-за дат, которых никто не менял.
    ///
    /// Тронули — конец окна становится КОНЦОМ выбранных суток: выбрав «17
    /// сентября», человек имеет в виду весь день, а полночь отрезала бы всё,
    /// что в этот день ездилось.
    ///
    /// У окна, залезающего в будущее, «не трогали» не выполняется вовсе:
    /// границу уже сдвинул в сегодня `clampedWindow` при открытии листа, и
    /// первое же сохранение — хоть бы и одного имени — перепишет дату в базе
    /// на сегодняшнюю. Это НАМЕРЕННО. Вернуть будущую границу как было значило
    /// бы сохранить окно, которое пикер не умеет показать, то есть починить
    /// лист ровно до следующего открытия.
    private func plannedWindow() -> Journey {
        // Границы, перепутанные местами, — это не отказ, а описка: окно
        // разворачивается само, потому что человек всё равно имел в виду его.
        let calendar = Calendar.current
        var window = journey
        if !calendar.isDate(min(startDate, endDate), inSameDayAs: journey.startDate) {
            window.startDate = calendar.startOfDay(for: min(startDate, endDate))
        }
        if !endDayUntouched {
            window.endDate = Self.endOfDay(max(startDate, endDate), calendar: calendar)
        }
        // Единственное место, где список исключений УМЕНЬШАЕТСЯ. Считается
        // здесь, а не в `save()`, чтобы живой счёт под датами мерил ровно то
        // окно, которое сохранится.
        if !returningIds.isEmpty {
            window.excludedTripIds.removeAll { returningIds.contains($0) }
        }
        return window
    }

    /// Конец окна остаётся хранимым: выбранный день — тот же, что в базе.
    /// Открытое окно (`endDate == nil`) считается тронутым: `save()` его
    /// закроет, второй даты у листа быть не может.
    private var endDayUntouched: Bool {
        guard let stored = journey.endDate else { return false }
        return Calendar.current.isDate(max(startDate, endDate), inSameDayAs: stored)
    }

    private func recountWindow() {
        let planned = plannedWindow()
        windowTripCount = manager.trips(in: planned).count
        // Полка спрашивает ТЕ ЖЕ даты, но ПОЛНЫЙ список исключений: карточка
        // отмеченного к возврату плеча обязана остаться на месте, иначе
        // передумать было бы негде. И наоборот — плечо само уходит с полки,
        // если человек увёл границу так, что оно оказалось вне окна: возврат
        // ему уже не помог бы, а карточка обещала бы.
        var shelf = planned
        shelf.excludedTripIds = journey.excludedTripIds
        removedLegs = manager.excludedTrips(in: shelf)
    }

    private func save() {
        var updated = plannedWindow()
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmed.isEmpty ? nil : trimmed
        updated.coverPhotoId = coverPhotoId
        updated.lastModifiedAt = Date()
        do {
            try manager.update(updated)
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
            self.error = AppStrings.journeyOverlaps(lang.language)
        }
    }
}
