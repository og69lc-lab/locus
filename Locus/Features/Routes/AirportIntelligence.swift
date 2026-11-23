import CoreLocation
import Foundation
import MapKit
import SwiftUI

// Airport Intelligence: offline seed airports + Apple Maps lookups. The airport
// centre is not an actual gate, taxiway or runway threshold.
struct AirportRecord: Codable, Hashable, Identifiable {
    var code: String
    var icao: String
    var name: String
    var city: String
    var country: String
    var latitude: Double
    var longitude: Double
    var id: String {
        if !code.isEmpty { return code }
        if !icao.isEmpty { return icao }
        return String(format:"%.5f,%.5f",latitude,longitude)
    }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var displayName: String {
        let identifier = code.isEmpty ? icao : code
        return identifier.isEmpty ? name : "\(identifier) · \(name)"
    }

    static let featured: [AirportRecord] = [
        .init(code:"DEL",icao:"VIDP",name:"Indira Gandhi International Airport",city:"Delhi",country:"India",latitude:28.5562,longitude:77.1000),
        .init(code:"DXB",icao:"OMDB",name:"Dubai International Airport",city:"Dubai",country:"UAE",latitude:25.2528,longitude:55.3644),
        .init(code:"DOH",icao:"OTHH",name:"Hamad International Airport",city:"Doha",country:"Qatar",latitude:25.2731,longitude:51.6081),
        .init(code:"LHR",icao:"EGLL",name:"Heathrow Airport",city:"London",country:"UK",latitude:51.4700,longitude:-0.4543),
        .init(code:"JFK",icao:"KJFK",name:"John F. Kennedy International Airport",city:"New York",country:"USA",latitude:40.6413,longitude:-73.7781),
        .init(code:"BOM",icao:"VABB",name:"Chhatrapati Shivaji Maharaj International Airport",city:"Mumbai",country:"India",latitude:19.0896,longitude:72.8656),
        .init(code:"BLR",icao:"VOBL",name:"Kempegowda International Airport",city:"Bengaluru",country:"India",latitude:13.1986,longitude:77.7066),
        .init(code:"ATQ",icao:"VIAR",name:"Sri Guru Ram Dass Jee International Airport",city:"Amritsar",country:"India",latitude:31.7096,longitude:74.7973),
        .init(code:"LHE",icao:"OPLA",name:"Allama Iqbal International Airport",city:"Lahore",country:"Pakistan",latitude:31.5216,longitude:74.4036),
        .init(code:"AUH",icao:"OMAA",name:"Zayed International Airport",city:"Abu Dhabi",country:"UAE",latitude:24.4330,longitude:54.6511),
        .init(code:"SIN",icao:"WSSS",name:"Changi Airport",city:"Singapore",country:"Singapore",latitude:1.3644,longitude:103.9915),
        .init(code:"HKG",icao:"VHHH",name:"Hong Kong International Airport",city:"Hong Kong",country:"China",latitude:22.3080,longitude:113.9185),
        .init(code:"NRT",icao:"RJAA",name:"Narita International Airport",city:"Tokyo",country:"Japan",latitude:35.7720,longitude:140.3929),
        .init(code:"HND",icao:"RJTT",name:"Haneda Airport",city:"Tokyo",country:"Japan",latitude:35.5494,longitude:139.7798),
        .init(code:"ICN",icao:"RKSI",name:"Incheon International Airport",city:"Seoul",country:"South Korea",latitude:37.4602,longitude:126.4407),
        .init(code:"SYD",icao:"YSSY",name:"Sydney Kingsford Smith Airport",city:"Sydney",country:"Australia",latitude:-33.9399,longitude:151.1753),
        .init(code:"MEL",icao:"YMML",name:"Melbourne Airport",city:"Melbourne",country:"Australia",latitude:-37.6733,longitude:144.8433),
        .init(code:"AKL",icao:"NZAA",name:"Auckland Airport",city:"Auckland",country:"New Zealand",latitude:-37.0082,longitude:174.7850),
        .init(code:"WLG",icao:"NZWN",name:"Wellington Airport",city:"Wellington",country:"New Zealand",latitude:-41.3272,longitude:174.8050),
        .init(code:"LAX",icao:"KLAX",name:"Los Angeles International Airport",city:"Los Angeles",country:"USA",latitude:33.9416,longitude:-118.4085),
        .init(code:"SFO",icao:"KSFO",name:"San Francisco International Airport",city:"San Francisco",country:"USA",latitude:37.6213,longitude:-122.3790),
        .init(code:"BOS",icao:"KBOS",name:"Logan International Airport",city:"Boston",country:"USA",latitude:42.3656,longitude:-71.0096),
        .init(code:"EWR",icao:"KEWR",name:"Newark Liberty International Airport",city:"Newark",country:"USA",latitude:40.6895,longitude:-74.1745),
        .init(code:"ORD",icao:"KORD",name:"O'Hare International Airport",city:"Chicago",country:"USA",latitude:41.9742,longitude:-87.9073),
        .init(code:"YYZ",icao:"CYYZ",name:"Toronto Pearson International Airport",city:"Toronto",country:"Canada",latitude:43.6777,longitude:-79.6248),
        .init(code:"YVR",icao:"CYVR",name:"Vancouver International Airport",city:"Vancouver",country:"Canada",latitude:49.1967,longitude:-123.1815),
        .init(code:"CDG",icao:"LFPG",name:"Charles de Gaulle Airport",city:"Paris",country:"France",latitude:49.0097,longitude:2.5479),
        .init(code:"FRA",icao:"EDDF",name:"Frankfurt Airport",city:"Frankfurt",country:"Germany",latitude:50.0379,longitude:8.5622),
        .init(code:"AMS",icao:"EHAM",name:"Schiphol Airport",city:"Amsterdam",country:"Netherlands",latitude:52.3105,longitude:4.7683),
        .init(code:"IST",icao:"LTFM",name:"Istanbul Airport",city:"Istanbul",country:"Türkiye",latitude:41.2753,longitude:28.7519),
        .init(code:"KUL",icao:"WMKK",name:"Kuala Lumpur International Airport",city:"Kuala Lumpur",country:"Malaysia",latitude:2.7456,longitude:101.7072),
        .init(code:"BKK",icao:"VTBS",name:"Suvarnabhumi Airport",city:"Bangkok",country:"Thailand",latitude:13.6900,longitude:100.7501),
        .init(code:"COK",icao:"VOCI",name:"Cochin International Airport",city:"Kochi",country:"India",latitude:10.1520,longitude:76.4019),
        .init(code:"MAA",icao:"VOMM",name:"Chennai International Airport",city:"Chennai",country:"India",latitude:12.9941,longitude:80.1709),
        .init(code:"HYD",icao:"VOHS",name:"Rajiv Gandhi International Airport",city:"Hyderabad",country:"India",latitude:17.2403,longitude:78.4294),
        .init(code:"GOX",icao:"VOGA",name:"Manohar International Airport",city:"Goa",country:"India",latitude:15.7443,longitude:73.8606),
        .init(code:"JED",icao:"OEJN",name:"King Abdulaziz International Airport",city:"Jeddah",country:"Saudi Arabia",latitude:21.6796,longitude:39.1565),
        .init(code:"RUH",icao:"OERK",name:"King Khalid International Airport",city:"Riyadh",country:"Saudi Arabia",latitude:24.9576,longitude:46.6988),
        .init(code:"CPT",icao:"FACT",name:"Cape Town International Airport",city:"Cape Town",country:"South Africa",latitude:-33.9696,longitude:18.5972),
        .init(code:"ZRH",icao:"LSZH",name:"Zurich Airport",city:"Zurich",country:"Switzerland",latitude:47.4581,longitude:8.5555),
        .init(code:"MUC",icao:"EDDM",name:"Munich Airport",city:"Munich",country:"Germany",latitude:48.3538,longitude:11.7861)
    ]

