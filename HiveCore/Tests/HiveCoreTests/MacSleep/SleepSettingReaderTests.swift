@testable import HiveCore
import HiveKit
import Testing

struct SleepSettingReaderTests {
    private static let desktop = """
    System-wide power settings:
     SleepDisabled\t\t0
    Currently in use:
     standby              1
     disksleep            10
     sleep                0 (sleep prevented by powerd, caffeinate)
     displaysleep         60 (display sleep prevented by UniversalControl)
    """

    private static let laptop = """
    System-wide power settings:
     SleepDisabled\t\t0
    Currently in use:
     standby              1
     sleep                1 (sleep prevented by Hive)
     displaysleep         2
    """

    private static let disabled = """
    System-wide power settings:
     SleepDisabled\t\t1
    Currently in use:
     sleep                10
    """

    @Test("The sleep timer is read from the settings in use, whatever is holding sleep off now", arguments: [
        (desktop, MacSleep.never),
        (laptop, .afterIdle(minutes: 1)),
        (disabled, .never),
        ("", .unknown),
        ("Currently in use:\n sleep  soon\n", .unknown),
    ])
    func reads(output: String, expected: MacSleep) {
        // Act
        let setting = SleepSettingReader.setting(in: output)

        // Assert
        #expect(setting == expected)
    }
}
