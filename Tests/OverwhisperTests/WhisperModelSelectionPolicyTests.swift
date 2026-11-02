import XCTest
@testable import Overwhisper

final class WhisperModelSelectionPolicyTests: XCTestCase {
    private typealias Policy = WhisperModelSelectionPolicy

    private func model(_ id: String) -> WhisperModel { WhisperModel(rawValue: id) }

    // MARK: - Language → variant

    func testOnlyExplicitEnglishWithoutTranslationIsEnglishOnly() {
        XCTAssertEqual(Policy.variant(language: "en", translateToEnglish: false), .englishOnly)

        XCTAssertEqual(Policy.variant(language: "auto", translateToEnglish: false), .multilingual,
                       "Auto-detect must not get an English-only model")
        XCTAssertEqual(Policy.variant(language: "ja", translateToEnglish: false), .multilingual)
        XCTAssertEqual(Policy.variant(language: "en", translateToEnglish: true), .multilingual,
                       "Translation needs a multilingual model even when English is pinned")
        XCTAssertEqual(Policy.variant(language: "auto", translateToEnglish: true), .multilingual)
    }

    func testEnglishMapsSmallAndMediumToEnglishOnlyBuilds() {
        XCTAssertEqual(Policy.model(for: .small, language: "en", translateToEnglish: false).variantName,
                       "openai_whisper-small.en")
        XCTAssertEqual(Policy.model(for: .medium, language: "en", translateToEnglish: false).variantName,
                       "openai_whisper-medium.en")
    }

    func testEveryNonEnglishSettingMapsToMultilingualBuilds() {
        let settings: [(String, Bool)] = [("auto", false), ("ja", false), ("es", false), ("en", true), ("ko", true)]
        for (language, translate) in settings {
            let small = Policy.model(for: .small, language: language, translateToEnglish: translate)
            let medium = Policy.model(for: .medium, language: language, translateToEnglish: translate)
            XCTAssertEqual(small.variantName, "openai_whisper-small", "\(language), translate=\(translate)")
            XCTAssertEqual(medium.variantName, "openai_whisper-medium", "\(language), translate=\(translate)")
            XCTAssertFalse(small.isEnglishOnly)
            XCTAssertFalse(medium.isEnglishOnly)
        }
    }

    /// Large is the standard full-precision large-v3 everywhere: not a quantized, turbo, dated or
    /// distilled build, and never English-only (distil-large-v3 would be).
    func testLargeIsStandardLargeV3ForEverySetting() {
        for (language, translate) in [("en", false), ("en", true), ("auto", false), ("fr", false)] {
            let large = Policy.model(for: .large, language: language, translateToEnglish: translate)
            XCTAssertEqual(large.variantName, "openai_whisper-large-v3")
            XCTAssertEqual(large.family, .largeV3)
            XCTAssertFalse(large.isQuantized)
            XCTAssertFalse(large.isTurbo)
            XCTAssertFalse(large.isEnglishOnly)
        }
    }

    func testCuratedModelsAreFullPrecisionPlausibleVariantsOfTheirFamily() {
        let expectedFamily: [WhisperModelTier: WhisperModel.Family] = [
            .small: .small, .medium: .medium, .large: .largeV3
        ]
        for tier in WhisperModelTier.allCases {
            for variant in [WhisperLanguageVariant.englishOnly, .multilingual] {
                let curated = Policy.model(for: tier, variant: variant)
                XCTAssertTrue(curated.isPlausibleVariant, curated.rawValue)
                XCTAssertFalse(curated.isQuantized, curated.rawValue)
                XCTAssertFalse(curated.isTurbo, curated.rawValue)
                XCTAssertEqual(curated.family, expectedFamily[tier], curated.rawValue)
            }
        }
        XCTAssertEqual(Policy.curatedModels.count, 5, "small(.en), medium(.en), large-v3")
    }

    func testPrimaryChoiceIsExactlySmallMediumLargeWithSmallRecommended() {
        XCTAssertEqual(WhisperModelTier.allCases.map(\.title), ["Small", "Medium", "Large"])
        XCTAssertEqual(WhisperModelTier.recommended, .small)
    }

    // MARK: - Migration / inference

    func testLegacyAndQualifiedCuratedIdsInferTheirTier() {
        let cases: [(String, WhisperModelTier)] = [
            ("small.en", .small), ("small", .small),
            ("openai_whisper-small.en", .small), ("openai_whisper-small", .small),
            ("medium.en", .medium), ("medium", .medium),
            ("openai_whisper-medium", .medium),
            ("large-v3", .large), ("openai_whisper-large-v3", .large)
        ]
        for (id, tier) in cases {
            XCTAssertEqual(Policy.inferredTier(for: model(id)), tier, id)
        }
    }

