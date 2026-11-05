import Darwin
@testable import HiveCore
import Testing

struct FullDiskAccessProbeTests {
    @Test("Reports what opening the protected file says", arguments: [
        (Int32(0), FullDiskAccess.granted),
        (EPERM, .missing),
        (EACCES, .missing),
        (ENOENT, .unknown),
    ])
    func reports(result: Int32, expected: FullDiskAccess) {
        // Arrange
        let probe = FullDiskAccessProbe { _ in result }

        // Act
        let access = probe.check()

        // Assert
        #expect(access == expected)
    }
}