    static func matching(_ search: String) -> [AirportRecord] {
        let normalized = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var records: [AirportRecord] = []
        for record in AirportRecordStore.saved() + featured where !records.contains(where: { $0.id == record.id }) {
            records.append(record)
        }
        guard !normalized.isEmpty else { return Array(records.prefix(12)) }
        return records.filter { record in
            [record.code,record.icao,record.name,record.city,record.country]
                .contains { $0.localizedCaseInsensitiveContains(normalized) }
        }.prefix(12).map { $0 }
    }

    static func searchMapKit(_ query: String) async -> [AirportRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(trimmed) airport"
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.prefix(10).compactMap { item in
            let c = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(c) else { return nil }
            let name = item.name ?? ""
            guard name.localizedCaseInsensitiveContains("airport") ||
                  name.localizedCaseInsensitiveContains("aeropuerto") ||
                  name.localizedCaseInsensitiveContains("aeroport") ||
                  name.localizedCaseInsensitiveContains("aerodrome") else { return nil }
            let letters = trimmed.uppercased()
            let code = letters.count == 3 && letters.allSatisfy(\.isLetter) ? letters : ""
            let icao = letters.count == 4 && letters.allSatisfy(\.isLetter) ? letters : ""
            return AirportRecord(code:code,icao:icao,name:name,
                                 city:item.placemark.locality ?? "",country:item.placemark.country ?? "",
                                 latitude:c.latitude,longitude:c.longitude)
        }
    }
}

