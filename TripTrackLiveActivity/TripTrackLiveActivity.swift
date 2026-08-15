import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Colors

// 0.6.0 (Figma 356:119/365:119): brand accent #EB571E, cream light bg,
// #19191F dark bg.
private let accentOrange = Color(red: 235/255, green: 87/255, blue: 30/255)
private let accentRed = Color(red: 1.0, green: 0.231, blue: 0.188)
private let lightBg = Color(red: 248/255, green: 246/255, blue: 242/255)
private let darkBg = Color(red: 25/255, green: 25/255, blue: 31/255)

// MARK: - Adaptive colors

private struct WidgetColors {
    let bg: Color
    let text: Color
    let textSecondary: Color
    let textTertiary: Color
    let cellBg: Color
    let buttonBg: Color

    static func from(isDark: Bool) -> WidgetColors {
        isDark ? .dark : .light
    }

    static let light = WidgetColors(
        bg: lightBg,
        text: Color.black.opacity(0.85),
        textSecondary: Color.black.opacity(0.45),
        textTertiary: Color.black.opacity(0.3),
        cellBg: Color.black.opacity(0.04),
        buttonBg: Color.black.opacity(0.05)
    )

    static let dark = WidgetColors(
        bg: darkBg,
        text: Color.white.opacity(0.9),
        textSecondary: Color.white.opacity(0.5),
        textTertiary: Color.white.opacity(0.35),
        cellBg: Color.white.opacity(0.08),
        buttonBg: Color.white.opacity(0.1)
    )
}

// MARK: - Availability helper

extension WidgetConfiguration {
    func withWatchSupport() -> some WidgetConfiguration {
        if #available(iOSApplicationExtension 18.0, *) {
            return supplementalActivityFamilies([.small])
        } else {
            return self
        }
    }
}

// MARK: - Widget

