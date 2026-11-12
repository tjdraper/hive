import Foundation
import HiveKit
import Testing

struct ReleaseVersionTests {
    @Test("Orders versions by each number in turn, not as text", arguments: [
        ("2026.2", "2026.10"),
        ("2026.9", "2027.1"),
        ("2026.3", "2026.3.1"),
        ("2026.3.1", "2026.4"),
    ])
    func ordersByNumber(older: String, newer: String) throws {
        // Arrange
        let older = try #require(ReleaseVersion(older))
        let newer = try #require(ReleaseVersion(newer))

        // Act
        let isOlder = older < newer

        // Assert
        #expect(isOlder)
        #expect(!(newer < older))
    }

    @Test("Trailing zeros don't make a different version")
    func trailingZerosAreEqual() throws {
        // Arrange
        let short = try #require(ReleaseVersion("2026.3"))
        let long = try #require(ReleaseVersion("2026.3.0"))

        // Act
        let isEqual = short == long

        // Assert
        #expect(isEqual)
        #expect(!(short < long) && !(long < short))
        #expect(Set([short, long]).count == 1)
    }

    @Test("Refuses anything but numbers separated by dots", arguments: [
        "", "2026.", ".3", "2026..3", "2026.3-beta", "+2026", "v2026.3", "2026.٣",
    ])
    func refusesOtherText(text: String) {
        // Act
        let version = ReleaseVersion(text)

        // Assert
        #expect(version == nil)
    }

    @Test("Travels as the text it was made from")
    func codesAsText() throws {
        // Arrange
        let version = try #require(ReleaseVersion("2026.3.1"))

        // Act
        let encoded = try JSONEncoder().encode([version])
        let decoded = try JSONDecoder().decode([ReleaseVersion].self, from: encoded)

        // Assert
        #expect(String(bytes: encoded, encoding: .utf8) == #"["2026.3.1"]"#)
        #expect(decoded.first?.description == "2026.3.1")
    }
}
