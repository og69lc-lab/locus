import CoreLocation
import Foundation
import MapKit
import Security
import SwiftUI

// Locus Free Real Flights — live observed aircraft positions, optional free-tier flight boards,
// and OpenStreetMap infrastructure. This is an educational simulation, NOT aviation navigation.
// ADS-B data: adsb.lol (ODbL 1.0). OSM data: OpenStreetMap contributors (ODbL 1.0).

struct ObservedAircraft: Identifiable, Equatable {
    var hex: String
    var callsign: String
    var registration: String
    var aircraftType: String
    var latitude: Double
    var longitude: Double
    var groundSpeedKnots: Double
    var heading: Double
    var altitudeFeet: Double?
    var ageSeconds: Double
    var id: String { hex }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    static func fromJSON(_ obj: [String: Any]) -> ObservedAircraft? {
        func number(_ value: Any?) -> Double? {
            if let value = value as? NSNumber { return value.doubleValue }
            if let value = value as? String { return Double(value) }
            return nil
        }
        guard let hex = obj["hex"] as? String,
              let lat = number(obj["lat"]), let lon = number(obj["lon"]),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        let age = number(obj["seen_pos"]) ?? number(obj["seen"]) ?? 1_000
        // A stale position must not be presented as a current aircraft location.
        guard age <= 120 else { return nil }
        return ObservedAircraft(hex: hex.lowercased(),
            callsign: (obj["flight"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            registration: obj["r"] as? String ?? "",
            aircraftType: obj["t"] as? String ?? "",
            latitude: lat, longitude: lon,
            groundSpeedKnots: number(obj["gs"]) ?? 0,
            heading: number(obj["track"]) ?? 0,
            altitudeFeet: number(obj["alt_baro"]) ?? number(obj["alt_geom"]),
            ageSeconds: age)
    }
}

struct FlightRouteHint: Equatable {
    var originIATA: String
    var originICAO: String
    var destinationIATA: String
    var destinationICAO: String
    var airline: String
    var icaoCallsign: String

    func matches(origin: AirportRecord, destination: AirportRecord) -> Bool {
        let from = originIATA == origin.code || originICAO == origin.icao
        let to = destinationIATA == destination.code || destinationICAO == destination.icao
        return from && to
    }
}

struct FlightObservation: Identifiable {
    var aircraft: ObservedAircraft
    var routeHint: FlightRouteHint?
    var id: String { aircraft.hex }
}

enum FreeFlightFeeds {
    static func json(url: URL, headers: [String: String] = [:]) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.timeoutInterval = 18
        req.setValue("Locus-FreeFlight-Research/1.0", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw FeedError.invalidResponse }
        if http.statusCode == 429 { throw FeedError.limitReached }
        guard (200..<300).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FeedError.invalidResponse
        }
        return root
    }

