import AVFoundation
import XCTest
@testable import TripTrack

/// Route reads leave the main thread and their answers come back in order.
/// Sentry APPLE-IOS-18 (0.9.3, 5 Nov 2026): the main thread waited 2 s in
/// `AVAudioSession.currentRoute` under `handleRouteChange`.
///
/// Each detector gets its own notification center, so the simulator's real
/// route changes never reach it, and a scripted reader stands in for the
/// audio server.
final class AudioRouteDetectorQueueTests: XCTestCase {
    private var center: NotificationCenter?
    private var detector: AudioRouteDetector?
    private var events: [String] = []

    override func tearDown() {
        detector?.stopMonitoring()
        detector = nil
        center = nil
        events = []
        super.tearDown()
    }

    /// `answers` are handed out in order, one per route read, each after its
    /// own delay; `nil` is «no stereo».
    private func makeDetector(answers: [(String?, TimeInterval)]) -> (AudioRouteDetector, ReadLog) {
        let center = NotificationCenter()
        let log = ReadLog(answers: answers)
        let detector = AudioRouteDetector(center: center, readOutput: {
            let (answer, delay) = log.next(onMain: Thread.isMainThread)
            Thread.sleep(forTimeInterval: delay)
            return answer
        }, isSaved: { _ in true })
        detector.onDeviceEvent = { [weak self] event in
            XCTAssertTrue(Thread.isMainThread)
            switch event {
            case .connected(let name): self?.events.append("connected:\(name)")
            case .disconnected(let name): self?.events.append("disconnected:\(name)")
            }
        }
        self.center = center
        self.detector = detector
        return (detector, log)
    }

    private func postRouteChange(_ reason: AVAudioSession.RouteChangeReason) {
        center?.post(name: AVAudioSession.routeChangeNotification, object: nil,
                     userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue])
    }

    /// Waits until every queued read has run and its answer has landed on main.
    private func drain() {
        AudioRouteDetector.sessionQueue.sync {}
        let drained = expectation(description: "main drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
    }

    func testASlowRouteReadDoesNotHoldTheMainThread() {
        let (detector, log) = makeDetector(answers: [("Car stereo", 0.5), ("Car stereo", 0.5)])

        let started = Date()
        detector.startMonitoring()
        postRouteChange(.categoryChange)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.2, "start and the route change waited for the reads")

        drain()
        XCTAssertEqual(log.reads, 2)
        XCTAssertEqual(log.readsOnMain, 0)
        XCTAssertEqual(events, ["connected:Car stereo"], "the second answer is the same stereo")
    }

    func testAnswersArriveInTheOrderTheRouteChanged() {
        // Start finds nothing, then the stereo connects with a slow answer and
        // a second output takes over with a fast one. Out of order, the second
        // would land first and the stereo would read as the current output.
        let (detector, _) = makeDetector(answers: [(nil, 0), ("Car stereo", 0.4), ("Hands-free", 0)])

        detector.startMonitoring()
        postRouteChange(.newDeviceAvailable)
        postRouteChange(.routeConfigurationChange)

        drain()
        XCTAssertEqual(events, ["connected:Car stereo", "connected:Hands-free"])
    }

    /// The owner's drive, 7 Nov 2026, 17:41:29: Yandex Maps activated
    /// PlayAndRecord without Bluetooth, the speaker became the output, and
    /// the category change read as the stereo leaving. In auto mode that ended
    /// the trip on the spot, with the car still running and paired.
    func testAnotherAppTakingTheOutputIsNotADisconnect() {
        let (detector, _) = makeDetector(answers: [("Car stereo", 0), (nil, 0)])

        detector.startMonitoring()
        postRouteChange(.categoryChange)

        drain()
        XCTAssertEqual(events, ["connected:Car stereo"], "a moved output ended the trip")
    }

    /// Forgotten quietly, the stereo coming back is a connect: it keeps a
    /// recording going and starts one when nothing records.
    func testTheStereoComingBackAfterAnotherAppReadsAsAConnect() {
        let (detector, _) = makeDetector(answers: [("Car stereo", 0), (nil, 0), ("Car stereo", 0)])

        detector.startMonitoring()
        postRouteChange(.override)
        postRouteChange(.categoryChange)

        drain()
        XCTAssertEqual(events, ["connected:Car stereo", "connected:Car stereo"])
    }

    func testStoppingDropsAnswersStillOnTheWay() {
        let (detector, log) = makeDetector(answers: [("Car stereo", 0.3), ("Car stereo", 0.3)])

        detector.startMonitoring()
        postRouteChange(.categoryChange)
        detector.stopMonitoring()

        drain()
        XCTAssertEqual(log.reads, 2)
        XCTAssertEqual(events, [], "a stopped detector reported a stereo")
    }

    func testARestartIgnoresAnswersFromTheSessionBefore() {
        // The first session's read is slow and finds the stereo. By the time it
        // lands, monitoring was stopped and started again, and the new session
        // sees no stereo.
        let (detector, log) = makeDetector(answers: [("Car stereo", 0.4), (nil, 0)])

        detector.startMonitoring()
        detector.stopMonitoring()
        detector.startMonitoring()

        drain()
        XCTAssertEqual(log.reads, 2)
        XCTAssertEqual(events, [], "an answer from the stopped session reached the new one")
    }

    @MainActor
    func testAScreenReadsTheStereoOffTheMainThread() async {
        let log = ReadLog(answers: [])
        let output = await AudioRouteDetector.stereoOutput {
            _ = log.next(onMain: Thread.isMainThread)
            Thread.sleep(forTimeInterval: 0.3)
            return .init(name: "Car stereo", isCarPlay: true)
        }
        XCTAssertEqual(output, .init(name: "Car stereo", isCarPlay: true))
        XCTAssertEqual(log.reads, 1)
        XCTAssertEqual(log.readsOnMain, 0)
    }
}

/// The scripted audio server. Reads happen on `sessionQueue`, the test reads
/// the counters on main, hence the lock.
private final class ReadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [(String?, TimeInterval)]
    private var count = 0
    private var onMainCount = 0

    init(answers: [(String?, TimeInterval)]) { self.answers = answers }

    func next(onMain: Bool) -> (String?, TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        count += 1
        if onMain { onMainCount += 1 }
        return answers.isEmpty ? (nil, 0) : answers.removeFirst()
    }

    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }
    var readsOnMain: Int { lock.lock(); defer { lock.unlock() }; return onMainCount }
}
