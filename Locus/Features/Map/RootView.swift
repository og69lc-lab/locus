import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct RootView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @State private var showSettings = false
    @State private var showPlaces = false
    @State private var showJourney = false

    var body: some View {
        // Bottom chrome is a sibling overlay aligned to the bottom — no full-screen
        // Spacer layer that can steal / pass map taps through the tray.
        ZStack(alignment: .bottom) {
            MapHomeView(onOpenSettings: { showSettings = true })

            BottomControlsView(
                showSettings: $showSettings,
                showPlaces: $showPlaces,
                showJourney: $showJourney
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showJourney) { JourneyAutopilotView() }
        .sheet(isPresented: $showPlaces) {
            PlacesView()
        }
        .alert("Locus", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
    }
}

struct StatusBarView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var tunnel: DeveloperTunnelMonitor
    var onOpenSettings: () -> Void

    private enum Display {
        case notSpoofing
        case tunnelUnavailable
        case status(String)
    }

    private var display: Display {
        switch session.status {
        case .idle:
            return tunnel.probe.availability == .reachable ? .notSpoofing : .tunnelUnavailable
        case .connecting:
            return .status(String(localized: "Connecting…"))
        case .active:
            if session.routeSimulation.phase == .paused { return .status(String(localized: "Route paused")) }
            if session.routeSimulation.phase == .running { return .status(String(localized: "Route running")) }
            return .status(String(localized: "Spoofing"))
        case .reconnecting:
            return .status(String(localized: "Reconnecting…"))
        case .dropped(let reason):
            return .status(reason.isEmpty ? String(localized: "Disconnected") : String(format: String(localized: "Disconnected — %@"), reason))
        }
    }

    private var color: Color {
        switch display {
        case .notSpoofing:
            return Color.primary.opacity(0.55)
        case .tunnelUnavailable:
            return LocusTheme.statusWarn
        case .status:
            switch session.status {
            case .active: return LocusTheme.statusGood
            case .connecting, .reconnecting: return LocusTheme.statusWarn
            case .dropped: return LocusTheme.statusBad
            case .idle: return Color.primary.opacity(0.55)
            }
        }
    }

    private var title: String {
        switch display {
        case .notSpoofing: return String(localized: "Not Spoofing")
        case .tunnelUnavailable:
            return tunnel.statusLabel
        case .status(let text): return text
        }
    }

    var body: some View {
        Group {
            if case .tunnelUnavailable = display {
                Button(action: onOpenSettings) {
                    statusContent
                }
                .buttonStyle(.plain)
            } else {
                statusContent
            }
        }
    }

    private var statusContent: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.7), radius: 4)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if case .tunnelUnavailable = display {
                Image(systemName: "lock.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LocusTheme.accent)
            } else if case .active = session.status, let sim = session.simulated {
                Text(String(format: "%.4f, %.4f", sim.latitude, sim.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .locusGlass(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct BottomControlsView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Binding var showSettings: Bool
    @Binding var showPlaces: Bool
    @Binding var showJourney: Bool

    private let trayShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        VStack(spacing: 12) {
            if session.joystickActive {
                JoystickPad { vector in
                    session.updateJoystick(vector: vector)
                }
                .frame(width: 148, height: 148)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if session.routeSimulation.phase != .idle {
                RoutePlaybackControls()
            }

            Button { showJourney = true } label: {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                    Text(session.journeyEnabled ? session.journeyActivity : "Journey Autopilot").lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                }.font(.subheadline.weight(.semibold)).padding(10)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius:12))
            }.buttonStyle(.plain)
            SpeedControls()

            HStack(spacing: 10) {
                trayIcon("gearshape.fill") { showSettings = true }
                    .accessibilityLabel(String(localized: "Settings"))
                trayIcon("star.fill") { showPlaces = true }
                    .accessibilityLabel(String(localized: "Places"))

                Button {
                    if session.joystickActive {
                        session.stopJoystick()
                    } else {
                        session.startJoystick(pairing: pairing)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "dot.circle.and.hand.point.up.left.fill")
                        Text(session.joystickActive ? String(localized: "On") : String(localized: "Joy"))
                            .lineLimit(1)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(session.joystickActive ? .black : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(session.joystickActive ? LocusTheme.accentSecondary : Color.primary.opacity(0.08))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                if session.isSpoofing || session.isBusy {
                    Button {
                        session.stop(pairing: pairing)
                    } label: {
                        Text(String(localized: "End spoofing short"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 72)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 8)
                            .background(Capsule().fill(LocusTheme.danger))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "End spoofing"))
                    .accessibilityHint(String(localized: "Restores the real device location."))
                } else {
                    Button {
                        guard let pin = session.pin else {
                            session.lastError = String(localized: "Tap the map to drop a pin first.")
                            return
                        }
                        session.teleport(to: pin, pairing: pairing)
                    } label: {
                        Text(String(localized: "Teleport"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(minWidth: 96)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 10)
                            .background(Capsule().fill(LocusTheme.accent))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isBusy)
                }
            }
        }
        .padding(14)
        .locusGlass(.regular, in: trayShape)
        // Whole tray absorbs taps so near-misses don't fall through to the map.
        .contentShape(trayShape)
    }

    private func trayIcon(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct IconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .locusGlass(.interactive, in: Circle())
        .foregroundStyle(.primary)
    }
}

struct JourneyAutopilotView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section("Import") {
                    Text("Scheduled GPS simulation. Import a planned itinerary, not an observed travel record.").font(.footnote).foregroundStyle(.secondary)
                    Button("Import Journey JSON") { importing = true }.disabled(session.journeyEnabled)
                    Button("Paste Journey JSON") {
                        guard let text = UIPasteboard.general.string else { error = "Clipboard is empty."; return }
                        load(Data(text.utf8))
                    }.disabled(session.journeyEnabled)
                }
                if let plan = session.journeyPlan {
                    Section("Journey") {
                        Text(plan.title).font(.headline)
                        Text("\(plan.legs.count) activities · \(session.status.label)")
                        Text(session.journeyActivity.isEmpty ? "Ready" : session.journeyActivity).foregroundStyle(.secondary)
                        if session.journeyEnabled {
                            if session.journeyPaused || session.status != .active {
                                Button("Resume at scheduled time") { session.resumeJourney(pairing:pairing) }.disabled(session.isBusy)
                            } else {
                                Button("Pause") { session.pauseJourney() }
                            }
                            Button("Stop and restore real GPS",role:.destructive) { session.stop(pairing:pairing) }
                        } else {
                            Button("Start / resume journey") { session.startJourney(pairing:pairing) }.disabled(session.isBusy)
                        }
                    }
                    Section("Itinerary") {
                        ForEach(plan.legs) { leg in
                            VStack(alignment:.leading,spacing:4) {
                                Text(leg.title).font(.headline)
                                Text("\(leg.mode.capitalized) · \(format(leg.start,leg.zone)) – \(format(leg.end,leg.zone))").font(.caption).foregroundStyle(.secondary)
                                if let notes = leg.notes { Text(notes).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                Section("Background & safety") {
                    Text("The clock continues while paused. When resumed, missed movement may be skipped. Keep the developer tunnel connected. iOS can suspend the app; after force quit, reopen and tap Start / resume. At completion the app attempts to restore real GPS. Never use simulated coordinates for navigation, emergencies or proof of travel.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Journey Autopilot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented:$importing,allowedContentTypes:[.json],allowsMultipleSelection:false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                    guard size <= JourneyPlan.maxBytes else { throw JourneyError.invalid("File exceeds 2 MB.") }
                    load(try Data(contentsOf:url))
                } catch { self.error = error.localizedDescription }
            }
            .alert("Journey Autopilot",isPresented:Binding(get:{error != nil},set:{if !$0 {error = nil}})) {
                Button("OK",role:.cancel) {error = nil}
            } message: { Text(error ?? "") }
        }
    }
    private func load(_ data:Data) { do {try session.importJourney(data)} catch {self.error = error.localizedDescription} }
    private func format(_ date:Date,_ zone:TimeZone) -> String {
        let f = DateFormatter(); f.timeZone = zone; f.dateFormat = "MMM d, HH:mm z"; return f.string(from:date)
    }
}