    /// Anything the curated sizes don't map to stays an exact, custom choice so it is never
    /// silently replaced.
    func testNonCuratedVariantsAreCustom() {
        let custom = [
            "tiny.en", "base", "large-v2", "large-v3_turbo",
            "openai_whisper-large-v3_947MB",
            "openai_whisper-large-v3-v20240930",
            "openai_whisper-large-v3-v20240930_626MB",
            "distil-whisper_distil-large-v3",
            "openai_whisper-small_216MB"
        ]
        for id in custom {
            XCTAssertNil(Policy.inferredTier(for: model(id)), id)
        }
    }

    func testInitialTierPrefersStoredValueThenInfers() {
        XCTAssertEqual(Policy.initialTier(storedValue: nil, model: model("small.en")), .small,
                       "Upgraded default users keep small.en and see it as Small")
        XCTAssertNil(Policy.initialTier(storedValue: nil, model: model("openai_whisper-large-v3_947MB")))
        XCTAssertNil(Policy.initialTier(storedValue: Policy.customTierStorageValue, model: model("small.en")),
                     "An explicit custom choice survives relaunch even when the model is curated")
        XCTAssertEqual(Policy.initialTier(storedValue: "medium", model: model("small.en")), .medium)
        XCTAssertEqual(Policy.initialTier(storedValue: "garbage", model: model("large-v3")), .large)
    }

    // MARK: - Reconciliation on language / translate change

    func testCuratedChoiceFollowsLanguageWhenTargetIsDownloaded() {
        let next = Policy.reconciledModel(
            current: model("openai_whisper-small.en"),
            tier: .small,
            language: "ja",
            translateToEnglish: false,
            downloadedVariants: ["openai_whisper-small.en", "openai_whisper-small"]
        )
        XCTAssertEqual(next?.variantName, "openai_whisper-small")

        let back = Policy.reconciledModel(
            current: model("openai_whisper-small"),
            tier: .small,
            language: "en",
            translateToEnglish: false,
            downloadedVariants: ["openai_whisper-small.en", "openai_whisper-small"]
        )
        XCTAssertEqual(back?.variantName, "openai_whisper-small.en")
    }

    func testTurningOnTranslationMovesEnglishOnlyToMultilingual() {
        let next = Policy.reconciledModel(
            current: model("medium.en"),
            tier: .medium,
            language: "en",
            translateToEnglish: true,
            downloadedVariants: ["openai_whisper-medium.en", "openai_whisper-medium"]
        )
        XCTAssertEqual(next?.variantName, "openai_whisper-medium")
    }

    /// A language toggle must never select a missing model: that would start a download the
    /// moment the engine reinitializes.
    func testLanguageChangeNeverSelectsAMissingModel() {
        let next = Policy.reconciledModel(
            current: model("openai_whisper-small.en"),
            tier: .small,
            language: "auto",
            translateToEnglish: false,
            downloadedVariants: ["openai_whisper-small.en"]
        )
        XCTAssertNil(next)
    }

    func testCustomExactChoiceIsNeverChangedByLanguage() {
        for current in ["small.en", "openai_whisper-large-v3-v20240930_626MB"] {
            for (language, translate) in [("en", false), ("auto", false), ("ja", true)] {
                let next = Policy.reconciledModel(
                    current: model(current), tier: nil, language: language,
                    translateToEnglish: translate,
                    downloadedVariants: Set(Policy.curatedModels.map(\.variantName))
                )
                XCTAssertNil(next, "Exact pick \(current) must stay pinned")
            }
        }
    }

    func testReconcileIsANoOpWhenAlreadyOnTarget() {
        // Legacy short id equals its qualified twin, so this must not "switch" and reinitialize.
        let next = Policy.reconciledModel(
            current: model("small.en"),
            tier: .small,
            language: "en",
            translateToEnglish: false,
            downloadedVariants: ["openai_whisper-small.en"]
        )
        XCTAssertNil(next)
    }

    // MARK: - Row presentation

    func testRowActions() {
        let downloaded: Set<String> = ["openai_whisper-small.en", "openai_whisper-medium.en"]

        let active = Policy.rowState(tier: .small, selectedTier: .small, active: model("small.en"),
                                     language: "en", translateToEnglish: false, downloadedVariants: downloaded)
        XCTAssertTrue(active.isActive)
        XCTAssertEqual(active.action, .none)
        XCTAssertNil(active.note)

        let selectable = Policy.rowState(tier: .medium, selectedTier: .small, active: model("small.en"),
                                         language: "en", translateToEnglish: false, downloadedVariants: downloaded)
        XCTAssertEqual(selectable.action, .select)
        XCTAssertNil(selectable.note)

        let missing = Policy.rowState(tier: .large, selectedTier: .small, active: model("small.en"),
                                      language: "en", translateToEnglish: false, downloadedVariants: downloaded)
        XCTAssertEqual(missing.action, .downloadAndUse)
        XCTAssertFalse(missing.isDownloaded)
    }