enum AirportRecordStore {
    private static let key = "locus.airport.savedRecords"
    static func saved() -> [AirportRecord] {
        guard let data = UserDefaults.standard.data(forKey:key),
              let records = try? JSONDecoder().decode([AirportRecord].self,from:data) else { return [] }
        return records
    }
    static func remember(_ record: AirportRecord) {
        var records = saved()
        records.removeAll { $0.id == record.id }
        records.insert(record,at:0)
        if let data = try? JSONEncoder().encode(Array(records.prefix(100))) {
            UserDefaults.standard.set(data,forKey:key)
        }
    }
}

enum AircraftPreset: String, Codable, CaseIterable, Identifiable {
    case commercial, privateJet, turboprop
    var id: String { rawValue }
    var name: String {
        switch self {
        case .commercial: return "Commercial airliner"
        case .privateJet: return "Private jet"
        case .turboprop: return "Turboprop"
        }
    }
    var cruiseMetersPerSecond: Double {
        switch self {
        case .commercial: return 235   // ~846 km/h
        case .privateJet: return 215
        case .turboprop: return 135
        }
    }
    var takeoffMetersPerSecond: Double {
        switch self {
        case .commercial: return 78
        case .privateJet: return 67
        case .turboprop: return 51
        }
    }
}

enum AirportStageKind: String, Codable {
    case driveToAirport, taxiOut, takeoff, cruise, approach, taxiIn, driveToHotel
    var label: String {
        switch self {
        case .driveToAirport: return "Driving to airport"
        case .taxiOut: return "Departure hold / taxi"
        case .takeoff: return "Takeoff / climb"
        case .cruise: return "Cruising"
        case .approach: return "Approach / landing"
        case .taxiIn: return "Taxi to terminal"
        case .driveToHotel: return "Driving to destination"
        }
    }
    var accel: Double {
        switch self {
        case .driveToAirport, .driveToHotel: return 1.8
        case .taxiOut, .taxiIn: return 1.1
        case .takeoff: return 4.0
        case .cruise: return 5.5
        case .approach: return 4.0
        }
    }
    var braking: Double { self == .cruise ? 4 : 2.5 }
}

struct AirportJourneyStage {
    var kind: AirportStageKind
    var endDistance: Double
    var speed: Double
    var holdBeforeSeconds: Double
}

struct AirportGeneratedPlan {
    var departure: AirportRecord
    var destination: AirportRecord
    var aircraft: AircraftPreset
    var departureTerminal: String
    var arrivalTerminal: String
    var departureGate: String
    var arrivalGate: String
    var route: [CLLocationCoordinate2D]
    var stages: [AirportJourneyStage]
    var approximateSeconds: Double

    var distance: Double { stages.last?.endDistance ?? 0 }
}

