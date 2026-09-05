import SwiftUI
import MapKit
import OSLog

private let recLog = Logger(subsystem: "com.triptrack", category: "record-screen")

/// Where both bottom control blocks dock. The artboard is 780 pt tall and the
/// idle card (144:1182) and the recording block (146:1199) both end at 756 — the
/// design docks them to one y. 8 pt put the idle card's bottom edge below the
/// home indicator, which drew straight over the slider; a full safe-area inset
/// overshot the other way and left a band of map showing under a panel that is
/// supposed to sit at the bottom.
///
/// The recording block used `safeAreaBottom + 12` (~46 pt on a home-indicator
/// phone) against the card's 24, so the whole control block hopped ~22 pt the
/// moment recording started.
private let controlBlockBottomInset: CGFloat = 24

struct TrackingView: View {
    @EnvironmentObject var viewModel: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    @State private var safeAreaTop: CGFloat = 59
    @State private var tabBarHeight: CGFloat = 88
    /// Mirrors `viewModel.trackingMapDidRender` so the fade animates locally;
    /// the source of truth outlives this view (see the view model).
    @State private var isMapReady = false
    /// The chip in the top bar opens the same picker the Idle card does —
    /// the canon's «один и тот же sheet отовсюду». Changing car mid-drive
    /// reassigns the WHOLE trip, it does not split it.
    @State private var showVehiclePicker = false
    /// Гараж, открытый прямо с экрана записи. Свой `NavigationStack`: экран
    /// записи — корень таба и стека не имеет, а `GarageView` намеренно живёт
    /// без собственного, потому что под «Я» он полноценная страница.
    @State private var showGarage = false
    /// См. `IdleHUDView.pendingGarage` — гараж ждёт закрытия шторки.
    @State private var pendingGarage = false
    /// Ending a recording is the one irreversible control on this screen.
    @State private var confirmStop = false