struct TripTrackLiveActivity: Widget {
    /// Both island buttons share a height and a radius so the row reads as one
    /// control strip rather than two controls that happened to land together.
    ///
    /// The expanded island has a hard height budget and clips whatever exceeds
    /// it — at 34pt clock plus 38pt buttons the control strip was sliced in
    /// half by the island's bottom edge. These are sized against the tallest
    /// arrangement that was observed to fit whole.
    private static let islandButtonHeight: CGFloat = 32
    private static let islandButtonRadius: CGFloat = 12

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            if context.state.isFinished {
                FinishedLockScreenView(context: context)
                    .widgetURL(URL(string: "triptrack://trip/\(context.attributes.tripId.uuidString)"))
            } else {
                LiveLockScreenView(context: context)
                    .widgetURL(URL(string: "triptrack://recording"))
            }
        } dynamicIsland: { context in
            DynamicIsland {
                // Figma «Расширенный (удержание)»: labelled speed on the left of
                // the camera, distance on its right, the running clock big and
                // centred underneath, then the controls.
                //
                // The stats used to be built as `Text(…) + Text(…)` string
                // concatenation across two fonts, and both regions came out
                // empty on device — a black band where the numbers should be.
                // Plain stacks render.
                DynamicIslandExpandedRegion(.leading) {
                    if context.state.isFinished {
                        Image("app_icon")
                            .resizable().scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        statBlock(
                            caption: LiveActivityStrings.speedCaption(context.state.language),
                            value: "\(Int(context.state.speedKmh))",
                            unit: LiveActivityStrings.kmh(context.state.language),
                            alignment: .leading
                        )
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.state.isFinished {
                        statBlock(
                            caption: LiveActivityStrings.distanceCaption(context.state.language),
                            value: fmtDist(context.state.distanceKm),
                            unit: LiveActivityStrings.km(context.state.language),
                            alignment: .trailing
                        )
                    }
                }
                // The clock belongs in `.bottom`, not `.center`.
                //
                // The three top regions share one row, so a centre region that
                // asks for `maxWidth: .infinity` takes the whole width and
                // squeezes the flanks to nothing — «СКОРОСТЬ 59 км/ч» came out
                // as a column of single letters pressed against the island's
                // edges. `.bottom` spans the full width on its own line, which
                // is where the mock puts the clock anyway.
                DynamicIslandExpandedRegion(.bottom) {
                    // One grid for the whole block: three rows on a single
                    // 10pt rhythm, every one of them the full width of the
                    // region. No per-element horizontal padding — that is what
                    // left the gradient rule inset further than the buttons
                    // under it and made the stack look hand-nudged.
                    VStack(spacing: 8) {
                        // `Text(timerInterval:)` reserves the width of the
                        // widest time it could ever show and sits at the
                        // leading edge of it, so the clock hung off to the left
                        // instead of under the camera.
                        Group {
                            if context.state.isFinished {
                                Text(context.state.finalDuration ?? "")
                                    .monospacedDigit()
                            } else {
                                timerText(context: context)
                                    .foregroundStyle(context.state.isPaused ? accentOrange : .white)
                            }
                        }
                        .font(.system(size: 28, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)

                        // The speed scale from the app's route colouring — the
                        // one line in the mock that says this is a driving app
                        // and not a stopwatch.
                        Capsule()
                            .fill(LinearGradient(
                                colors: [
                                    Color(red: 0.30, green: 0.85, blue: 0.39),
                                    Color(red: 1.00, green: 0.84, blue: 0.04),
                                    Color(red: 0.98, green: 0.27, blue: 0.23),
                                ],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(height: 3)
                            .opacity(context.state.isPaused ? 0.35 : 1)

                        if !context.state.isFinished {
                            HStack(spacing: 10) {
                                // Pause takes the room, because pausing is what
                                // you do dozens of times and finishing is what
                                // you do once — same rule as the phone's HUD.
                                Button(intent: PauseTripIntent()) {
                                    HStack(spacing: 7) {
                                        Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                                            .font(.system(size: 13, weight: .bold))
                                        Text(context.state.isPaused
                                             ? (LiveActivityStrings.resume(context.state.language))
                                             : (LiveActivityStrings.pause(context.state.language)))
                                            .font(.system(size: 13, weight: .bold))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: Self.islandButtonHeight)
                                }
                                .buttonStyle(.plain)
                                // Same rule as the Lock Screen: paused has to
                                // look different from running, not just say so.
                                .background(
                                    context.state.isPaused ? accentOrange : Color.white.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: Self.islandButtonRadius)
                                )

                                // Figma draws this one outlined. Outlined and
                                // grey is what it looked like on the Lock
                                // Screen too, where it read as disabled — so it
                                // takes the same warm red it took there: the
                                // word plus a colour that says what it does.
                                Button(intent: StopTripIntent()) {
                                    Text(LiveActivityStrings.finish(context.state.language))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(accentRed)
                                        .lineLimit(1)
                                        .padding(.horizontal, 16)
                                        .frame(height: Self.islandButtonHeight)
                                }
                                .buttonStyle(.plain)
                                .background(accentRed.opacity(0.16),
                                            in: RoundedRectangle(cornerRadius: Self.islandButtonRadius))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Self.islandButtonRadius)
                                        .strokeBorder(accentRed.opacity(0.5), lineWidth: 1)
                                )
                            }
                        }
                    }
                    // The flanking regions and this one do not share a gutter:
                    // measured off the render, the stat blocks sit ~6pt deeper
                    // than the buttons, so «СКОРОСТЬ» and «Пауза» did not share
                    // a left edge. Matching by moving THIS block inward is the
                    // safe direction — the other way pushes the captions back
                    // into the island's corner curve, which is what clipped
                    // them before.
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                if context.state.isFinished {
                    Image("app_icon")
                        .resizable().scaledToFit()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    // Figma 03b: red REC dot + speed on the leading side. The
                    // dot is the state light — it goes amber pause while the
                    // trip is held, which is why the speed can read 0.
                    //
                    // A `Label` here spaced the dot and the number apart with
                    // its own icon gutter and pinned the pair against the left
                    // edge of the island. The mock has them tight and inset.
                    HStack(spacing: 4) {
                        if context.state.isPaused {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(accentOrange)
                        } else {
                            Circle().fill(accentRed).frame(width: 7, height: 7)
                        }
                        Text("\(Int(context.state.speedKmh))").font(.caption.bold())
                    }
                    .padding(.leading, 3)
                }
            } compactTrailing: {
                if context.state.isFinished {
                    Text(fmtDist(context.state.distanceKm) + (" " + LiveActivityStrings.km(context.state.language))).font(.caption)
                } else {
                    // Figma 03b: elapsed time on the trailing side — frozen
                    // rather than ticking while paused (`timerText` handles
                    // that), because the pause used to swap this whole region
                    // for a lone glyph. The island sizes the trailing slot to
                    // its content, so that glyph got pinned against the right
                    // edge with a hole where the time had been.
                    timerText(context: context)
                        .font(.caption)
                        .frame(maxWidth: 44)
                        .foregroundStyle(context.state.isPaused ? accentOrange : .primary)
                }
            } minimal: {
                if context.state.isFinished {
                    Image("app_icon")
                        .resizable().scaledToFit()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if context.state.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(accentOrange)
                } else {
                    // Figma 03b: red dot (static — ActivityKit minimal can't pulse).
                    Circle().fill(accentRed).frame(width: 8, height: 8)
                }
            }
            .widgetURL(context.state.isFinished
                ? URL(string: "triptrack://trip/\(context.attributes.tripId.uuidString)")
                : URL(string: "triptrack://recording"))
        }
        .withWatchSupport()
    }

    /// One labelled number for the expanded island's flanks (Figma
    /// «Расширенный»): a tiny grey caption over the value with its unit.
    private func statBlock(
        caption: String, value: String, unit: String, alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(caption)
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.3)
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 17, weight: .heavy))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity,
               alignment: alignment == .leading ? .leading : .trailing)
        // The regions run right up to the island's rounded corners, so text
        // pinned to their outer edge gets eaten by the curve — «СКОРОСТЬ» lost
        // its С and «ПРОЙДЕНО» its О. Hold it off the bend.
        .padding(alignment == .leading ? .leading : .trailing, 6)
    }

    @ViewBuilder
    private func timerText(context: ActivityViewContext<TripActivityAttributes>) -> some View {
        if context.state.isPaused, let elapsed = context.state.elapsedAtPause {
            Text(fmtTime(elapsed)).monospacedDigit()
        } else if context.state.isPaused {
            Text("--:--").monospacedDigit()
        } else {
            let adj = context.attributes.startDate.addingTimeInterval(context.state.pausedDuration)
            Text(timerInterval: adj...(.distantFuture), countsDown: false).monospacedDigit()
        }
    }

    private func fmtDist(_ km: Double) -> String {
        km < 10 ? String(format: "%.1f", km) : String(format: "%.0f", km)
    }

    private func fmtTime(_ s: TimeInterval) -> String {
        let t = max(0, Int(s)); let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Live Recording Lock Screen

private struct LiveLockScreenView: View {
    let context: ActivityViewContext<TripActivityAttributes>
    private var lng: String { context.state.language }
    private var isPixel: Bool { context.attributes.vehicleAvatar.hasPrefix("pixel_car_") }
    private var c: WidgetColors { .from(isDark: context.state.isDarkMode) }

    var body: some View {
        VStack(spacing: 0) {
            // Row 1: Header + TripTrack label
            HStack(spacing: 10) {
                // Car icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentOrange.opacity(0.1))
                        .frame(width: 36, height: 36)
                    if isPixel {
                        Image(context.attributes.vehicleAvatar)
                            .resizable().scaledToFit()
                            .frame(width: 28, height: 28)
                    } else {
                        Text(context.attributes.vehicleAvatar)
                            .font(.system(size: 18))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(context.state.isPaused
                             ? (LiveActivityStrings.paused(context.state.language))
                             : (LiveActivityStrings.recording(context.state.language)))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(c.text)
                            .lineLimit(1)
                        if !context.state.isPaused {
                            Circle().fill(accentRed).frame(width: 6, height: 6)
                        }
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "car.fill").font(.system(size: 10))
                        Text(context.attributes.vehicleName).font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(c.textSecondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)

                // TripTrack branding
                Text("TripTrack")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.bottom, 10)

            // Row 2: Stats
            HStack(spacing: 8) {
                statCell(
                    label: LiveActivityStrings.timeCaption(lng),
                    value: { timerValue }
                )
                statCell(
                    label: LiveActivityStrings.distanceCaptionShort(lng),
                    value: {
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text(fmtDist(context.state.distanceKm))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(c.text)
                            Text(LiveActivityStrings.km(context.state.language))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(c.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                )
            }
            .padding(.bottom, 8)

            // Row 3: Controls — 0.6.0 safety redesign (Figma 356:119): END is
            // a de-emphasized grey ghost chip on the far LEFT (users kept
            // fat-fingering the old bottom-right stop next to the lock-screen
            // camera), Pause is the wide primary on the right.
            HStack(spacing: 8) {
                // End stays small and on the left (the fat-finger fix above),
                // but grey-on-grey made it read as disabled rather than as
                // «this ends the recording». Red says what it does; small and
                // left still says «not by accident».
                Button(intent: StopTripIntent()) {
                    Text(LiveActivityStrings.end(context.state.language))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accentRed)
                        .frame(width: 90)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .background(accentRed.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(accentRed.opacity(0.45), lineWidth: 1)
                )

                // Paused is a state you should be able to read at a glance
                // from the Lock Screen: the button goes solid accent and says
                // «Продолжить», instead of looking identical to running.
                Button(intent: PauseTripIntent()) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(context.state.isPaused
                             ? (LiveActivityStrings.resume(context.state.language))
                             : (LiveActivityStrings.pause(context.state.language)))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(context.state.isPaused ? .white : c.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                }
                .buttonStyle(.plain)
                .background(
                    context.state.isPaused ? Color(red: 0.92, green: 0.34, blue: 0.12) : c.buttonBg,
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .activityBackgroundTint(c.bg)
    }

    private func statCell<V: View>(label: String, @ViewBuilder value: () -> V) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(c.textTertiary)
                .tracking(0.4)
            value()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(c.cellBg, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var timerValue: some View {
        Group {
            if context.state.isPaused, let elapsed = context.state.elapsedAtPause {
                Text(fmtTime(elapsed))
            } else if context.state.isPaused {
                Text("--:--")
            } else {
                let adj = context.attributes.startDate.addingTimeInterval(context.state.pausedDuration)
                Text(timerInterval: adj...(.distantFuture), countsDown: false)
            }
        }
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(c.text)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func fmtDist(_ km: Double) -> String {
        km < 10 ? String(format: "%.1f", km) : String(format: "%.0f", km)
    }

    private func fmtTime(_ s: TimeInterval) -> String {
        let t = max(0, Int(s)); let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Gradient colors (finished screen)

private let gradientStart = Color(red: 1.0, green: 0.78, blue: 0.47)
private let gradientEnd = Color(red: 1.0, green: 0.63, blue: 0.31)

// MARK: - Finished Lock Screen

private struct FinishedLockScreenView: View {
    let context: ActivityViewContext<TripActivityAttributes>
    private var lng: String { context.state.language }
    private var isPixel: Bool { context.attributes.vehicleAvatar.hasPrefix("pixel_car_") }

    var body: some View {
        VStack(spacing: 0) {
            // Row 1: vehicle avatar + text + AppIcon
            HStack(spacing: 12) {
                // Left: vehicle avatar
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 44, height: 44)
                    if isPixel {
                        Image(context.attributes.vehicleAvatar)
                            .resizable().scaledToFit()
                            .frame(width: 32, height: 32)
                    } else {
                        Text(context.attributes.vehicleAvatar)
                            .font(.system(size: 22))
                    }
                }

                // Center: title + subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(LiveActivityStrings.routeSaved(lng))
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(Color.black.opacity(0.8))
                        .lineLimit(1)
                    Text(summaryText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Right: AppIcon
                Image("app_icon")
                    .resizable().scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.bottom, 12)

            // Row 2: Glass CTA button
            Text(LiveActivityStrings.openDiary(lng))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [gradientStart, gradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .activityBackgroundTint(accentOrange)
    }

    private var summaryText: String {
        let d = context.state.distanceKm < 10
            ? String(format: "%.1f", context.state.distanceKm)
            : String(format: "%.0f", context.state.distanceKm)
        let u = LiveActivityStrings.km(lng)
        return "\(context.attributes.vehicleName) • \(d) \(u) • \(context.state.finalDuration ?? "--:--")"
    }
}