    enum FeedError: LocalizedError {
        case invalidResponse, limitReached, http(Int), missingAircraft
        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "The flight provider returned an unreadable response."
            case .limitReached: return "The free aircraft-data daily limit was reached. Try again after 00:00 UTC."
            case .http(let status): return "Flight data unavailable (HTTP \(status))."
            case .missingAircraft: return "No recent observed position was available for this aircraft."
            }
        }
    }

    static func nearby(_ airport: AirportRecord, radiusNM: Int = 120) async throws -> [ObservedAircraft] {
        let lat = String(format: "%.5f", airport.latitude)
        let lon = String(format: "%.5f", airport.longitude)
        guard let url = URL(string: "https://api.adsb.lol/v2/lat/\(lat)/lon/\(lon)/dist/\(min(250, max(1, radiusNM)))") else {
            throw FeedError.invalidResponse
        }
        let root = try await json(url: url)
        return (root["ac"] as? [[String: Any]] ?? []).compactMap(ObservedAircraft.fromJSON)
    }

    static func byHex(_ hex: String) async throws -> ObservedAircraft {
        let cleaned = hex.lowercased().filter { $0.isHexDigit }
        guard cleaned.count == 6, let url = URL(string: "https://api.adsb.lol/v2/hex/\(cleaned)") else {
            throw FeedError.invalidResponse
        }
        let root = try await json(url: url)
        guard let aircraft = (root["ac"] as? [[String: Any]] ?? []).compactMap(ObservedAircraft.fromJSON).first else {
            throw FeedError.missingAircraft
        }
        return aircraft
    }

    static func byCallsign(_ callsign: String) async throws -> [ObservedAircraft] {
        let cleaned = callsign.uppercased().filter { $0.isLetter || $0.isNumber }
        guard (3...12).contains(cleaned.count),
              let url = URL(string: "https://api.adsb.lol/v2/callsign/\(cleaned)") else {
            throw FeedError.invalidResponse
        }
        let root = try await json(url: url)
        return (root["ac"] as? [[String: Any]] ?? []).compactMap(ObservedAircraft.fromJSON)
    }

    // Route hints are external community-maintained metadata, not confirmed scheduled flight legs.
    // Results are used transiently; they are not copied into a route database.
    static func routeHint(callsign: String) async -> FlightRouteHint? {
        let cleaned = callsign.uppercased().filter { $0.isLetter || $0.isNumber }
        guard (3...12).contains(cleaned.count),
              let url = URL(string: "https://api.adsbdb.com/v0/callsign/\(cleaned)") else { return nil }
        guard let root = try? await json(url: url),
              let response = root["response"] as? [String: Any],
              let route = response["flightroute"] as? [String: Any],
              let origin = route["origin"] as? [String: Any],
              let destination = route["destination"] as? [String: Any] else { return nil }
        let airline = route["airline"] as? [String: Any]
        return .init(originIATA: (origin["iata_code"] as? String ?? "").uppercased(),
                     originICAO: (origin["icao_code"] as? String ?? "").uppercased(),
                     destinationIATA: (destination["iata_code"] as? String ?? "").uppercased(),
                     destinationICAO: (destination["icao_code"] as? String ?? "").uppercased(),
                     airline: airline?["name"] as? String ?? "",
                     icaoCallsign: route["callsign_icao"] as? String ?? "")
    }
}

