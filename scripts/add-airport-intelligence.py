#!/usr/bin/env python3
"""All-in-one, idempotent source upgrade for Locus airport intelligence."""
from pathlib import Path
import os

ROOT=Path.cwd()

def edit(path, changes):
    p=ROOT/path
    s=p.read_text()
    for needle,replacement in changes:
        if needle not in s:
            if replacement in s:
                continue
            raise SystemExit(f'Expected source anchor missing in {path}: {needle[:120]!r}')
        s=s.replace(needle,replacement,1)
    p.write_text(s)

engine=Path('Locus/Engine/SpoofSession.swift')

edit(engine,[
('    @Published private(set) var routeSimulation = RouteSimulation()\n',
 '    @Published private(set) var routeSimulation = RouteSimulation()\n    @Published private(set) var activeAirportJourney: AirportGeneratedPlan?\n'),
('        routeSimulation.clear()\n        travelDynamics.reset()\n        stopJoystick()',
 '        routeSimulation.clear()\n        travelDynamics.reset()\n        activeAirportJourney = nil\n        stopJoystick()'),
('    func followRoute(_ coordinates: [CLLocationCoordinate2D], pairing: PairingStore) {',
 '    func followRoute(_ coordinates: [CLLocationCoordinate2D], pairing: PairingStore,\n                     airportPlan: AirportGeneratedPlan? = nil) {'),
('        cancelMovement()\n        startAfterResolving { [self] in\n            apply(coordinates[0], pairing: pairing, markRecent: true)',
 '        cancelMovement()\n        activeAirportJourney = airportPlan\n        startAfterResolving { [self] in\n            apply(coordinates[0], pairing: pairing, markRecent: true)'),
('            travelDynamics.reset(route: next.path)\n            lastMotionTime',
 '            travelDynamics.reset(route: next.path)\n            if let airportPlan { travelDynamics.configureAirport(airportPlan.stages) }\n            lastMotionTime'),
('    var travelStatusDescription: String {\n        travelDynamics.status(',
 '    var travelStatusDescription: String {\n        if let label = travelDynamics.airportStageLabel { return label }\n        return travelDynamics.status('),
('    private var junctionDistances: [Double] = []\n',
 '    private var junctionDistances: [Double] = []\n    private var airportStages: [AirportJourneyStage] = []\n    private var airportIndex = 0\n    private var airportHoldRemaining = 0.0\n    private var airportStageEntered = false\n'),
('        estimatedFlightAltitude = 0\n        isWaiting = false\n    }\n\n    mutating func advanceDistance',
 '        estimatedFlightAltitude = 0\n        isWaiting = false\n        airportStages = []\n        airportIndex = 0\n        airportHoldRemaining = 0\n        airportStageEntered = false\n    }\n\n    mutating func configureAirport(_ stages: [AirportJourneyStage]) {\n        airportStages = stages\n        airportIndex = 0\n        airportHoldRemaining = 0\n        airportStageEntered = false\n        currentSpeed = 0\n    }\n\n    var airportStageLabel: String? {\n        guard !airportStages.isEmpty else { return nil }\n        let index = min(airportIndex, airportStages.count - 1)\n        if airportHoldRemaining > 0 {\n            return "Airport hold · \\(Int(ceil(airportHoldRemaining / 60))) min remaining"\n        }\n        return airportStages[index].kind.label\n    }\n\n    mutating func advanceDistance'),
('        guard dt > 0, total > 0 else { return 0 }\n        let remaining',
 '        guard dt > 0, total > 0 else { return 0 }\n        if !airportStages.isEmpty {\n            return airportAdvance(seconds: dt, travelled: travelled, variation: variation)\n        }\n        let remaining'),
('    func status(mode: TravelMode, travelled: Double, total: Double) -> String {',
 '''    private mutating func airportAdvance(seconds dt: Double, travelled: Double, variation: Double) -> Double {
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

    func status(mode: TravelMode, travelled: Double, total: Double) -> String {'''),
])