enum AirportPlanBuilder {
    static func build(departure: AirportRecord, destination: AirportRecord, aircraft: AircraftPreset,
                      departureAddress: String, arrivalAddress: String,
                      departureHold: Double, arrivalHold: Double,
                      departureTerminal: String, arrivalTerminal: String,
                      departureGate: String, arrivalGate: String) async throws -> AirportGeneratedPlan {
        let origin = MotionPoint(departure.coordinate)
        let dest = MotionPoint(destination.coordinate)
        let flightDistance = origin.distance(to: dest)
        guard flightDistance > 10_000 else {
            throw NSError(domain:"LocusAirport",code:1,userInfo:[NSLocalizedDescriptionKey:
                "Choose two different airports at least 10 km apart."])
        }
        var route: [CLLocationCoordinate2D] = []
        var stages: [AirportJourneyStage] = []
        var total = 0.0
        var estimate = 0.0

        func append(_ coords: [CLLocationCoordinate2D], kind: AirportStageKind, speed: Double, hold: Double = 0) {
            guard coords.count > 1 else { return }
            let next = RouteGeometry.joined([route.map(MotionPoint.init),coords.map(MotionPoint.init)]).map(\.coordinate)
            guard next.count >= 2 else { return }
            let distance = RoutePlayback(points: next.map(MotionPoint.init))?.totalDistance ?? total
            guard distance > total + 0.1 else { return }
            estimate += (distance - total) / max(speed * 0.72,1) + hold
            total = distance
            route = next
            stages.append(.init(kind:kind,endDistance:total,speed:speed,holdBeforeSeconds:hold))
        }
        func road(_ location: String, near airport: AirportRecord) async throws -> CLLocationCoordinate2D? {
            let query = location.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return nil }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(center:airport.coordinate,latitudinalMeters:100_000,longitudinalMeters:100_000)
            guard let response = try? await MKLocalSearch(request:request).start(),
                  let item = response.mapItems.first else {
                throw NSError(domain:"LocusAirport",code:2,userInfo:[NSLocalizedDescriptionKey:
                    "Could not find transfer location: \(query). Leave the field empty to skip it."])
            }
            return item.placemark.coordinate
        }
        let startTransfer = try await road(departureAddress, near:departure)
        let endTransfer = try await road(arrivalAddress, near:destination)
        if let startTransfer {
            let coords = try await RouteBuilder.roadRoute(from:startTransfer,to:departure.coordinate,transportType:.automobile)
            append(coords,kind:.driveToAirport,speed:14)
        }

        // A synthetic terminal-centre/taxi/runway approximation. It deliberately
        // does NOT claim real taxiways, runway thresholds, gates or ATC routes.
        let taxiEnd = origin.interpolated(to:dest,fraction:min(0.15, 800 / flightDistance))
        let takeoffEnd = origin.interpolated(to:dest,fraction:min(0.23, 6000 / flightDistance))
        let approachStart = origin.interpolated(to:dest,fraction:max(0.52, 1 - 28_000 / flightDistance))
        let landingEnd = origin.interpolated(to:dest,fraction:max(0.76, 1 - 800 / flightDistance))

        append([origin.coordinate,taxiEnd.coordinate],kind:.taxiOut,speed:8,
               hold:max(0,departureHold) * 60)
        append(sample(taxiEnd,to:takeoffEnd,every:150),kind:.takeoff,speed:aircraft.takeoffMetersPerSecond)
        append(sample(takeoffEnd,to:approachStart,every:15_000),kind:.cruise,speed:aircraft.cruiseMetersPerSecond)
        append(sample(approachStart,to:landingEnd,every:800),kind:.approach,
               speed:min(aircraft.cruiseMetersPerSecond * 0.55,90))
        append([landingEnd.coordinate,dest.coordinate],kind:.taxiIn,speed:8)
        if let endTransfer {
            let coords = try await RouteBuilder.roadRoute(from:destination.coordinate,to:endTransfer,transportType:.automobile)
            append(coords,kind:.driveToHotel,speed:14,hold:max(0,arrivalHold) * 60)
        }
        guard route.count >= 2, !stages.isEmpty else {
            throw NSError(domain:"LocusAirport",code:3,userInfo:[NSLocalizedDescriptionKey:"Unable to create the airport route."])
        }
        return .init(departure:departure,destination:destination,aircraft:aircraft,
                     departureTerminal:departureTerminal,arrivalTerminal:arrivalTerminal,
                     departureGate:departureGate,arrivalGate:arrivalGate,
                     route:route,stages:stages,approximateSeconds:estimate)
    }

    private static func sample(_ start: MotionPoint, to end: MotionPoint, every metres: Double) -> [CLLocationCoordinate2D] {
        let count = max(1,Int(ceil(start.distance(to:end) / metres)))
        return (0...count).map { start.interpolated(to:end,fraction:Double($0)/Double(count)).coordinate }
    }
}

