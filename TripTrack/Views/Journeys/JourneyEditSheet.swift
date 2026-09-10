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

    /// Имя длиннее этого не помещается ни в шапку, ни в карточку ленты, а
    /// обрезать его при показе значило бы принять то, что нельзя прочитать.
    private static let titleLimit = 60

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
        _title = State(initialValue: journey.title ?? "")
        let window = Self.clampedWindow(start: journey.startDate, end: journey.endDate, now: now)
        _startDate = State(initialValue: window.start)
        _endDate = State(initialValue: window.end)
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
    static func clampedWindow(start: Date, end: Date?, now: Date,
                              calendar: Calendar = .current) -> (start: Date, end: Date) {
        let cappedStart = notFuture(start, now: now, calendar: calendar)
        // Конец берётся от УЖЕ зажатого начала, иначе будущее вернулось бы
        // через него.
        let cappedEnd = notFuture(end ?? cappedStart, now: now, calendar: calendar)
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
            coverShelf(c)
            saveButton(c)
            deleteButton(c)
        }
        .padding(20)
        .background(c.bg)
        .animation(.easeInOut(duration: 0.15), value: error)
        .animation(.easeInOut(duration: 0.15), value: windowTripCount)
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
                    HStack(spacing: 8) {
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
        .disabled(windowTripCount == 0)
        .opacity(windowTripCount == 0 ? 0.5 : 1)
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

    /// Окно с выбранными датами, как его посчитает `save()`: границы дней,
    /// те же исключённые поездки.
    private func recountWindow() {
        let calendar = Calendar.current
        var probe = journey
        probe.startDate = calendar.startOfDay(for: min(startDate, endDate))
        probe.endDate = calendar.startOfDay(for: max(startDate, endDate)).addingTimeInterval(86_400 - 1)
        windowTripCount = manager.trips(in: probe).count
    }

    private func save() {
        var updated = journey
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmed.isEmpty ? nil : trimmed
        // Границы, перепутанные местами, — это не отказ, а описка: окно
        // разворачивается само, потому что человек всё равно имел в виду его.
        let calendar = Calendar.current
        let pickedStart = min(startDate, endDate)
        let pickedEnd = max(startDate, endDate)
        // День НЕ трогали — граница остаётся ровно та, что в базе.
        //
        // Иначе переименование двигало бы даты: выборы дат отдают полночь, и
        // сохранение имени растягивало окно на целые сутки в обе стороны. Оно
        // могло прихватить чужую поездку или упереться в соседнее путешествие
        // — то есть отказать в сохранении ИМЕНИ из-за дат, которых никто не
        // менял.
        //
        // Тронули — конец окна становится КОНЦОМ выбранных суток: выбрав «17
        // сентября», человек имеет в виду весь день, а полночь отрезала бы всё,
        // что в этот день ездилось.
        //
        // У окна, залезающего в будущее, «не трогали» не выполняется вовсе:
        // границу уже сдвинул в сегодня `clampedWindow` при открытии листа, и
        // первое же сохранение — хоть бы и одного имени — перепишет дату в
        // базе на сегодняшнюю. Это НАМЕРЕННО. Вернуть будущую границу как было
        // значило бы сохранить окно, которое пикер не умеет показать, то есть
        // починить лист ровно до следующего открытия.
        if !calendar.isDate(pickedStart, inSameDayAs: journey.startDate) {
            updated.startDate = calendar.startOfDay(for: pickedStart)
        }
        let endDayUntouched = journey.endDate.map { calendar.isDate(pickedEnd, inSameDayAs: $0) } ?? false
        if !endDayUntouched {
            updated.endDate = calendar.startOfDay(for: pickedEnd).addingTimeInterval(86_400 - 1)
        }
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
