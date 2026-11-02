import Foundation

/// The three model sizes Transcription settings offer as the primary WhisperKit choice.
///
/// The full catalog (two dozen variants of quantized, turbo, dated and distilled builds) is
/// still reachable under "Choose exact model", but almost nobody should have to read variant ids
/// to pick a model. Each tier maps to one deliberately chosen, long-standing variant, so the
/// mapping never follows a remote "recommended" field to an arbitrary or experimental build.
enum WhisperModelTier: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    /// A conservative app default, not a benchmark result: Small is the size the app has always
    /// shipped as its default, downloads quickly, and runs comfortably on every Apple Silicon Mac.
    static let recommended: WhisperModelTier = .small

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// Relative, qualitative trade-offs only. These are the same direction-of-travel statements
    /// OpenAI makes about the Whisper sizes; no speeds or error rates are claimed.
    var summary: String {
        switch self {
        case .small: return "Fast, with good accuracy for everyday dictation."
        case .medium: return "Slower than Small, and more accurate."
        case .large: return "Most accurate and slowest. Uses the most memory."
        }
    }
}

/// Whether a curated tier resolves to an English-only or a multilingual build.
enum WhisperLanguageVariant: Equatable {
    case englishOnly
    case multilingual
}

/// How a tier row in Settings should present itself. Computed by
/// `WhisperModelSelectionPolicy.rowState` so the view stays declarative and the rules are tested.
struct WhisperTierRowState: Equatable {
    enum Action: Equatable {
        /// This tier's model is the one in use.
        case none
        /// Downloaded but not chosen: clicking the row switches to it.
        case select
        /// Chosen, downloaded, but a different model is still active (e.g. after a language
        /// change made a different variant the right one). An explicit "Use" button switches.
        case use
        /// Not downloaded. Only an explicit "Download & use" fetches it — never a row click and
        /// never a language change.
        case downloadAndUse
    }

    let tier: WhisperModelTier
    /// The variant this tier resolves to for the current language settings.
    let target: WhisperModel
    let isSelected: Bool
    let isActive: Bool
    let isDownloaded: Bool
    let action: Action
    /// Why the selected tier isn't active yet, if it isn't.
    let note: String?
}

/// Pure rules mapping language settings and tiers to concrete model variants.
///
/// Kept free of UI, `UserDefaults` and WhisperKit state so every rule is unit-testable.
enum WhisperModelSelectionPolicy {
    /// Value persisted under `whisperModelTier` when the user picked an exact model that isn't a
    /// curated tier. Distinguishes "deliberately custom" from "never set" (which is inferred).
    static let customTierStorageValue = "custom"

    // MARK: - Tier → variant

    /// English-only builds are used only when the user has explicitly pinned English and isn't
    /// translating. Auto-detect, any other language, and translation all need multilingual.
    static func variant(language: String, translateToEnglish: Bool) -> WhisperLanguageVariant {
        language == "en" && !translateToEnglish ? .englishOnly : .multilingual
    }

    /// The reviewed variant for a tier.
    ///
    /// - Small / Medium: OpenAI's standard builds, with their `.en` twins for English.
    /// - Large: standard `large-v3` for every language setting. There is no OpenAI English-only
    ///   large model; distil-large-v3 is a third-party distillation, the `_NNNMB` builds are
    ///   quantized, and the `v20240930` build is OpenAI's reduced-decoder "turbo", which OpenAI
    ///   documents as not trained for translation. `large-v3` is the plain, full-precision
    ///   model and is in Argmax's supported list for M1 and M2–M4 Macs.
    static func model(for tier: WhisperModelTier, variant: WhisperLanguageVariant) -> WhisperModel {
        switch (tier, variant) {
        case (.small, .englishOnly): return WhisperModel(rawValue: "openai_whisper-small.en")
        case (.small, .multilingual): return WhisperModel(rawValue: "openai_whisper-small")
        case (.medium, .englishOnly): return WhisperModel(rawValue: "openai_whisper-medium.en")
        case (.medium, .multilingual): return WhisperModel(rawValue: "openai_whisper-medium")
        case (.large, _): return WhisperModel(rawValue: "openai_whisper-large-v3")
        }
    }

    static func model(
        for tier: WhisperModelTier,
        language: String,
        translateToEnglish: Bool
    ) -> WhisperModel {
        model(for: tier, variant: variant(language: language, translateToEnglish: translateToEnglish))
    }

    /// Every variant any tier can resolve to, in tier order, without duplicates.
    static var curatedModels: [WhisperModel] {
        var seen = Set<WhisperModel>()
        var result: [WhisperModel] = []
        for tier in WhisperModelTier.allCases {
            for variant in [WhisperLanguageVariant.englishOnly, .multilingual] {
                let model = model(for: tier, variant: variant)
                if seen.insert(model).inserted { result.append(model) }
            }
        }
        return result
    }

    // MARK: - Variant → tier

