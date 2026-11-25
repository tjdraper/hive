import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import ScoutProtocol
import Testing

struct ContainerNamingTests {
    private static let firstDB = TestMetrics.containerID(0xA1)
    private static let replacementDB = TestMetrics.containerID(0xA2)
    private static let shopDB = TestMetrics.containerID(0xB1)
    private static let blogDB = TestMetrics.containerID(0xC1)
    private static let loose = TestMetrics.containerID(0xD1)

    /// What `docker ps` prints on the server: Swarm replicas, two Compose projects that each have a
    /// `db`, and a container with no service at all.
    private static let listing = [
        "\(firstDB)\tbuzzingpixel_db.1.tatuwopj5rl0\tbuzzingpixel_db\t\t",
        "\(replacementDB)\tbuzzingpixel_db.1.n2zbr1sruif0\tbuzzingpixel_db\t\t",
        "\(shopDB)\tshop-db-1\t\tshop\tdb",
        "\(blogDB)\tblog-db-1\t\tblog\tdb",
        "\(loose)\tadminer,shop-db-1/adminer\t\t\t",
    ].joined(separator: "\n") + "\n"

    private let fixture: APIFixture
    private let server: Server
    private let scout: TestScout

    init() async throws {
        fixture = try APIFixture()
        try fixture.setAddressOptions()
        server = try await fixture.addServer()
        try await fixture.confirmHostKey(of: server)
        scout = try await fixture.enrollScout(for: server)
    }

    private var now: Int64 {
        Int64(fixture.signIn.clock.now.timeIntervalSince1970)
    }

    /// Each test names containers itself before reporting samples that hold them, so the naming a
    /// kept report starts on a task of its own, which a test couldn't wait for, finds nothing to do.
    private func report(_ samples: [MetricsSample]) async throws {
        let token = try await fixture.scoutToken(scout)
        let body = try JSONEncoder().encode(TestMetrics.report(samples, sentAt: now))
        let answer = try await fixture.send(.post, ScoutEndpoint.metrics, token: token, body: body)
        #expect(answer.status == .noContent)
    }

    private func sample(at takenAt: Int64, containers ids: [String], cpuCores: Double = 0.5) -> MetricsSample {
        var sample = TestMetrics.sample(at: takenAt)
        var containers = TestMetrics.cgroups(ids, cpuCores: cpuCores)
        for index in containers.top.indices {
            containers.top[index].commands = ["postgres"]
        }
        sample.containers = containers
        sample.services = TestMetrics.cgroups(["cron.service"], cpuCores: 0.25)
        return sample
    }

    private func name(_ ids: [String]) async -> ContainerNamingWorkflow.Outcome {
        await fixture.api.containerNaming.nameContainers(of: sample(at: now, containers: ids), forServer: server.id)
    }

    private func moment(at time: Int64) async throws -> CgroupMoment {
        let answer = try await fixture.send(.get, HiveEndpoint.containers(ofServer: server.id, at: time))
        guard answer.status == .ok else { throw APIFixtureError.unexpectedStatus(answer.status) }
        return try answer.decoded(as: CgroupMoment.self)
    }

    private func dockerListing(status: Int32 = 0) {
        fixture.ssh.answer { _, _ in
            ChildProcess.Result(status: status, standardOutput: Data(Self.listing.utf8), standardError: Data())
        }
    }

