import CoreLocation
import Foundation
import MapKit
import UIKit
import UserNotifications

enum TravelMode: String, CaseIterable, Identifiable {
    case walk, run, cycle, drive, realisticDrive, flight, ship, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return String(localized: "Walk")
        case .run: return String(localized: "Run")
        case .cycle: return String(localized: "Cycle")
        case .drive: return String(localized: "Drive")
        case .realisticDrive: return String(localized: "Traffic drive")
        case .flight: return String(localized: "Airplane")
        case .ship: return String(localized: "Ship")
        case .custom: return String(localized: "Custom")
        }
    }

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .cycle: return "bicycle"
        case .drive: return "car.fill"
        case .realisticDrive: return "car.side.fill"
        case .flight: return "airplane"
        case .ship: return "ferry.fill"
        case .custom: return "speedometer"
        }
    }

    /// Base meters per second before natural variation.
    var baseSpeed: CLLocationSpeed {
        switch self {
        case .walk: return 1.4
        case .run: return 3.3
        case .cycle: return 6.5
        case .drive, .realisticDrive: return 13.4
        case .flight: return 235.0  // 846 km/h cruise; profile handles departure and arrival
        case .ship: return 9.0     // 32.4 km/h cruise; profile handles ports
        case .custom: return 5.0 / 3.6
        }
    }

    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .walk, .run, .custom, .flight, .ship: return .walking
        case .cycle, .drive, .realisticDrive: return .automobile
        }
    }
}

enum SpoofStatus: Equatable {
    case idle
    case connecting
    case active
    case reconnecting
    case dropped(String)

    var label: String {
        switch self {
        case .idle: return String(localized: "Not Spoofing")
        case .connecting: return String(localized: "Starting…")
        case .active: return String(localized: "Spoofing")
        case .reconnecting: return String(localized: "Reconnecting…")
        case .dropped: return String(localized: "Interrupted")
        }
    }

    var isDropped: Bool {
        if case .dropped = self { return true }
        return false
    }
}

@MainActor
final class SpoofSession: ObservableObject {
    @Published var status: SpoofStatus = .idle
    @Published var pin: CLLocationCoordinate2D?
    @Published var simulated: CLLocationCoordinate2D?
    @Published var travelMode: TravelMode = .walk {
        didSet {
            UserDefaults.standard.set(travelMode.rawValue, forKey: "locus.travelMode")
            travelDynamics.reset(route: routeSimulation.path)
        }
    }
    @Published var motionSettings = MotionSettings.load() {
        didSet { motionSettings.save() }
    }
    /// Unperturbed source for movement, history, and route starts.
    private(set) var idealCoordinate: CLLocationCoordinate2D?

    var baseSpeed: Double {
        travelMode == .custom ? motionSettings.normalized.customSpeedKPH / 3.6 : travelMode.baseSpeed
    }

    var roadTransportType: MKDirectionsTransportType {
        travelMode == .custom ? (motionSettings.customRoadDriving ? .automobile : .walking) : travelMode.mkTransportType
    }
    @Published var mapStyleIndex: Int = 0
    @Published var lastError: String?
    @Published var isBusy = false
    @Published var joystickActive = false

    // Observed aircraft follow (free ADS-B feed). These are reported measurements,
    // not GPS altitude/speed injected into other applications.
    @Published private(set) var liveFlightHex: String?
    @Published private(set) var liveFlightAircraft: ObservedAircraft?
    @Published private(set) var liveFlightStatus = ""
    private var liveFlightTask: Task<Void, Never>?
    private var liveFrom: MotionPoint?
    private var liveTo: MotionPoint?
    private var liveBlendStarted: TimeInterval = 0

    @Published var favorites: [SavedPlace] = []
    @Published var recents: [SavedPlace] = []

    private var connectionTask: Task<Void, Never>?
    private var connectionRequestID = UUID()
    private var resendTimer: Timer?
    private var healthTimer: Timer?
    private var motionTimer: Timer?
    @Published private(set) var routeSimulation = RouteSimulation()
    @Published private(set) var activeAirportJourney: AirportGeneratedPlan?
    private var variation = MotionVariation()
    private var travelDynamics = TravelDynamics()
    private var driftOffset = (east: 0.0, north: 0.0)
    private var lastMotionTime = ProcessInfo.processInfo.systemUptime
    private var generation = UUID()
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var joystickVector: CGVector = .zero
    private let locationKeeper = BackgroundKeepAlive()

