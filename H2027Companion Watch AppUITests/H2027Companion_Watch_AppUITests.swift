//
//  H2027Companion_Watch_AppUITests.swift
//  H2027Companion Watch AppUITests
//
//  Created by Shawn Huang on 11/16/26.
//

import XCTest

final class H2027Companion_Watch_AppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDoseDetailShowsRecordingActions() throws {
        let app = launchWithDemoDose()
        let row = app.buttons["watch.dose.row.watch-demo-dose"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(app.buttons["watch.dose.taken"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["watch.dose.snoozed"].exists)
        XCTAssertTrue(app.buttons["watch.dose.skipped"].exists)
    }

    @MainActor
    func testTakenActionUpdatesSummary() throws {
        let app = launchWithDemoDose()
        let row = app.buttons["watch.dose.row.watch-demo-dose"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let takenButton = app.buttons["watch.dose.taken"]
        XCTAssertTrue(takenButton.waitForExistence(timeout: 3))
        takenButton.tap()

        let summary = app.staticTexts["watch.summary.completed"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(summary.label.contains("1/1"))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    private func launchWithDemoDose() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--watch-demo-dose")
        app.launch()
        return app
    }
}