struct AirportIntelligenceSheet: View {
    var onGenerate: (AirportGeneratedPlan, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("locus.airport.favoriteCodes") private var favoriteCodes = "DEL,DXB,DOH"
    @AppStorage("locus.airport.recentCodes") private var recentCodes = ""
    @State private var departure: AirportRecord? = AirportRecord.featured.first
    @State private var destination: AirportRecord? = AirportRecord.featured.dropFirst().first
    @State private var aircraft = AircraftPreset.commercial
    @State private var departureAddress = ""
    @State private var arrivalAddress = ""
    @State private var departureTerminal = ""
    @State private var arrivalTerminal = ""
    @State private var departureGate = ""
    @State private var arrivalGate = ""
    @State private var departureHold = 15.0
    @State private var arrivalHold = 10.0
    @State private var startImmediately = false
    @State private var building = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Airports") {
                    AirportSelectionRow(title:"Departure airport",airport:$departure,
                                        favorites:$favoriteCodes,recents:$recentCodes)
                    AirportSelectionRow(title:"Destination airport",airport:$destination,
                                        favorites:$favoriteCodes,recents:$recentCodes)
                    if let departure, let destination {
                        let metres = MotionPoint(departure.coordinate).distance(to: MotionPoint(destination.coordinate))
                        LabeledContent("Air distance",value:String(format:"%.0f km",metres/1000))
                        let flightHours = metres / aircraft.cruiseMetersPerSecond / 3600 + 0.25
                        LabeledContent("Flight estimate",value:String(format:"~%.1f hours",flightHours))
                    }
                }
                Section("Aircraft") {
                    Picker("Aircraft profile",selection:$aircraft) {
                        ForEach(AircraftPreset.allCases) { preset in Text(preset.name).tag(preset) }
                    }
                    LabeledContent("Cruise speed",value:String(format:"%.0f km/h",aircraft.cruiseMetersPerSecond*3.6))
                }
                Section("Departure airport") {
                    TextField("Terminal (optional)",text:$departureTerminal)
                    TextField("Gate label (optional)",text:$departureGate)
                    Stepper(value:$departureHold,in:0...90,step:5) {
                        Text("Departure hold: \(Int(departureHold)) min")
                    }
                }
                Section("Arrival airport") {
                    TextField("Terminal (optional)",text:$arrivalTerminal)
                    TextField("Gate label (optional)",text:$arrivalGate)
                    Stepper(value:$arrivalHold,in:0...90,step:5) {
                        Text("Transfer hold: \(Int(arrivalHold)) min")
                    }
                }
                Section("Optional full journey") {
                    TextField("Before flight: hotel / address",text:$departureAddress)
                        .textInputAutocapitalization(.words)
                    TextField("After flight: hotel / address",text:$arrivalAddress)
                        .textInputAutocapitalization(.words)
                    Text("Leave either field empty to start or finish at the airport. Addresses are resolved using Apple Maps; ground transfers use driving routes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Journey controls") {
                    Toggle("Start immediately after building",isOn:$startImmediately)
                    Button {
                        Task { await generate() }
                    } label: {
                        Label("Generate complete airport journey",systemImage:"airplane.departure")
                            .frame(maxWidth:.infinity)
                    }
                    .disabled(building || departure == nil || destination == nil || departure?.id == destination?.id)
                    if building { ProgressView("Finding transfers and building flight...") }
                    if let errorText { Text(errorText).font(.footnote).foregroundStyle(.red) }
                }
                Section("Simulation accuracy") {
                    Text("Airport-centre coordinates, synthetic taxi/runway movements, approximate aircraft performance and estimated altitude are for simulation only. Gate and terminal labels are descriptive; they do not establish real gate locations. Flight routes are great-circle approximations, not published ATC routes.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Locus's developer-location backend injects coordinates, not aircraft speed or barometric altitude. Other apps determine how location information is displayed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Airport Intelligence")
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @MainActor
    private func generate() async {
        guard let departure, let destination, !building else { return }
        building = true
        errorText = nil
        defer { building = false }
        do {
            let plan = try await AirportPlanBuilder.build(departure:departure,destination:destination,aircraft:aircraft,
                departureAddress:departureAddress,arrivalAddress:arrivalAddress,
                departureHold:departureHold,arrivalHold:arrivalHold,
                departureTerminal:departureTerminal,arrivalTerminal:arrivalTerminal,
                departureGate:departureGate,arrivalGate:arrivalGate)
            recentCodes = ([departure.id,destination.id] + recentCodes.split(separator:",").map(String.init))
                .reduce(into:[String]()) { result, code in if !result.contains(code) { result.append(code) } }
                .prefix(12).joined(separator:",")
            onGenerate(plan,startImmediately)
            dismiss()
        } catch { errorText = error.localizedDescription }
    }
}

private struct AirportSelectionRow: View {
    var title: String
    @Binding var airport: AirportRecord?
    @Binding var favorites: String
    @Binding var recents: String
    @State private var showPicker = false

    var body: some View {
        HStack(spacing:8) {
            Button { showPicker = true } label: {
                HStack {
                    VStack(alignment:.leading,spacing:3) {
                        Text(title).font(.caption).foregroundStyle(.secondary)
                        Text(airport?.displayName ?? "Choose airport")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        if let airport { Text("\(airport.city), \(airport.country)").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Image(systemName:"chevron.right").foregroundStyle(.tertiary)
                }
            }.buttonStyle(.plain)
            if let airport {
                Button {
                    var codes = favorites.split(separator:",").map(String.init)
                    if codes.contains(airport.id) { codes.removeAll { $0 == airport.id } }
                    else { codes.insert(airport.id,at:0); AirportRecordStore.remember(airport) }
                    favorites = codes.joined(separator:",")
                } label: {
                    Image(systemName:favorites.split(separator:",").contains(Substring(airport.id)) ? "star.fill":"star")
                }
                .accessibilityLabel("Toggle favourite airport")
            }
        }
        .sheet(isPresented:$showPicker) {
            AirportPickerSheet(title:title,selected:$airport,favorites:favorites,recents:recents)
        }
    }
}

private struct AirportPickerSheet: View {
    let title: String
    @Binding var selected: AirportRecord?
    var favorites: String
    var recents: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var mapResults: [AirportRecord] = []
    @State private var searching = false

    private var curated: [AirportRecord] {
        let matches = AirportRecord.matching(query)
        let preferred = (favorites + "," + recents).split(separator:",").map(String.init)
        return matches.sorted { a,b in
            let x = preferred.firstIndex(of:a.id) ?? Int.max
            let y = preferred.firstIndex(of:b.id) ?? Int.max
            return x == y ? a.city < b.city : x < y
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Airport name, city, IATA or ICAO",text:$query)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    Button {
                        Task { await searchWorldwide() }
                    } label: {
                        Label("Search more airports using Apple Maps",systemImage:"magnifyingglass")
                    }
                    .disabled(searching || query.trimmingCharacters(in:.whitespacesAndNewlines).count < 2)
                    if searching { ProgressView() }
                }
                Section("Available airports") {
                    ForEach(curated) { item in airportRow(item) }
                }
                if !mapResults.isEmpty {
                    Section("Apple Maps results — verify before choosing") {
                        ForEach(mapResults) { item in airportRow(item) }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func airportRow(_ record: AirportRecord) -> some View {
        Button {
            selected = record
            AirportRecordStore.remember(record)
            dismiss()
        } label: {
            VStack(alignment:.leading,spacing:3) {
                HStack {
                    if !(record.code.isEmpty && record.icao.isEmpty) {
                        Text(record.code.isEmpty ? record.icao : record.code).font(.headline.monospaced())
                    }
                    Text(record.name).font(.subheadline)
                }
                Text("\(record.city), \(record.country)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
    }
    @MainActor private func searchWorldwide() async {
        searching = true
        defer { searching = false }
        mapResults = await AirportRecord.searchMapKit(query)
    }
}
