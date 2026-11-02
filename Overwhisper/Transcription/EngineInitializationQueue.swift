import Foundation

/// Serializes engine startup and coalesces changes made while startup is suspended.
/// Each run reads the current selection, so the latest model cannot be dropped by a busy guard.
@MainActor
final class EngineInitializationQueue {
    private let initialize: () async -> Void
    private var pending = false
    private var task: Task<Void, Never>?

    init(initialize: @escaping () async -> Void) {
        self.initialize = initialize
    }

    func request() {
        pending = true
        guard task == nil else { return }
        task = Task {
            while pending && !Task.isCancelled {
                pending = false
                await initialize()
            }
            task = nil
        }
    }

    func waitUntilIdle() async {
        await task?.value
    }
}
