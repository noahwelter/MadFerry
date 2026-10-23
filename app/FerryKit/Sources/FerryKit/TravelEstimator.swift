import CoreLocation
import Foundation
import MapKit

/// Computes on-device travel time from the current location to the departure terminal.
@MainActor
public final class TravelEstimator: NSObject, CLLocationManagerDelegate {
    public static let shared = TravelEstimator()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    public var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    public func requestAuthorization() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    public func currentLocation() async throws -> CLLocation {
        if let loc = manager.location, -loc.timestamp.timeIntervalSinceNow < 120 { return loc }
        requestAuthorization()
        continuation?.resume(throwing: CancellationError())
        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            manager.requestLocation()
        }
    }

    /// Terminal to depart from (respecting a fixed preference) and the travel estimate to reach it.
    public func estimate(preferences: TripPreferences, schedule: Schedule) async throws -> TravelEstimate {
        let location = try await currentLocation()
        let terminalID = preferences.fixedTerminal ?? Geography.departureTerminal(
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        guard let terminal = schedule.terminal(terminalID) else { throw URLError(.resourceUnavailable) }
        let destination = CLLocation(latitude: terminal.latitude, longitude: terminal.longitude)

        var seconds: TimeInterval
        if location.distance(from: destination) < 250 {
            seconds = 0
        } else {
            let request = MKDirections.Request()
            request.source = MKMapItem(location: location, address: nil)
            request.destination = MKMapItem(location: destination, address: nil)
            request.transportType = preferences.travelMode == .driving ? .automobile : .walking
            seconds = try await MKDirections(request: request).calculateETA().expectedTravelTime
        }
        let estimate = TravelEstimate(terminal: terminalID, seconds: seconds, computedAt: .now,
                                      mode: preferences.travelMode)
        estimate.save()
        return estimate
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            continuation?.resume(returning: loc)
            continuation = nil
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .denied || status == .restricted {
                continuation?.resume(throwing: CLError(.denied))
                continuation = nil
            }
        }
    }
}
