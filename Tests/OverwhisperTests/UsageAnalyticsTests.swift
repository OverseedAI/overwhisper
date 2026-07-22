import XCTest
@testable import Overwhisper

final class UsageAnalyticsTests: XCTestCase {
    func testDurationBuckets() {
        XCTAssertEqual(AnalyticsBuckets.duration(-1), "under_5s")
        XCTAssertEqual(AnalyticsBuckets.duration(4.99), "under_5s")
        XCTAssertEqual(AnalyticsBuckets.duration(5), "5_to_14s")
        XCTAssertEqual(AnalyticsBuckets.duration(15), "15_to_29s")
        XCTAssertEqual(AnalyticsBuckets.duration(30), "30_to_59s")
        XCTAssertEqual(AnalyticsBuckets.duration(60), "1_to_2m")
        XCTAssertEqual(AnalyticsBuckets.duration(120), "over_2m")
    }

    func testLatencyBuckets() {
        XCTAssertEqual(AnalyticsBuckets.latency(-1), "under_1s")
        XCTAssertEqual(AnalyticsBuckets.latency(0.99), "under_1s")
        XCTAssertEqual(AnalyticsBuckets.latency(1), "1_to_2s")
        XCTAssertEqual(AnalyticsBuckets.latency(2), "2_to_5s")
        XCTAssertEqual(AnalyticsBuckets.latency(5), "5_to_10s")
        XCTAssertEqual(AnalyticsBuckets.latency(10), "over_10s")
    }

    func testPrivacyAllowlistDropsSensitiveAndUnneededProperties() {
        let properties = AnalyticsPrivacy.sanitized([
            "engine": "whisperkit",
            "outcome": "success",
            "$app_version": "1.8.0",
            "$locale": "en_CA",
            "$timezone": "America/Vancouver",
            "transcript": "sensitive text",
            "error": "raw error",
        ])

        XCTAssertEqual(properties["engine"] as? String, "whisperkit")
        XCTAssertEqual(properties["outcome"] as? String, "success")
        XCTAssertEqual(properties["$app_version"] as? String, "1.8.0")
        XCTAssertNil(properties["$locale"])
        XCTAssertNil(properties["$timezone"])
        XCTAssertNil(properties["transcript"])
        XCTAssertNil(properties["error"])
    }

    func testPrivacyAllowlistRejectsUnknownEvents() {
        XCTAssertTrue(AnalyticsPrivacy.allowedEvents.contains("dictation_completed"))
        XCTAssertFalse(AnalyticsPrivacy.allowedEvents.contains("$screen"))
        XCTAssertFalse(AnalyticsPrivacy.allowedEvents.contains("$exception"))
    }
}