    /// The tier a model belongs to regardless of language variant (`small.en` and `small` are
    /// both Small). Used only to migrate a stored model that predates tiers. Any non-curated
    /// variant — quantized, turbo, dated, distilled, tiny, base, large-v2 — is custom.
    static func inferredTier(for model: WhisperModel) -> WhisperModelTier? {
        WhisperModelTier.allCases.first { tier in
            model == Self.model(for: tier, variant: .englishOnly)
                || model == Self.model(for: tier, variant: .multilingual)
        }
    }

    /// Restores the tier preference on launch. An explicit stored tier (or explicit "custom")
    /// wins; otherwise it is inferred from the stored model, so upgraded users keep the model
    /// they had and simply see it under the matching tier.
    static func initialTier(storedValue: String?, model: WhisperModel) -> WhisperModelTier? {
        if let storedValue {
            if storedValue == customTierStorageValue { return nil }
            if let tier = WhisperModelTier(rawValue: storedValue) { return tier }
        }
        return inferredTier(for: model)
    }

    /// An unset language follows the existing model's capability. Explicit preferences, including
    /// Auto-detect, are preserved. This avoids an English-only model paired with Auto-detect on
    /// first launch without replacing any existing model or downloading another one.
    static func initialLanguage(storedValue: String?, model: WhisperModel) -> String {
        storedValue ?? (model.isEnglishOnly ? "en" : "auto")
    }

    // MARK: - Reconciliation

    /// The model to switch to after language/translation settings change, or nil to stay put.
    ///
    /// Only curated selections follow the language; a custom exact pick never changes. And the
    /// switch happens only when the new target is already on disk: changing a picker must
    /// never start a multi-gigabyte download. When the target is missing the current model
    /// stays active and Settings offers "Download & use".
    static func reconciledModel(
        current: WhisperModel,
        tier: WhisperModelTier?,
        language: String,
        translateToEnglish: Bool,
        downloadedVariants: Set<String>
    ) -> WhisperModel? {
        guard let tier else { return nil }
        let target = model(for: tier, language: language, translateToEnglish: translateToEnglish)
        guard target != current, downloadedVariants.contains(target.variantName) else { return nil }
        return target
    }

    // MARK: - Presentation

    static func rowState(
        tier: WhisperModelTier,
        selectedTier: WhisperModelTier?,
        active: WhisperModel,
        language: String,
        translateToEnglish: Bool,
        downloadedVariants: Set<String>
    ) -> WhisperTierRowState {
        let target = model(for: tier, language: language, translateToEnglish: translateToEnglish)
        let isSelected = selectedTier == tier
        let isDownloaded = downloadedVariants.contains(target.variantName)
        let isActive = isSelected && active == target && isDownloaded

        let action: WhisperTierRowState.Action
        if isActive {
            action = .none
        } else if !isDownloaded {
            action = .downloadAndUse
        } else if isSelected {
            action = .use
        } else {
            action = .select
        }

        let note = isSelected && !isActive
            ? mismatchNote(tier: tier, active: active, language: language, translateToEnglish: translateToEnglish)
            : nil

        return WhisperTierRowState(
            tier: tier,
            target: target,
            isSelected: isSelected,
            isActive: isActive,
            isDownloaded: isDownloaded,
            action: action,
            note: note
        )
    }

    /// Explains why the chosen tier's model isn't the one in use yet.
    static func mismatchNote(
        tier: WhisperModelTier,
        active: WhisperModel,
        language: String,
        translateToEnglish: Bool
    ) -> String? {
        let target = model(for: tier, language: language, translateToEnglish: translateToEnglish)
        guard active != target else { return nil }

        guard active.family == target.family else {
            return "Still using \(active.displayName)."
        }

        if active.isEnglishOnly && !target.isEnglishOnly {
            let reason: String
            if translateToEnglish {
                reason = "Translation needs"
            } else if language == "auto" {
                reason = "Auto-detect needs"
            } else {
                reason = "\(languageName(for: language)) needs"
            }
            return "Using \(active.displayName), which only understands English. \(reason) the multilingual \(tier.title)."
        }

        if !active.isEnglishOnly && target.isEnglishOnly {
            return "Using the multilingual \(tier.title). The English-only \(tier.title) is tuned for English."
        }

        return "Still using \(active.displayName)."
    }

    static func languageName(for code: String) -> String {
        WhisperLanguages.all.first { $0.0 == code }?.1 ?? "This language"
    }

    // MARK: - Exact model list

    /// Everything "Choose exact model" lists: the catalog, every curated variant (so a tier
    /// target is always reachable even when the device support matrix omits it — no Mac tier
    /// lists `medium`), the selected model, and anything on disk (so it stays deletable).
    /// Deduplicated by variant, so a legacy `small.en` and `openai_whisper-small.en` are one row.
    static func exactChoices(
        catalog: [WhisperModel],
        selected: WhisperModel,
        downloadedVariants: Set<String>
    ) -> [WhisperModel] {
        var seen = Set<WhisperModel>()
        var result: [WhisperModel] = []
        let downloaded = downloadedVariants.sorted().map(WhisperModel.init(rawValue:))
        for model in catalog + curatedModels + [selected] + downloaded {
            if seen.insert(model).inserted { result.append(model) }
        }
        return whisperModelsSorted(result)
    }
}
