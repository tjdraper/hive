import Foundation
import HiveKit
import Observation
import os

/// This device's copies of one Hive's recovery file (§14), kept in step with the Hive: the latest file
/// fetched whenever the Hive writes one, and copies made with an older recovery key deleted.
@Observable
final class RecoveryFileCopies {
    private static let logger = Logger(subsystem: BeekeeperLog.subsystem, category: "RecoveryFile")

    /// What the Hive last said about its key and latest file. Nil until it's been heard from.
    private(set) var hiveState: RecoveryKeyState?
    /// `RecoveryFileHeader.digest(of:)` of this device's copy. Nil without one.
    private(set) var copyDigest: Data?
    /// Named in the copy kept in the chosen folder.
    var hiveName: String
    #if os(macOS)
    private(set) var folder: RecoveryCopyFiles.ChosenFolder?
    private(set) var folderName: String?
    /// Why the chosen folder doesn't have this device's copy.
    private(set) var folderProblem: String?
    #endif

    private let hiveID: UUID
    private let link: HiveLink
    private let files: RecoveryCopyFiles
    private var updating: Task<Void, Never>?
    private var needsUpdate = false

    init(hiveID: UUID, hiveName: String, link: HiveLink, files: RecoveryCopyFiles? = nil) {
        self.hiveID = hiveID
        self.hiveName = hiveName
        self.link = link
        self.files = files ?? .standard(for: hiveID)
        #if os(macOS)
        do {
            folder = try self.files.loadFolder()
        } catch {
            Self.logger.error("Couldn't read the chosen recovery folder: \(Self.describe(error), privacy: .public)")
        }
        #endif
        // Reads the copy already here, so it shows while the Hive is offline.
        startUpdating()
    }

    /// This device has the file the Hive wrote last.
    var hasLatest: Bool {
        copyDigest != nil && copyDigest == hiveState?.fileDigest
    }

    /// Asks the Hive for its state, such as when a view appears before live updates have said anything.
    func refresh() async {
        guard let state: RecoveryKeyState = try? await link.perform({ try await $0.get(HiveEndpoint.recoveryKey) }) else { return }
        receive(state)
    }

    /// Brings the copies in step with `state`. One that arrives while they're being updated is caught up
    /// on once that's done.
    func receive(_ state: RecoveryKeyState) {
        hiveState = state
        startUpdating()
    }

    private func startUpdating() {
        needsUpdate = true
        guard updating == nil else { return }
        updating = Task {
            while needsUpdate {
                needsUpdate = false
                await update()
            }
            updating = nil
        }
    }

    private func update() async {
        var copy: Data?
        do {
            copy = try await files.readCopy()
        } catch {
            Self.logger.error("Couldn't read this device's recovery file: \(Self.describe(error), privacy: .public)")
        }

        if let state = hiveState, let key = state.publicKey {
            if let existing = copy, RecoveryFileHeader.publicKey(of: existing) != key {
                copy = nil
                await removeCopy()
            }
            if let digest = state.fileDigest, copy.map(RecoveryFileHeader.digest(of:)) != digest,
               let latest = await download(for: key) {
                copy = latest
            }
        }
        copyDigest = copy.map(RecoveryFileHeader.digest(of:))

        #if os(macOS)
        if let key = hiveState?.publicKey ?? copy.flatMap(RecoveryFileHeader.publicKey(of:)) {
            await updateFolder(copy: copy, currentKey: key)
        }
        #endif
    }

    /// Made with an older key: the Hive's new files don't open with it, and keeping it keeps the old key useful.
    private func removeCopy() async {
        do {
            try await files.removeCopy()
            Self.logger.notice("Deleted this device's recovery file made with an older key")
        } catch {
            Self.logger.error("Couldn't delete a recovery file made with an older key: \(Self.describe(error), privacy: .public)")
        }
    }

    /// Nil when it couldn't be fetched or saved, or it was written for another key, as when the key changed
    /// meanwhile. The update that follows a change fetches the file again.
    private func download(for key: Data) async -> Data? {
        do {
            let download: RecoveryFileDownload = try await link.perform { try await $0.get(HiveEndpoint.recoveryFile) }
            guard RecoveryFileHeader.publicKey(of: download.file) == key else { return nil }
            try await files.saveCopy(download.file)
            Self.logger.notice("Saved the Hive's latest recovery file")
            return download.file
        } catch {
            Self.logger.error("Couldn't fetch the Hive's recovery file: \(Self.describe(error), privacy: .public)")
            return nil
        }
    }

    #if os(macOS)
    /// The copy is kept in the chosen folder as well.
    func chooseFolder(_ url: URL) async {
        let bookmark: Data
        do {
            bookmark = try RecoveryCopyFiles.bookmark(for: url)
        } catch {
            Self.logger.error("Couldn't remember a chosen recovery folder: \(Self.describe(error), privacy: .public)")
            folderProblem = "Beekeeper couldn't keep track of that folder. Choose another."
            return
        }
        await removeFolderCopy()
        remember(RecoveryCopyFiles.ChosenFolder(bookmark: bookmark))
        folderName = try? await files.folderName(of: RecoveryCopyFiles.ChosenFolder(bookmark: bookmark))
        Self.logger.notice("Chose a folder for recovery files")
        startUpdating()
    }

    /// Deletes the copy in the chosen folder, and keeps none there from now on.
    func stopUsingFolder() async {
        await removeFolderCopy()
        remember(nil)
        Self.logger.notice("Stopped keeping recovery files in a chosen folder")
    }

    private func removeFolderCopy() async {
        guard let folder else { return }
        do {
            try await files.removeFolderCopy(in: folder)
        } catch {
            Self.logger.error("Couldn't delete the recovery file in the chosen folder: \(Self.describe(error), privacy: .public)")
        }
    }

    private func updateFolder(copy: Data?, currentKey: Data) async {
        guard let folder else { return }
        do {
            let updated = try await files.updateFolderCopy(in: folder, copy: copy, currentKey: currentKey, fileName: folderFileName)
            folderName = updated.name
            folderProblem = nil
            if updated.folder != folder, self.folder == folder { remember(updated.folder) }
        } catch RecoveryCopyFiles.FolderError.notFound {
            folderProblem = "Beekeeper can't find the folder. It may have been deleted, or be on a disk that isn't connected."
        } catch {
            Self.logger.error("Couldn't update the recovery file in the chosen folder: \(Self.describe(error), privacy: .public)")
            folderProblem = "Beekeeper couldn't write to the folder."
        }
    }

    private func remember(_ chosen: RecoveryCopyFiles.ChosenFolder?) {
        folder = chosen
        folderProblem = nil
        if chosen == nil { folderName = nil }
        do {
            try files.saveFolder(chosen)
        } catch {
            Self.logger.error("Couldn't save the chosen recovery folder: \(Self.describe(error), privacy: .public)")
        }
    }

    /// The Hive's name, so the person can tell whose file it is, and the start of its ID, so two Hives
    /// with the same name never share one.
    private var folderFileName: String {
        let name = hiveName
            .replacing("/", with: "-")
            .replacing(":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let id = hiveID.uuidString.prefix(8)
        return "\(name.isEmpty ? "Hive" : name) \(id).\(RecoveryFileHeader.fileExtension)"
    }
    #endif

    /// File errors name their path, which the system log never holds (AGENTS.md).
    private static func describe(_ error: any Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }
}
