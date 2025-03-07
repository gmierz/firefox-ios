// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import XCTest
@testable import Client

final class ContentContainerTests: XCTestCase {
    private var profile: MockProfile!
    private var overlayModeManager: MockOverlayModeManager!

    override func setUp() {
        super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        FeatureFlagsManager.shared.initializeDeveloperFeatures(with: AppContainer.shared.resolve())
        self.profile = MockProfile()
        self.overlayModeManager = MockOverlayModeManager()
    }

    override func tearDown() {
        super.tearDown()
        self.profile = nil
        self.overlayModeManager = nil
        AppContainer.shared.reset()
    }

    func testCanAddHomepage() {
        let subject = ContentContainer(frame: .zero)
        let homepage = HomepageViewController(profile: profile, overlayManager: overlayModeManager)

        XCTAssertTrue(subject.canAdd(viewController: homepage))
    }

    func testCanAddHomepageOnceOnly() {
        let subject = ContentContainer(frame: .zero)
        let homepage = HomepageViewController(profile: profile, overlayManager: overlayModeManager)

        subject.addContent(viewController: homepage)
        XCTAssertFalse(subject.canAdd(viewController: homepage))
    }
}
