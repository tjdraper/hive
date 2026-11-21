import ScoutProtocol

/// Turns one minute's samples into a ``MetricsMinute``: each figure's average and highest, and the
/// lowest where it matters.
enum MinuteRollup {
    /// - Parameter samples: at least one, all from the minute starting at `startsAt`.
    static func minute(startingAt startsAt: Int64, of samples: [MetricsSample]) -> MetricsMinute {
        MetricsMinute(
            startsAt: startsAt,
            sampleCount: samples.count,
            average: Combination.average.figures(of: samples),
            highest: Combination.highest.figures(of: samples),
            lowest: lows(of: samples)
        )
    }

    private static func lows(of samples: [MetricsSample]) -> MinuteLows {
        let filesystems = grouped(samples.flatMap(\.filesystems), by: \.mountPoint).compactMap { group -> FilesystemLows? in
            let spaces = group.compactMap(\.space)
            guard let lowestAvailable = spaces.map(\.availableBytes).min() else { return nil }
            return FilesystemLows(
                mountPoint: group[0].mountPoint,
                availableBytes: lowestAvailable,
                inodesFree: spaces.compactMap(\.inodes?.free).min()
            )
        }
        return MinuteLows(memoryAvailableBytes: samples.compactMap(\.memory?.availableBytes).min(), filesystems: filesystems)
    }

    /// Each name's figures, in the order the names first appear.
    fileprivate static func grouped<Figures>(_ figures: [Figures], by name: (Figures) -> String) -> [[Figures]] {
        var order: [String] = []
        var groups: [String: [Figures]] = [:]
        for figure in figures {
            let key = name(figure)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(figure)
        }
        return order.compactMap { groups[$0] }
    }
}

/// One way of combining a minute's values, applied to every figure alike, so the average and the
/// highest can't drift apart in which figures they cover.
private struct Combination: Sendable {
    static let average = Combination(
        doubles: { $0.reduce(0, +) / Double($0.count) },
        bytes: { UInt64(($0.reduce(0.0) { $0 + Double($1) } / Double($0.count)).rounded()) },
        counts: { Int((Double($0.reduce(0, +)) / Double($0.count)).rounded()) }
    )
    static let highest = Combination(
        doubles: { $0.max() ?? 0 },
        bytes: { $0.max() ?? 0 },
        counts: { $0.max() ?? 0 }
    )

    // Each is given at least one value.
    let doubles: @Sendable ([Double]) -> Double
    let bytes: @Sendable ([UInt64]) -> UInt64
    let counts: @Sendable ([Int]) -> Int

    func figures(of samples: [MetricsSample]) -> MinuteFigures {
        MinuteFigures(
            cpu: present(samples.map(\.cpu)) { cpu($0) },
            memory: present(samples.map(\.memory)) { memory($0) },
            pressure: present(samples.map(\.pressure)) { pressure($0) },
            filesystems: MinuteRollup.grouped(samples.flatMap(\.filesystems), by: \.mountPoint).map { filesystem($0) },
            disks: MinuteRollup.grouped(samples.flatMap(\.disks), by: \.name).map { disk($0) },
            networkInterfaces: MinuteRollup.grouped(samples.flatMap(\.networkInterfaces), by: \.name).map { interface($0) }
        )
    }

    /// Combines the values that are there, or nil when none are.
    private func present<Value>(_ values: [Value?], _ combine: ([Value]) -> Value) -> Value? {
        let present = values.compactMap(\.self)
        return present.isEmpty ? nil : combine(present)
    }

    private func cpu(_ values: [CPUFigures]) -> CPUFigures {
        CPUFigures(
            cores: counts(values.map(\.cores)),
            use: present(values.map(\.use)) { use in
                CPUUse(
                    user: doubles(use.map(\.user)),
                    system: doubles(use.map(\.system)),
                    ioWait: doubles(use.map(\.ioWait)),
                    steal: doubles(use.map(\.steal))
                )
            },
            load: present(values.map(\.load)) { load in
                LoadAverages(
                    oneMinute: doubles(load.map(\.oneMinute)),
                    fiveMinutes: doubles(load.map(\.fiveMinutes)),
                    fifteenMinutes: doubles(load.map(\.fifteenMinutes))
                )
            }
        )
    }