    private let favoritesKey = "locus.favorites"
    private let recentsKey = "locus.recents"

    init() {
        favorites = SavedPlace.load(key: favoritesKey)
        recents = SavedPlace.load(key: recentsKey)
        travelMode = TravelMode(rawValue: UserDefaults.standard.string(forKey: "locus.travelMode") ?? "") ?? .walk
    }

    var isSpoofing: Bool {
        if case .active = status { return true }
        if case .reconnecting = status { return true }
        return false
    }

    func teleport(to coordinate: CLLocationCoordinate2D, pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = String(localized: "Import an RPPairing file in Settings first.")
            return
        }
        cancelMovement()
        variation = MotionVariation()
        driftOffset = (0, 0)
        startAfterResolving { [self] in apply(coordinate, pairing: pairing, markRecent: true) }
    }

    func stop(pairing: PairingStore) {
        cancelMovement()
        motionTimer?.invalidate()
        motionTimer = nil
        generation = UUID()
        variation = MotionVariation()
        driftOffset = (0, 0)
        stopResend()
        stopHealth()
        if !LocationEngine.isSessionActive && simulated == nil {
            status = .idle
            endBackground()
            return
        }
        isBusy = true
        let result = LocationEngine.clear()
        isBusy = false
        switch result {
        case .success:
            simulated = nil
            idealCoordinate = nil
            status = .idle
            endBackground()
            // Keep location updates running so the map puck / locate button
            // can return to the real GPS fix (not the leftover pin).
            locationKeeper.start()
        case .failure(let error):
            lastError = error.localizedDescription
            status = .dropped(error.localizedDescription)
            postDropNotification(error.localizedDescription)
            endBackground()
        }
    }

    /// Best-known real device coordinate (not the teleport pin).
    var realCoordinate: CLLocationCoordinate2D? {
        locationKeeper.lastKnownCoordinate
    }

    /// Start lightweight GPS updates for the map puck / locate button.
    func startLocationUpdates() {
        locationKeeper.start()
    }

    func startJoystick(pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = String(localized: "Import an RPPairing file in Settings first.")
            return
        }
        let start = idealCoordinate ?? pin ?? locationKeeper.lastKnownCoordinate
        guard let start else {
            lastError = String(localized: "Drop a pin or teleport somewhere before using the joystick.")
            return
        }
        cancelMovement()
        startAfterResolving { [self] in
            if simulated == nil || status != .active { apply(start, pairing: pairing, markRecent: false) }
            guard status == .active else { return }
            joystickActive = true
            lastMotionTime = ProcessInfo.processInfo.systemUptime
        }
    }

    func updateJoystick(vector: CGVector) {
        joystickVector = vector
    }

    func stopJoystick() {
        joystickActive = false
        joystickVector = .zero
    }

    private func cancelMovement() {
        stopFreeLiveFlight()
        cancelConnectionAttempt()
        routeSimulation.clear()
        travelDynamics.reset()
        activeAirportJourney = nil
        stopJoystick()
    }

    func followRoute(_ coordinates: [CLLocationCoordinate2D], pairing: PairingStore,
                     airportPlan: AirportGeneratedPlan? = nil) {
        guard pairing.hasPairingFile else {
            lastError = String(localized: "Import an RPPairing file in Settings first.")
            return
        }
        var next = RouteSimulation()
        guard next.start(points: coordinates.map(MotionPoint.init)) else { return }
        cancelMovement()
        activeAirportJourney = airportPlan
        startAfterResolving { [self] in
            apply(coordinates[0], pairing: pairing, markRecent: true)
            guard status == .active else { return }
            routeSimulation = next
            travelDynamics.reset(route: next.path)
            if let airportPlan { travelDynamics.configureAirport(airportPlan.stages) }
            lastMotionTime = ProcessInfo.processInfo.systemUptime
        }
    }

    /// Start following one observed aircraft. Explicitly replaces any running route;
    /// follow reports can lag by around 3 minutes to respect the free daily quota.
    func startFreeLiveFlight(_ first: ObservedAircraft, pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = String(localized: "Import an RPPairing file in Settings first.")
            return
        }
        cancelMovement()
        travelMode = .flight
        startAfterResolving { [self] in
            apply(first.coordinate, pairing: pairing, markRecent: true)
            guard status == .active else { return }
            liveFlightHex = first.hex
            liveFlightAircraft = first
            liveFlightStatus = "Connected; following observed ADS-B fixes (3-minute polling)."
            liveFrom = MotionPoint(first.coordinate)
            liveTo = MotionPoint(first.coordinate)
            liveBlendStarted = ProcessInfo.processInfo.systemUptime
            liveFlightTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.liveFlightHex == first.hex else { break }
                    do {
                        let reported = try await FreeFlightFeeds.byHex(first.hex)
                        guard !Task.isCancelled, self.liveFlightHex == first.hex else { break }
                        // Blend the previous simulated GPS point toward the new observation.
                        // This avoids instant long-range teleports but is NOT exact live position.
                        if let current = self.idealCoordinate {
                            self.liveFrom = MotionPoint(current)
                            self.liveTo = MotionPoint(reported.coordinate)
                            self.liveBlendStarted = ProcessInfo.processInfo.systemUptime
                        }
                        self.liveFlightAircraft = reported
                        self.liveFlightStatus = "Observed position refreshed; \(Int(reported.ageSeconds))s old. Smooth delayed follow active."
                    } catch {
                        guard !Task.isCancelled else { break }
                        self.liveFlightStatus = "Live feed unavailable: \(error.localizedDescription). Last reported location held."
                    }
                    // 180s polling keeps continuous tracking to at most 480 requests/day,
                    // leaving a small fraction of the 500/day no-key quota for discovery.
                    try? await Task.sleep(nanoseconds: 180_000_000_000)
                }
            }
        }
    }

    /// Stop following the aircraft; the last simulated coordinate is retained.
    /// The normal End spoofing control restores physical GPS.
    func stopFreeLiveFlight() {
        liveFlightTask?.cancel()
        liveFlightTask = nil
        liveFlightHex = nil
        liveFlightAircraft = nil
        liveFlightStatus = ""
        liveFrom = nil
        liveTo = nil
    }

    var travelStatusDescription: String {
        if let label = travelDynamics.airportStageLabel { return label }
        return travelDynamics.status(mode: travelMode,
                              travelled: routeSimulation.travelledDistance,
                              total: routeSimulation.totalDistance)
    }

    /// For display only: Apple's developer-location service used here injects
    /// coordinates, not actual speed/altitude sensor readings into Snapchat.
    var estimatedFlightAltitude: Double { travelDynamics.estimatedFlightAltitude }

    private func cancelConnectionAttempt() {
        connectionRequestID = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        isBusy = false
    }

    private func startAfterResolving(_ operation: @escaping @MainActor () -> Void) {
        cancelConnectionAttempt()
        if LocationEngine.isSessionActive { operation(); return }
        let request = connectionRequestID
        isBusy = true
        if status != .reconnecting { status = .connecting }
        connectionTask = Task { [weak self] in
            await DeveloperTunnelMonitor.shared.resolveBeforeConnecting()
            guard let self, !Task.isCancelled, self.connectionRequestID == request else { return }
            self.connectionTask = nil
            self.isBusy = false
            DeveloperTunnelMonitor.shared.prepareForSimulation()
            operation()
        }
    }

    func pauseRoute() {
        guard status == .active else { return }
        routeSimulation.pause()
        lastMotionTime = ProcessInfo.processInfo.systemUptime
    }

    func resumeRoute() {
        guard status == .active else { return }
        // Exclude the entire paused interval from the next movement tick.
        lastMotionTime = ProcessInfo.processInfo.systemUptime
        routeSimulation.resume()
    }

    func stopRoute() {
        routeSimulation.stop()
        lastMotionTime = ProcessInfo.processInfo.systemUptime
        // Keep the simulation, resend timer, health checks, and current ideal center.
    }

    private func interruptMovement() {
        cancelConnectionAttempt()
        routeSimulation.stop()
        stopJoystick()
    }

    func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        // Don't let a generic star overwrite a named favorite for the same spot.
        if let existing = favorites.first(where: { $0.id == place.id }),
           Self.isGenericFavoriteName(place.name),
           !Self.isGenericFavoriteName(existing.name) {
            return
        }
        favorites.removeAll { $0.id == place.id }
        favorites.insert(place, at: 0)
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func renameFavorite(_ place: SavedPlace, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        favorites[index].name = trimmed
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeFavorite(_ place: SavedPlace) {
        favorites.removeAll { $0.id == place.id }
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeRecent(_ place: SavedPlace) {
        recents.removeAll { $0.id == place.id }
        SavedPlace.save(recents, key: recentsKey)
    }

    /// Best display name for starring the current pin (search title, matching recent, etc.).
    func suggestedFavoriteName(for coordinate: CLLocationCoordinate2D, fallback: String? = nil) -> String {
        if let fallback, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let favorite = favorites.first(where: { $0.id == SavedPlace(name: "", latitude: coordinate.latitude, longitude: coordinate.longitude).id }),
           !Self.isGenericFavoriteName(favorite.name) {
            return favorite.name
        }
        if let recent = recents.first(where: {
            abs($0.latitude - coordinate.latitude) < 0.00015 && abs($0.longitude - coordinate.longitude) < 0.00015
        }), !Self.isGenericFavoriteName(recent.name) {
            return recent.name
        }
        return Self.coordinateLabel(coordinate)
    }

    private static func coordinateLabel(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private static func isGenericFavoriteName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Favorite" { return true }
        // Coordinate-looking labels from older teleports.
        let parts = trimmed.split(separator: ",")
        if parts.count == 2,
           Double(parts[0].trimmingCharacters(in: .whitespaces)) != nil,
           Double(parts[1].trimmingCharacters(in: .whitespaces)) != nil {
            return true
        }
        return false
    }

    private func apply(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore, markRecent: Bool) {
        if status == .idle || status.isDropped {
            status = .connecting
        }
        let output = MotionPoint(coordinate).offset(east: driftOffset.east, north: driftOffset.north).coordinate
        DeveloperTunnelMonitor.shared.prepareForSimulation()
        isBusy = true
        let result = LocationEngine.set(
            latitude: output.latitude,
            longitude: output.longitude,
            pairingPath: pairing.pairingPath,
            deviceIP: TunnelConfig.targetIP
        )
        isBusy = false
        switch result {
        case .success:
            simulated = output
            idealCoordinate = coordinate
            pin = coordinate
            status = .active
            lastError = nil
            beginBackground()
            locationKeeper.start()
            startResend(pairing: pairing)
            startHealth(pairing: pairing)
            startMotion(pairing: pairing)
            if markRecent {
                pushRecent(coordinate)
            }
        case .failure(let error):
            interruptMovement()
            lastError = error.localizedDescription
            if simulated != nil {
                status = .dropped(error.localizedDescription)
                postDropNotification(error.localizedDescription)
            } else {
                status = .idle
            }
        }
    }

    private func startMotion(pairing: PairingStore) {
        guard motionTimer == nil else { return }
        lastMotionTime = ProcessInfo.processInfo.systemUptime
        let token = generation
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.tickMotion(pairing: pairing)
            }
        }
        motionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tickMotion(pairing: PairingStore) {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = max(0, now - lastMotionTime)
        lastMotionTime = now
        guard status == .active, let ideal = idealCoordinate else { return }
        let noise = variation.update(seconds: dt, settings: motionSettings)
        let oldOffset = driftOffset
        driftOffset = (noise.east, noise.north)
        var next = MotionPoint(ideal)
        var moved = false
        var advancedRoute: RouteSimulation?
        if liveFlightHex != nil, let from = liveFrom, let target = liveTo {
            // Follow historical ADS-B fixes smoothly with deliberate latency.
            let fraction = min(1, max(0, (now - liveBlendStarted) / 180))
            let desired = from.interpolated(to: target, fraction: fraction)
            let separation = next.distance(to: desired)
            // On an iOS foreground resume, don't jump across the entire missed interval.
            if separation > 0.35 {
                let maxStep = max(0, min(1, dt)) * 300
                next = next.interpolated(to: desired,
                    fraction: min(1, maxStep / separation))
                moved = true
            }
        } else if routeSimulation.phase == .running {
            var candidate = routeSimulation
            let distance = travelDynamics.advanceDistance(
                mode: travelMode,
                baseSpeed: baseSpeed,
                seconds: dt,
                travelled: candidate.travelledDistance,
                total: candidate.totalDistance,
                variation: noise.multiplier
            )
            candidate.advance(meters: distance)
            next = candidate.position ?? next
            advancedRoute = candidate
            moved = true
        } else if joystickActive {
            let magnitude = hypot(joystickVector.dx, joystickVector.dy)
            if magnitude > 0.08 {
                let meters = baseSpeed * noise.multiplier * min(1, magnitude) * dt
                next = next.offset(east: joystickVector.dx / magnitude * meters,
                                   north: -joystickVector.dy / magnitude * meters)
                moved = true
            }
        }
        if moved || driftOffset.east != oldOffset.east || driftOffset.north != oldOffset.north {
            // Idle drift must not move a pin the user is placing elsewhere on the map.
            let selectedPin = pin
            apply(next.coordinate, pairing: pairing, markRecent: false)
            if status == .active, let advancedRoute { routeSimulation = advancedRoute }
            if !moved { pin = selectedPin }
        }
    }

    private func startResend(pairing: PairingStore) {
        guard resendTimer == nil else { return }
        let token = generation
        let timer = Timer(timeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token, self.status == .active,
                      let sim = self.simulated else { return }
                let result = LocationEngine.set(
                    latitude: sim.latitude,
                    longitude: sim.longitude,
                    pairingPath: pairing.pairingPath,
                    deviceIP: TunnelConfig.targetIP
                )
                if case .failure(let error) = result {
                    self.interruptMovement()
                    self.lastError = error.localizedDescription
                    self.status = .dropped(error.localizedDescription)
                    self.postDropNotification(error.localizedDescription)
                }
            }
        }
        resendTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopResend() {
        resendTimer?.invalidate()
        resendTimer = nil
    }

    private func startHealth(pairing: PairingStore) {
        guard healthTimer == nil else { return }
        let token = generation
        let timer = Timer(timeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token, let ideal = self.idealCoordinate else { return }
                let selectedPin = self.pin
                if case .dropped = self.status {
                    self.status = .reconnecting
                    self.startAfterResolving { [weak self] in
                        self?.apply(ideal, pairing: pairing, markRecent: false)
                        self?.pin = selectedPin
                    }
                } else if !LocationEngine.isSessionActive, self.isSpoofing {
                    self.interruptMovement()
                    self.status = .reconnecting
                    self.startAfterResolving { [weak self] in
                        self?.apply(ideal, pairing: pairing, markRecent: false)
                        self?.pin = selectedPin
                    }
                }
                self.pin = selectedPin
            }
        }
        healthTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopHealth() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    private func pushRecent(_ coordinate: CLLocationCoordinate2D) {
        pushNamedRecent(
            name: Self.coordinateLabel(coordinate),
            coordinate: coordinate
        )
    }

    func pushNamedRecent(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        recents.removeAll {
            abs($0.latitude - place.latitude) < 0.00015 && abs($0.longitude - place.longitude) < 0.00015
        }
        recents.insert(place, at: 0)
        if recents.count > 20 { recents = Array(recents.prefix(20)) }
        SavedPlace.save(recents, key: recentsKey)
    }

    private func beginBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackground()
        }
    }

    private func endBackground() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func postDropNotification(_ message: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Locus spoof dropped")
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

extension MotionPoint {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}


/// Route-based speed simulation. Junction pauses are synthetic; this controller
/// does NOT know actual red/green light phases or live congestion.
/// The idevice location backend transmits coordinates only, so the altitude
/// below is a local estimate, not an altitude injected into other apps.
private struct TravelDynamics {
    private var currentSpeed: Double = 0
    private var junctionDistances: [Double] = []
    private var airportStages: [AirportJourneyStage] = []
    private var airportIndex = 0
    private var airportHoldRemaining = 0.0
    private var airportStageEntered = false
    private var nextJunction = 0
    private var waitingSeconds: Double = 0
    private(set) var estimatedFlightAltitude: Double = 0
    private(set) var isWaiting = false

    mutating func reset(route: [MotionPoint] = []) {
        currentSpeed = 0
        junctionDistances = Self.junctionCandidates(route)
        nextJunction = 0
        waitingSeconds = 0
        estimatedFlightAltitude = 0
        isWaiting = false
        airportStages = []
        airportIndex = 0
        airportHoldRemaining = 0
        airportStageEntered = false
    }

    mutating func configureAirport(_ stages: [AirportJourneyStage]) {
        airportStages = stages
        airportIndex = 0
        airportHoldRemaining = 0
        airportStageEntered = false
        currentSpeed = 0
    }

    var airportStageLabel: String? {
        guard !airportStages.isEmpty else { return nil }
        let index = min(airportIndex, airportStages.count - 1)
        if airportHoldRemaining > 0 {
            return "Airport hold · \(Int(ceil(airportHoldRemaining / 60))) min remaining"
        }
        return airportStages[index].kind.label
    }

    mutating func advanceDistance(mode: TravelMode, baseSpeed: Double, seconds: Double,
                                  travelled: Double, total: Double, variation: Double) -> Double {
        // Avoid giant jumps following an iOS suspension/resume.
        let dt = min(1.0, max(0.0, seconds))
        guard dt > 0, total > 0 else { return 0 }
        if !airportStages.isEmpty {
            return airportAdvance(seconds: dt, travelled: travelled, variation: variation)
        }
        let remaining = max(0, total - travelled)
        var target = max(0, baseSpeed * variation)
        var acceleration = 2.0
        var braking = 3.0

        if mode == .realisticDrive {
            acceleration = 1.7
            braking = 3.0
            if waitingSeconds > 0 {
                waitingSeconds = max(0, waitingSeconds - dt)
                currentSpeed = 0
                isWaiting = true
                if waitingSeconds == 0 { nextJunction += 1; isWaiting = false }
                return 0
            }
            if nextJunction < junctionDistances.count {
                let toJunction = max(0, junctionDistances[nextJunction] - travelled)
                if toJunction <= 1.5 {
                    waitingSeconds = Double(12 + (nextJunction % 3) * 12)
                    currentSpeed = 0
                    isWaiting = true
                    return 0
                }
                // Kinematic braking toward the next simulated junction hold.
                target = min(target, sqrt(2 * braking * toJunction))
            }
            // Slow naturally near the destination.
            target = min(target, sqrt(2 * braking * remaining))
        } else if mode == .flight {
            acceleration = 5.0
            braking = 4.0
            let takeoffLength = max(600, min(15000, total * 0.18))
            let arrivalLength = max(600, min(25000, total * 0.20))
            if travelled < min(500, takeoffLength / 4) {
                target = 8.0 // airport taxi
            } else if travelled < takeoffLength {
                target = max(35, target * min(1, travelled / takeoffLength))
            }
            if remaining < arrivalLength {
                target = min(target, max(12, baseSpeed * remaining / arrivalLength))
            }
            // Altitude changes over a much longer distance than takeoff acceleration.
            let climbLength = max(1000, min(160000, total * 0.30))
            let descentLength = max(1000, min(130000, total * 0.30))
            let climbRatio = min(1, max(0, (travelled - 500) / climbLength))
            let descentRatio = min(1, remaining / descentLength)
            estimatedFlightAltitude = 11000 * min(climbRatio, descentRatio)
        } else if mode == .ship {
            acceleration = 0.2
            braking = 0.3
            let portDistance = max(100, min(1500, total * 0.10))
            target = min(target, max(1.0, baseSpeed * min(1, travelled / portDistance + 0.12)))
            if remaining < portDistance {
                target = min(target, max(0.5, baseSpeed * remaining / portDistance))
            }
        } else {
            // Preserve normal Locus movement for walk, cycle, run, drive, custom.
            return min(remaining, target * dt)
        }

        let delta = target - currentSpeed
        currentSpeed += max(-braking * dt, min(acceleration * dt, delta))
        currentSpeed = max(0, currentSpeed)
        var move = min(remaining, currentSpeed * dt)
        if mode == .realisticDrive && nextJunction < junctionDistances.count {
            move = min(move, max(0, junctionDistances[nextJunction] - travelled))
        }
        return move
    }

    private mutating func airportAdvance(seconds dt: Double, travelled: Double, variation: Double) -> Double {
        while airportIndex < airportStages.count - 1 &&
              travelled >= airportStages[airportIndex].endDistance - 0.01 {
            airportIndex += 1
            airportStageEntered = false
        }
        guard airportIndex < airportStages.count else { return 0 }
        let stage = airportStages[airportIndex]
        if !airportStageEntered {
            airportStageEntered = true
            airportHoldRemaining = stage.holdBeforeSeconds
        }
        if airportHoldRemaining > 0 {
            airportHoldRemaining = max(0, airportHoldRemaining - dt)
            currentSpeed = 0
            return 0
        }
        let previousEnd = airportIndex == 0 ? 0 : airportStages[airportIndex - 1].endDistance
        let legDistance = max(1, stage.endDistance - previousEnd)
        let along = max(0, travelled - previousEnd)
        let remaining = max(0, stage.endDistance - travelled)
        let braking = stage.kind.braking
        var target = max(0.5, stage.speed * variation)
        // Smooth arrivals and stage transitions, particularly before holds.
        if stage.kind != .cruise {
            target = min(target, max(1, sqrt(2 * braking * max(remaining, 0.5))))
        }
        let delta = target - currentSpeed
        currentSpeed = max(0, currentSpeed + max(-braking * dt, min(stage.kind.accel * dt, delta)))
        let move = min(remaining, currentSpeed * dt)
        switch stage.kind {
        case .takeoff:
            estimatedFlightAltitude = 1800 * min(1, along / legDistance)
        case .cruise:
            let climb = max(1, min(160_000, legDistance * 0.28))
            estimatedFlightAltitude = 1800 + 9200 * min(1, along / climb)
        case .approach:
            estimatedFlightAltitude = 11000 * max(0, 1 - along / legDistance)
        case .driveToAirport, .taxiOut, .taxiIn, .driveToHotel:
            estimatedFlightAltitude = 0
        }
        return move
    }

    func status(mode: TravelMode, travelled: Double, total: Double) -> String {
        guard total > 0 else { return "" }
        let remaining = max(0, total - travelled)
        switch mode {
        case .flight:
            if travelled < min(15000, total * 0.18) { return String(localized: "Taxi / takeoff") }
            if remaining < min(25000, total * 0.20) { return String(localized: "Approach / landing") }
            return String(localized: "Cruising")
        case .ship:
            if remaining < min(1500, total * 0.10) { return String(localized: "Approaching port") }
            return String(localized: "At sea")
        case .realisticDrive:
            return isWaiting ? String(localized: "Simulated junction stop") : String(localized: "Traffic-style driving")
        default: return ""
        }
    }

    /// Approximate potential junctions from strong changes of road direction.
    /// A turn is NOT evidence of a traffic signal; stops are illustrative only.
    private static func junctionCandidates(_ path: [MotionPoint]) -> [Double] {
        guard path.count > 12 else { return [] }
        var accumulated = [Double](repeating: 0, count: path.count)
        for i in 1..<path.count {
            accumulated[i] = accumulated[i - 1] + path[i - 1].distance(to: path[i])
        }
        let length = accumulated.last ?? 0
        var candidates: [Double] = []
        for i in stride(from: 5, to: path.count - 5, by: 5) {
            let prev = path[i - 5], mid = path[i], next = path[i + 5]
            let latRad = mid.latitude * Double.pi / 180
            let headingIn = atan2((mid.longitude - prev.longitude) * cos(latRad), mid.latitude - prev.latitude)
            let headingOut = atan2((next.longitude - mid.longitude) * cos(latRad), next.latitude - mid.latitude)
            let angle = abs(atan2(sin(headingOut - headingIn), cos(headingOut - headingIn)))
            let at = accumulated[i]
            if angle > Double.pi / 3, at > 250, length - at > 250,
               at - (candidates.last ?? 0) > 300 {
                candidates.append(at)
            }
        }
        return candidates
    }
}
