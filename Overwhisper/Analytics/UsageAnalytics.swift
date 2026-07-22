import Foundation
import PostHog

enum AnalyticsEngine: String {
    case whisperKit = "whisperkit"
    case parakeet
    case openAI = "openai"
}

enum AnalyticsDictationOutcome: String {
    case success
    case empty
    case silent
    case recordingError = "recording_error"
    case transcriptionError = "transcription_error"
    case fallbackError = "fallback_error"
    case cancelled
}

enum AnalyticsDelivery: String {
    case pasted
    case clipboard
    case none
}

enum AnalyticsBuckets {
    static func duration(_ seconds: TimeInterval) -> String {
        switch max(seconds, 0) {
        case ..<5: return "under_5s"
        case ..<15: return "5_to_14s"
        case ..<30: return "15_to_29s"
        case ..<60: return "30_to_59s"
        case ..<120: return "1_to_2m"
        default: return "over_2m"
        }
    }

    static func latency(_ seconds: TimeInterval) -> String {
        switch max(seconds, 0) {
        case ..<1: return "under_1s"
        case ..<2: return "1_to_2s"
        case ..<5: return "2_to_5s"
        case ..<10: return "5_to_10s"
        default: return "over_10s"
        }
    }
}

enum AnalyticsPrivacy {
    static let allowedEvents: Set<String> = [
        "analytics_enabled",
        "app_installed",
        "app_updated",
        "app_opened",
        "onboarding_completed",
        "model_download_completed",
        "model_download_failed",
        "dictation_completed",
    ]

    static let allowedProperties: Set<String> = [
        "$app_version",
        "$app_build",
        "$device_model",
        "$device_type",
        "$is_identified",
        "$lib",
        "$lib_version",
        "$os_name",
        "$os_version",
        "$process_person_profile",
        "product",
        "surface",
        "version",
        "previous_version",
        "engine",
        "model",
        "outcome",
        "duration_bucket",
        "latency_bucket",
        "used_cloud_fallback",
        "delivery",
    ]

    static func sanitized(_ properties: [String: Any]) -> [String: Any] {
        properties.filter { allowedProperties.contains($0.key) }
    }
}

@MainActor
enum UsageAnalytics {
    private static let projectToken = "phc_8FR5IV8BeamZHuDiuUqMB5YkiovMOmLhCDItahCxIRk"
    private static let proxyHost = "https://s.overseed.ai"
    private static let lastTrackedVersionKey = "analyticsLastTrackedVersion"

    private static var isConfigured = false
    private static var didTrackLaunch = false

    static func start(enabled: Bool) {
        guard enabled else { return }

        configureIfNeeded()
        PostHogSDK.shared.optIn()
        trackLaunchIfNeeded()
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            configureIfNeeded()
            PostHogSDK.shared.optIn()
            capture("analytics_enabled")
            trackLaunchIfNeeded()
        } else if isConfigured {
            PostHogSDK.shared.optOut()
        }
    }

    static func trackOnboardingCompleted() {
        capture("onboarding_completed")
    }

    static func flush() {
        guard isConfigured else { return }
        PostHogSDK.shared.flush()
    }

    static func trackModelDownload(engine: AnalyticsEngine, model: String, succeeded: Bool) {
        capture(
            succeeded ? "model_download_completed" : "model_download_failed",
            properties: [
                "engine": engine.rawValue,
                "model": model,
            ]
        )
    }

    static func trackDictation(
        outcome: AnalyticsDictationOutcome,
        engine: AnalyticsEngine,
        model: String,
        recordingDuration: TimeInterval,
        latency: TimeInterval,
        usedCloudFallback: Bool,
        delivery: AnalyticsDelivery = .none
    ) {
        capture(
            "dictation_completed",
            properties: [
                "outcome": outcome.rawValue,
                "engine": engine.rawValue,
                "model": model,
                "duration_bucket": AnalyticsBuckets.duration(recordingDuration),
                "latency_bucket": AnalyticsBuckets.latency(latency),
                "used_cloud_fallback": usedCloudFallback,
                "delivery": delivery.rawValue,
            ]
        )
    }

    private static func configureIfNeeded() {
        guard !isConfigured else { return }

        let config = PostHogConfig(projectToken: projectToken, host: proxyHost)
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.enableSwizzling = false
        config.personProfiles = .never
        config.setDefaultPersonProperties = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.errorTrackingConfig.autoCapture = false
        config.setBeforeSend { event in
            guard AnalyticsPrivacy.allowedEvents.contains(event.event) else { return nil }
            event.properties = AnalyticsPrivacy.sanitized(event.properties)
            return event
        }

        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register([
            "product": "overwhisper",
            "surface": "macos",
        ])

        isConfigured = true
    }

    private static func trackLaunchIfNeeded() {
        guard !didTrackLaunch else { return }

        let defaults = UserDefaults.standard
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let previousVersion = defaults.string(forKey: lastTrackedVersionKey)

        if previousVersion == nil {
            capture("app_installed", properties: ["version": currentVersion])
        } else if previousVersion != currentVersion {
            capture(
                "app_updated",
                properties: [
                    "version": currentVersion,
                    "previous_version": previousVersion ?? "unknown",
                ]
            )
        }

        defaults.set(currentVersion, forKey: lastTrackedVersionKey)
        capture("app_opened", properties: ["version": currentVersion])
        didTrackLaunch = true
    }

    private static func capture(_ event: String, properties: [String: Any]? = nil) {
        guard isConfigured, !PostHogSDK.shared.isOptOut() else { return }
        PostHogSDK.shared.capture(event, properties: properties)
    }
}

extension TranscriptionEngineType {
    var analyticsEngine: AnalyticsEngine {
        switch self {
        case .whisperKit: return .whisperKit
        case .parakeet: return .parakeet
        case .openAI: return .openAI
        }
    }
}

extension AppState {
    var analyticsModel: String {
        switch transcriptionEngine {
        case .whisperKit: return whisperModel.rawValue
        case .parakeet: return parakeetModel.rawValue
        case .openAI: return "whisper-1"
        }
    }
}
