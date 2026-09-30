import XCTest

/// Walks the app through a few plays in both orientations and saves screenshots
/// to $SCREENSHOT_DIR (for checking layout, and later for the App Store listing).
final class ScreenshotTests: XCTestCase {
    private var outDir: URL? {
        ProcessInfo.processInfo.environment["SCREENSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private func shoot(_ name: String, args: [String], orientation: UIDeviceOrientation, openSetup: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments = args
        XCUIDevice.shared.orientation = orientation
        app.launch()
        if openSetup { app.buttons["Set Up Situation"].tap() }
        sleep(5)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = outDir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
        }
        app.terminate()
    }

    func testScreens() {
        shoot("landscape-ll-gap", args: ["-level", "ll", "-hit", "gap_LC", "-runners", "100", "-outs", "0", "-reveal", "YES"], orientation: .landscapeLeft)
        shoot("landscape-setup", args: ["-level", "u14", "-hit", "single_RF", "-runners", "010", "-outs", "1"], orientation: .landscapeLeft)
        shoot("portrait-setup-open", args: ["-level", "hs", "-hit", "gb_SS", "-runners", "100", "-outs", "0"], orientation: .portrait, openSetup: true)
        shoot("landscape-scrubbed", args: ["-level", "hs", "-hit", "single_RF", "-runners", "010", "-outs", "1", "-reveal", "YES", "-at", "2400"], orientation: .landscapeLeft)
        shoot("portrait-quiz", args: ["-level", "ll", "-hit", "bunt", "-runners", "110", "-outs", "0", "-focus", "2B", "-reveal", "YES"], orientation: .portrait)
    }
}
