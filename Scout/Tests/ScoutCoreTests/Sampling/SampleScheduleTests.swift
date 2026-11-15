import ScoutCore
import Testing

struct SampleScheduleTests {
    private static let second: Int64 = 1_000_000_000

    @Test("The next mark is the next multiple of 10 seconds, never the current moment")
    func nextMark() {
        #expect(SampleSchedule.nextMark(after: 1_700_000_003 * Self.second) == 1_700_000_010 * Self.second)
        #expect(SampleSchedule.nextMark(after: 1_700_000_009 * Self.second + 999_999_999) == 1_700_000_010 * Self.second)
        #expect(SampleSchedule.nextMark(after: 1_700_000_010 * Self.second) == 1_700_000_020 * Self.second)
    }
}