    /// Upgraded default user: small.en with Auto-detect. Small is chosen, the multilingual Small
    /// isn't on disk, so the row explains the gap and offers Download & use — it doesn't switch.
    func testSelectedTierWithMissingTargetExplainsAndOffersDownload() {
        let state = Policy.rowState(tier: .small, selectedTier: .small, active: model("small.en"),
                                    language: "auto", translateToEnglish: false,
                                    downloadedVariants: ["openai_whisper-small.en"])
        XCTAssertTrue(state.isSelected)
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.action, .downloadAndUse)
        XCTAssertEqual(state.target.variantName, "openai_whisper-small")
        XCTAssertNotNil(state.note)
        XCTAssertTrue(state.note?.contains("Auto-detect") == true)
    }

    func testSelectedTierWithDownloadedTargetOffersUse() {
        let state = Policy.rowState(tier: .small, selectedTier: .small, active: model("small.en"),
                                    language: "ja", translateToEnglish: false,
                                    downloadedVariants: ["openai_whisper-small.en", "openai_whisper-small"])
        XCTAssertEqual(state.action, .use)
        XCTAssertTrue(state.note?.contains("Japanese") == true)
    }

    func testNoTierRowIsSelectedForACustomChoice() {
        for tier in WhisperModelTier.allCases {
            let state = Policy.rowState(tier: tier, selectedTier: nil,
                                        active: model("openai_whisper-large-v3_947MB"),
                                        language: "auto", translateToEnglish: false, downloadedVariants: [])
            XCTAssertFalse(state.isSelected)
            XCTAssertFalse(state.isActive)
            XCTAssertNil(state.note)
        }
    }

    func testMismatchNotes() {
        XCTAssertTrue(Policy.mismatchNote(tier: .small, active: model("small.en"),
                                          language: "en", translateToEnglish: true)?
            .contains("Translation") == true)
        XCTAssertTrue(Policy.mismatchNote(tier: .small, active: model("small"),
                                          language: "en", translateToEnglish: false)?
            .contains("English-only") == true)
        XCTAssertEqual(Policy.mismatchNote(tier: .small, active: model("openai_whisper-large-v3_947MB"),
                                           language: "auto", translateToEnglish: false),
                       "Still using Large v3 · 947MB.")
        XCTAssertNil(Policy.mismatchNote(tier: .large, active: model("large-v3"),
                                         language: "auto", translateToEnglish: false))
    }

    // MARK: - Exact model list

    /// No Mac support tier lists medium, so a catalog-only list would make the Medium size's
    /// variants unreachable in "Choose exact model".
    func testExactChoicesAlwaysIncludeCuratedVariants() {
        let choices = Policy.exactChoices(
            catalog: [model("openai_whisper-tiny"), model("openai_whisper-small")],
            selected: model("openai_whisper-small"),
            downloadedVariants: []
        )
        for curated in Policy.curatedModels {
            XCTAssertTrue(choices.contains(curated), curated.rawValue)
        }
    }

    func testExactChoicesKeepSelectedAndDownloadedWithoutDuplicates() {
        let choices = Policy.exactChoices(
            catalog: [model("openai_whisper-small.en"), model("openai_whisper-tiny")],
            selected: model("small.en"),
            downloadedVariants: ["openai_whisper-small.en", "distil-whisper_distil-large-v3_594MB"]
        )
        let variants = choices.map(\.variantName)
        XCTAssertEqual(Set(variants).count, variants.count, "legacy and qualified ids must be one row")
        XCTAssertTrue(variants.contains("distil-whisper_distil-large-v3_594MB"),
                      "Downloaded models outside the catalog must stay listed so they can be deleted")
        XCTAssertTrue(variants.contains("openai_whisper-small.en"))
    }
    func testUnsetLanguageMatchesModelCapabilityAndExplicitAutoIsPreserved() {
        XCTAssertEqual(Policy.initialLanguage(storedValue: nil, model: model("small.en")), "en")
        XCTAssertEqual(Policy.initialLanguage(storedValue: nil, model: model("large-v3")), "auto")
        XCTAssertEqual(Policy.initialLanguage(storedValue: "auto", model: model("small.en")), "auto")
        XCTAssertEqual(Policy.initialLanguage(storedValue: "ja", model: model("small.en")), "ja")
    }

    func testSelectedMissingModelOffersDownloadInsteadOfActive() {
        let row = Policy.rowState(tier: .small, selectedTier: .small, active: model("small.en"),
                                  language: "en", translateToEnglish: false, downloadedVariants: [])
        XCTAssertFalse(row.isActive)
        XCTAssertEqual(row.action, .downloadAndUse)
    }

}
