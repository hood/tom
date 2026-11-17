import SwiftUI

struct PanelContent: View {
    let model: PanelModel
    @State private var draft = ""
    @State private var listHeight: CGFloat = 0
    @FocusState private var inputFocused: Bool

    private var store: TodoStore { model.store }
    private var up: Bool { model.geometry.growsUp }

    var body: some View {
        let accent = model.accent
        VStack(alignment: .leading, spacing: 10) {
            header(accent).reveal(model.bloom, 0, fromBelow: up)
            input(accent).reveal(model.bloom, 1, fromBelow: up)
            if store.active.isEmpty {
                emptyState(accent).reveal(model.bloom, 2, fromBelow: up)
            } else {
                list(accent)
            }
            doneSection(accent).reveal(model.bloom, store.activeCount + 2, fromBelow: up)
            hints.reveal(model.bloom, store.activeCount + 3, fromBelow: up)
        }
        .padding(12)
        .frame(width: PanelGeometry.width)
        .onChange(of: model.focusInput) { inputFocused = true }
        .onAppear { inputFocused = true }
    }

    // MARK: pieces

    private func header(_ accent: Color) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Top of mind")
                .font(.system(size: 13, weight: .semibold))
            if store.activeCount > 0 {
                Text("\(store.activeCount)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(accent)
            }
            Spacer()
            if store.doneCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                    Text("\(store.doneCount)").contentTransition(.numericText())
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .phaseAnimator([1.0, 1.35, 1.0], trigger: store.doneCount) { v, s in v.scaleEffect(s) } animation: { _ in
                    .spring(response: 0.25, dampingFraction: 0.5)
                }
                .help("done today")
            }
            Menu {
                Button("Settings…") { model.requestSettings() }
                Divider()
                Button("Quit tom") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func input(_ accent: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("", text: $draft, prompt: Text("What's on your mind?"))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($inputFocused)
                .onSubmit(submit)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.quaternary.opacity(0.6)))
    }

    private func list(_ accent: Color) -> some View {
        let maxList = max(120, model.geometry.maxHeight - 200)
        return ScrollView(.vertical) {
            VStack(spacing: 2) {
                ForEach(Array(store.active.enumerated()), id: \.element.id) { i, item in
                    TodoRow(item: item, model: model, accent: accent)
                        .reveal(model.bloom, min(i, 10) + 2, fromBelow: up)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.96))))
                }
            }
            .padding(.vertical, 2)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { listHeight = $0 }
        }
        .scrollIndicators(.never)
        .frame(height: min(max(listHeight, 1), maxList))
    }

    private func emptyState(_ accent: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.breathe, options: .repeating)
            Text("Mind clear")
                .font(.system(size: 13, weight: .semibold))
            Text("Nothing on your plate.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    @ViewBuilder private func doneSection(_ accent: Color) -> some View {
        let done = store.doneToday
        if !done.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { model.showDone.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(model.showDone ? 90 : 0))
                        Text("Done today")
                        Text("\(done.count)").contentTransition(.numericText()).monospacedDigit()
                        Spacer()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if model.showDone {
                    ForEach(done.prefix(8)) { item in
                        DoneRow(item: item, model: model, accent: accent)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private var hints: some View {
        HStack(spacing: 10) {
            hint("⏎", "add")
            hint("↑↓", "select")
            hint("⌘⏎", "done")
            hint("⌘⌫", "delete")
            hint("esc", "close")
        }
        .frame(maxWidth: .infinity)
    }

    private func hint(_ k: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(k).fontWeight(.medium)
            Text(label)
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
    }

    private func submit() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            if model.selection != nil { model.completeSelectedOrFirst() }
            return
        }
        model.add(t)
        draft = ""
        inputFocused = true
    }
}
