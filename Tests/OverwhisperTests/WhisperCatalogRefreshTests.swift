import XCTest
import WhisperKit
@testable import Overwhisper

@MainActor
final class WhisperCatalogRefreshTests: XCTestCase {
    func testFailedRefreshPreservesLastSuccessfulList() async {
        var fail = false
        let custom = "openai_whisper-large-v3_123MB"
        let catalog = WhisperModelCatalog(loadRemoteSupport: {
            if fail { throw URLError(.notConnectedToInternet) }
            return ModelSupport(default: custom, supported: [custom])
        })
        await catalog.refresh()
        let previous = catalog.models
        XCTAssertTrue(catalog.didLoadRemoteCatalog)
        fail = true
        await catalog.refresh()
        XCTAssertEqual(catalog.models, previous)
        XCTAssertTrue(catalog.models.contains(WhisperModel(rawValue: custom)))
        XCTAssertTrue(catalog.lastRefreshFailed)
        XCTAssertFalse(catalog.isRefreshing)
    }

    func testOfflineFirstRefreshKeepsBundledAndLegacyChoices() async {
        let catalog = WhisperModelCatalog(loadRemoteSupport: { throw URLError(.notConnectedToInternet) })
        let previous = catalog.models
        await catalog.refresh()
        XCTAssertEqual(catalog.models, previous)
        XCTAssertFalse(catalog.didLoadRemoteCatalog)
        XCTAssertTrue(catalog.lastRefreshFailed)
        XCTAssertTrue(catalog.models.contains(.medium))
        XCTAssertTrue(catalog.models.contains(.mediumEn))
    }
}
