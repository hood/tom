import Foundation
import Observation

struct TodoItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var text: String
    var createdAt: Date = Date()
    var completedAt: Date? = nil
}

@MainActor @Observable
final class TodoStore {
    private(set) var items: [TodoItem] = []
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tom", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("items.json")
        load()
    }

    var active: [TodoItem] { items.filter { $0.completedAt == nil } }
    var doneToday: [TodoItem] {
        items.filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
    var activeCount: Int { items.reduce(0) { $0 + ($1.completedAt == nil ? 1 : 0) } }
    var doneCount: Int { items.count - activeCount }
    var isFirstLaunch: Bool { !FileManager.default.fileExists(atPath: fileURL.path) }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        items = (try? dec.decode([TodoItem].self, from: data)) ?? []
        purgeOld()
    }

    /// Done items only live until midnight.
    func purgeOld() {
        let start = Calendar.current.startOfDay(for: Date())
        let before = items.count
        items.removeAll { ($0.completedAt ?? .distantFuture) < start }
        if items.count != before { save() }
    }

    @discardableResult
    func add(_ raw: String, atEnd: Bool = false) -> TodoItem? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let item = TodoItem(text: text)
        if atEnd { items.append(item) } else { items.insert(item, at: 0) }
        save()
        return item
    }

    func complete(_ id: UUID) { mutate(id) { $0.completedAt = Date() } }

    func restore(_ id: UUID) {
        guard let i = index(id) else { return }
        var item = items.remove(at: i)
        item.completedAt = nil
        items.insert(item, at: 0)
        save()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func update(_ id: UUID, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        mutate(id) { $0.text = t }
    }

    /// Live reorder: moving down lands after target, moving up lands before it.
    func move(_ id: UUID, onto target: UUID) {
        guard id != target, let from = index(id), let to = index(target) else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)
        save()
    }

    func shift(_ id: UUID, by delta: Int) {
        let act = active
        guard let pos = act.firstIndex(where: { $0.id == id }), act.indices.contains(pos + delta) else { return }
        move(id, onto: act[pos + delta].id)
    }

    func flush() {
        pendingSave?.cancel()
        writeNow()
    }

    private func index(_ id: UUID) -> Int? { items.firstIndex { $0.id == id } }

    private func mutate(_ id: UUID, _ f: (inout TodoItem) -> Void) {
        guard let i = index(id) else { return }
        f(&items[i])
        save()
    }

    private func save() {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }

    private func writeNow() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
