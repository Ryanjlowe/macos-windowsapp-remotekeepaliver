import XCTest
@testable import KeepAliveCore

final class SessionWindowSelectorTests: XCTestCase {
    private func win(_ id: Int, _ title: String, _ w: CGFloat, _ h: CGFloat, onScreen: Bool = true) -> WindowInfo {
        WindowInfo(id: id, pid: 100, title: title, frame: CGRect(x: 0, y: 0, width: w, height: h), isOnScreen: onScreen)
    }

    /// The inventory measured in docs/scout-findings.md.
    private var scoutInventory: [WindowInfo] {
        [
            win(1, "Australia Desktop", 3292, 1410),
            win(2, "Windows App", 1728, 1017),
            win(3, "", 3440, 30, onScreen: false),
            win(4, "", 5120, 30, onScreen: false),
            win(5, "", 810, 440, onScreen: false),
            win(6, "", 64, 64, onScreen: false),
        ]
    }

    func testChoosesSessionFromScoutInventory() {
        let result = SessionWindowSelector.select(from: scoutInventory)
        XCTAssertEqual(result.map(\.title), ["Australia Desktop"])
    }

    func testRejectsConnectionCenter() {
        let result = SessionWindowSelector.select(from: [win(2, "Windows App", 1728, 1017)])
        XCTAssertTrue(result.isEmpty)
    }

    func testRejectsUntitledOffscreenWindows() {
        let result = SessionWindowSelector.select(from: Array(scoutInventory.suffix(4)))
        XCTAssertTrue(result.isEmpty)
    }

    func testRejectsTitledButOffscreenWindow() {
        let result = SessionWindowSelector.select(from: [win(1, "Australia Desktop", 3292, 1410, onScreen: false)])
        XCTAssertTrue(result.isEmpty)
    }

    func testOrdersTwoSessionsByAreaLargestFirst() {
        let windows = [
            win(1, "Berlin Desktop", 1000, 700),
            win(2, "Australia Desktop", 3292, 1410),
            win(3, "Windows App", 1728, 1017),
        ]
        XCTAssertEqual(SessionWindowSelector.select(from: windows).map(\.title), ["Australia Desktop", "Berlin Desktop"])
    }

    func testDesktopSuffixIsCaseInsensitive() {
        let result = SessionWindowSelector.select(from: [win(1, "work DESKTOP", 800, 600)])
        XCTAssertEqual(result.count, 1)
    }

    func testRenamedConnectionChosenWhenNothingEndsWithDesktop() {
        let windows = [win(1, "Build Box", 1600, 900), win(2, "Windows App", 1728, 1017)]
        XCTAssertEqual(SessionWindowSelector.select(from: windows).map(\.title), ["Build Box"])
    }

    func testDesktopSuffixPreferredOverRenamedWindows() {
        let windows = [win(1, "Build Box", 3000, 2000), win(2, "Australia Desktop", 800, 600)]
        XCTAssertEqual(SessionWindowSelector.select(from: windows).map(\.title), ["Australia Desktop"])
    }

    func testRejectsDevicesAndOtherKnownTitles() {
        let windows = ["Devices", "Apps", "Settings", "Connection Center", "Preferences"].enumerated().map {
            win($0.offset, $0.element, 900, 700)
        }
        XCTAssertTrue(SessionWindowSelector.select(from: windows).isEmpty)
    }

    func testEmptyInput() {
        XCTAssertTrue(SessionWindowSelector.select(from: []).isEmpty)
    }
}