    @Test("docker ps output is read by full ID, a linked container by its own name, and lines that aren't its own are left out")
    func listingParsed() {
        // Arrange
        let output = Self.listing + "abc123\tshort\t\t\t\nnot a line\n\(String(repeating: "0", count: 64))\ttoo\tfew\n"

        // Act
        let names = ContainerListing.names(in: Data(output.utf8))

        // Assert
        #expect(names.map(\.containerID) == [Self.firstDB, Self.replacementDB, Self.shopDB, Self.blogDB, Self.loose])
        #expect(names[0] == ContainerName(
            containerID: Self.firstDB, name: "buzzingpixel_db.1.tatuwopj5rl0", swarmService: "buzzingpixel_db",
            composeProject: nil, composeService: nil
        ))
        #expect(names[2].composeProject == "shop")
        #expect(names[2].composeService == "db")
        #expect(names[4].name == "adminer")
        #expect(names[4].swarmService == nil && names[4].composeService == nil)
    }

    @Test("The command Hive runs is a constant, whatever IDs a Scout sends")
    func commandIsConstant() async throws {
        // Arrange
        dockerListing()
        try await report([TestMetrics.sample(at: now)])

        // Act
        let outcome = await name([Self.firstDB])

        // Assert
        #expect(outcome == .named(listed: 5))
        #expect(fixture.ssh.ran.map(\.command) == [ContainerListing.command])
        #expect(!ContainerListing.command.contains(Self.firstDB))
    }

    @Test("Swarm replicas group by service, each Compose project's db stays its own, and a container without either goes by its name")
    func grouping() async throws {
        // Arrange
        dockerListing()
        try await report([TestMetrics.sample(at: now - 10)])
        _ = await name([Self.firstDB])
        let ids = [Self.firstDB, Self.replacementDB, Self.shopDB, Self.blogDB, Self.loose]
        try await report([sample(at: now, containers: ids)])

        // Act
        let moment = try await moment(at: now)

        // Assert
        guard case .sample(_, let containerCount, let serviceCount, let containers, let services) = moment else {
            Issue.record("Not a sample: \(moment)")
            return
        }
        #expect(containerCount == 5)
        #expect(serviceCount == 1)
        let swarm = try #require(containers.first { $0.name == "buzzingpixel_db" })
        #expect(swarm.kind == .swarmService)
        #expect(swarm.containerCount == 2)
        #expect(swarm.cpuCores == 1.0)
        #expect(swarm.memoryBytes == 2_000_000)
        #expect(Set(swarm.containers.map(\.id)) == [Self.firstDB, Self.replacementDB])
        let compose = containers.filter { $0.name == "db" }
        #expect(Set(compose.map(\.composeProject)) == ["shop", "blog"])
        #expect(compose.allSatisfy { $0.kind == .composeService && $0.containerCount == 1 })
        #expect(containers.first { $0.name == "adminer" }?.kind == .container)
        #expect(services.map(\.name) == ["cron.service"])
        #expect(services.first?.cpuCores == 0.25)
    }

    @Test("A service's hours keep its name across a replaced container, and after its containers' names are gone")
    func historyAcrossReplacement() async throws {
        // Arrange: the first container runs for the first half of the hour, its replacement the second.
        dockerListing()
        let start = MetricsResolution.hour.periodStart(of: now) - 3_600
        try await report([TestMetrics.sample(at: start - 10)])
        _ = await name([Self.firstDB])
        let samples = (0 ..< 6).map { index in
            sample(at: start + Int64(index) * 600, containers: [index < 3 ? Self.firstDB : Self.replacementDB], cpuCores: 0.6)
        }
        try await report(samples)
        fixture.api.metricsUpkeep.runOnce()

        // Act: well past the day the samples and names are kept.
        fixture.signIn.clock.advance(by: 3 * 86_400)
        fixture.api.metricsUpkeep.runOnce()
        let hourly = try await moment(at: start + 1_800)
        let seriesAnswer = try await fixture.send(.get, HiveEndpoint.containerSeries(ofServer: server.id, from: start, to: start + 3_600))
        let series = try seriesAnswer.decoded(as: CgroupSeries.self)

        // Assert
        #expect(try fixture.metricsDatabase.count("containerName") == 0)
        guard case .hour(let hour, let containers, let services) = hourly else {
            Issue.record("Not an hour: \(hourly)")
            return
        }
        #expect(hour == start)
        #expect(containers.map(\.name) == ["buzzingpixel_db"])
        #expect(containers.first?.cpuCores.map { TestMetrics.isClose($0, 0.6) } == true)
        #expect(services.map(\.name) == ["cron.service"])
        #expect(series.bucketSeconds >= 3_600)
        #expect(series.containers.map(\.name) == ["buzzingpixel_db"])
        #expect(series.containers.first?.bucketStarts == [start])
    }

    @Test("Within the day, a range's series groups containers by service and has every bucket for each")
    func seriesFromSamples() async throws {
        // Arrange: the shop's db only in the second sample, so the first bucket reads it as nothing.
        dockerListing()
        try await report([TestMetrics.sample(at: now - 120)])
        _ = await name([Self.firstDB])
        try await report([
            sample(at: now - 60, containers: [Self.firstDB, Self.replacementDB], cpuCores: 0.2),
            sample(at: now, containers: [Self.firstDB, Self.shopDB], cpuCores: 0.4),
        ])

        // Act
        let answer = try await fixture.send(.get, HiveEndpoint.containerSeries(ofServer: server.id, from: now - 3_600, to: now + 10))
        let series = try answer.decoded(as: CgroupSeries.self)

        // Assert
        #expect(series.bucketSeconds == 10)
        let swarm = try #require(series.containers.first { $0.name == "buzzingpixel_db" })
        #expect(swarm.bucketStarts == [now - 60, now])
        #expect(swarm.averageCPUCores.map { ($0 * 10).rounded() / 10 } == [0.4, 0.4])
        let shop = try #require(series.containers.first { $0.composeProject == "shop" })
        #expect(shop.averageCPUCores == [0, 0.4])
    }

    @Test("Where docker ps fails, containers show by short ID and commands, and Hive asks again only a day later or with new SSH details")
    func dockerUnavailable() async throws {
        // Arrange: the shell can't find docker.
        dockerListing(status: 127)
        try await report([TestMetrics.sample(at: now - 10)])

        // Act
        let first = await name([Self.loose])
        fixture.signIn.clock.advance(by: 61)
        let aMinuteLater = await name([Self.loose])
        try await report([sample(at: now, containers: [Self.loose])])
        let unnamed = try await moment(at: now)
        fixture.signIn.clock.advance(by: ContainerNamingWorkflow.retryAfterFailure)
        let aDayLater = await name([Self.loose])

        fixture.signIn.clock.advance(by: 61)
        var draft = ConfigurationSamples.server
        draft.connection?.user = "deploy"
        let changed = try await fixture.sendConfirmed(.put, HiveEndpoint.server(server.id), json: draft)
        try await fixture.confirmHostKey(of: server)
        let newDetails = await name([Self.loose])

        // Assert
        #expect(first == .failed)
        #expect(aMinuteLater == .notAsked)
        guard case .sample(_, _, _, let containers, _) = unnamed else {
            Issue.record("Not a sample: \(unnamed)")
            return
        }
        #expect(containers.map(\.name) == [String(Self.loose.prefix(12))])
        #expect(containers.first?.kind == .unnamed)
        #expect(containers.first?.commands == ["postgres"])
        #expect(aDayLater == .failed)
        #expect(changed.status == .ok)
        #expect(newDetails == .failed)
        #expect(fixture.ssh.ran.filter { $0.command == ContainerListing.command }.count == 3)
    }

    @Test("A container docker ps doesn't list isn't asked about every minute")
    func unlistedContainer() async throws {
        // Arrange: a Podman container, which Docker doesn't know.
        dockerListing()
        try await report([TestMetrics.sample(at: now - 10)])
        let podman = TestMetrics.containerID(0xE1)

        // Act
        let first = await name([podman])
        fixture.signIn.clock.advance(by: 61)
        let again = await name([podman])

        // Assert
        #expect(first == .named(listed: 5))
        #expect(again == .nothingNew)
        #expect(fixture.ssh.ran.count == 1)
    }

    @Test("A server without SSH details is never asked")
    func noSSHDetails() async throws {
        // Arrange
        let other = try await fixture.addServer(ServerDraft(name: "Metrics only", connection: nil, quotaBytes: nil))
        let otherScout = try await fixture.enrollScout(for: other)
        let token = try await fixture.scoutToken(otherScout)
        let body = try JSONEncoder().encode(TestMetrics.report([TestMetrics.sample(at: now)], sentAt: now))
        _ = try await fixture.send(.post, ScoutEndpoint.metrics, token: token, body: body)

        // Act
        let outcome = await fixture.api.containerNaming.nameContainers(of: sample(at: now, containers: [Self.loose]), forServer: other.id)

        // Assert
        #expect(outcome == .notAsked)
        #expect(fixture.ssh.ran.isEmpty)
    }
}
