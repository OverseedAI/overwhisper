import SwiftUI

struct ModelSelectionView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var modelManager: ModelManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedModel: WhisperModel?
    @State private var showingInfoSheet = false
    @State private var infoModel: WhisperModel?
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: WhisperModel?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                
                Text("Choose a Transcription Model")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Select a model based on your needs for accuracy, speed, and language support.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            // Model Categories
            ScrollView {
                VStack(spacing: 20) {
                    // English Models Section
                    modelSection(
                        title: "English-Only Models",
                        subtitle: "Faster and more accurate for English speech only",
                        models: WhisperModel.englishModels,
                        systemImage: "character.textbox"
                    )
                    
                    // Multilingual Models Section
                    modelSection(
                        title: "Multilingual Models",
                        subtitle: "Supports 99+ languages including Korean, Japanese, Chinese, etc.",
                        models: WhisperModel.multilingualModels,
                        systemImage: "globe"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            
            // Bottom Actions
            VStack(spacing: 12) {
                Divider()
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Select Model") {
                        if let model = selectedModel {
                            selectModel(model)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedModel == nil)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 500, maxWidth: 500, minHeight: 550, maxHeight: 650)
        .sheet(item: $infoModel) { model in
            ModelInfoSheet(model: model)
        }
        .alert("Delete Model?", isPresented: $showDeleteConfirmation, presenting: modelToDelete) { model in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteModel(model)
            }
        } message: { model in
            Text("Are you sure you want to delete \(model.displayName)? You'll need to download it again to use it.")
        }
        .onAppear {
            // Pre-select current model if available
            if appState.transcriptionEngine == .whisperKit {
                selectedModel = appState.whisperModel
            }
        }
    }
    
    private func modelSection(title: String, subtitle: String, models: [WhisperModel], systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
            }
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Model Cards
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(models) { model in
                    ModelSelectionCard(
                        model: model,
                        isSelected: selectedModel == model,
                        isDownloaded: appState.downloadedModels.contains(model.rawValue),
                        isDownloading: appState.currentlyDownloadingModel == model.rawValue,
                        downloadProgress: appState.modelDownloadProgress,
                        onSelect: { selectedModel = model },
                        onInfo: { infoModel = model },
                        onDownload: { downloadModel(model) },
                        onDelete: { 
                            modelToDelete = model
                            showDeleteConfirmation = true
                        }
                    )
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(12)
    }
    
    private func selectModel(_ model: WhisperModel) {
        appState.transcriptionEngine = .whisperKit
        appState.whisperModel = model
        
        // Download if not already downloaded
        if !appState.downloadedModels.contains(model.rawValue) {
            Task {
                try? await modelManager.downloadModel(model.rawValue)
            }
        }
        
        dismiss()
    }
    
    private func downloadModel(_ model: WhisperModel) {
        Task {
            try? await modelManager.downloadModel(model.rawValue)
        }
    }
    
    private func deleteModel(_ model: WhisperModel) {
        Task {
            try? modelManager.deleteModel(model.rawValue)
            // If this was the selected model, clear selection
            if selectedModel == model {
                selectedModel = nil
            }
        }
    }
}

struct ModelSelectionCard: View {
    let model: WhisperModel
    let isSelected: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let onSelect: () -> Void
    let onInfo: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.displayName)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                } else if isDownloaded {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            
            Text(model.size)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Action buttons row
            HStack(spacing: 8) {
                // Download/Delete button based on state
                if isDownloading {
                    // Show progress
                    HStack(spacing: 4) {
                        ProgressView(value: downloadProgress)
                            .frame(width: 50)
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else if isDownloaded {
                    // Delete button
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete model")
                } else {
                    // Download button
                    Button(action: onDownload) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                            Text("Download")
                                .font(.caption)
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Download model")
                }
                
                Spacer()
                
                // Info button
                Button(action: { onInfo() }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Model info")
            }
        }
        .padding(10)
        .frame(height: 90)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

struct ModelInfoSheet: View {
    let model: WhisperModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                
                Text(model.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(model.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)
            }
            .padding(.top, 20)
            
            // Info Grid
            VStack(spacing: 16) {
                InfoRow(icon: "externaldrive", title: "Size", value: model.size)
                InfoRow(icon: "globe", title: "Languages", value: model.isEnglishOnly ? "English only" : "99+ languages")
                InfoRow(icon: "speedometer", title: "Speed", value: speedDescription(for: model))
                InfoRow(icon: "checkmark.shield", title: "Accuracy", value: accuracyDescription(for: model))
            }
            .padding(.horizontal, 20)
            
            // Description
            VStack(alignment: .leading, spacing: 8) {
                Text("Best for:")
                    .font(.headline)
                
                Text(bestForDescription(for: model))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            
            Spacer()
            
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 20)
        }
        .frame(width: 350, height: 400)
    }
    
    private func speedDescription(for model: WhisperModel) -> String {
        switch model {
        case .tinyEn, .tiny:
            return "Fastest (~10x real-time)"
        case .baseEn, .base:
            return "Very fast (~7x real-time)"
        case .smallEn, .small:
            return "Fast (~4x real-time)"
        case .mediumEn, .medium:
            return "Moderate (~2x real-time)"
        case .largeV2, .largeV3:
            return "Slower (~1x real-time)"
        case .largeV3Turbo:
            return "Fast (~4x real-time)"
        }
    }
    
    private func accuracyDescription(for model: WhisperModel) -> String {
        switch model {
        case .tinyEn, .tiny:
            return "Basic"
        case .baseEn, .base:
            return "Good"
        case .smallEn, .small:
            return "Very Good"
        case .mediumEn, .medium:
            return "Excellent"
        case .largeV2, .largeV3:
            return "Best"
        case .largeV3Turbo:
            return "Excellent"
        }
    }
    
    private func bestForDescription(for model: WhisperModel) -> String {
        switch model {
        case .tinyEn, .tiny:
            return "Quick tests, limited storage, or when speed is more important than perfect accuracy."
        case .baseEn, .base:
            return "General use with good balance of speed and accuracy for simple recordings."
        case .smallEn, .small:
            return "Everyday transcription with very good accuracy and reasonable speed."
        case .mediumEn, .medium:
            return "Professional use where accuracy is critical and you have sufficient storage."
        case .largeV2, .largeV3:
            return "Maximum accuracy requirements, research, or when working with challenging audio."
        case .largeV3Turbo:
            return "High accuracy with faster processing. Great balance for demanding workloads."
        }
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            Text(title)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let appState = AppState()
    let modelManager = ModelManager(appState: appState)
    
    ModelSelectionView(modelManager: modelManager)
        .environmentObject(appState)
}
