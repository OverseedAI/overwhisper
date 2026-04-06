import SwiftUI
import UniformTypeIdentifiers

struct TranscriptionHistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedEntries = Set<UUID>()
    @State private var showExportSheet = false
    @State private var showDeleteConfirmation = false
    @State private var entryToDelete: TranscriptionHistoryEntry?
    @State private var newTagText = ""
    @State private var entryForTagging: TranscriptionHistoryEntry?
    @State private var showTagSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Search and Filter Bar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search transcriptions...", text: $appState.historySearchQuery)
                        .textFieldStyle(.plain)
                    if !appState.historySearchQuery.isEmpty {
                        Button(action: { appState.historySearchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                
                Toggle("Favorites Only", isOn: $appState.showOnlyFavorites)
                    .toggleStyle(.checkbox)
                
                Spacer()
                
                // Export Button
                Button(action: { showExportSheet = true }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(appState.filteredTranscriptionHistory.isEmpty)
                
                // Clear All Button
                if !appState.transcriptionHistory.isEmpty {
                    Button(action: { showDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            
            Divider()
            
            // History List
            if appState.filteredTranscriptionHistory.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    if appState.transcriptionHistory.isEmpty {
                        Text("No transcriptions yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Start recording to see your transcriptions here.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No matches found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Try adjusting your search or filters.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(appState.filteredTranscriptionHistory) { entry in
                    EnhancedTranscriptionHistoryRow(
                        entry: entry,
                        isSelected: selectedEntries.contains(entry.id),
                        onToggleSelect: { toggleSelection(entry.id) },
                        onToggleFavorite: { appState.toggleFavorite(for: entry.id) },
                        onAddTag: {
                            entryForTagging = entry
                            showTagSheet = true
                        },
                        onDelete: {
                            entryToDelete = entry
                            showDeleteConfirmation = true
                        },
                        onCopy: {
                            copyToClipboard(entry.text)
                        }
                    )
                    .contextMenu {
                        Button(action: { copyToClipboard(entry.text) }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        
                        Button(action: { appState.toggleFavorite(for: entry.id) }) {
                            Label(entry.isFavorite ? "Remove Favorite" : "Add Favorite", 
                                  systemImage: entry.isFavorite ? "star.slash" : "star")
                        }
                        
                        Button(action: {
                            entryForTagging = entry
                            showTagSheet = true
                        }) {
                            Label("Add Tag", systemImage: "tag")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: {
                            deleteEntry(entry)
                        }) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.plain)
            }
            
            // Status Bar
            HStack {
                Text("\(appState.filteredTranscriptionHistory.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !selectedEntries.isEmpty {
                    Text("\(selectedEntries.count) selected")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    
                    Button("Export Selected") {
                        exportSelected()
                    }
                    .buttonStyle(.link)
                    
                    Button("Clear Selection") {
                        selectedEntries.removeAll()
                    }
                    .buttonStyle(.link)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheetView(
                entries: appState.filteredTranscriptionHistory,
                onExport: { format, entries in
                    exportToFormat(format, entries: entries)
                }
            )
        }
        .sheet(isPresented: $showTagSheet) {
            if let entry = entryForTagging {
                TagSheetView(
                    entry: entry,
                    onAddTag: { tag in
                        appState.addTag(tag, to: entry.id)
                    },
                    onRemoveTag: { tag in
                        appState.removeTag(tag, from: entry.id)
                    }
                )
            }
        }
        .alert("Delete All History?", isPresented: $showDeleteConfirmation, presenting: entryToDelete) { entry in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteEntry(entry)
            }
        } message: { entry in
            Text("Are you sure you want to delete this transcription? This action cannot be undone.")
        }
        .alert("Clear All History?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                appState.clearTranscriptionHistory()
                selectedEntries.removeAll()
            }
        } message: {
            Text("Are you sure you want to delete all transcriptions? This action cannot be undone.")
        }
    }
    
    private func toggleSelection(_ id: UUID) {
        if selectedEntries.contains(id) {
            selectedEntries.remove(id)
        } else {
            selectedEntries.insert(id)
        }
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    private func deleteEntry(_ entry: TranscriptionHistoryEntry) {
        appState.transcriptionHistory.removeAll { $0.id == entry.id }
        appState.persistTranscriptionHistory()
        selectedEntries.remove(entry.id)
    }
    
    private func exportSelected() {
        let entries = appState.transcriptionHistory.filter { selectedEntries.contains($0.id) }
        exportToFormat(.txt, entries: entries)
    }
    
    private func exportToFormat(_ format: ExportFormat, entries: [TranscriptionHistoryEntry]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Transcriptions_\(format.fileExtension)"
        panel.allowedContentTypes = [format.utType]
        
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            
            let content: String
            switch format {
            case .txt:
                content = entries.map { entry in
                    "[\(formatDate(entry.timestamp))] \(entry.text)"
                }.joined(separator: "\n\n")
                
            case .markdown:
                content = entries.map { entry in
                    "## \(formatDate(entry.timestamp))\n\n\(entry.text)\n"
                }.joined(separator: "\n---\n\n")
                
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                encoder.dateEncodingStrategy = .iso8601
                if let data = try? encoder.encode(entries),
                   let string = String(data: data, encoding: .utf8) {
                    content = string
                } else {
                    content = "{}"
                }
            }
            
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                AppLogger.system.error("Export failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

enum ExportFormat: CaseIterable {
    case txt
    case markdown
    case json
    
    var displayName: String {
        switch self {
        case .txt: return "Plain Text (.txt)"
        case .markdown: return "Markdown (.md)"
        case .json: return "JSON (.json)"
        }
    }
    
    var fileExtension: String {
        switch self {
        case .txt: return "txt"
        case .markdown: return "md"
        case .json: return "json"
        }
    }
    
    var utType: UTType {
        switch self {
        case .txt: return .plainText
        case .markdown: return .plainText
        case .json: return .json
        }
    }
}

struct EnhancedTranscriptionHistoryRow: View {
    let entry: TranscriptionHistoryEntry
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onAddTag: () -> Void
    let onDelete: () -> Void
    let onCopy: () -> Void
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                // Selection checkbox
                Button(action: onToggleSelect) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                
                // Favorite button
                Button(action: onToggleFavorite) {
                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                        .foregroundColor(entry.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                
                // Text content
                Text(entry.text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Actions
                HStack(spacing: 4) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy")
                    
                    Button(action: onAddTag) {
                        Image(systemName: "tag")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Add Tag")
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }
            
            // Tags row
            if !entry.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(entry.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .foregroundColor(.accentColor)
                            .cornerRadius(4)
                    }
                }
            }
            
            // Date
            Text(Self.dateFormatter.string(from: entry.timestamp))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
    }
}

struct ExportSheetView: View {
    let entries: [TranscriptionHistoryEntry]
    let onExport: (ExportFormat, [TranscriptionHistoryEntry]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .txt
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Export Transcriptions")
                .font(.headline)
            
            Text("Exporting \(entries.count) entries")
                .foregroundColor(.secondary)
            
            Picker("Format", selection: $selectedFormat) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.radioGroup)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Export") {
                    onExport(selectedFormat, entries)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

struct TagSheetView: View {
    let entry: TranscriptionHistoryEntry
    let onAddTag: (String) -> Void
    let onRemoveTag: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""
    @State private var suggestedTags = ["Important", "Work", "Personal", "Meeting", "Todo"]
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Manage Tags")
                .font(.headline)
            
            // Current tags
            if !entry.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(entry.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                            Button(action: { onRemoveTag(tag) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .foregroundColor(.accentColor)
                        .cornerRadius(6)
                    }
                }
            }
            
            Divider()
            
            // Add new tag
            HStack {
                TextField("New tag...", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                
                Button("Add") {
                    if !newTag.isEmpty {
                        onAddTag(newTag)
                        newTag = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTag.isEmpty)
            }
            
            // Suggested tags
            Text("Suggested")
                .font(.caption)
                .foregroundColor(.secondary)
            
            FlowLayout(spacing: 8) {
                ForEach(suggestedTags.filter { !entry.tags.contains($0) }, id: \.self) { tag in
                    Button(action: { onAddTag(tag) }) {
                        Text(tag)
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 320)
    }
}

// Flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

#Preview {
    let appState = AppState()
    return TranscriptionHistoryView()
        .environmentObject(appState)
}
