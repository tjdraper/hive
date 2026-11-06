import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct BackupJobDraftCheckTests {
    private static func problems(in draft: BackupJobDraft) throws -> [ConfigurationProblem] {
        do {
            _ = try BackupJobDraftCheck.validated(draft)
            return []
        } catch ConfigurationChangeError.refused(let problems) {
            return problems
        }
    }

    private static func database(container: String? = nil, user: String = "site", name: String = "site") -> DatabaseSettings {
        DatabaseSettings(kind: .mysql, location: container.map { .container(serviceName: $0) } ?? .host, user: user, name: name)
    }

    private static func job(directories: [BackupDirectory]) -> BackupJobDraft {
        var draft = ConfigurationSamples.job()
        draft.directories = directories
        return draft
    }

    @Test("The sample job passes")
    func samplePasses() throws {
        // Act / Assert
        #expect(try Self.problems(in: ConfigurationSamples.job()).isEmpty)
    }

    @Test(
        "A directory's path on the server has to be absolute",
        arguments: [
            ("var/www", ConfigurationProblemReason.notAbsolute),
            ("~/www", .notAbsolute),
            ("", .invalid),
            ("/var/www\n", .invalid),
        ]
    )
    func refusesPath(path: String, reason: ConfigurationProblemReason) throws {
        // Arrange
        let draft = Self.job(directories: [BackupDirectory(path: path, folder: "www")])

        // Act / Assert
        #expect(try Self.problems(in: draft) == [ConfigurationProblem(field: .directoryPath, index: 0, reason: reason)])
    }

    @Test("A path keeps everything but its trailing slashes, and the root stays the root")
    func trimsPath() throws {
        // Arrange
        let draft = Self.job(directories: [
            BackupDirectory(path: "/var/www//", folder: "www"),
            BackupDirectory(path: "/", folder: "root"),
            BackupDirectory(path: "/srv/My Site", folder: "site"),
        ])

        // Act
        let validated = try BackupJobDraftCheck.validated(draft)

        // Assert
        #expect(validated.directories.map(\.path) == ["/var/www", "/", "/srv/My Site"])
    }

    @Test(
        "A folder has to stay inside the snapshot",
        arguments: [
            ("/uploads", ConfigurationProblemReason.notRelative),
            ("..", .dotPart),
            ("../uploads", .dotPart),
            ("images/../../uploads", .dotPart),
            ("./uploads", .dotPart),
            ("images/.", .dotPart),
            ("images//galleries", .emptyPart),
            ("images/", .emptyPart),
            ("", .invalid),
            ("uploads\u{0}", .invalid),
            ("up\nloads", .invalid),
            (String(repeating: "a", count: 256), .invalid),
        ]
    )
    func refusesFolder(folder: String, reason: ConfigurationProblemReason) throws {
        // Arrange
        let draft = Self.job(directories: [BackupDirectory(path: "/var/www", folder: folder)])

        // Act / Assert
        #expect(try Self.problems(in: draft) == [ConfigurationProblem(field: .directoryFolder, index: 0, reason: reason)])
    }

    @Test("Nested folders, dots within names and spaces are fine", arguments: ["images/galleries", "..hidden", "file.d", "My Files"])
    func acceptsFolder(folder: String) throws {
        // Arrange
        let draft = Self.job(directories: [BackupDirectory(path: "/var/www", folder: folder)])

        // Act / Assert
        #expect(try Self.problems(in: draft).isEmpty)
    }

    @Test("A folder used twice is refused at its second use")
    func refusesDuplicateFolder() throws {
        // Arrange
        let draft = Self.job(directories: [
            BackupDirectory(path: "/a", folder: "files"),
            BackupDirectory(path: "/b", folder: "other"),
            BackupDirectory(path: "/c", folder: "files"),
        ])

        // Act / Assert
        #expect(try Self.problems(in: draft) == [ConfigurationProblem(field: .directoryFolder, index: 2, reason: .duplicate)])
    }

    @Test("A folder inside another of the job's folders is refused, in either order, while a similar name isn't")
    func refusesFolderInsideAnother() throws {
        // Arrange
        let draft = Self.job(directories: [
            BackupDirectory(path: "/a", folder: "images/galleries/2026"),
            BackupDirectory(path: "/b", folder: "images"),
            BackupDirectory(path: "/c", folder: "images-old"),
            BackupDirectory(path: "/d", folder: "imagesgalleries"),
        ])

        // Act / Assert
        #expect(try Self.problems(in: draft) == [ConfigurationProblem(field: .directoryFolder, index: 0, reason: .insideAnother)])
    }

    @Test("Folders differing only in case are different folders on the case-sensitive backup drive")
    func foldersAreCaseSensitive() throws {
        // Arrange
        let draft = Self.job(directories: [BackupDirectory(path: "/a", folder: "Files"), BackupDirectory(path: "/b", folder: "files")])

        // Act / Assert
        #expect(try Self.problems(in: draft).isEmpty)
    }

    @Test(
        "Times have to be real times of day, each once",
        arguments: [
            ([TimeOfDay(hour: 24, minute: 0)], [ConfigurationProblem(field: .time, index: 0, reason: .outOfRange)]),
            ([TimeOfDay(hour: -1, minute: 0)], [ConfigurationProblem(field: .time, index: 0, reason: .outOfRange)]),
            ([TimeOfDay(hour: 2, minute: 60)], [ConfigurationProblem(field: .time, index: 0, reason: .outOfRange)]),
            (
                [TimeOfDay(hour: 2, minute: 0), TimeOfDay(hour: 2, minute: 0)],
                [ConfigurationProblem(field: .time, index: 1, reason: .duplicate)]
            ),
            ([], [ConfigurationProblem(field: .times, reason: .missing)]),
        ]
    )
    func refusesTimes(times: [TimeOfDay], problems: [ConfigurationProblem]) throws {
        // Arrange
        var draft = ConfigurationSamples.job()
        draft.times = times

        // Act / Assert
        #expect(try Self.problems(in: draft) == problems)
    }

    @Test("Midnight and the last minute of the day are times a job can run, and come back in order")
    func acceptsEdgeTimes() throws {
        // Arrange
        var draft = ConfigurationSamples.job()
        draft.times = [TimeOfDay(hour: 23, minute: 59), TimeOfDay(hour: 0, minute: 0)]

        // Act
        let validated = try BackupJobDraftCheck.validated(draft)

        // Assert
        #expect(validated.times == [TimeOfDay(hour: 0, minute: 0), TimeOfDay(hour: 23, minute: 59)])
    }

    @Test(
        "Tiers have to keep at least the newest daily snapshot, within sensible limits",
        arguments: [
            (0, 12, [ConfigurationField.dailySnapshots]),
            (3651, 12, [.dailySnapshots]),
            (7, -1, [.monthlySnapshots]),
            (7, 1201, [.monthlySnapshots]),
            (1, 0, []),
            (3650, 1200, []),
        ]
    )
    func checksTiers(daily: Int, monthly: Int, fields: [ConfigurationField]) throws {
        // Arrange
        var draft = ConfigurationSamples.job()
        draft.retention = RetentionTiers(dailySnapshots: daily, monthlySnapshots: monthly)

        // Act / Assert
        #expect(try Self.problems(in: draft) == fields.map { ConfigurationProblem(field: $0, reason: .outOfRange) })
    }

    @Test("A job with neither directories nor databases is refused, and one with only either is fine")
    func needsSomethingToBackUp() throws {
        // Arrange
        var empty = ConfigurationSamples.job()
        empty.directories = []
        empty.databases = []
        var directoriesOnly = ConfigurationSamples.job()
        directoriesOnly.databases = []
        var databasesOnly = ConfigurationSamples.job()
        databasesOnly.directories = []

        // Act / Assert
        #expect(try Self.problems(in: empty) == [ConfigurationProblem(field: .directories, reason: .nothingToBackUp)])
        #expect(try Self.problems(in: directoriesOnly).isEmpty)
        #expect(try Self.problems(in: databasesOnly).isEmpty)
    }

    @Test(
        "A database's names and password are refused when a dump command or file name couldn't hold them",
        arguments: [
            (database(user: "site", name: "-e"), "x", ConfigurationField.databaseName),
            (database(user: "site", name: "a/b"), "x", .databaseName),
            (database(user: "site", name: "site; drop"), "x", .databaseName),
            (database(user: "site", name: ""), "x", .databaseName),
            (database(user: "--all", name: "site"), "x", .databaseUser),
            (database(user: "si'te", name: "site"), "x", .databaseUser),
            (database(container: ""), "x", .databaseServiceName),
            (database(container: "_db"), "x", .databaseServiceName),
            (database(container: "db name"), "x", .databaseServiceName),
            (database(user: "site", name: "site"), "", .databasePassword),
            (database(user: "site", name: "site"), "line\nbreak", .databasePassword),
        ]
    )
    func refusesDatabase(settings: DatabaseSettings, password: String, field: ConfigurationField) throws {
        // Arrange
        var draft = ConfigurationSamples.job()
        draft.databases = [BackupDatabaseDraft(id: nil, settings: settings, password: password)]

        // Act / Assert
        #expect(try Self.problems(in: draft) == [ConfigurationProblem(field: field, index: 0, reason: .invalid)])
    }

    @Test("Two databases with the same name, or the same ID, in one job are refused")
    func refusesDuplicateDatabases() throws {
        // Arrange
        let id = UUID()
        var draft = ConfigurationSamples.job()
        draft.databases = [
            BackupDatabaseDraft(id: id, settings: ConfigurationSamples.database, password: nil),
            BackupDatabaseDraft(id: id, settings: Self.database(user: "app", name: "app"), password: nil),
            BackupDatabaseDraft(id: nil, settings: Self.database(user: "app", name: "site"), password: nil),
        ]

        // Act / Assert
        #expect(try Self.problems(in: draft) == [
            ConfigurationProblem(field: .database, index: 1, reason: .duplicate),
            ConfigurationProblem(field: .databaseName, index: 2, reason: .duplicate),
        ])
    }
}