mapview=Path('Locus/Features/Map/MapHomeView.swift')
edit(mapview,[
('    @State private var routeCoords: [CLLocationCoordinate2D] = []\n',
 '    @State private var routeCoords: [CLLocationCoordinate2D] = []\n    @State private var preparedAirportJourney: AirportGeneratedPlan?\n    @State private var pendingAirportStopChange: AirportGeneratedPlan?\n'),
('            preparedDistance: preparedDistance,',
 '            preparedDistance: preparedDistance,\n            airportPlan: preparedAirportJourney,'),
('        .onChange(of: routeStops) { _, _ in\n            cancelRoadBuild()\n            routeCoords.removeAll()\n            preparedDistance = 0\n        }',
 '''        .onChange(of: routeStops) { _, _ in
            cancelRoadBuild()
            if let pendingAirportStopChange {
                self.pendingAirportStopChange = nil
                setPreparedRoute(pendingAirportStopChange.route, isRoad: false)
            } else {
                preparedAirportJourney = nil
                routeCoords.removeAll()
                preparedDistance = 0
            }
        }'''),
('        .onChange(of: session.travelMode) { _, _ in\n            if routeIsRoadRoute || isRouting {',
 '''        .onChange(of: session.travelMode) { _, mode in
            if mode != .flight && preparedAirportJourney != nil {
                preparedAirportJourney = nil
                routeCoords.removeAll()
                preparedDistance = 0
            }
            if routeIsRoadRoute || isRouting {'''),
('            onBuild: buildRoadRoute,',
 '''            onAirportFlight: { plan, startNow in
                cancelRoadBuild()
                session.travelMode = .flight
                preparedAirportJourney = plan
                pendingAirportStopChange = plan
                var newStops: [RouteStop] = []
                func appendStop(_ coordinate: CLLocationCoordinate2D, name: String) {
                    let point = MotionPoint(coordinate)
                    if newStops.last.map({ $0.point.distance(to: point) > 2 }) ?? true {
                        newStops.append(RouteStop(point: point, name: name))
                    }
                }
                if let first = plan.route.first {
                    appendStop(first, name: plan.stages.first?.kind == .driveToAirport ? "Starting address" : plan.departure.displayName)
                }
                appendStop(plan.departure.coordinate, name: plan.departure.displayName)
                appendStop(plan.destination.coordinate, name: plan.destination.displayName)
                if let last = plan.route.last {
                    appendStop(last, name: plan.stages.last?.kind == .driveToHotel ? "Destination address" : plan.destination.displayName)
                }
                routeStops = newStops
                setPreparedRoute(plan.route, isRoad: false)
                position = .region(MKCoordinateRegion(center: plan.departure.coordinate,
                    latitudinalMeters: 20000, longitudinalMeters: 20000))
                if startNow { session.followRoute(plan.route, pairing: pairing, airportPlan: plan) }
            },
            onBuild: buildRoadRoute,'''),
('                cancelRoadBuild()\n                setPreparedRoute(RouteBuilder.sample(coordinates: drawnPath, every: 10), isRoad: false)',
 '                cancelRoadBuild()\n                preparedAirportJourney = nil\n                setPreparedRoute(RouteBuilder.sample(coordinates: drawnPath, every: 10), isRoad: false)'),
('    private func buildRoadRoute() {\n        let points',
 '    private func buildRoadRoute() {\n        preparedAirportJourney = nil\n        let points'),
('        session.followRoute(routeCoords, pairing: pairing)\n',
 '        session.followRoute(routeCoords, pairing: pairing, airportPlan: preparedAirportJourney)\n'),
('            cancelRoadBuild()\n            setPreparedRoute(RouteBuilder.sample(coordinates: coords, every: 10), isRoad: false)',
 '            cancelRoadBuild()\n            preparedAirportJourney = nil\n            setPreparedRoute(RouteBuilder.sample(coordinates: coords, every: 10), isRoad: false)'),
])

