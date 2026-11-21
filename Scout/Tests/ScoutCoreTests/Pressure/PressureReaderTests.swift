@testable import ScoutCore
import ScoutProtocol
import Testing

struct PressureReaderTests {
    @Test("A kernel without /proc/pressure sends none", arguments: CapturedServer.allCases)
    func withoutPressure(server: CapturedServer) {
        // Arrange
        var reader = PressureReader(files: server.files)

        // Act, Assert
        #expect(reader.read(elapsed: nil) == nil)
        #expect(reader.read(elapsed: 10) == nil)
    }

    @Test("Pressure is the share of time stalled since the previous reading, from the kernel's totals")
    func shares() throws {
        // Arrange: CPU without a full line, as before Linux 5.13.
        let server = try TemporaryServer()
        try server.write("/proc/pressure/cpu", "some avg10=9.00 avg60=9.00 avg300=9.00 total=1000000\n")
        try server.write("/proc/pressure/memory", """
            some avg10=0.00 avg60=0.00 avg300=0.00 total=0
            full avg10=0.00 avg60=0.00 avg300=0.00 total=0

            """)
        try server.write("/proc/pressure/io", """
            some avg10=0.00 avg60=0.00 avg300=0.00 total=5000000
            full avg10=0.00 avg60=0.00 avg300=0.00 total=4000000

            """)
        var reader = PressureReader(files: server.files)
        let first = reader.read(elapsed: nil)

        try server.write("/proc/pressure/cpu", "some avg10=9.00 avg60=9.00 avg300=9.00 total=3500000\n")
        try server.write("/proc/pressure/memory", """
            some avg10=0.00 avg60=0.00 avg300=0.00 total=1000000
            full avg10=0.00 avg60=0.00 avg300=0.00 total=500000

            """)
        // More stalled time than passed, since the totals and the uptime aren't read at one instant.
        try server.write("/proc/pressure/io", """
            some avg10=0.00 avg60=0.00 avg300=0.00 total=15500000
            full avg10=0.00 avg60=0.00 avg300=0.00 total=6000000

            """)

        // Act
        let pressure = reader.read(elapsed: 10)

        // Assert
        #expect(first == nil)
        #expect(pressure == PressureFigures(
            cpu: PressureStall(some: 0.25, full: nil),
            memory: PressureStall(some: 0.1, full: 0.05),
            inputOutput: PressureStall(some: 1, full: 0.2)
        ))
    }
}
