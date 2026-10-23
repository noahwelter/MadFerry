import Foundation

public enum FerryConfig {
    public static let appGroup = "group.com.noahwelter.madferry"
    public static let feedBaseURL = URL(string: "https://noahwelter.github.io/MadFerry/v1/")!
    public static let officialScheduleURL = URL(string: "https://madferry.com/ferry-schedule")!
    public static let alertsURL = URL(string: "https://madferry.com/weather-alerts")!
    public static let windsledURL = URL(string: "https://madferry.com/ice-road-windsled-information")!
    public static let ferryPhone = "715-747-2051"

    public static var sharedDefaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    public static var sharedContainer: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return url
        }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }
}

/// Fetches the coordinator's static JSON and caches it in the App Group so widgets and
/// extensions can read the same data offline.
public actor FeedClient {
    public static let shared = FeedClient()

    private let baseURL: URL
    private let directory: URL
    private let session: URLSession

    public init(baseURL: URL = FerryConfig.feedBaseURL, directory: URL? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.directory = (directory ?? FerryConfig.sharedContainer).appending(path: "Feed", directoryHint: .isDirectory)
        self.session = session
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public struct Snapshot: Sendable {
        public let schedule: Schedule
        public let live: LiveFeed?
        public let scheduleLastChecked: Date?
        public let liveLastChecked: Date?
        public var lastChecked: Date? {
            guard let scheduleLastChecked, let liveLastChecked else { return nil }
            return min(scheduleLastChecked, liveLastChecked)
        }

        public var engine: ScheduleEngine { ScheduleEngine(schedule: schedule, status: live?.status) }

        public init(schedule: Schedule, live: LiveFeed?, scheduleLastChecked: Date?, liveLastChecked: Date?) {
            self.schedule = schedule
            self.live = live
            self.scheduleLastChecked = scheduleLastChecked
            self.liveLastChecked = liveLastChecked
        }
    }

    /// Cached data, falling back to the schedule bundled with the app.
    public func cached() -> Snapshot {
        let schedule: Schedule = load("schedule.json") ?? Self.bundledSchedule
        return Snapshot(schedule: schedule, live: load("live.json"),
                        scheduleLastChecked: checkedAt("schedule.json"),
                        liveLastChecked: checkedAt("live.json"))
    }

    @discardableResult
    public func refresh() async throws -> Snapshot {
        async let s: Void = fetch("schedule.json", as: Schedule.self)
        async let l: Void = fetch("live.json", as: LiveFeed.self)
        _ = try await (s, l)
        return cached()
    }

    public static let bundledSchedule: Schedule = {
        let url = Bundle.module.url(forResource: "BundledSchedule", withExtension: "json")!
        return try! JSONDecoder.ferry.decode(Schedule.self, from: Data(contentsOf: url))
    }()

    private func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appending(path: name)) else { return nil }
        return try? JSONDecoder.ferry.decode(T.self, from: data)
    }

    private func checkedAt(_ name: String) -> Date? {
        (try? directory.appending(path: name).resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
    }

    private func fetch<T: Decodable>(_ name: String, as: T.Type) async throws {
        let file = directory.appending(path: name)
        let etagFile = directory.appending(path: name + ".etag")
        var request = URLRequest(url: baseURL.appending(path: name))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if FileManager.default.fileExists(atPath: file.path()),
           let etag = try? String(contentsOf: etagFile, encoding: .utf8) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 304 {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path())
            return
        }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        _ = try JSONDecoder.ferry.decode(T.self, from: data) // never cache data we can't read
        try data.write(to: file, options: .atomic)
        if let etag = http.value(forHTTPHeaderField: "ETag") {
            try? etag.write(to: etagFile, atomically: true, encoding: .utf8)
        }
    }
}
