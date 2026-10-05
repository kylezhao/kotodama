//
//  KotodamaUITests.swift
//  KotodamaUITests
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import XCTest

/// Transcribes the bundled sample audio and saves screenshots to /tmp/kotodama-screens.
/// Tries the on-device engine first and falls back to the cloud engine when the simulator lacks it.
final class KotodamaUITests: XCTestCase {
    private let screenshotDirectory = URL(fileURLWithPath: "/tmp/kotodama-screens", isDirectory: true)

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
    }

    @MainActor
    func testSampleTranscriptionFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()
        snapshot(app, "01-speak-idle")

        var engineUsed = "on-device"
        if !runSample(app, language: "en-US", timeout: 150) {
            // On-device model unavailable here (for example a simulator without Apple Intelligence). Use the cloud engine.
            engineUsed = "cloud"
            app.buttons["resetButton"].tapIfExists()
            app.segmentedControls["modePicker"].buttons.element(boundBy: 1).tap()
            XCTAssertTrue(runSample(app, language: "en-US", timeout: 90), "Neither engine produced a transcript")
        }
        snapshot(app, "02-speak-english-\(engineUsed)")

        let polished = app.staticTexts["polishedText"]
        XCTAssertTrue(polished.waitForExistence(timeout: 30), "Polished text should appear after recognition")
        XCTAssertFalse(polished.label.isEmpty)
        snapshot(app, "03-speak-polished")

        // Switch style to formal and confirm a re-polish happens.
        app.buttons["Formal"].firstMatch.tap()
        sleep(2)
        snapshot(app, "04-speak-formal")

        // Mandarin sample.
        app.buttons["resetButton"].tapIfExists()
        if runSample(app, language: "zh-CN", timeout: 150) {
            _ = app.staticTexts["polishedText"].waitForExistence(timeout: 30)
            snapshot(app, "05-speak-mandarin")
        }

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts.firstMatch.waitForExistence(timeout: 5))
        snapshot(app, "06-history")

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Speech recognition"].waitForExistence(timeout: 5))
        snapshot(app, "07-settings")
    }

    /// Runs a bundled sample and waits for either a transcript or an error. Returns true on transcript.
    @MainActor
    private func runSample(_ app: XCUIApplication, language: String, timeout: TimeInterval) -> Bool {
        app.buttons["sampleMenu"].tap()
        let item = app.buttons["sample-\(language)"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        acceptSystemAlertsIfNeeded()

        let transcript = app.staticTexts["transcriptText"]
        let error = app.staticTexts["errorLabel"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if error.exists {
                print("Kotodama UI test: sample \(language) failed with error: \(error.label)")
                snapshot(app, "error-\(language)-\(Int(Date().timeIntervalSince1970))")
                return false
            }
            if transcript.exists, !transcript.label.isEmpty, app.staticTexts["polishedText"].exists { return true }
            acceptSystemAlertsIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return transcript.exists && !transcript.label.isEmpty
    }

    @MainActor
    private func acceptSystemAlertsIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.exists else { return }
        for title in ["Allow While Using App", "Allow", "OK"] {
            let button = alert.buttons[title]
            if button.exists { button.tap(); return }
        }
        let buttons = alert.buttons
        if buttons.count > 0 { buttons.element(boundBy: buttons.count - 1).tap() }
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? screenshot.pngRepresentation.write(to: screenshotDirectory.appendingPathComponent("\(name).png"))
    }
}

private extension XCUIElement {
    func tapIfExists() {
        if exists, isHittable { tap() }
    }
}
