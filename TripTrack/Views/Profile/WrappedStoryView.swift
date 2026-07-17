import SwiftUI

/// «Итоги года» story (fork FK-5, option A): minimal tap-through pager over
/// full-bleed gradients — one REAL client-side stat per slide, nothing
/// fabricated. Slides with missing data are skipped by the builder; the Я
/// hero only presents this cover when ≥2 slides exist (else it routes to
/// Статистика). Share = plain text summary via UIActivityViewController —
/// the S1/S2/S3 share-image pipeline is deliberately out of scope.
struct WrappedStoryView: View {
    let aggregates: MeAggregates

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0

    struct Slide {
        let kicker: String
        let value: String
        let label: String
        let sub: String?
        let colors: [Color]
    }

    var body: some View {
        let slides = Self.slides(from: aggregates, lang: lang.language)

        ZStack {
            TabView(selection: $index) {
                ForEach(Array(slides.enumerated()), id: \.offset) { i, slide in
                    slideView(slide, isLast: i == slides.count - 1)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            // Tap-through: anywhere advances; the last slide keeps its CTA.
            .contentShape(Rectangle())
            .onTapGesture {
                guard index < slides.count - 1 else { return }
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.25)) { index += 1 }
            }

            VStack {
                HStack(spacing: 4) {
                    // Stories-style progress capsules.
                    ForEach(0..<slides.count, id: \.self) { i in
                        Capsule()
                            .fill(.white.opacity(i <= index ? 0.9 : 0.35))
                            .frame(height: 3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.trailing, 44)

                Spacer()
            }
            .padding(.top, 12)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        ZStack {
                            Circle().fill(.white.opacity(0.22))
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wrapped_close")
                }
                .padding(.horizontal, 16)
                Spacer()
            }
        }
        .accessibilityIdentifier("wrapped_story")
    }

    private func slideView(_ slide: Slide, isLast: Bool) -> some View {
        ZStack {
            LinearGradient(colors: slide.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(slide.kicker)
                    .font(.custom("PressStart2P-Regular", size: 10))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)

                Text(slide.value)
                    .font(.system(size: 46, weight: .heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)

                Text(slide.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                if let sub = slide.sub {
                    Text(sub)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }

                if isLast {
                    Button {
                        Haptics.action()
                        presentShare()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                            Text(AppStrings.share(lang.language))
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.22), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                }
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Slide builder (skips empty data)

    static func slides(from a: MeAggregates, lang l: LanguageManager.Language) -> [Slide] {
        let kicker = "\(AppStrings.wrappedKicker(l)) · \(a.year)"
        var result: [Slide] = []

        if a.yearKm > 0 {
            result.append(Slide(
                kicker: kicker,
                value: GarageFormat.odometer(a.yearKm),
                label: AppStrings.wrappedKmYear(l),
                sub: AppStrings.tripsCount(l, n: a.yearTripCount),
                colors: [AppTheme.accent, AppTheme.teal]
            ))
        }
        if a.yearHours >= 1 {
            result.append(Slide(
                kicker: kicker,
                value: "\(Int(a.yearHours.rounded()))",
                label: AppStrings.statsHours(l),
                sub: nil,
                colors: [AppTheme.blue, AppTheme.teal]
            ))
        }
        if a.maxDayKm > 0 {
            result.append(Slide(
                kicker: kicker,
                value: "\(GarageFormat.odometer(a.maxDayKm)) \(AppStrings.km(l))",
                label: AppStrings.wrappedBestDay(l),
                sub: nil,
                colors: [AppTheme.green, AppTheme.teal]
            ))
        }
        if let region = a.topRegion {
            result.append(Slide(
                kicker: kicker,
                value: region,
                label: AppStrings.wrappedTopRegion(l),
                sub: nil,
                colors: [AppTheme.teal, AppTheme.blue]
            ))
        }
        if a.yearStreak >= 2 {
            result.append(Slide(
                kicker: kicker,
                value: AppStrings.daysCount(l, n: a.yearStreak),
                label: AppStrings.recordStreak(l).lowercased(),
                sub: AppStrings.recordStreakSub(l),
                colors: [AppTheme.accent, AppTheme.red]
            ))
        }
        return Array(result.prefix(5))
    }

    private func presentShare() {
        let text = AppStrings.wrappedShareText(
            lang.language,
            year: aggregates.year,
            km: GarageFormat.odometer(aggregates.yearKm),
            trips: aggregates.yearTripCount
        )
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        var vc = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        vc?.present(av, animated: true)
    }
}
