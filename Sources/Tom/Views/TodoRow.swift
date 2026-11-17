import SwiftUI

struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.12, y: r.midY + r.height * 0.02))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.40, y: r.maxY - r.height * 0.14))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.08, y: r.minY + r.height * 0.16))
        return p
    }
}

struct CheckCircle: View {
    var checked: Bool
    var accent: Color

    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.secondary.opacity(checked ? 0 : 0.6), lineWidth: 1.2)
            Circle()
                .fill(accent)
                .scaleEffect(checked ? 1 : 0.01)
                .opacity(checked ? 1 : 0)
            CheckShape()
                .trim(from: 0, to: checked ? 1 : 0)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .padding(4.5)
        }
        .frame(width: 16, height: 16)
    }
}

/// Pure visual of a row. Also rendered offscreen as the source image for the dissolve.
struct TodoRowContent: View {
    let text: String
    var checked: Bool
    var hovered = false
    var selected = false
    var accent: Color
    var age: String? = nil

    var body: some View {
        HStack(spacing: 9) {
            CheckCircle(checked: checked, accent: accent)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(checked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .strikethrough(checked)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let age {
                Text(age)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? AnyShapeStyle(accent.opacity(0.22)) : AnyShapeStyle(Color.primary.opacity(hovered ? 0.07 : 0)))
        )
    }
}

struct TodoRow: View {
    let item: TodoItem
    let model: PanelModel
    let accent: Color

    @State private var hovering = false
    @State private var editText = ""
    @State private var shimmer: CGFloat = -0.5
    @FocusState private var editFocused: Bool

    private var isEditing: Bool { model.editing == item.id }

    var body: some View {
        Group {
            if isEditing { editor } else { display }
        }
        .opacity(model.burning.contains(item.id) ? 0 : 1)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("root")) }) { model.rowFrames[item.id] = $0 }
        .onHover { hovering = $0 }
        .onDrag {
            model.dragging = item.id
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: RowDropDelegate(target: item.id, model: model))
        .contextMenu {
            Button("Edit") { model.editing = item.id }
            Button("Done") { model.complete(item.id) }
            Divider()
            Button("Delete", role: .destructive) { model.delete(item.id) }
        }
    }

    private var display: some View {
        TodoRowContent(text: item.text, checked: model.completing.contains(item.id), hovered: hovering,
                       selected: model.selection == item.id, accent: accent, age: Self.age(item.createdAt))
            .overlay {
                // sibling hit areas: the dot fires instantly, the double-click to edit can't delay it
                HStack(spacing: 0) {
                    Button { model.complete(item.id) } label: {
                        Color.clear.frame(width: 32).frame(maxHeight: .infinity).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { model.editing = item.id }
                }
            }
            .overlay(alignment: .trailing) {
                if hovering && !model.completing.contains(item.id) {
                    Button { model.delete(item.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay { shimmerOverlay }
    }

    private var editor: some View {
        HStack(spacing: 9) {
            CheckCircle(checked: false, accent: accent)
            TextField("", text: $editText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($editFocused)
                .onSubmit {
                    model.store.update(item.id, text: editText)
                    model.editing = nil
                    model.focusInput += 1
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.07)))
        .onAppear {
            editText = item.text
            editFocused = true
        }
    }

    @ViewBuilder private var shimmerOverlay: some View {
        if model.justAdded == item.id {
            GeometryReader { g in
                LinearGradient(colors: [.clear, accent.opacity(0.25), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 90)
                    .offset(x: shimmer * g.size.width)
                    .blendMode(.plusLighter)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .allowsHitTesting(false)
            .onAppear {
                shimmer = -0.4
                withAnimation(.easeInOut(duration: 0.9).delay(0.1)) { shimmer = 1.2 }
                after(1.1) { if model.justAdded == item.id { model.justAdded = nil } }
            }
        }
    }

    static func age(_ d: Date) -> String? {
        let days = Int(Date().timeIntervalSince(d) / 86400)
        return days >= 1 ? "\(days)d" : nil
    }
}

struct RowDropDelegate: DropDelegate {
    let target: UUID
    let model: PanelModel

    func dropEntered(info: DropInfo) {
        guard let d = model.dragging, d != target else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.store.move(d, onto: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        model.dragging = nil
        return true
    }
}

struct DoneRow: View {
    let item: TodoItem
    let model: PanelModel
    let accent: Color
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            Button { model.restore(item.id) } label: {
                ZStack {
                    Circle().fill(Color.secondary.opacity(0.35))
                    CheckShape().stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .padding(4.5)
                }
                .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Bring it back")
            Text(item.text)
                .font(.system(size: 12))
                .strikethrough(true)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hovering {
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.store.delete(item.id) } } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
