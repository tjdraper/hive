@testable import ScoutCore
import Testing

struct OSReleaseTests {
    @Test("Quotes are removed and escaped characters kept")
    func quoting() {
        // Arrange
        let text = """
            # A comment
            PRETTY_NAME='Example "Linux" 1'
            NAME="Back\\\\slash \\"Linux\\""
            VERSION=1
            """

        // Act
        let release = OSRelease(parsing: text)

        // Assert
        #expect(release.prettyName == "Example \"Linux\" 1")
        #expect(release.name == "Back\\slash \"Linux\"")
        #expect(release.version == "1")
    }

    @Test("Without a pretty name, the name and version stand in")
    func withoutPrettyName() {
        #expect(OSRelease(parsing: "NAME=Example\nVERSION=\"2 (Two)\"").distribution == "Example 2 (Two)")
        #expect(OSRelease(parsing: "NAME=Example").distribution == "Example")
        #expect(OSRelease(parsing: "ID=example").distribution == nil)
    }
}
