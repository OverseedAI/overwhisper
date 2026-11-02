import XCTest
@testable import Overwhisper

@MainActor
final class EngineInitializationQueueTests: XCTestCase {
    func testSelectionChangesDuringStartupInitializeLatestSelection() async {
        var selection = "Small"
        var initialized: [String] = []
        var release: CheckedContinuation<Void, Never>?
        let firstStarted = expectation(description: "First initialization suspended")
        let queue = EngineInitializationQueue {
            initialized.append(selection)
            if initialized.count == 1 {
                await withCheckedContinuation { continuation in
                    release = continuation
                    firstStarted.fulfill()
                }
            }
        }
        queue.request()
        await fulfillment(of: [firstStarted], timeout: 2)
        selection = "Medium"
        queue.request()
        selection = "Large"
        queue.request()
        release?.resume()
        await queue.waitUntilIdle()
        XCTAssertEqual(initialized, ["Small", "Large"])
    }

    func testNewRequestAfterIdleStartsAgain() async {
        var count = 0
        let queue = EngineInitializationQueue { count += 1 }
        queue.request()
        await queue.waitUntilIdle()
        queue.request()
        await queue.waitUntilIdle()
        XCTAssertEqual(count, 2)
    }
}
