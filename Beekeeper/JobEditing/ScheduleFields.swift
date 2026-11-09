import HiveKit
import SwiftUI

/// The times of day the job runs, as many as the person likes.
struct ScheduleFields: View {
    /// Hive runs jobs in its own Mac's time zone, which may not be this device's. Showing each time in
    /// GMT keeps the picker from shifting it, so 02:00 stays 02:00 wherever Beekeeper is.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    @Binding var times: [JobEditorDraft.Time]
    let problems: JobFieldProblems

    var body: some View {
        Section {
            ForEach($times) { $time in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        DatePicker("Time", selection: date(for: $time), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .environment(\.timeZone, .gmt)
                            .environment(\.calendar, Self.calendar)
                        Spacer()
                        RemoveRowButton(label: "Remove Time") { times.removeAll { $0.id == time.id } }
                            .disabled(times.count == 1)
                    }
                        FieldProblemText(problems[.time, times.firstIndex { $0.id == time.id }])
                }
            }
            Button("Add Time", systemImage: "plus") { times.append(JobEditorDraft.Time(time: nextFreeTime)) }
            FieldProblemText(problems[.times])
        } header: {
            Text("Runs At")
        } footer: {
            Text("In the time zone of the Hive's Mac. A run missed while the Mac was off or asleep happens once it's back.")
                .foregroundStyle(.secondary)
        }
    }

    private func date(for time: Binding<JobEditorDraft.Time>) -> Binding<Date> {
        Binding {
            let time = time.wrappedValue.time
            let components = DateComponents(year: 2001, month: 1, day: 1, hour: time.hour, minute: time.minute)
            return Self.calendar.date(from: components) ?? .distantPast
        } set: { date in
            let components = Self.calendar.dateComponents([.hour, .minute], from: date)
            time.wrappedValue.time = TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
        }
    }

    /// Twelve hours after the last time, or the next hour after that which isn't taken.
    private var nextFreeTime: TimeOfDay {
        let taken = Set(times.map(\.time))
        let start = times.last.map { ($0.time.hour + 12) % 24 } ?? 0
        for offset in 0 ..< 24 {
            let time = TimeOfDay(hour: (start + offset) % 24, minute: times.last?.time.minute ?? 0)
            if !taken.contains(time) { return time }
        }
        return TimeOfDay(hour: start, minute: 0)
    }
}