    var body: some View {
        let _ = recLog.notice("body: isRecording=\(viewModel.isRecording, privacy: .public) isMapReady=\(isMapReady, privacy: .public) refusal=\(String(describing: viewModel.startRefusal), privacy: .public)")
        return ZStack {
            // Map is ALWAYS instantiated so "ready" can never hang on a missed
            // async hop. The loader overlay sits on top until the map's first
            // render (onMapReady) or the timeout fallback in `.task` below.
            MapViewRepresentable(
                userTrackingMode: $viewModel.userTrackingMode,
                overlays: viewModel.trackOverlays,
                isDarkMap: viewModel.isDarkMap,
                bottomInset: viewModel.isRecording ? 0 : idleHUDInset,
                zoomDelta: $viewModel.zoomDelta,
                isRecording: viewModel.isRecording,
                onCameraDistanceChanged: { viewModel.currentCameraDistance = $0 },
                onVisibleRectChanged: { viewModel.handleVisibleRectChange($0) },
                onFogRendererCreated: { viewModel.fogRenderer = $0 },
                onMapReady: { markMapReady() }
            )
            .ignoresSafeArea()
            .allowsHitTesting(!viewModel.isRecording)

            // Loading overlay until the map reports its first render. Never
            // swallows taps on the slide-to-start control beneath it.
            if !isMapReady {
                CarLoadingView()
                    .allowsHitTesting(false)
            }

            // Only the overlay that is actually on screen exists.
            //
            // Both used to be mounted at all times and crossfaded by opacity,
            // with `accessibilityHidden` meant to keep the invisible one out
            // of the accessibility tree. A hierarchy dump says it does not:
            // while the idle card was up, `tracking_stop` and `tracking_pause`
            // were still listed, and VoiceOver activation bypasses
            // `allowsHitTesting` — so a blind user could «pause» a trip that
            // was not running. `.transition(.opacity)` under the animation
            // below crossfades exactly the same way.
            if viewModel.isRecording {
                recordingOverlay
                    .transition(.opacity)
            } else {
                idleOverlay
                    .transition(.opacity)
            }

            // Shared top bar — always the same position. Слева шеврон выхода
            // (в записи рядом с ним встаёт чип машины), справа GPS.
            //
            // That slot used to hold a «REC · 0:34:12» pill. The canon rules
            // it out — «БЕЗ отдельного REC-индикатора — запись очевидна из
            // HUD (Стоп/пауза + тикающее время)» — and it was right: the HUD
            // already shows a red STOP button and seconds ticking over, so
            // the pill spent the whole drive repeating them. The chip earns
            // the slot instead, and it is the only place the recording screen
            // says which car you are driving.
            //
            // Re-ruled by the owner on 2026-08-13 against Figma 146:1196,
            // which still draws the pill: the chip stays, the pill does not
            // come back.
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    // Шеврон стоит ВСЕГДА, и в простое, и в записи.
                    //
                    // Канон рисует верхний ряд как «чип слева + GPS справа», но
                    // из этого следовало, что во время записи выхода с экрана
                    // нет вообще: в простое слот занимал шеврон, а на старте
                    // записи его подменял чип. Решение владельца (02.09):
                    // выход важнее правила. Побочно ряд стал СТАБИЛЬНЕЕ —
                    // шеврон больше не прыгает, чип просто встаёт рядом.
                    //
                    // Запись живёт в фоне (фоновая геолокация + Live Activity),
                    // так что уход на другой экран её не обрывает.
                    backButton
                    if viewModel.isRecording {
                        VehicleChip(compact: true,
                                    isTransfer: viewModel.tripManager.activeTrip?.isTransfer ?? false) {
                            showVehiclePicker = true
                        }
                    }
                    Spacer()
                    if !(viewModel.locationDenied && !viewModel.isRecording) {
                        GPSIndicatorView(
                            accuracy: viewModel.gpsAccuracy,
                            isStale: viewModel.isRecording && viewModel.gpsSignalStale
                        )
                    }
                }
                // The GPS legend hangs off the pill as an overlay, so it is
                // out of this stack's flow — and the signal banners below,
                // being later siblings, painted straight over it. Exactly
                // when you tap «GPS потерян» to find out what it means, the
                // banner about it covers the answer.
                .zIndex(1)

                if viewModel.isRecording && viewModel.isPaused {
                    pausedPill
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Signal-state banners are suppressed while paused — the
                // paused pill already explains why nothing is moving, and
                // signal loss is expected in a parking garage.
                if viewModel.isRecording && !viewModel.isPaused && viewModel.gpsSignalStale {
                    signalLostBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if viewModel.isRecording && !viewModel.isPaused
                            && viewModel.gpsAccuracy > 35 {
                    weakSignalToast
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, safeAreaTop + 4)
            .animation(.easeInOut(duration: 0.25), value: viewModel.isPaused)
            .animation(.easeInOut(duration: 0.25), value: viewModel.gpsSignalStale)
            .animation(.easeInOut(duration: 0.25), value: viewModel.startRefusal)
            .ignoresSafeArea(edges: .top)
        }
        .animation(.easeInOut(duration: 0.5), value: viewModel.isRecording)
        .onChange(of: viewModel.isRecording) { _, now in
            recLog.notice("VIEW sees isRecording=\(now, privacy: .public)")
        }
        // Does the change even reach this view? If this fires while `body:`
        // stays silent, SwiftUI is receiving the invalidation and skipping the
        // redraw. If it never fires, the subscription itself is broken.
        .onReceive(viewModel.objectWillChange) { _ in
            recLog.notice("objectWillChange received")
        }
        // Гараж поверх записи, а не переключением таба: «назад» возвращает
        // сюда же, к записи, откуда человек и шёл его открывать.
        .fullScreenCover(isPresented: $showGarage) {
            NavigationStack {
                GarageView()
                    .environmentObject(lang)
            }
        }
        .sheet(isPresented: $showVehiclePicker, onDismiss: {
            guard pendingGarage else { return }
            pendingGarage = false
            showGarage = true
        }) {
            // The chip is reachable mid-recording, and a trip carries the car
            // it was stamped with at start — picking a different one has to
            // reach the trip in flight, or the drive lands on the wrong car
            // while the chip claims otherwise.
            // Метка `onPick:` обязательна: после появления `onPickTransfer`
            // хвостовое замыкание без метки всё ещё связывается верно, но
            // компилятор ругается на устаревшее обратное сопоставление.
            VehiclePickerSheet(
                checkedVehicleId: .some(viewModel.tripManager.activeTrip?.vehicleId),
                onPick: { picked in
                    guard viewModel.isRecording,
                          let tripId = viewModel.tripManager.activeTrip?.id else { return }
                    // ПОРЯДОК ВАЖЕН: `setTransfer(true)` внутри себя обнуляет
                    // машину, поэтому снимать метку надо ДО того, как машину
                    // назначили. Наоборот — и только что выбранная машина
                    // молча улетит в nil, а поездка окажется ничьей.
                    if viewModel.tripManager.activeTrip?.isTransfer == true {
                        viewModel.tripManager.setTransfer(for: tripId, isTransfer: false)
                    }
                    viewModel.tripManager.updateVehicle(for: tripId, vehicleId: picked)
                },
                showsTransferOption: true,
                isTransferSelected: viewModel.tripManager.activeTrip?.isTransfer ?? false,
                onPickTransfer: {
                    guard viewModel.isRecording,
                          let tripId = viewModel.tripManager.activeTrip?.id else { return }
                    viewModel.tripManager.setTransfer(for: tripId, isTransfer: true)
                },
                onManageGarage: { pendingGarage = true }
            )
            .environmentObject(lang)
        }
        .overlay {
            if confirmStop {
                stopConfirmSheet
                    // Everything behind the scrim is out of bounds while the
                    // question is on screen — for the rotor as much as for a
                    // finger.
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
            }
        }
        .onAppear {
            // Returning to a map that has already rendered once: no loader,
            // no fade, nothing to announce.
            isMapReady = viewModel.trackingMapDidRender
            recLog.notice("onAppear didRender=\(viewModel.trackingMapDidRender, privacy: .public) denied=\(viewModel.locationDenied, privacy: .public) recovery=\(viewModel.showRecoveryPrompt, privacy: .public) recording=\(viewModel.isRecording, privacy: .public)")
            viewModel.refreshTripStats()
            viewModel.requestLocationPermission()
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first {
                safeAreaTop = window.safeAreaInsets.top
                tabBarHeight = 54 + window.safeAreaInsets.bottom
            }
        }
        .task {
            // Hard fallback so the loader can NEVER outlive ~0.6s even if the
            // map's render callback is delayed (offline tiles, contended cold
            // start). The old fire-and-forget onAppear Task could be starved on
            // a busy launch and leave the spinner stuck forever — the reported
            // "Готов к поездке" infinite-loading hang.
            try? await Task.sleep(for: .milliseconds(600))
            markMapReady()
        }
        .onDisappear {
            if !viewModel.isRecording {
                viewModel.stopLocationUpdates()
            }
        }
        // The trip summary sheet is presented from ContentView's root —
        // «Завершить и сохранить» in the recovery prompt can finish a trip
        // while ANY tab is active, and this view only exists on .record.
    }

    // MARK: - Recording Overlay (Figma 146:1178 — everything lives at the bottom)

    private var recordingOverlay: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                // Speedometer — 92pt fixed accent (grey while paused/lost).
                VStack(spacing: 0) {
                    Text(speedText)
                        .font(.inter(92, weight: .heavy))
                        .kerning(-3.68)
                        .foregroundStyle(speedDimmed ? mapDimmedText : AppTheme.accent)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: speedText)
                    Text(AppStrings.kmh(lang.language).uppercased(lang.language))
                        .font(.inter(13, weight: .medium))
                        .kerning(0.78)
                        .foregroundStyle(mapSecondaryText)
                }

