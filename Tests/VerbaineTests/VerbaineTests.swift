import Foundation
import Testing
@testable import Polish

@Test func hostAppBundleIdentifierIsPolish() {
    #expect(Bundle.main.bundleIdentifier == "com.saswat.polish")
}
