import XCTest

@testable import Overwhisper

@MainActor
final class TranscriptionTaskControllerTests: XCTestCase {
  private final class Gate {
    var isOpen = false
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
      if isOpen { return }
      await withCheckedContinuation { continuation = $0 }
    }
    func resume() { isOpen = true; continuation?.resume(); continuation = nil }
  }

  func testCancelledTaskCannotPublishOrFinishNewerOperation() async {
    let controller = TranscriptionTaskController()
    let firstGate = Gate()
    let secondGate = Gate()
    var delivered: [String] = []
    var finished: [String] = []
    let first = controller.start(operation: { id in
      await firstGate.wait() // Deliberately ignores cancellation like an engine can.
      if controller.isCurrent(id) { delivered.append("first") }
    }, onFinish: { finished.append("first") })
    await Task.yield()
    controller.cancel()
    let second = controller.start(operation: { id in
      await secondGate.wait()
      if controller.isCurrent(id) { delivered.append("second") }
    }, onFinish: { finished.append("second") })
    await Task.yield()

    firstGate.resume()
    await first.value
    XCTAssertTrue(delivered.isEmpty)
    XCTAssertTrue(finished.isEmpty, "Old cleanup must not clear the new retry's UI")
    XCTAssertNotNil(controller.currentID)

    secondGate.resume()
    await second.value
    XCTAssertEqual(delivered, ["second"])
    XCTAssertEqual(finished, ["second"])
    XCTAssertNil(controller.currentID)
  }

  func testCancelledFallbackCannotPublishLateResponse() async {
    let controller = TranscriptionTaskController()
    let response = Gate()
    var committed = false
    var cleanedUp = false
    let task = controller.start(operation: { id in
      await response.wait()
      if controller.isCurrent(id) { committed = true }
    }, onFinish: { cleanedUp = true })
    await Task.yield()
    controller.cancel()
    response.resume()
    await task.value
    XCTAssertFalse(committed)
    XCTAssertFalse(cleanedUp, "Cancellation handles UI cleanup synchronously")
    XCTAssertNil(controller.currentID)
  }
}
