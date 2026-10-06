import XCTest
import SwiftUI
import MapKit
import CoreData
@testable import TripTrack

/// Mount the real detail screen: setting `showsFog: false` on a standalone
/// RouteMapView in a test would not catch the wrong argument at its call site.
@MainActor
final class TripDetailMapScopeTests: XCTestCase {
    func testOwnTripHeroShowsOnlyTheSelectedRouteWithoutTheAtlasLayer() async throws {
        // Detail also asks the shared reactions service. This integration
        // check is deliberately local, including those incidental requests.
        let host = AppConfig.apiBaseURL.host
        try XCTSkipUnless(host == "127.0.0.1" || host == "localhost",
                          "Run with API_BASE_URL=http://127.0.0.1:1")

        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataTripRepository(persistenceController: persistence)
        let selected = insertTrip(into: persistence, north: 0, seconds: 200)
        _ = insertTrip(into: persistence, north: 2_500, seconds: 0)
        _ = insertTrip(into: persistence, north: -2_500, seconds: 400)
        let selectedID = try XCTUnwrap(selected.id)
        let manager = TripManager(locationManager: LocationManager(),
                                  persistenceController: persistence,
                                  repository: repository)
        let viewModel = TripsViewModel(tripManager: manager)
        viewModel.loadTrips()
        XCTAssertEqual(viewModel.trips.count, 3)

        let detail = TripDetailView(tripId: selectedID, viewModel: viewModel)
            .environmentObject(LanguageManager())
            .environmentObject(MapViewModel())
            .environmentObject(ThemeManager())
        let controller = UIHostingController(rootView: AnyView(NavigationStack { detail }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 440, height: 956)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            // Release the hosted map before another MapKit test starts.
            controller.rootView = AnyView(EmptyView())
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }

        var renderedMap: MKMapView?
        for _ in 0..<100 {
            window.layoutIfNeeded()
            if let map = maps(in: controller.view).first,
               map.overlays.contains(where: { $0 is MKPolyline }) {
                renderedMap = map
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let map = try XCTUnwrap(renderedMap, "The actual trip hero must render its route")
        XCTAssertEqual(maps(in: controller.view).count, 1)
        let coordinator = try XCTUnwrap(map.delegate as? RouteMapView.Coordinator)
        XCTAssertNil(coordinator.veilSeat, "Trip detail must not allocate the history/atlas veil")
        XCTAssertNil(coordinator.fogMetal)
        XCTAssertFalse(coordinator.fogRequested, "Opening one trip must not load cumulative history")
        XCTAssertFalse(map is VeilHostMapView)
        XCTAssertFalse(map.overlays.contains(where: { $0 is FogVeilOverlay }))

        let lines = map.overlays.compactMap { $0 as? MKPolyline }
        XCTAssertFalse(lines.isEmpty)
        let start = TrackTestKit.coordinate(east: 0, north: 0)
        let end = TrackTestKit.coordinate(east: 1_200, north: 0)
        for line in lines {
            for index in 0..<line.pointCount {
                let coordinate = line.points()[index].coordinate
                XCTAssertEqual(coordinate.latitude, start.latitude, accuracy: 0.00001,
                               "A neighbouring trip leaked into this trip's map")
                XCTAssertGreaterThanOrEqual(coordinate.longitude, start.longitude - 0.00001)
                XCTAssertLessThanOrEqual(coordinate.longitude, end.longitude + 0.00001)
            }
        }
        let endpoints = map.annotations.compactMap { $0 as? MKPointAnnotation }
        XCTAssertEqual(endpoints.count, 2, "Only this trip's start and finish belong here")
        XCTAssertTrue(endpoints.contains { abs($0.coordinate.longitude - start.longitude) < 0.00001 })
        XCTAssertTrue(endpoints.contains { abs($0.coordinate.longitude - end.longitude) < 0.00001 })
    }

    private func insertTrip(into persistence: PersistenceController,
                            north: Double, seconds: Double) -> TripEntity {
        let specs = (0...12).map { index in
            TrackTestKit.PointSpec(east: Double(index) * 100, north: north,
                                   seconds: seconds + Double(index) * 10, speed: 10)
        }
        let entity = TrackTestKit.insertTrip(into: persistence, points: specs)
        entity.distance = 1_200
        entity.isPrivate = true
        entity.previewPolyline = Trip.encodePolyline(specs.map {
            TrackTestKit.coordinate(east: $0.east, north: $0.north)
        })
        try? persistence.container.viewContext.save()
        return entity
    }

    private func maps(in view: UIView) -> [MKMapView] {
        if let map = view as? MKMapView { return [map] }
        return view.subviews.flatMap { maps(in: $0) }
    }
}
