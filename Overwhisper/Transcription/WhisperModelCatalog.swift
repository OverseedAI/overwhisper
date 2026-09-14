import Foundation
import WhisperKit

/// A single WhisperKit model variant published in the `argmaxinc/whisperkit-coreml` repo.
///
/// Historically this was a fixed `enum` with 11 hand-written cases, which meant the app could
/// only ever offer a subset of what Argmax publishes (no distil-whisper, no quantized builds,
/// no `large-v3-v20240930`). It is now a value type keyed on the variant id so the catalog can
/// be populated dynamically from the SDK at runtime while still round-tripping through
/// `UserDefaults` exactly like the old enum did.
struct WhisperModel: Identifiable, Hashable, Codable {
    /// The persisted identifier. Either a legacy short name (`small.en`) for the models that
    /// shipped with the old enum, or a full variant folder name (`distil-whisper_distil-large-v3`).
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Identity is the *variant*, not the stored string: `small.en` and
    /// `openai_whisper-small.en` name the same download, so they must compare equal. Deriving
    /// identity from `rawValue` instead would make a legacy preference look like a distinct
    /// model and render it as a second row alongside its fully-qualified twin.
    var id: String { variantName }

    static func == (lhs: WhisperModel, rhs: WhisperModel) -> Bool {
        lhs.variantName == rhs.variantName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(variantName)
    }

    // MARK: - Naming

    /// The variant folder name as published on Hugging Face, e.g. `openai_whisper-small.en`.
    ///
    /// Legacy short names are expanded so both spellings resolve to the same download.
    var variantName: String {
        if rawValue.contains("_whisper") || rawValue.hasPrefix("distil") {
            return rawValue
        }
        // Legacy enum values were bare Whisper names; the old code relied on WhisperKit's
        // "openai" disambiguation fallback. Make it explicit.
        return "openai_whisper-\(rawValue)"
    }

    /// The variant stripped of its publisher prefix, e.g. `large-v3_turbo`.
    var shortName: String {
        if let range = rawValue.range(of: "openai_whisper-") {
            return String(rawValue[range.upperBound...])
        }
        if rawValue.hasPrefix("distil-whisper_") {
            return String(rawValue.dropFirst("distil-whisper_".count))
        }
        return rawValue
    }

    // MARK: - Derived attributes

    /// distil-whisper models are English-only distillations; `.en` marks OpenAI English builds.
    var isEnglishOnly: Bool {
        let name = shortName
        return name.hasSuffix(".en") || name.contains("distil-large")
    }

    var isTurbo: Bool { rawValue.contains("_turbo") }

    /// Quantized builds carry an explicit size suffix such as `_626MB`.
    var quantizationSuffix: String? {
        guard let match = rawValue.range(
            of: "_[0-9]+MB$",
            options: .regularExpression
        ) else { return nil }
        return String(rawValue[match].dropFirst())
    }

    var isQuantized: Bool { quantizationSuffix != nil }

    /// The underlying Whisper architecture, used for grouping and size estimates.
    var family: Family {
        let name = shortName
        if name.contains("distil-large") { return .distilLargeV3 }
        if name.contains("large-v3-v20240930") { return .largeV3Turbo }
        if name.contains("large-v3") { return .largeV3 }
        if name.contains("large-v2") { return .largeV2 }
        if name.hasPrefix("medium") { return .medium }
        if name.hasPrefix("small") { return .small }
        if name.hasPrefix("base") { return .base }
        if name.hasPrefix("tiny") { return .tiny }
        return .other
    }

    enum Family: String, CaseIterable {
        case tiny, base, small, medium
        case largeV2, largeV3, largeV3Turbo, distilLargeV3
        case other

        var sortOrder: Int {
            switch self {
            case .tiny: return 0
            case .base: return 1
            case .small: return 2
            case .medium: return 3
            case .distilLargeV3: return 4
            case .largeV3Turbo: return 5
            case .largeV2: return 6
            case .largeV3: return 7
            case .other: return 8
            }
        }