// Optional user-provided free-tier API key. Stored on-device in iOS Keychain, never in GitHub.
private enum FlightBoardKeychain {
    private static let service = "com.chrismack.locus.freeflight.board"
    static func load() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: service, kSecAttrAccount as String: "rapidapi",
             kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: service, kSecAttrAccount as String: "rapidapi"]
        SecItemDelete(query as CFDictionary)
        guard !key.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(key.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

struct FreeFlightBoardEntry: Identifiable {
    var id: String { "\(flightNumber)-\(scheduled)-\(destination)" }
    var flightNumber: String
    var icaoCallsign: String
    var airline: String
    var destination: String
    var scheduled: String
    var terminal: String
    var gate: String
    var status: String
    var delayMinutes: Int?
}

enum FreeFlightBoard {
    static func departures(from airport: AirportRecord, key: String) async throws -> [FreeFlightBoardEntry] {
        guard !key.isEmpty else { return [] }
        var parts = URLComponents(string: "https://skylink-api.p.rapidapi.com/v3/schedules/departures")!
        parts.queryItems = [URLQueryItem(name: "icao", value: airport.icao)]
        let root = try await FreeFlightFeeds.json(url: parts.url!, headers: [
            "x-rapidapi-key": key, "x-rapidapi-host": "skylink-api.p.rapidapi.com"])
        let rows = root["flights"] as? [[String: Any]] ?? []
        func str(_ row: [String: Any], _ names: [String]) -> String {
            for name in names { if let value = row[name] as? String, !value.isEmpty { return value } }
            return ""
        }
        return rows.map { item in
            let delay = item["delay_minutes"] as? Int
            return FreeFlightBoardEntry(
                flightNumber: str(item, ["flight_number", "flight_number_iata"]),
                icaoCallsign: str(item, ["flight_number_icao", "icao_flight_number"]),
                airline: str(item, ["airline_name", "airline"]),
                destination: str(item, ["destination_airport", "destination_iata", "destination_airport_iata"]),
                scheduled: str(item, ["scheduled_time", "scheduled_departure"]),
                terminal: str(item, ["terminal", "departure_terminal"]),
                gate: str(item, ["gate", "departure_gate"]),
                status: str(item, ["status", "flight_status"]),
                delayMinutes: delay)
        }
    }
}

struct AirportMapLine: Identifiable {
    var id: String
    var kind: String
    var label: String
    var coordinates: [CLLocationCoordinate2D]
}

struct AirportGroundMap {
    var features: [AirportMapLine]
    var runways: [String] { features.filter { $0.kind == "runway" }.map(\.label) }
    var terminals: [String] { features.filter { $0.kind == "terminal" }.map(\.label) }
    var gates: [String] { features.filter { $0.kind == "gate" }.map(\.label) }
}

enum FreeAirportMap {
    static func load(_ airport: AirportRecord) async throws -> AirportGroundMap {
        let lat = String(format: "%.5f", airport.latitude)
        let lon = String(format: "%.5f", airport.longitude)
        let query = """
        [out:json][timeout:20];(
          way(around:5000,\(lat),\(lon))["aeroway"~"^(runway|taxiway|terminal)$"];
          way(around:5000,\(lat),\(lon))["building"="terminal"];
          node(around:5000,\(lat),\(lon))["aeroway"="gate"];
        );out geom;
        """
        // Public community instances may be temporarily overloaded. Use on-demand
        // fallback rather than silently treating a failed request as "no airport map".
        let hosts = ["https://overpass.private.coffee/api/interpreter",
                     "https://overpass.kumi.systems/api/interpreter",
                     "https://overpass-api.de/api/interpreter"]
        var root: [String: Any]?
        for host in hosts {
            var parts = URLComponents(string: host)!
            parts.queryItems = [URLQueryItem(name: "data", value: query)]
            guard let url = parts.url else { continue }
            if let found = try? await FreeFlightFeeds.json(url: url) {
                root = found
                break
            }
        }
        guard let root else { throw FreeFlightFeeds.FeedError.invalidResponse }
        let elements = root["elements"] as? [[String: Any]] ?? []
        let features: [AirportMapLine] = elements.prefix(500).compactMap { row in
            guard let osmID = row["id"] as? NSNumber else { return nil }
            let tags = row["tags"] as? [String: Any] ?? [:]
            let aeroway = tags["aeroway"] as? String ?? ""
            let kind = aeroway.isEmpty ? "terminal" : aeroway
            let name = tags["ref"] as? String ?? tags["name"] as? String ?? kind.capitalized
            var points: [CLLocationCoordinate2D] = []
            if let geometry = row["geometry"] as? [[String: Any]] {
                points = geometry.compactMap { p in
                    guard let la = p["lat"] as? Double, let lo = p["lon"] as? Double else { return nil }
                    return CLLocationCoordinate2D(latitude: la, longitude: lo)
                }
            } else if let la = row["lat"] as? Double, let lo = row["lon"] as? Double {
                points = [.init(latitude: la, longitude: lo)]
            }
            guard !points.isEmpty else { return nil }
            return AirportMapLine(id: "\(kind)-\(osmID)", kind: kind, label: name, coordinates: points)
        }
        return AirportGroundMap(features: features)
    }
}

private struct FlightAirportPicker: View {
    var title: String
    @Binding var selected: AirportRecord
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                TextField("Search IATA, ICAO, name or city", text: $search)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                ForEach(AirportRecord.matching(search)) { airport in
                    Button {
                        selected = airport
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(airport.code) • \(airport.name)").foregroundStyle(.primary)
                            Text("\(airport.city), \(airport.country)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            } }
        }
    }
}

struct FreeRealFlightsSheet: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss
    @State private var departure: AirportRecord = AirportRecord.featured[0]
    @State private var arrival: AirportRecord = AirportRecord.featured[1]
    @State private var chooseDeparture = false
    @State private var chooseArrival = false
    @State private var scanning = false
    @State private var statusText = ""
    @State private var observations: [FlightObservation] = []
    @State private var selectedHex: String?
    @State private var manualCallsign = ""
    @State private var layout: AirportGroundMap?
    @State private var layoutAirport: AirportRecord?
    @State private var loadingLayout = false
    @State private var scheduleKey = ""
    @State private var scheduledFlights: [FreeFlightBoardEntry] = []
    @State private var loadingSchedule = false
    @State private var errorText: String?

    private var matches: [FlightObservation] {
        observations.filter { $0.routeHint?.matches(origin: departure, destination: arrival) == true }
    }
    private var otherFlights: [FlightObservation] {
        observations.filter { $0.routeHint?.matches(origin: departure, destination: arrival) != true }
    }
    private var selected: FlightObservation? { observations.first { $0.aircraft.hex == selectedHex } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Airport pair") {
                    Button { chooseDeparture = true } label: {
                        LabeledContent("Departure", value: departure.displayName)
                    }
                    Button { chooseArrival = true } label: {
                        LabeledContent("Arrival", value: arrival.displayName)
                    }
                    Text("Only currently observed flights can be discovered without a schedule provider. Airport pairing does not guarantee a matching live flight is operating.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Free live aircraft finder") {
                    Button { Task { await scanNearby() } } label: {
                        Label("Find real aircraft around both airports", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .disabled(scanning || departure.id == arrival.id)
                    if scanning { ProgressView("Scanning aircraft and checking possible routes...") }
                    if !statusText.isEmpty { Text(statusText).font(.caption).foregroundStyle(.secondary) }
                    if !matches.isEmpty {
                        ForEach(matches) { item in aircraftButton(item, verified: false) }
                    }
                    if !otherFlights.isEmpty {
                        DisclosureGroup("Other aircraft nearby — route not matched (\(otherFlights.count))") {
                            ForEach(otherFlights.prefix(35)) { item in aircraftButton(item, verified: false) }
                        }
                    }
                    HStack {
                        TextField("ICAO callsign, e.g. UAE515", text: $manualCallsign)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        Button("Find") { Task { await lookupCallsign() } }
                            .disabled(scanning || manualCallsign.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("ADS-B callsigns aren't always passenger flight numbers. Route matches come from community data and must not be treated as verified current schedules.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let selected {
                    Section("Selected live aircraft") {
                        LabeledContent("Callsign", value: selected.aircraft.callsign.isEmpty ? selected.aircraft.hex : selected.aircraft.callsign)
                        if !selected.aircraft.registration.isEmpty { LabeledContent("Registration", value: selected.aircraft.registration) }
                        if !selected.aircraft.aircraftType.isEmpty { LabeledContent("Aircraft type", value: selected.aircraft.aircraftType) }
                        LabeledContent("Observed groundspeed", value: String(format: "%.0f km/h", selected.aircraft.groundSpeedKnots * 1.852))
                        LabeledContent("Heading", value: String(format: "%.0f°", selected.aircraft.heading))
                        if let alt = selected.aircraft.altitudeFeet { LabeledContent("Reported altitude", value: String(format: "%.0f ft", alt)) }
                        LabeledContent("Position age", value: String(format: "%.0f sec", selected.aircraft.ageSeconds))
                        if let hint = selected.routeHint {
                            LabeledContent("Possible route", value: "\(hint.originIATA) → \(hint.destinationIATA)")
                            if !hint.airline.isEmpty { LabeledContent("Airline", value: hint.airline) }
                        }
                        Button {
                            session.startFreeLiveFlight(selected.aircraft, pairing: pairing)
                            dismiss()
                        } label: { Label("Follow this aircraft in Locus", systemImage: "location.north.line.fill") }
                        Text("Live-follow updates your simulated GPS coordinates from observed ADS-B locations. Because the free source permits 500 requests/day per IP without a key, tracking polls about every 3 minutes, smoothing between reports. Expect a delayed track, not exact real-time position.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if session.liveFlightHex != nil {
                    Section("Active live tracking") {
                        Text(session.liveFlightStatus)
                        if let aircraft = session.liveFlightAircraft {
                            Text("\(aircraft.callsign) • \(aircraft.hex)")
                            LabeledContent("Last reported speed", value: String(format: "%.0f km/h", aircraft.groundSpeedKnots * 1.852))
                        }
                        Button(role: .destructive) { session.stopFreeLiveFlight() } label: {
                            Label("Stop live following (hold last GPS)", systemImage: "stop.fill")
                        }
                    }
                }
                Section("Free airport ground map") {
                    Picker("Map airport", selection: $layoutAirport) {
                        Text("Departure: \(departure.code)").tag(Optional(departure))
                        Text("Arrival: \(arrival.code)").tag(Optional(arrival))
                    }
                    Button { Task { await loadGroundMap() } } label: {
                        Label("Load mapped runways, taxiways, terminals and gates", systemImage: "map")
                    }.disabled(loadingLayout)
                    if loadingLayout { ProgressView("Requesting OpenStreetMap features...") }
                    if let layout, let airport = layoutAirport {
                        LabeledContent("Runways mapped", value: "\(layout.features.filter { $0.kind == "runway" }.count)")
                        LabeledContent("Taxiways mapped", value: "\(layout.features.filter { $0.kind == "taxiway" }.count)")
                        LabeledContent("Terminal outlines mapped", value: "\(layout.terminals.count)")
                        LabeledContent("Gate markers mapped", value: "\(layout.gates.count)")
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: airport.coordinate, latitudinalMeters: 6500, longitudinalMeters: 6500))) {
                            ForEach(layout.features) { f in
                                if f.kind == "gate", let coordinate = f.coordinates.first {
                                    Annotation(f.label, coordinate: coordinate) {
                                        Circle().fill(.blue).frame(width: 7, height: 7)
                                    }
                                } else if f.coordinates.count >= 2 {
                                    MapPolyline(coordinates: f.coordinates)
                                        .stroke(f.kind == "runway" ? .yellow : (f.kind == "terminal" ? .blue : .orange),
                                                lineWidth: f.kind == "runway" ? 4 : 2)
                                }
                            }
                        }
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        if !layout.runways.isEmpty {
                            Text("Mapped runway labels: \(layout.runways.prefix(8).joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("OpenStreetMap geometry isn't certified navigation data. A mapped gate does not prove which flight uses it, and a mapped taxiway does not reveal ATC clearance.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Optional free flight departure board") {
                    SecureField("Optional SkyLink RapidAPI key", text: $scheduleKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save free-tier key to iOS Keychain") { FlightBoardKeychain.save(scheduleKey) }
                        .disabled(scheduleKey.isEmpty)
                    Link("Get an optional free-tier schedule key (no card advertised)",
                         destination: URL(string: "https://rapidapi.com/skylink-api-skylink-api-default/api/skylink-api")!)
                    Button { Task { await loadBoard() } } label: {
                        Label("Read live departure board for \(departure.code)", systemImage: "list.bullet.rectangle")
                    }.disabled(loadingSchedule || scheduleKey.isEmpty)
                    if loadingSchedule { ProgressView("Fetching published schedule...") }
                    ForEach(scheduledFlights.filter { $0.destination.uppercased() == arrival.icao || $0.destination.uppercased() == arrival.code }) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(entry.flightNumber) • \(entry.airline)").font(.headline)
                            Text("Scheduled (UTC): \(entry.scheduled) | Status: \(entry.status)")
                                .font(.caption)
                            HStack {
                                Text("Terminal: \(entry.terminal.isEmpty ? "Not reported" : entry.terminal)")
                                Spacer()
                                Text("Gate: \(entry.gate.isEmpty ? "Not reported" : entry.gate)")
                            }.font(.caption).foregroundStyle(.secondary)
                            if !entry.icaoCallsign.isEmpty {
                                Button("Find this flight in live aircraft feed") {
                                    manualCallsign = entry.icaoCallsign
                                    Task { await lookupCallsign() }
                                }
                            }
                        }
                    }
                    if !scheduledFlights.isEmpty && !scheduledFlights.contains(where: {
                        $0.destination.uppercased() == arrival.icao || $0.destination.uppercased() == arrival.code
                    }) {
                        Text("No matching \(departure.code) → \(arrival.code) flight in the returned page. This is not proof that no flight operates.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Flight boards require a separately obtained free-tier key and have monthly request limits. Schedule, terminal and gate fields are shown only when supplied by the provider. No key is needed for live aircraft or airport maps.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Privacy, accuracy and source credits") {
                    Text("Live ADS-B: adsb.lol · ODbL 1.0. Airport map: © OpenStreetMap contributors · ODbL 1.0. Route metadata: adsbdb, displayed transiently and unverified. Live schedule (optional): SkyLink API under its own terms.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("No service provides a guaranteed, free, worldwide combination of future flights, exact gates, ATC movements and uninterrupted live tracking. Locus injects only coordinates; reported altitude and speed are shown for reference. Do not use for navigation.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let errorText { Section("Provider message") { Text(errorText).foregroundStyle(.red) } }
            }
            .navigationTitle("Free Real Flights")
            .onAppear {
                layoutAirport = departure
                scheduleKey = FlightBoardKeychain.load()
            }
            .sheet(isPresented: $chooseDeparture) { FlightAirportPicker(title: "Departure airport", selected: $departure) }
            .sheet(isPresented: $chooseArrival) { FlightAirportPicker(title: "Arrival airport", selected: $arrival) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func aircraftButton(_ item: FlightObservation, verified: Bool) -> some View {
        Button {
            selectedHex = item.aircraft.hex
        } label: {
            HStack {
                Image(systemName: "airplane")
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.aircraft.callsign.isEmpty ? item.aircraft.hex : item.aircraft.callsign)
                        .font(.subheadline.weight(.semibold))
                    Text("\(item.aircraft.aircraftType) • \(Int(item.aircraft.groundSpeedKnots * 1.852)) km/h • seen \(Int(item.aircraft.ageSeconds))s ago")
                        .font(.caption).foregroundStyle(.secondary)
                    if let route = item.routeHint {
                        Text("Route hint: \(route.originIATA) → \(route.destinationIATA) (unverified)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if selectedHex == item.aircraft.hex { Image(systemName: "checkmark.circle.fill") }
            }
        }.foregroundStyle(.primary)
    }

    @MainActor private func scanNearby() async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        errorText = nil
        observations = []
        selectedHex = nil
        do {
            // Two free ADS-B calls, then bounded, temporary community route lookups.
            async let nearFrom = FreeFlightFeeds.nearby(departure)
            async let nearTo = FreeFlightFeeds.nearby(arrival)
            let (a, b) = try await (nearFrom, nearTo)
            var aircraft = [ObservedAircraft]()
            var known = Set<String>()
            for entry in (a + b).sorted(by: { $0.ageSeconds < $1.ageSeconds }) {
                if known.insert(entry.hex).inserted { aircraft.append(entry) }
            }
            // Only enrich 30 callsigns; route metadata can be inaccurate and isn't a schedule.
            let check = Array(aircraft.filter { !$0.callsign.isEmpty }.prefix(30))
            var hints: [String: FlightRouteHint] = [:]
            await withTaskGroup(of: (String, FlightRouteHint?).self) { group in
                for entry in check {
                    group.addTask {
                        let hint = await FreeFlightFeeds.routeHint(callsign: entry.callsign)
                        return (entry.hex, hint)
                    }
                }
                for await (hex, hint) in group { if let hint { hints[hex] = hint } }
            }
            observations = aircraft.prefix(80).map { FlightObservation(aircraft: $0, routeHint: hints[$0.hex]) }
            let matched = matches.count
            statusText = "\(observations.count) currently observed aircraft near the airports. \(matched) matched community route hints."
        } catch { errorText = error.localizedDescription }
    }

    @MainActor private func lookupCallsign() async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        errorText = nil
        do {
            var results = (try? await FreeFlightFeeds.byCallsign(manualCallsign)) ?? []
            var hintFromLookup = await FreeFlightFeeds.routeHint(callsign: manualCallsign)
            // Passenger IATA codes (EK515) usually differ from radio ICAO callsigns (UAE515).
            // Resolve via the public route database when available, without inventing a match.
            if results.isEmpty, let converted = hintFromLookup?.icaoCallsign, !converted.isEmpty {
                results = try await FreeFlightFeeds.byCallsign(converted)
            }
            guard let plane = results.first else { throw FreeFlightFeeds.FeedError.missingAircraft }
            if hintFromLookup == nil {
                hintFromLookup = await FreeFlightFeeds.routeHint(callsign: plane.callsign)
            }
            let hint = hintFromLookup
            observations.removeAll { $0.aircraft.hex == plane.hex }
            observations.insert(.init(aircraft: plane, routeHint: hint), at: 0)
            selectedHex = plane.hex
            statusText = "Current aircraft found. Check the reported position before starting."
        } catch { errorText = error.localizedDescription }
    }

    @MainActor private func loadGroundMap() async {
        loadingLayout = true
        defer { loadingLayout = false }
        errorText = nil
        layout = nil
        do { layout = try await FreeAirportMap.load(layoutAirport ?? departure) }
        catch { errorText = "Airport geometry: \(error.localizedDescription)" }
    }

    @MainActor private func loadBoard() async {
        loadingSchedule = true
        defer { loadingSchedule = false }
        errorText = nil
        scheduledFlights = []
        do { scheduledFlights = try await FreeFlightBoard.departures(from: departure, key: scheduleKey) }
        catch { errorText = "Flight board: \(error.localizedDescription)" }
    }
}