    private func memory(_ values: [MemoryFigures]) -> MemoryFigures {
        MemoryFigures(
            totalBytes: bytes(values.map(\.totalBytes)),
            availableBytes: bytes(values.map(\.availableBytes)),
            cacheBytes: bytes(values.map(\.cacheBytes)),
            swapTotalBytes: bytes(values.map(\.swapTotalBytes)),
            swapUsedBytes: bytes(values.map(\.swapUsedBytes)),
            swapping: present(values.map(\.swapping)) { swapping in
                Swapping(
                    pagesInPerSecond: doubles(swapping.map(\.pagesInPerSecond)),
                    pagesOutPerSecond: doubles(swapping.map(\.pagesOutPerSecond))
                )
            }
        )
    }

    private func pressure(_ values: [PressureFigures]) -> PressureFigures {
        PressureFigures(
            cpu: present(values.map(\.cpu)) { stall($0) },
            memory: present(values.map(\.memory)) { stall($0) },
            inputOutput: present(values.map(\.inputOutput)) { stall($0) }
        )
    }

    private func stall(_ values: [PressureStall]) -> PressureStall {
        PressureStall(some: doubles(values.map(\.some)), full: present(values.map(\.full)) { doubles($0) })
    }

    /// The last sample's device and type, in case the mount point was remounted from another.
    private func filesystem(_ values: [FilesystemFigures]) -> FilesystemFigures {
        let last = values[values.count - 1]
        return FilesystemFigures(
            mountPoint: last.mountPoint,
            device: last.device,
            type: last.type,
            space: present(values.map(\.space)) { space in
                FilesystemSpace(
                    sizeBytes: bytes(space.map(\.sizeBytes)),
                    usedBytes: bytes(space.map(\.usedBytes)),
                    availableBytes: bytes(space.map(\.availableBytes)),
                    inodes: present(space.map(\.inodes)) { inodes in
                        InodeCounts(used: bytes(inodes.map(\.used)), free: bytes(inodes.map(\.free)))
                    }
                )
            }
        )
    }

    private func disk(_ values: [DiskFigures]) -> DiskFigures {
        DiskFigures(
            name: values[0].name,
            activity: present(values.map(\.activity)) { activity in
                DiskActivity(
                    readBytesPerSecond: doubles(activity.map(\.readBytesPerSecond)),
                    writtenBytesPerSecond: doubles(activity.map(\.writtenBytesPerSecond)),
                    readsPerSecond: doubles(activity.map(\.readsPerSecond)),
                    writesPerSecond: doubles(activity.map(\.writesPerSecond)),
                    busy: doubles(activity.map(\.busy))
                )
            }
        )
    }

    private func interface(_ values: [NetworkInterfaceFigures]) -> NetworkInterfaceFigures {
        NetworkInterfaceFigures(
            name: values[0].name,
            traffic: present(values.map(\.traffic)) { traffic in
                NetworkTraffic(
                    receivedBytesPerSecond: doubles(traffic.map(\.receivedBytesPerSecond)),
                    sentBytesPerSecond: doubles(traffic.map(\.sentBytesPerSecond)),
                    receiveErrorsPerSecond: doubles(traffic.map(\.receiveErrorsPerSecond)),
                    sendErrorsPerSecond: doubles(traffic.map(\.sendErrorsPerSecond)),
                    receiveDropsPerSecond: doubles(traffic.map(\.receiveDropsPerSecond)),
                    sendDropsPerSecond: doubles(traffic.map(\.sendDropsPerSecond))
                )
            }
        )
    }
}
