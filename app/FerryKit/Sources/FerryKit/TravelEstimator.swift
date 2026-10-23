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

    public func currentLocation(requestAuthorizationIfNeeded: Bool = false) async throws -> CLLocation {
        let status = manager.authorizationStatus
        guard isAuthorized(status) || (status == .notDetermined && requestAuthorizationIfNeeded) else {
            throw CLError(.denied)
        }
        if let loc = manager.location, -loc.timestamp.timeIntervalSinceNow < 120 { return loc }
        continuation?.resume(throwing: CancellationError())
        continuation = nil

        switch status {
        case .authorizedAlways:
            return try await withCheckedThrowingContinuation { cont in
                continuation = cont
                manager.requestLocation()
            }
        #if !os(macOS)
        case .authorizedWhenInUse:
            return try await withCheckedThrowingContinuation { cont in
                continuation = cont
                manager.requestLocation()
            }
        #endif
        case .notDetermined where requestAuthorizationIfNeeded:
            return try await withCheckedThrowingContinuation { cont in
                continuation = cont
                manager.requestWhenInUseAuthorization()
            }
        case .notDetermined, .denied, .restricted:
            throw CLError(.denied)
        @unknown default:
            throw CLError(.locationUnknown)
        }
    }

    private func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        #if os(macOS)
        status == .authorizedAlways
        #else
        status == .authorizedAlways || status == .authorizedWhenInUse
        #endif
    }

    /// Terminal to depart from (respecting a fixed preference) and the travel estimate to reach it.
    public func estimate(preferences: TripPreferences, schedule: Schedule,
                         requestAuthorizationIfNeeded: Bool = false) async throws -> TravelEstimate {
        let location = try await currentLocation(requestAuthorizationIfNeeded: requestAuthorizationIfNeeded)
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
            authorizationDidChange(status)
        }
    }

    private func authorizationDidChange(_ status: CLAuthorizationStatus) {
        if status == .denied || status == .restricted {
            continuation?.resume(throwing: CLError(.denied))
            continuation = nil
        } else if isAuthorized(status), continuation != nil {
            manager.requestLocation()
        }
    }
}
