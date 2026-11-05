import HiveCore
import Testing

struct HiveLogTests {
    @Test("The subsystem matches the log show predicate in AGENTS.md")
    func subsystem() {
        // Act
        let subsystem = HiveLog.subsystem

        // Assert
        #expect(subsystem == "com.buzzingpixel.Hive")
    }
}
