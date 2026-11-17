import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store: TodoStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        let f = settings.fullness(for: store.activeCount)
        let accent = Palette.color(f)
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                PlasmaView(fullness: f, radius: 0.55...0.7, glow: true, fps: 60)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("tom").font(.system(size: 26, weight: .heavy, design: .rounded))
                    Text("top of mind").font(.system(size: 13, design: .rounded)).foregroundStyle(.secondary)
                }
            }

            section("Orb position") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(OrbPlacement.allCases) { p in
                        PlacementCard(placement: p, selected: settings.placement == p, accent: accent)
                            .onTapGesture { withAnimation(.spring(response: 0.3)) { settings.placement = p } }
                    }
                }
                .opacity(settings.hidden ? 0.4 : 1)
            }

            section("Behavior") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $settings.hidden) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Invisible mode")
                            Text("No orb at all. Summon tom with the hotkey only.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Hotkey")
                        Spacer()
                        HotKeyRecorder(settings: settings)
                    }
                    if let e = settings.hotKeyError {
                        Text(e).font(.caption).foregroundStyle(.red)
                    }
                    Stepper(value: $settings.fullAt, in: 3...25) {
                        HStack {
                            Text("Orb is full at")
                            Text("\(settings.fullAt) items").foregroundStyle(accent).bold()
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Visuals", selection: $settings.quality) {
                            ForEach(VisualQuality.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text(settings.quality == .candy
                             ? "Full plasma, Retina resolution, up to 60fps."
                             : "Lighter shaders, 1x resolution, 30fps. For older Macs.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Sounds", isOn: $settings.soundOn)
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, on in
                            do {
                                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                                loginError = nil
                            } catch {
                                loginError = "Needs the bundled Tom.app: \(error.localizedDescription)"
                            }
                        }
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.red)
                    }
                }
                .toggleStyle(.switch)
            }
        }
        .padding(26)
        .frame(width: 460)
        .tint(accent)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)
            content()
        }
    }
}

struct PlacementCard: View {
    let placement: OrbPlacement
    let selected: Bool
    let accent: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 7)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7, style: .continuous))
                marker
            }
            .frame(height: 62)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? accent : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1)
            )
            Text(placement.title)
                .font(.system(size: 11, weight: selected ? .semibold : .regular, design: .rounded))
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var marker: some View {
        let dot = Circle().fill(RadialGradient(colors: [.white, accent], center: .center, startRadius: 0, endRadius: 5))
            .frame(width: 9, height: 9).shadow(color: accent, radius: 4)
        switch placement {
        case .menuBar:
            HStack { Spacer(); dot.scaleEffect(0.7) }.padding(.trailing, 14).frame(height: 7)
        default:
            VStack {
                if placement.growsUp { Spacer() }
                HStack {
                    if !placement.isLeft { Spacer() }
                    dot
                    if placement.isLeft { Spacer() }
                }
                if !placement.growsUp { Spacer() }
            }
            .padding(.horizontal, 7)
            .padding(.top, 12)
            .padding(.bottom, 6)
        }
    }
}

struct HotKeyRecorder: View {
    @Bindable var settings: AppSettings
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "press keys…" : settings.hotKey.display)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(minWidth: 90)
                .padding(.vertical, 3)
        }
        .buttonStyle(.bordered)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil }
            if let combo = HotKeyCombo.from(e) {
                settings.hotKey = combo
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            HotKeyCenter.shared.resume()
        }
    }
}
