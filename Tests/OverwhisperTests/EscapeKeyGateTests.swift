import XCTest
@testable import Overwhisper

final class EscapeKeyGateTests: XCTestCase {
    func testIdleEscapePassesThrough() {
        var gate = EscapeKeyGate()
        XCTAssertEqual(gate.handle(keyCode: 53, isKeyDown: true, isRepeat: false, isActive: false), .passThrough)
        XCTAssertEqual(gate.handle(keyCode: 53, isKeyDown: false, isRepeat: false, isActive: false), .passThrough)
    }

    func testCancellationConsumesWholePressAfterBecomingIdle() {
        var gate = EscapeKeyGate()
        XCTAssertEqual(gate.handle(keyCode: 53, isKeyDown: true, isRepeat: false, isActive: true), .cancelAndConsume)
        XCTAssertEqual(gate.handle(keyCode: 53, isKeyDown: true, isRepeat: true, isActive: false), .consume)
        XCTAssertEqual(gate.handle(keyCode: 53, isKeyDown: false, isRepeat: false, isActive: false), .consume)
        XCTAssertEqual(gate.handle(keyCode: 53, isKeyDown: true, isRepeat: false, isActive: false), .passThrough)
    }

    func testEscapeHeldBeforeRecordingDoesNotCancelOnRepeatOrRelease() {
        var gate = EscapeKeyGate()
        XCTAssertEqual(gate.handle(keyCode: 53, isKeyDown: true, isRepeat: false, isActive: false), .passThrough)
        XCTAssertEqual(gate.handle(keyCode: 53, isKeyDown: true, isRepeat: true, isActive: true), .passThrough)
        XCTAssertEqual(gate.handle(keyCode: 53, isKeyDown: false, isRepeat: false, isActive: true), .passThrough)
    }

    func testOtherKeysDoNotAffectTheCancellingPress() {
        var gate = EscapeKeyGate()
        XCTAssertEqual(gate.handle(keyCode: 0, isKeyDown: true, isRepeat: false, isActive: true), .passThrough)
        XCTAssertEqual(gate.handle(keyCode: 53, isKeyDown: true, isRepeat: false, isActive: true), .cancelAndConsume)
        XCTAssertEqual(gate.handle(keyCode: 0, isKeyDown: false, isRepeat: false, isActive: false), .passThrough)
        XCTAssertEqual(gate.handle(keyCode: 53, isKeyDown: false, isRepeat: false, isActive: false), .consume)
    }

    func testFreshPressRecoversFromAMissedKeyUp() {
        var gate = EscapeKeyGate()
        XCTAssertEqual(gate.handle(keyCode: 53, isKeyDown: true, isRepeat: false, isActive: true), .cancelAndConsume)
        XCTAssertEqual(gate.handle(keyCode: 53, isKeyDown: true, isRepeat: false, isActive: false), .passThrough)
        XCTAssertEqual(gate.handle(keyCode: 53, isKeyDown: false, isRepeat: false, isActive: false), .passThrough)
    }
}
