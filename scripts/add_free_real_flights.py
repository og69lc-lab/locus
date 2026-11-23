#!/usr/bin/env python3
"""One-shot, fail-fast integration of no-key live aircraft, airport maps, and optional free flight boards."""
from pathlib import Path


def change(path, before, after, *, times=1):
    p = Path(path)
    s = p.read_text()
    assert s.count(before) == times, f"Expected {times} exact code anchors in {path}, found {s.count(before)} for {before[:90]!r}"
    p.write_text(s.replace(before, after, times))


session = 'Locus/Engine/SpoofSession.swift'
route = 'Locus/Features/Routes/RoutePlannerSheet.swift'

change(session, '    @Published var joystickActive = false\n', '''    @Published var joystickActive = false

    // Observed aircraft follow (free ADS-B feed). These are reported measurements,
    // not GPS altitude/speed injected into other applications.
    @Published private(set) var liveFlightHex: String?
    @Published private(set) var liveFlightAircraft: ObservedAircraft?
    @Published private(set) var liveFlightStatus = ""
    private var liveFlightTask: Task<Void, Never>?
    private var liveFrom: MotionPoint?
    private var liveTo: MotionPoint?
    private var liveBlendStarted: TimeInterval = 0
''')

change(session, '''    private func cancelMovement() {
        cancelConnectionAttempt()
''', '''    private func cancelMovement() {
        stopFreeLiveFlight()
        cancelConnectionAttempt()
''')

change(session, '''    var travelStatusDescription: String {
''', '''    /// Start following one observed aircraft. Explicitly replaces any running route;
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
                        self.liveFlightStatus = "Observed position refreshed; \\(Int(reported.ageSeconds))s old. Smooth delayed follow active."
                    } catch {
                        guard !Task.isCancelled else { break }
                        self.liveFlightStatus = "Live feed unavailable: \\(error.localizedDescription). Last reported location held."
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
''')

change(session, '''        if routeSimulation.phase == .running {
            var candidate = routeSimulation
''', '''        if liveFlightHex != nil, let from = liveFrom, let target = liveTo {
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
''')

change(route, '''    @State private var showAirportIntelligence = false
''', '''    @State private var showAirportIntelligence = false
    @State private var showFreeRealFlights = false
''')
change(route, '''                Section("Airport Intelligence") {
                    Button { showAirportIntelligence = true } label: {
''', '''                if session.liveFlightHex != nil {
                    Section("Following an observed aircraft") {
                        Text(session.liveFlightStatus).font(.caption).foregroundStyle(.secondary)
                        if let observed = session.liveFlightAircraft {
                            Text("\\(observed.callsign) • \\(observed.hex)")
                        }
                        Button(role: .destructive) { session.stopFreeLiveFlight() } label: {
                            Label("Stop live following — hold GPS", systemImage: "stop.fill")
                        }
                    }
                }
                Section("Airport Intelligence") {
                    Button { showFreeRealFlights = true } label: {
                        Label("FREE Real Flights — live aircraft and airport map", systemImage: "airplane.circle")
                    }
                    Button { showAirportIntelligence = true } label: {
''')
change(route, '''            .sheet(isPresented: $showAirportIntelligence) {
''', '''            .sheet(isPresented: $showFreeRealFlights) {
                FreeRealFlightsSheet()
            }
            .sheet(isPresented: $showAirportIntelligence) {
''')

Path('FREE-REAL-FLIGHTS.md').write_text('''# Locus Free Real Flights — one-click upgrade

## What is included
- Browse real ADS-B aircraft currently observed near two chosen airports.
- ICAO callsign lookup, aircraft identification, reported heading/altitude/groundspeed and observations age.
- Transient adsbdb callsign route hints, explicitly **unverified**; mismatched route hints are not promoted as confirmed flights.
- Continuous delayed GPS follow using a 180-second ADS-B poll interval and interpolation to prevent sudden jumps.
- Airport runways, taxiways, terminal outlines and mapped gates from OpenStreetMap Overpass; these do NOT identify airline gate assignments.
- Optional real scheduled departure board, terminal and gate details using a free-tier SkyLink RapidAPI key (you obtain it yourself). Key saved in iOS Keychain only.
- Distinct play/stop controls, error messages, source credits and clear limitations.

## How to use
Open **Routes → FREE Real Flights**. Pick departure and arrival airports. Tap **Find real aircraft around both airports** (current positions only) or search a real ICAO callsign such as `UAE515`. Select an observed aircraft and tap **Follow this aircraft in Locus**. Use **Stop live following** to hold the last simulated GPS fix. Use the normal **End spoofing** control to return to real location.

## Pricing and limitations
- Zero payment, signup, or API key necessary for observed aircraft and OpenStreetMap airport maps.
- adsb.lol: **500 requests/day per IP without key**. A poll every 180 seconds uses up to 480 per 24 hours, so scanning and other uses can exhaust quota. The provider can change limits/availability.
- OpenStreetMap Overpass is a community service. Load only on demand; rate limits and missing mapped features may occur.
- There is **no universal, reliable, zero-key free service** that supplies all scheduled future flights, exact assigned airline terminals/gates, runway use and ATC taxi clearance worldwide.
- Optional schedules: SkyLink RapidAPI advertised free plan, around 1,000 calls per month, requires the user's own API key. Not an unlimited free feed.
- ADS-B positions can be delayed or absent and aircraft routes can be mismatched; this is a **simulation and testing tool**, not flight navigation.
- The iPhone location backend injects **coordinates only**, not real aircraft barometric altitude/speed and not Snapchat Actionmoji.
- Background execution and GPS injection are subject to iOS limitations and the connected pairing/tunnel.

## Sources and attributions
- [adsb.lol](https://www.adsb.lol/docs/open-data/api) (ODbL 1.0)
- [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors (ODbL 1.0), via Overpass
- [adsbdb](https://www.adsbdb.com/) route hints, transient display only; not reproduced into route databases
- [SkyLink Flight Schedules](https://github.com/SkyLink-API/flight-schedules-api) optional free-tier connection

## Build
The GitHub Action creates `feature/free-live-flight-pro` from `feature/airport-intelligence-all-in-one`. Build that branch in Codemagic with its existing `Locus Travel Modes - Unsigned IPA` workflow. This does not alter the working installation until you sideload the new IPA.
''')
print('Installed all integration anchors successfully.')
