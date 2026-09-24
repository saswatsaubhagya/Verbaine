import Foundation
import Testing
@testable import Verbaine

@Test func hostAppBundleIdentifierIsVerbaine() {
    #expect(Bundle.main.bundleIdentifier == "in.saswatsaubhagya.verbaine")
}
