import SwiftUI
import SwiftData

/// Native label management. Creation and renaming stay local until committed.
struct LabelSettingsView: View {
    @Query(sort: \Label.sortOrder) private var labels: [Label]
    @Environment(\.modelContext) private var modelContext

    var onShowClips: (PersistentIdentifier) -> Void = { _ in }

    @State private var labelPendingDeletion: Label?
    @State private var isCreating = false
    @State private var newName = ""
    @State private var newColorName = LabelColor.blue.rawValue
    @State private var newEmoji: String?
    @State private var showingNewPalette = false
    @State private var creationError: String?
    @State private var creationRequestID = 0
    @State private var listError: String?
    @FocusState private var isNewNameFocused: Bool

    var body: some View {
        Group {
            if labels.isEmpty && !isCreating {
                ContentUnavailableView {
                    SwiftUI.Label("Organize clips with labels", systemImage: "tag")
                } description: {
                    Text("Give related clips a name, then find them from the panel or History.")
                } actions: {
                    Button("Add Label", action: startCreating)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if labels.count > 1 {
                        Text("Drag labels to change their order in the panel.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                    }
                    if let listError {
                        Text(listError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                    }
                    ScrollViewReader { scrollProxy in
                        List {
                            ForEach(labels) { label in
                                let index = labels.firstIndex {
                                    $0.persistentModelID == label.persistentModelID
                                } ?? 0
                                LabelRow(
                                    label: label,
                                    otherNames: labels.filter {
                                        $0.persistentModelID != label.persistentModelID
                                    }.map(\.name),
                                    canMoveUp: index > 0,
                                    canMoveDown: index < labels.count - 1,
                                    onShowClips: { onShowClips(label.persistentModelID) },
                                    onMoveUp: { moveLabel(label, by: -1) },
                                    onMoveDown: { moveLabel(label, by: 1) },
                                    onRequestDelete: { labelPendingDeletion = label }
                                )
                            }
                            .onMove(perform: moveLabels)

                            if isCreating {
                                newLabelRow
                                    .id("new-label-draft")
                                    .onAppear {
                                        focusAndRevealDraft(using: scrollProxy)
                                    }
                            }
                        }
                        .listStyle(.inset)
                        .onChange(of: creationRequestID) { _, _ in
                            focusAndRevealDraft(using: scrollProxy)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: startCreating) {
                    SwiftUI.Label("Add Label", systemImage: "plus")
                }
                .help(isCreating ? "Focus the new label" : "Add a new label")
            }
        }
        .alert(
            "Delete Label?",
            isPresented: Binding(
                get: { labelPendingDeletion != nil },
                set: { if !$0 { labelPendingDeletion = nil } }
            ),
            presenting: labelPendingDeletion
        ) { label in
            Button("Delete", role: .destructive) {
                deleteLabel(label)
                labelPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { labelPendingDeletion = nil }
        } message: { label in
            Text(LabelDeletion.warning(for: label))
        }
    }

    private var newLabelRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    showingNewPalette.toggle()
                } label: {
                    LabelAppearanceSwatch(colorName: newColorName, emoji: newEmoji)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose appearance for new label")
                .help("Choose label appearance")
                .popover(isPresented: $showingNewPalette, arrowEdge: .leading) {
                    LabelStyleSelector(colorName: $newColorName, emoji: $newEmoji)
                        .padding(12)
                        .frame(width: LabelStyleSelector.popoverWidth)
                }

                TextField("New label name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNewNameFocused)
                    .onSubmit(createLabel)
                    .onExitCommand(perform: cancelCreating)
                    .onChange(of: newName) { _, _ in creationError = nil }

                Button("Add", action: createLabel)
                    .disabled(LabelName.normalized(newName).isEmpty)
                Button("Cancel", action: cancelCreating)
            }
            if let creationError {
                Text(creationError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 38)
            } else if !LabelName.normalized(newName).isEmpty && labels.contains(where: {
                LabelName.normalized($0.name).localizedCaseInsensitiveCompare(
                    LabelName.normalized(newName)
                ) == .orderedSame
            }) {
                Text("Another label uses this name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 38)
            }
        }
        .padding(.vertical, 4)
    }

    private func startCreating() {
        if !isCreating {
            newName = ""
            newColorName = (LabelColor.allCases.randomElement() ?? .blue).rawValue
            newEmoji = nil
            creationError = nil
            isCreating = true
        }
        creationRequestID &+= 1
        DispatchQueue.main.async { isNewNameFocused = true }
    }

    private func focusAndRevealDraft(using scrollProxy: ScrollViewProxy) {
        guard isCreating else { return }
        DispatchQueue.main.async {
            scrollProxy.scrollTo("new-label-draft", anchor: .bottom)
            isNewNameFocused = true
        }
    }

    private func cancelCreating() {
        showingNewPalette = false
        creationError = nil
        isNewNameFocused = false
        isCreating = false
        newName = ""
    }

    private func createLabel() {
        let name = LabelName.normalized(newName)
        guard !name.isEmpty else {
            creationError = "Enter a label name."
            isNewNameFocused = true
            return
        }
        let maxOrder = labels.map(\.sortOrder).max() ?? -1
        let label = Label(name: name, colorName: newColorName,
                          sortOrder: maxOrder + 1, emoji: newEmoji)
        modelContext.insert(label)
        do {
            try modelContext.save()
            cancelCreating()
        } catch {
            modelContext.delete(label)
            creationError = "Couldn't save this label. Try again."
        }
    }

    private func deleteLabel(_ label: Label) {
        deleteLabelWithCleanup(label, from: modelContext)
        saveWithLogging(modelContext, operation: "delete label")
    }

    private func moveLabels(from source: IndexSet, to destination: Int) {
        var reordered = Array(labels)
        reordered.move(fromOffsets: source, toOffset: destination)
        saveOrder(reordered)
    }

    private func moveLabel(_ label: Label, by offset: Int) {
        var reordered = Array(labels)
        guard let index = reordered.firstIndex(where: {
            $0.persistentModelID == label.persistentModelID
        }), reordered.indices.contains(index + offset) else { return }
        reordered.swapAt(index, index + offset)
        saveOrder(reordered)
    }

    private func saveOrder(_ reordered: [Label]) {
        let previousOrder = labels.map { ($0, $0.sortOrder) }
        for (index, label) in reordered.enumerated() where label.sortOrder != index {
            label.sortOrder = index
        }
        do {
            try modelContext.save()
            listError = nil
        } catch {
            for (label, order) in previousOrder { label.sortOrder = order }
            listError = "Couldn't save label order. Try again."
        }
    }
}

private struct LabelRow: View {
    @Bindable var label: Label
    @Environment(\.modelContext) private var modelContext

    let otherNames: [String]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onShowClips: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRequestDelete: () -> Void

    @State private var showingPalette = false
    @State private var draftName = ""
    @State private var originalName = ""
    @State private var isEditingName = false
    @State private var nameError: String?
    @FocusState private var isNameFocused: Bool

    private var usageCount: Int { label.safeItems.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(PanelStyle.Icon.control)
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
                    .help("Drag to reorder")
                    .accessibilityHidden(true)

                Button { showingPalette.toggle() } label: {
                    LabelAppearanceSwatch(colorName: label.colorName, emoji: label.emoji)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit appearance of \(label.name)")
                .help("Edit label appearance")
                .popover(isPresented: $showingPalette, arrowEdge: .leading) {
                    LabelStyleSelector(colorName: $label.colorName, emoji: $label.emoji)
                        .padding(12)
                        .frame(width: LabelStyleSelector.popoverWidth)
                        .onChange(of: label.colorName) { _, _ in
                            saveWithLogging(modelContext, operation: "update label color")
                        }
                        .onChange(of: label.emoji) { _, _ in
                            saveWithLogging(modelContext, operation: "update label emoji")
                        }
                }

                TextField("Label name", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($isNameFocused)
                    .onChange(of: draftName) { _, _ in nameError = nil }
                    .onSubmit {
                        commitName()
                        if nameError == nil { isNameFocused = false }
                    }
                    .onExitCommand(perform: cancelNameEdit)
                    .onChange(of: isNameFocused) { _, focused in
                        if focused {
                            originalName = label.name
                            isEditingName = true
                        } else if isEditingName {
                            commitName()
                        }
                    }
                    .onChange(of: label.name) { _, value in
                        if !isEditingName && nameError == nil { draftName = value }
                    }

                Button(usageCount == 1 ? "1 clip" : "\(usageCount) clips", action: showClips)
                    .buttonStyle(.plain)
                    .font(PanelStyle.Text.meta)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("Show clips with \(label.name)")

                Menu { rowActions } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel("Actions for \(label.name)")
                .help("Label actions")
            }
            if let nameError {
                Text(nameError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 52)
            } else if isEditingName && otherNames.contains(where: {
                LabelName.normalized($0).localizedCaseInsensitiveCompare(
                    LabelName.normalized(draftName)
                ) == .orderedSame
            }) {
                Text("Another label uses this name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 52)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            draftName = label.name
            originalName = label.name
        }
        .contextMenu { rowActions }
        .accessibilityAction(named: "Move Up", onMoveUp)
        .accessibilityAction(named: "Move Down", onMoveDown)
        .accessibilityAction(named: "Delete Label", onRequestDelete)
    }

    @ViewBuilder
    private var rowActions: some View {
        Button(usageCount == 1 ? "Show 1 Clip" : "Show \(usageCount) Clips", action: showClips)
        Button("Edit Appearance") { showingPalette = true }
        Divider()
        Button("Move Up", action: onMoveUp).disabled(!canMoveUp)
        Button("Move Down", action: onMoveDown).disabled(!canMoveDown)
        Divider()
        Button("Delete Label", role: .destructive, action: onRequestDelete)
    }

    private func cancelNameEdit() {
        isEditingName = false
        nameError = nil
        draftName = label.name
        isNameFocused = false
    }

    private func showClips() {
        if isEditingName { commitName() }
        guard nameError == nil else {
            isNameFocused = true
            return
        }
        onShowClips()
    }

    private func commitName() {
        guard isEditingName else { return }
        let normalized = LabelName.normalized(draftName)
        guard !normalized.isEmpty else {
            nameError = "Enter a label name."
            isEditingName = false
            return
        }
        guard label.name == originalName else {
            nameError = "This label changed elsewhere. Review its current name before saving."
            isEditingName = false
            return
        }
        if normalized != label.name {
            let previousName = label.name
            label.name = normalized
            do {
                try modelContext.save()
            } catch {
                label.name = previousName
                nameError = "Couldn't save this name. Try again."
                isEditingName = false
                return
            }
        }
        draftName = normalized
        nameError = nil
        isEditingName = false
    }
}

private struct LabelAppearanceSwatch: View {
    let colorName: String
    let emoji: String?

    var body: some View {
        Group {
            if let emoji, !emoji.isEmpty {
                Text(emoji).font(PanelStyle.Icon.control)
            } else {
                Circle()
                    .fill(LabelColor(rawValue: colorName)?.color ?? .gray)
                    .frame(width: 16, height: 16)
            }
        }
        .frame(width: 28, height: 28)
        .background(PanelStyle.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(PanelStyle.stroke, lineWidth: 1))
    }
}