        var baseDisplayName: String {
            switch self {
            case .tiny: return "Tiny"
            case .base: return "Base"
            case .small: return "Small"
            case .medium: return "Medium"
            case .largeV2: return "Large v2"
            case .largeV3: return "Large v3"
            case .largeV3Turbo: return "Large v3 (Sep 2024)"
            case .distilLargeV3: return "Distil Large v3"
            case .other: return "Whisper"
            }
        }

        /// Approximate on-disk size of the unquantized build.
        var approximateSize: String {
            switch self {
            case .tiny: return "~75 MB"
            case .base: return "~150 MB"
            case .small: return "~500 MB"
            case .medium: return "~1.5 GB"
            case .largeV2, .largeV3: return "~3 GB"
            case .largeV3Turbo: return "~1.6 GB"
            case .distilLargeV3: return "~1.5 GB"
            case .other: return "Unknown"
            }
        }
    }

    var displayName: String {
        var name = family.baseDisplayName
        if isTurbo { name += " Turbo" }
        if isEnglishOnly && family != .distilLargeV3 { name += " (English)" }
        if let quantizationSuffix { name += " · \(quantizationSuffix)" }
        return name
    }

    /// Human-readable download size. Quantized variants state their exact published size.
    var size: String {
        if let quantizationSuffix { return "~\(quantizationSuffix)" }
        return family.approximateSize
    }

    // MARK: - Known models (offline fallback)

    static let tinyEn = WhisperModel(rawValue: "tiny.en")
    static let baseEn = WhisperModel(rawValue: "base.en")
    static let smallEn = WhisperModel(rawValue: "small.en")
    static let mediumEn = WhisperModel(rawValue: "medium.en")
    static let tiny = WhisperModel(rawValue: "tiny")
    static let base = WhisperModel(rawValue: "base")
    static let small = WhisperModel(rawValue: "small")
    static let medium = WhisperModel(rawValue: "medium")
    static let largeV2 = WhisperModel(rawValue: "large-v2")
    static let largeV3 = WhisperModel(rawValue: "large-v3")
    static let largeV3Turbo = WhisperModel(rawValue: "large-v3_turbo")

    /// The variants the app shipped before the dynamic catalog existed. Retained so a user with
    /// no network connection, or a stored preference for one of these, keeps working unchanged.
    static let legacyModels: [WhisperModel] = [
        .tinyEn, .baseEn, .smallEn, .mediumEn,
        .tiny, .base, .small, .medium,
        .largeV2, .largeV3, .largeV3Turbo
    ]

    /// The variants to offer when Argmax's remote config is unreachable.
    ///
    /// This delegates to WhisperKit's bundled `recommendedModels()`, which resolves the support
    /// tier for *this* device without any network access. Hard-coding the Apple Silicon list
    /// here instead would over-offer on older hardware: the M1 tier excludes the nine `_turbo`
    /// and `large-v3-v20240930` variants that an M4 supports, and selecting one of those on an
    /// M1 fails at Core ML initialization.
    static var knownRemoteModels: [WhisperModel] {
        let local = WhisperKit.recommendedModels()
        var seen = Set<String>()
        return (local.supported + local.disabled).compactMap { name in
            guard seen.insert(name).inserted else { return nil }
            return WhisperModel(rawValue: name)
        }
    }

    /// Whether this id is a plausible WhisperKit variant.
    ///
    /// A stored preference is no longer validated against a fixed enum, so a corrupted or
    /// withdrawn id would previously persist forever: initialization fails, nothing resets it,
    /// and every transcription then throws `notInitialized` with no way back except a manual
    /// settings reset. Membership can't be checked at load time (the catalog is fetched later
    /// and is device-specific), so this checks the shape instead — a legacy short name or a
    /// published-variant prefix.
    var isPlausibleVariant: Bool {
        if Self.legacyModels.contains(where: { $0.rawValue == rawValue }) { return true }
        return rawValue.hasPrefix("openai_whisper-") || rawValue.hasPrefix("distil-whisper_")
    }

    /// Preserved for source compatibility with call sites that enumerated the old enum.
    static var allCases: [WhisperModel] { legacyModels }

    static var englishModels: [WhisperModel] { legacyModels.filter { $0.isEnglishOnly } }
    static var multilingualModels: [WhisperModel] { legacyModels.filter { !$0.isEnglishOnly } }
}