sheet=Path('Locus/Features/Routes/RoutePlannerSheet.swift')
edit(sheet,[
('    var preparedDistance: Double\n',
 '    var preparedDistance: Double\n    var airportPlan: AirportGeneratedPlan?\n'),
('    var onBuild: () -> Void\n',
 '    var onAirportFlight: (AirportGeneratedPlan, Bool) -> Void\n    var onBuild: () -> Void\n'),
('    @Environment(\\.dismiss) private var dismiss\n',
 '    @Environment(\\.dismiss) private var dismiss\n    @State private var showAirportIntelligence = false\n'),
('                Section(String(localized: "Movement speed")) {',
 '''                Section("Airport Intelligence") {
                    Button { showAirportIntelligence = true } label: {
                        Label("Plan airport → flight → arrival", systemImage: "airplane.departure")
                    }
                    Text("Search airports by IATA/ICAO or city, select an aircraft, configure terminal holds and optionally add hotel transfers. The flight is a simulation, not airport navigation.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let airportPlan {
                        Text("\\(airportPlan.departure.id) → \\(airportPlan.destination.id)")
                            .font(.headline)
                        LabeledContent("Aircraft", value: airportPlan.aircraft.name)
                        LabeledContent("Estimated journey duration",value:String(format:"%.0f min",airportPlan.approximateSeconds/60))
                        if !airportPlan.departureTerminal.isEmpty { LabeledContent("Departure terminal",value:airportPlan.departureTerminal) }
                        if !airportPlan.departureGate.isEmpty { LabeledContent("Departure gate",value:airportPlan.departureGate) }
                        if !airportPlan.arrivalTerminal.isEmpty { LabeledContent("Arrival terminal",value:airportPlan.arrivalTerminal) }
                        if !airportPlan.arrivalGate.isEmpty { LabeledContent("Arrival gate",value:airportPlan.arrivalGate) }
                    }
                }
                Section(String(localized: "Movement speed")) {'''),
('            .navigationTitle(String(localized: "Routes"))',
 '''            .sheet(isPresented: $showAirportIntelligence) {
                AirportIntelligenceSheet { plan, startNow in
                    onAirportFlight(plan, startNow)
                }
            }
            .navigationTitle(String(localized: "Routes"))'''),
])

# Update app version and build, preserving same bundle ID for reinstalling.
project=Path('project.yml')
s=project.read_text()
s=s.replace('MARKETING_VERSION: "1.0.3"','MARKETING_VERSION: "1.1.0"').replace('CURRENT_PROJECT_VERSION: "4"','CURRENT_PROJECT_VERSION: "5"')
project.write_text(s)

readme=Path('AIRPORT-INTELLIGENCE.md')
readme.write_text('''# Locus Airport Intelligence — all-in-one upgrade

## Included

- Airport picker with 40 curated international airports, IATA/ICAO/city/name search, and worldwide Apple Maps search fallback.
- Favourite/recent airports stored locally.
- Aircraft presets: commercial airliner, private jet, turboprop.
- Optional terminal and gate labels, departure holds, arrival transfer holds.
- Taxi-out, takeoff/climb, cruise, approach/landing, taxi-in, followed by optional airport-to-hotel driving route.
- Optional departure hotel-to-airport road route (Apple Maps).
- Route playback with per-stage movement speeds, stop/hold, status labels and estimated altitude.
- Existing Locus pairing, route playback, GPX export, map and other movement modes retained.

## Usage

Open Routes → Airport Intelligence → choose airports → optionally enter hotel/address transfer points → generate. If **Start immediately** is off, choose **Start route** back in Routes. To use the simulator with your paired device, your existing Locus pairing setup must be functioning.

## Important limitations

Airport coordinates approximate airport centres. Taxiing, takeoff and landing paths are **synthetic** and are not actual runway/taxiway or airport traffic-control routes. Terminal and gate inputs are labels only and do **not** locate real gates. The flight segment is an approximate great-circle route and aircraft speeds are presets, not actual flight tracking. Estimated altitude is shown only inside Locus, and the current backend injects coordinate fixes only. Apple Maps search/routing needs network connectivity. This is not a flight/navigation safety application. Snapchat decides its own map and Actionmoji display.

## Build

Use the existing `codemagic.yaml` workflow on branch `feature/airport-intelligence-all-in-one` and download the resulting unsigned IPA for signing/sideloading using the method you already used.
''')
print('Airport Intelligence applied to source files.')