                // Metrics glass panel: distance | time | altitude.
                HStack(spacing: 0) {
                    statItem(
                        value: String(format: "%.1f", viewModel.distance),
                        unit: AppStrings.km(lang.language),
                        icon: "point.topleft.down.curvedto.point.bottomright.up"
                    )
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 1, height: 40)
                    statItem(
                        value: viewModel.duration,
                        unit: nil,
                        icon: "clock"
                    )
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 1, height: 40)
                    statItem(
                        value: "\(Int(viewModel.altitude))",
                        unit: AppStrings.m(lang.language),
                        icon: "mountain.2"
                    )
                }
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(red: 40/255, green: 40/255, blue: 42/255).opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )

                controlsRow
            }
            .padding(.horizontal, 16)
            .padding(.bottom, controlBlockBottomInset)

        }
        .ignoresSafeArea(edges: [.top, .bottom])
    }

    /// Stop small on the left, pause/resume wide on the right.
    ///
    /// This is the layout the Live Activity already uses, and for the reason
    /// written there: people kept hitting the wide bottom-right control by
    /// accident, and on a phone that control should be the reversible one.
    /// Pause is the move you make dozens of times a drive; ending is the move
    /// you make once and cannot take back — so the big target under the thumb
    /// is pause, and stopping asks first.
    ///
    /// This MIRRORS the canon (Figma 146:1227 puts the wide red «Стоп» on the
    /// right), and it stays mirrored: ruled by the owner on 2026-08-13, after
    /// a conformance pass raised it. Do not "fix" it back — the design file is
    /// what needs annotating.
    private var controlsRow: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    confirmStop = true
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(AppTheme.red, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            }
            // Tap-only: both controls sit under the thumb that also reaches for
            // the home gesture, and a flick that begins on one of them must not
            // count as pressing it. See TapOnlyButtonStyle.
            .buttonStyle(TapOnlyButtonStyle())
            .accessibilityIdentifier("tracking_stop")
            .accessibilityLabel(AppStrings.stop(lang.language))

            Button {
                Haptics.tap()
                viewModel.togglePause()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 19, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(viewModel.isPaused
                         ? AppStrings.resumeAction(lang.language)
                         : AppStrings.pauseAction(lang.language))
                        .font(.inter(16, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                // Paused has to be legible as a STATE, not just as a label:
                // solid accent while paused, dark glass while running. The old
                // white-at-15% disc read as nothing at all on a daylight map.
                .background(
                    viewModel.isPaused
                        ? AppTheme.accent
                        : Color(red: 40/255, green: 40/255, blue: 42/255).opacity(0.78),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            }
            .buttonStyle(TapOnlyButtonStyle())
            .accessibilityIdentifier("tracking_pause")
        }
    }

    // MARK: - Stop confirmation

    /// Asks before ending a recording, in this screen's own language.
    ///
    /// It used to be a system `confirmationDialog`. That puts an iOS plate —
    /// light chrome, system greys, its own type — in the middle of a dark map,
    /// and it looked borrowed from another app. Worse, a centred modal answers
    /// a question you asked with your thumb at the bottom of the screen.
    ///
    /// So: the same dark-glass card the HUD is built from, docked to the same
    /// edge as the controls it is about, with the safe answer nearest the thumb
    /// and the irreversible one furthest from it.
    private var stopConfirmSheet: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissStopConfirm() }
                .transition(.opacity)
                // A plain overlay is not a modal to VoiceOver: the rotor walked
                // straight past the scrim onto «Пауза» and the stop button
                // underneath, so a blind user could pause the trip while being
                // asked whether to end it.
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text(AppStrings.stopConfirmTitle(lang.language))
                        .font(.inter(20, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(AppStrings.stopConfirmBody(lang.language))
                        .font(.inter(13.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // What is about to be saved. The question «завершить?» is much
                // easier to answer when the trip it is about is on the card.
                HStack(spacing: 8) {
                    Text(confirmDistanceText)
                    Text("·").foregroundStyle(.white.opacity(0.3))
                    Text(viewModel.duration)
                }
                .font(.inter(14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(0.08)))

                VStack(spacing: 8) {
                    confirmButton(
                        title: AppStrings.stopConfirmAction(lang.language),
                        icon: "checkmark",
                        fill: AppTheme.red,
                        identifier: "stop_confirm_finish"
                    ) {
                        Haptics.success()
                        confirmStop = false
                        viewModel.toggleRecording()
                    }

                    if !viewModel.isPaused {
                        confirmButton(
                            title: AppStrings.stopConfirmPause(lang.language),
                            icon: "pause.fill",
                            fill: Color.white.opacity(0.1),
                            identifier: "stop_confirm_pause"
                        ) {
                            Haptics.tap()
                            dismissStopConfirm()
                            viewModel.togglePause()
                        }
                    }

                    Button {
                        Haptics.tap()
                        dismissStopConfirm()
                    } label: {
                        Text(AppStrings.cancel(lang.language))
                            .font(.inter(16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("stop_confirm_cancel")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 10)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color(red: 28/255, green: 28/255, blue: 30/255))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
            .padding(.horizontal, 16)
            .padding(.bottom, safeAreaBottom + 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func confirmButton(
        title: String,
        icon: String,
        fill: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.inter(16, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(fill, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func dismissStopConfirm() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            confirmStop = false
        }
    }

    /// Recorded distance with the separator the language actually uses.
    private var confirmDistanceText: String {
        let s = String(format: "%.1f", viewModel.distance)
        let n = s.replacingOccurrences(of: ".", with: AppStrings.decimalSeparator(lang.language))
        return "\(n) \(AppStrings.km(lang.language))"
    }

    // MARK: - Recording status pills / banners (Figma 146:1178, 477:119, 435:119, 494:119)

    /// Says out loud why a start did not take, and — when the recovery prompt
    /// is the reason — puts that prompt back on screen, since resolving it is
    /// the actual way forward.
    private func refusalToast(_ refusal: MapViewModel.StartRefusal) -> some View {
        let amber = Color(red: 0xFF/255, green: 0x9F/255, blue: 0x0A/255)
        let text: String
        switch refusal {
        case .recoveryPending: text = AppStrings.startRefusedRecovery(lang.language)
        case .locationDenied:  text = AppStrings.startRefusedNoGeo(lang.language)
        case .unknown:         text = AppStrings.startRefusedUnknown(lang.language)
        case .noFix:           text = AppStrings.startRefusedNoFix(lang.language)
        }
        // The reason gets the full width and the way out sits under it.
        //
        // Side by side, «Всё равно начать» took 134pt of a 343pt row on a
        // 375pt phone, leaving 142pt for a sentence that needs three lines in
        // it — under `.lineLimit(2)` the explanation was cut off mid-word,
        // which is a poor way to explain anything. A capsule cannot grow to
        // two rows, so the container becomes a rounded rectangle when it has
        // to hold both.
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: refusal == .noFix
                      ? "antenna.radiowaves.left.and.right"
                      : "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(amber)
                Text(text)
                    .font(.inter(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            // An underground car park can withhold a fix for as long as you
            // are in it. Waiting is the right default, but never being able to
            // record is not an acceptable end state — so the refusal carries
            // its own way past itself.
            if refusal == .noFix {
                Button {
                    Haptics.tap()
                    viewModel.startRefusal = nil
                    viewModel.requestStartRecording(force: true)
                } label: {
                    Text(AppStrings.startAnyway(lang.language))
                        .font(.inter(13, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(AppTheme.accent.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("start_anyway")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: refusal == .noFix ? 18 : 22)
                .fill(Color(red: 40/255, green: 40/255, blue: 42/255).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: refusal == .noFix ? 18 : 22)
                .strokeBorder(amber.opacity(0.35), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        // Naming the container makes SwiftUI fold it into one element, which
        // swallowed «Всё равно начать» — the button was on screen and out of
        // reach of VoiceOver. `.contain` keeps the children addressable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("start_refused_toast")
        .task(id: refusal) {
            // Felt as well as seen: the refusal happens right as the finger
            // leaves the slider, and a buzz lands before the eye moves.
            Haptics.error()
            if refusal == .recoveryPending { viewModel.showRecoveryPrompt = true }
            // The no-fix one carries a button, so it has to outlive a glance.
            try? await Task.sleep(for: .seconds(refusal == .noFix ? 8 : 4))
            viewModel.startRefusal = nil
        }
    }

    /// The map has drawn at least once — dismiss the loader and remember it
    /// past this view's lifetime.
    private func markMapReady() {
        recLog.notice("markMapReady isMapReady=\(isMapReady, privacy: .public)")
        guard !isMapReady else { return }
        viewModel.trackingMapDidRender = true
        withAnimation(.easeOut(duration: 0.4)) { isMapReady = true }
    }

    /// «Поездка не сохранена — слишком короткая», said where the recording
    /// was, and cleared after a few seconds.
    private var junkDiscardedToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text(AppStrings.junkTripDiscarded(lang.language))
                .font(.inter(13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color(red: 40/255, green: 40/255, blue: 42/255).opacity(0.92)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("junk_discarded_toast")
        .task {
            try? await Task.sleep(for: .seconds(5))
            viewModel.discardedJunkTrip = false
        }
    }

    /// Solid accent «Запись на паузе» pill.
    ///
    /// It used to be amber text on a 16%-amber capsule, which is a fill you can
    /// read straight through: street labels and the car marker came through the
    /// pill and shredded the words. A status you must not miss cannot be
    /// translucent over a live map.
    ///
    /// Solid `accent` also ties it to the Resume button, which goes solid
    /// accent in the same state — paused is one colour, top and bottom.
    private var pausedPill: some View {
        HStack(spacing: 7) {
            Image(systemName: "pause.fill")
                .font(.system(size: 12, weight: .bold))
            Text(AppStrings.recordingPausedPill(lang.language))
                .font(.inter(14, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(AppTheme.accent))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
    }

    /// Red toast: sustained weak accuracy (>35м) while recording.
    private var weakSignalToast: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(red: 0xFF/255, green: 0x45/255, blue: 0x3A/255))
                .frame(width: 22, height: 22)
                .overlay(
                    Text("!")
                        .font(.inter(14, weight: .bold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(AppStrings.weakSignalTitle(lang.language))
                    .font(.inter(13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(AppStrings.weakSignalHint(lang.language))
                    .font(.inter(11.5))
                    .foregroundStyle(Color(red: 0xB8/255, green: 0xB8/255, blue: 0xC2/255))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 41/255, green: 20/255, blue: 18/255).opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(red: 0xFF/255, green: 0x45/255, blue: 0x3A/255).opacity(0.35), lineWidth: 1)
        )
    }

    /// Amber banner: GPS fix lost mid-trip (Kalman keeps the track alive).
    private var signalLostBanner: some View {
        let amber = Color(red: 0xF5/255, green: 0xA6/255, blue: 0x23/255)
        return HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(amber)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppStrings.signalLostTitle(lang.language))
                    .font(.inter(13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(AppStrings.signalLostHint(lang.language))
                    .font(.inter(11.5))
                    .foregroundStyle(Color(red: 0xC9/255, green: 0xA8/255, blue: 0x78/255))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 42/255, green: 31/255, blue: 18/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(amber.opacity(0.4), lineWidth: 1)
        )
    }

    /// «0» grey while paused, «–» while the signal is lost, live speed
    /// otherwise (en-dash: a 92pt em-dash reads as a redacted slab).
    private var speedText: String {
        if viewModel.isPaused { return "0" }
        if viewModel.gpsSignalStale { return "–" }
        return "\(Int(viewModel.speed))"
    }

    private var speedDimmed: Bool {
        viewModel.isPaused || viewModel.gpsSignalStale
    }

    /// The speedometer sits directly on the map with nothing behind it, so its
    /// greys follow the MAP's brightness, not the app theme. `AppTheme`'s
    /// adaptive greys answer «is the app in dark mode», which is the wrong
    /// question here — the map goes light at sunrise whatever the app is set
    /// to, and white-at-55% on a daylight map is not a caption, it is a smudge.
    private var mapSecondaryText: Color {
        viewModel.isDarkMap ? .white.opacity(0.55) : .black.opacity(0.45)
    }

    private var mapDimmedText: Color {
        viewModel.isDarkMap ? .white.opacity(0.28) : .black.opacity(0.3)
    }

    /// Figma metrics cell: dimmed 13pt icon ABOVE the value row, centered.
    private func statItem(value: String, unit: String?, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.inter(18, weight: .heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit).textCase(.uppercase)
                        .font(.inter(11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Back Button (idle only)

    private var backButton: some View {
        Button {
            NotificationCenter.default.post(name: .switchToFeedTab, object: nil)
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.4), in: Circle())
        }
        .accessibilityIdentifier("tracking_back")
    }

    // MARK: - Idle Overlay

    private var idleOverlay: some View {
        let _ = recLog.notice("idleOverlay rebuilt")
        return VStack(spacing: 0) {
            // Space for shared top bar. Not hit-testable: it is a spacer over a
            // live map, and as a hit-testable one it ate every drag that began
            // in the top ~110pt of the screen — the map simply would not move
            // there, for no reason a user could see.
            Color.clear
                .frame(height: safeAreaTop + 52)
                .allowsHitTesting(false)

            Spacer()

            // Map controls — right side
            HStack {
                Spacer()
                mapControls
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
            }

            // Refusals appear directly above the control that was refused —
            // the top of the screen is where the GPS toasts live, and it is
            // not where you are looking when you have just pushed a slider at
            // the bottom.
            if let refusal = viewModel.startRefusal {
                refusalToast(refusal)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // A trip below the junk threshold is deleted the moment you stop
            // it. That is the right call — nobody wants a 200 m crawl round
            // the car park in their history — but it used to happen in total
            // silence, and a recording that vanishes without a word reads as
            // lost data, not as tidying up.
            if viewModel.discardedJunkTrip {
                junkDiscardedToast
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            IdleHUDView(
                totalKm: viewModel.cachedTotalKm,
                tripCount: viewModel.cachedTripCount,
                locationDenied: viewModel.locationDenied,
                waitingForFix: !viewModel.hasGPSFix,
                onStartTrip: { viewModel.requestStartRecording() },
                // The toast itself fires the error haptic when it appears.
                onBlockedStart: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.startRefusal = .noFix
                    }
                },
                isTransfer: viewModel.pendingTransfer,
                onSetTransfer: { viewModel.pendingTransfer = $0 },
                onManageGarage: { showGarage = true }
            )
            .padding(.bottom, controlBlockBottomInset)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Map Controls (location on top, then +, then -)

    private var mapControls: some View {
        VStack(spacing: 8) {
            mapButton(icon: trackingIcon, color: trackingIconColor, enabled: true) {
                viewModel.cycleTrackingMode()
            }
            mapButton(icon: "plus", color: nil, enabled: viewModel.canZoomIn) {
                viewModel.zoomIn()
            }
            mapButton(icon: "minus", color: nil, enabled: viewModel.canZoomOut) {
                viewModel.zoomOut()
            }
        }
    }

    @ViewBuilder
    private func mapButton(icon: String, color: Color?, enabled: Bool, action: @escaping () -> Void) -> some View {
        let isDark = viewModel.isDarkMap
        let fg = color ?? (enabled ? (isDark ? .white : AppTheme.textPrimary) : (isDark ? Color.white.opacity(0.3) : AppTheme.textPrimary.opacity(0.3)))

        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(fg)
                .frame(width: 44, height: 44)
                .background {
                    if isDark {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(white: 0.2).opacity(0.85))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.3), lineWidth: 1))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    }
                }
        }
        .disabled(!enabled)
    }

    // MARK: - Helpers

    private var trackingIcon: String {
        switch viewModel.userTrackingMode {
        case .none: return "location"
        case .follow: return "location.fill"
        case .followWithHeading: return "location.north.line.fill"
        @unknown default: return "location"
        }
    }

    private var trackingIconColor: Color {
        viewModel.userTrackingMode == .none ? AppTheme.textPrimary : AppTheme.accent
    }

    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 34
    }

    private var idleHUDInset: CGFloat {
        tabBarHeight + 380
    }
}

// MARK: - Pixel Art Effect

// `PixelateModifier` lived here — a March experiment that wrapped the map in
// two compositing groups and scaled it 1/3 then 3× while recording. The
// transforms cancel out and SwiftUI never rasterises between them, so it drew
// nothing: the recording screenshots show crisp 1px map grid lines and legible
// street labels, which a real 3× downscale could not survive. What it did do
// was force two extra composited full-screen layers on a live, continuously
// redrawing map — and only while recording, which is exactly when the screen
// was reported to stutter.

#Preview {
    TrackingView()
        .environmentObject(MapViewModel())
        .preferredColorScheme(.dark)
}