extension WhisperModel: CustomStringConvertible {
    var description: String { rawValue }
}

/// Sorts variants into a stable, human-sensible order: smallest architecture first, then
/// quantized builds after the full-precision build of the same family.
func whisperModelsSorted(_ models: [WhisperModel]) -> [WhisperModel] {
    models.sorted { lhs, rhs in
        if lhs.family != rhs.family {
            return lhs.family.sortOrder < rhs.family.sortOrder
        }
        if lhs.isTurbo != rhs.isTurbo {
            return !lhs.isTurbo
        }
        if lhs.isQuantized != rhs.isQuantized {
            return !lhs.isQuantized
        }
        return lhs.rawValue < rhs.rawValue
    }
}

/// Fetches the set of model variants Argmax publishes for *this specific device* and exposes
/// them to the UI.
///
/// WhisperKit's remote `config.json` is device-tiered: an M-series Mac is offered considerably
/// more variants than an older Intel-era device, and asking a device to run a variant outside
/// its tier is how you get silent Core ML compilation failures. Reading the tier at runtime is
/// therefore both how we unlock the full catalog and how we stay honest about what will work.
@MainActor
final class WhisperModelCatalog: ObservableObject {
    /// Every variant published for this repo, including ones outside this device's tier.
    @Published private(set) var models: [WhisperModel]
    /// Variants Argmax lists as supported on this device. Everything in `models` not in here is
    /// still offered, but flagged — see `isUntested(_:)`.
    @Published private(set) var supportedOnThisDevice: Set<WhisperModel>
    /// The variant Argmax recommends for this device, if known.
    @Published private(set) var recommended: WhisperModel?
    @Published private(set) var isRefreshing = false
    /// True once a remote refresh has succeeded; false means `models` is the offline fallback.
    @Published private(set) var didLoadRemoteCatalog = false

    static let shared = WhisperModelCatalog()

    init() {
        // Seed from WhisperKit's bundled config so the picker is populated before (or without)
        // any network call.
        let local = WhisperKit.recommendedModels()
        let supported = local.supported.map(WhisperModel.init(rawValue:))
        self.supportedOnThisDevice = Set(supported)
        self.models = whisperModelsSorted(Self.union(supported: local.supported, disabled: local.disabled))
        self.recommended = WhisperModel(rawValue: local.default)
    }

    /// Argmax's config splits variants into `supported` and `disabled` *per device tier*. The
    /// union is the full published catalog; the split is advice about what Argmax has validated
    /// on this hardware. We show the union so no model is hidden — an M1 sees the same list as
    /// an M4 — and mark the difference in the UI instead of silently withholding it.
    private static func union(supported: [String], disabled: [String]) -> [WhisperModel] {
        var seen = Set<String>()
        return (supported + disabled).compactMap { name in
            guard seen.insert(name).inserted else { return nil }
            return WhisperModel(rawValue: name)
        }
    }

    /// True when Argmax doesn't list this variant for the current device. It is still selectable;
    /// this only drives a UI hint, since the practical outcome is usually slower inference rather
    /// than outright failure, and the user is entitled to decide.
    func isUntested(_ model: WhisperModel) -> Bool {
        !supportedOnThisDevice.isEmpty && !supportedOnThisDevice.contains(model)
    }

    var englishModels: [WhisperModel] { models.filter { $0.isEnglishOnly } }
    var multilingualModels: [WhisperModel] { models.filter { !$0.isEnglishOnly } }

    /// Refreshes the catalog from Argmax's remote config, falling back to the bundled list.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let support = await WhisperKit.recommendedRemoteModels()
        let supported = support.supported

        guard !supported.isEmpty else {
            AppLogger.transcription.warning("Remote model catalog empty; keeping bundled fallback list")
            return
        }

        let fetched = Self.union(supported: supported, disabled: support.disabled)
        supportedOnThisDevice = Set(supported.map(WhisperModel.init(rawValue:)))
        models = whisperModelsSorted(fetched)
        recommended = WhisperModel(rawValue: support.default)
        didLoadRemoteCatalog = true

        AppLogger.transcription.info(
            "Loaded \(fetched.count) model variants (\(supported.count) listed for this device, recommended: \(support.default))"
        )
    }
}
