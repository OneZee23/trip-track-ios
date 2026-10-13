import XCTest
import Combine
import MapKit
@testable import TripTrack

/// Delegate events are supplied explicitly: no network tiles, MapKit timing,
/// or prior simulator cache may decide whether the route is revealed.
@MainActor
final class TripMapRenderingReadinessTests: XCTestCase {
    private var host: TripMapHost!
    private var coordinator: RouteMapView.Coordinator!
    private var map: MKMapView!
    private var window: UIWindow!
    private var container: UIView!
    private weak var previousKeyWindow: UIWindow?

    override func setUpWithError() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 440, height: 956)
        let controller = UIViewController()
        window.rootViewController = controller
        container = UIView(frame: CGRect(x: 0, y: 80, width: 440, height: 380))
        controller.view.addSubview(container)
        host = TripMapHost()
        coordinator = host.coordinator(orMake: {
            RouteMapView.Coordinator(showsFog: false, rotatable: false)
        })
        coordinator.host = host
        let center = MKMapPoint(CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975))
        coordinator.overviewRect = MKMapRect(x: center.x - 12_000, y: center.y - 4_000,
                                             width: 24_000, height: 8_000)
        map = host.map(orMake: { MKMapView(frame: container.bounds) })
        // Fitting can start real MapKit work. Its automatic callbacks must
        // never participate in these controlled event-order assertions.
        map.delegate = nil
        container.addSubview(map)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        XCTAssertNotNil(map.window)
        XCTAssertEqual(map.bounds.size, container.bounds.size)
    }

    override func tearDownWithError() throws {
        map?.delegate = nil
        host?.tearDown()
        window?.isHidden = true
        window?.rootViewController = nil
        previousKeyWindow?.makeKey()
        coordinator = nil
        map = nil
        container = nil
        window = nil
        host = nil
    }

    func testRenderingCompletedBeforeTheRouteWasFittedCannotRevealItsNewViewport() async {
        await assertNoReveal {
            coordinator.mapViewDidFinishRenderingMap(map, fullyRendered: true)
            fitRoute()
        }
    }

    func testPartiallyRenderedFittedViewportKeepsTheRoutePreview() async {
        fitRoute()
        await assertNoReveal {
            coordinator.mapViewDidFinishRenderingMap(map, fullyRendered: false)
        }
    }

    func testCachedFittedViewportCanRevealWithoutAWillStartCallback() async {
        fitRoute()
        await finishCurrentRender()
        XCTAssertTrue(host.hasRenderedRoute)
    }

    func testRepeatedFitToTheSameViewportCanCompleteWithoutANewRenderingCycle() async {
        fitRoute()
        fitRoute()
        await finishCurrentRender()
        XCTAssertTrue(host.hasRenderedRoute)
    }

    func testForeignMapCallbackCannotRevealTheOwnedMap() async {
        fitRoute()
        let foreignMap = MKMapView(frame: container.bounds)
        foreignMap.delegate = nil
        container.addSubview(foreignMap)
        defer { foreignMap.removeFromSuperview() }
        foreignMap.setVisibleMapRect(map.visibleMapRect, animated: false)
        await assertNoReveal {
            coordinator.mapViewDidFinishRenderingMap(foreignMap, fullyRendered: true)
        }
    }

    func testViewportChangedBeforeDeferredPublicationDoesNotRevealOldTiles() async {
        fitRoute()
        await assertNoReveal {
            coordinator.mapViewDidFinishRenderingMap(map, fullyRendered: true)
            map.setCenter(CLLocationCoordinate2D(latitude: 55.75, longitude: 37.62), animated: false)
        }
    }

    func testRepeatedFitInvalidatesDeferredPublicationEvenWhenTheViewportIsUnchanged() async {
        fitRoute()
        let viewport = map.visibleMapRect
        await assertNoReveal {
            coordinator.mapViewDidFinishRenderingMap(map, fullyRendered: true)
            fitRoute()
            XCTAssertEqual(map.visibleMapRect.origin.x, viewport.origin.x, accuracy: 0.001)
            XCTAssertEqual(map.visibleMapRect.origin.y, viewport.origin.y, accuracy: 0.001)
            XCTAssertEqual(map.visibleMapRect.size.width, viewport.size.width, accuracy: 0.001)
            XCTAssertEqual(map.visibleMapRect.size.height, viewport.size.height, accuracy: 0.001)
        }
    }

    func testQueuedCompletionCannotRevealAReplacementAfterTheHostWasDestroyed() async {
        fitRoute()
        await assertNoReveal {
            coordinator.mapViewDidFinishRenderingMap(map, fullyRendered: true)
            host.tearDown()
            // Keep the obsolete map in a real window: rejecting it must be
            // about ownership, not merely its removal from the hierarchy.
            container.addSubview(map)
            let replacement = host.map(orMake: { MKMapView(frame: container.bounds) })
            replacement.delegate = nil
            container.addSubview(replacement)
            XCTAssertFalse(replacement === map)
        }
        XCTAssertFalse(host.hasRenderedRoute)
        XCTAssertEqual(host.creationCount, 2)
    }

    func testReadyRouteStaysReadyAcrossFullscreenAndHeroTransfer() async {
        fitRoute()
        await finishCurrentRender()
        host.retain()
        host.activePresentation = .fullscreen
        let fullscreenMap = host.map(orMake: { XCTFail("The shared map was rebuilt"); return MKMapView() })
        host.retain()
        host.release()
        XCTAssertTrue(fullscreenMap === map)
        XCTAssertTrue(host.hasRenderedRoute)

        // A later unfinished render while moving the same map must not
        // bring back the opening placeholder over a previously ready map.
        coordinator.mapViewDidFinishRenderingMap(map, fullyRendered: false)
        host.activePresentation = .hero
        let returnedMap = host.map(orMake: { XCTFail("The returning map was rebuilt"); return MKMapView() })
        XCTAssertTrue(returnedMap === map)
        XCTAssertTrue(host.hasRenderedRoute)
        XCTAssertEqual(host.creationCount, 1)
    }

    private func fitRoute() {
        coordinator.mapResized(map, refits: true,
                               insets: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24))
    }

    private func finishCurrentRender(file: StaticString = #filePath, line: UInt = #line) async {
        let rendered = expectation(description: "A completed fitted viewport becomes visible")
        let observation = host.$hasRenderedRoute.filter { $0 }.prefix(1).sink { _ in rendered.fulfill() }
        defer { observation.cancel() }
        // Cached tiles need not announce another "will start" after a
        // same-viewport fit. The completed fitted frame is sufficient.
        coordinator.mapViewDidFinishRenderingMap(map, fullyRendered: true)
        XCTAssertFalse(host.hasRenderedRoute,
                       "Publishing inside MapKit's delegate can mutate a representable update",
                       file: file, line: line)
        await fulfillment(of: [rendered], timeout: 2)
    }

    private func assertNoReveal(_ events: () -> Void,
                                file: StaticString = #filePath, line: UInt = #line) async {
        let revealed = expectation(description: "An unrelated or unfinished viewport stays hidden")
        revealed.isInverted = true
        let observation = host.$hasRenderedRoute.filter { $0 }.prefix(1).sink { _ in revealed.fulfill() }
        defer { observation.cancel() }
        events()
        await fulfillment(of: [revealed], timeout: 0.1)
        XCTAssertFalse(host.hasRenderedRoute, file: file, line: line)
    }
}
