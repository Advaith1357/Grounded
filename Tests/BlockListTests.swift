import XCTest

final class BlockListTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let name = "grounded.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testAnEmptyListIsNeverBlockingEvenWhenSwitchedOn() {
        let list = BlockList(name: "Social", isEnabled: true)
        XCTAssertEqual(list.itemCount, 0)
        XCTAssertFalse(list.isBlocking)
    }

    func testBlockingNamesAndCombinedSelectionIgnoreListsWithNothingInThem() {
        let lists = [BlockList(name: "Social"), BlockList(name: "Games", isEnabled: false)]
        XCTAssertTrue(BlockLists.blockingNames(of: lists).isEmpty)
        let combined = BlockLists.combinedSelection(of: lists)
        XCTAssertTrue(combined.applicationTokens.isEmpty)
        XCTAssertTrue(combined.categoryTokens.isEmpty)
        XCTAssertTrue(combined.webDomainTokens.isEmpty)
    }

    func testNewListsAreSwitchedOnByDefault() {
        XCTAssertTrue(BlockList(name: "Anything").isEnabled)
    }

    func testListsSurviveAnEncodeDecodeRoundTrip() throws {
        var lists = [BlockList(name: "Social"), BlockList(name: "Games"), BlockList(name: "Video")]
        lists[1].isEnabled = false
        lists[2].name = "Streaming"
        let data = try JSONEncoder().encode(lists)
        XCTAssertEqual(try JSONDecoder().decode([BlockList].self, from: data), lists)
    }

    func testPersistenceReturnsNilBeforeAnythingIsSaved() {
        XCTAssertNil(SharedBlockLists.load(from: makeDefaults()))
    }

    func testSavedListsComeBackIntactAndInOrder() {
        let defaults = makeDefaults()
        var lists = [BlockList(name: "Social"), BlockList(name: "Games")]
        lists[0].isEnabled = false
        lists.append(BlockList(name: "Focus"))
        SharedBlockLists.save(lists, to: defaults)
        XCTAssertEqual(SharedBlockLists.load(from: defaults), lists)
    }

    func testAnEmptySavedListIsDistinguishableFromNeverSaved() {
        // Deleting every list must not make the starters reappear on next launch.
        let defaults = makeDefaults()
        SharedBlockLists.save([], to: defaults)
        XCTAssertEqual(SharedBlockLists.load(from: defaults), [])
    }

    func testCorruptStoredDataLoadsAsNilRatherThanCrashing() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: SharedBlockLists.key)
        XCTAssertNil(SharedBlockLists.load(from: defaults))
    }

    func testStatusTextWhenBlockingIsAvailable() {
        XCTAssertEqual(BlockList(name: "A", isEnabled: true).statusText(blockingAvailable: true), "ON · PICK APPS TO START BLOCKING")
        XCTAssertEqual(BlockList(name: "A", isEnabled: false).statusText(blockingAvailable: true), "NO APPS YET")
    }

    func testStatusTextSaysPausedWhenScreenTimeIsOff() {
        // Whatever the switch says, a build without Screen Time never blocks.
        XCTAssertEqual(BlockList(name: "A", isEnabled: true).statusText(blockingAvailable: false), "PAUSED · NO APPS YET")
        XCTAssertEqual(BlockList(name: "A", isEnabled: false).statusText(blockingAvailable: false), "PAUSED · NO APPS YET")
    }

    func testAppGroupIsDerivedFromTheBundleID() {
        XCTAssertEqual(AppGroup.identifier(forBundleID: "com.advaith.grounded", isExtension: false), "group.com.advaith.grounded")
    }

    func testExtensionsArriveAtTheSameGroupAsTheApp() {
        for suffix in ["ShieldConfiguration", "ShieldAction", "DeviceActivityMonitor"] {
            XCTAssertEqual(
                AppGroup.identifier(forBundleID: "com.advaith.grounded.\(suffix)", isExtension: true),
                "group.com.advaith.grounded"
            )
        }
    }

    func testAppGroupFallsBackWhenThereIsNoBundleID() {
        XCTAssertEqual(AppGroup.identifier(forBundleID: nil, isExtension: false), "group.com.grounded.app")
        XCTAssertEqual(AppGroup.identifier(forBundleID: "", isExtension: true), "group.com.grounded.app")
    }
}
