import SwiftUI

struct Shockwave: Identifiable {
    let id = UUID()
    let center: CGPoint
    let color: Color
}

@MainActor @Observable
final class PanelModel {
    let store: TodoStore
    let settings: AppSettings

    var expanded = false
    var isOpen = false
    var geometry = PanelGeometry()
    var contentHeight: CGFloat = 220
    var selection: UUID?
    var editing: UUID?
    var completing: Set<UUID> = []
    var burning: Set<UUID> = []
    var shockwaves: [Shockwave] = []
    var justAdded: UUID?
    var showDone = false
    var focusInput = 0

    @ObservationIgnored var rowFrames: [UUID: CGRect] = [:]
    @ObservationIgnored var dragging: UUID?
    @ObservationIgnored weak var overlay: ParticleOverlayView?
    @ObservationIgnored var backingScale: CGFloat = 2
    @ObservationIgnored var requestClose: () -> Void = {}
    @ObservationIgnored var requestSettings: () -> Void = {}

    init(store: TodoStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    var fullness: Double { settings.fullness(for: store.activeCount) }
    var accent: Color { Palette.color(fullness) }

    var visibleActive: [TodoItem] { store.active }

    // MARK: actions

    func add(_ text: String) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.7)) {
            if let item = store.add(text) { justAdded = item.id }
        }
        SoundFX.shared.add(enabled: settings.soundOn)
    }

    func moveSelection(_ delta: Int) {
        let act = store.active.filter { !completing.contains($0.id) }
        guard !act.isEmpty else { selection = nil; return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            if let sel = selection, let i = act.firstIndex(where: { $0.id == sel }) {
                let ni = i + delta
                selection = ni < 0 ? nil : act[min(ni, act.count - 1)].id
            } else {
                selection = delta > 0 ? act.first?.id : act.last?.id
            }
        }
    }

    func shiftSelection(_ delta: Int) {
        guard let sel = selection else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { store.shift(sel, by: delta) }
    }

    func completeSelectedOrFirst() {
        if let id = selection ?? store.active.first(where: { !completing.contains($0.id) })?.id { complete(id) }
    }

    func deleteSelected() {
        guard let id = selection else { return }
        delete(id)
    }

    func delete(_ id: UUID) {
        if selection == id { selection = neighbor(of: id) }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { store.delete(id) }
    }

    func restore(_ id: UUID) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            store.restore(id)
            justAdded = id
        }
        SoundFX.shared.add(enabled: settings.soundOn)
    }

    /// Check -> chime + shockwave -> cinematic disintegration -> collapse.
    func complete(_ id: UUID) {
        guard !completing.contains(id),
              let item = store.items.first(where: { $0.id == id }), item.completedAt == nil else { return }
        let accentNow = accent
        withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { _ = completing.insert(id) }
        SoundFX.shared.done(enabled: settings.soundOn)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        if let f = rowFrames[id] {
            let wave = Shockwave(center: CGPoint(x: f.minX + 22, y: f.midY), color: accentNow)
            shockwaves.append(wave)
            after(1.0) { [weak self] in self?.shockwaves.removeAll { $0.id == wave.id } }
        }
        after(0.26) { [weak self] in self?.disintegrate(item, accent: accentNow) }
    }

    private func disintegrate(_ item: TodoItem, accent: Color) {
        if isOpen, let f = rowFrames[item.id], let overlay {
            let row = TodoRowContent(text: item.text, checked: true, accent: accent)
                .frame(width: f.width, height: f.height)
                .environment(\.colorScheme, NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
            let r = ImageRenderer(content: row)
            r.scale = backingScale
            if let cg = r.cgImage { overlay.burst(image: cg, frame: f, scale: backingScale) }
        }
        burning.insert(item.id)
        after(0.7) { [weak self] in
            guard let self else { return }
            if selection == item.id { selection = neighbor(of: item.id) }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                self.store.complete(item.id)
            }
            completing.remove(item.id)
            burning.remove(item.id)
            rowFrames[item.id] = nil
        }
    }

    private func neighbor(of id: UUID) -> UUID? {
        let act = store.active.filter { !completing.contains($0.id) || $0.id == id }
        guard let i = act.firstIndex(where: { $0.id == id }) else { return nil }
        if i + 1 < act.count { return act[i + 1].id }
        if i > 0 { return act[i - 1].id }
        return nil
    }
}
