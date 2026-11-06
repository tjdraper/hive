import HiveKit
import os
import XPC

/// The XPC service on the daemon's Mach service, through which Beekeeper on the Hive Mac pairs itself.
/// It answers only Beekeeper signed by Hive's own team, so nothing about the team is written into Hive.
public final class LocalPairingListener: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Pairing")

    private let listener: XPCListener

    public convenience init(machService: String, beekeeperSigningIdentifier: String, workflow: LocalPairingWorkflow) throws {
        try self.init(
            machService: machService,
            sender: .isFromSameTeam(andMatchesSigningIdentifier: beekeeperSigningIdentifier),
            workflow: workflow
        )
    }

    init(machService: String?, sender requirement: XPCPeerRequirement, workflow: LocalPairingWorkflow) throws {
        let handler: @Sendable (XPCListener.IncomingSessionRequest) -> XPCListener.IncomingSessionRequest.Decision = { request in
            request.accept { (message: XPCReceivedMessage) -> (any Encodable)? in
                Self.answer(message, requirement: requirement, workflow: workflow)
            }
        }
        if let machService {
            listener = try XPCListener(service: machService, incomingSessionHandler: handler)
        } else {
            listener = XPCListener(incomingSessionHandler: handler)
        }
        Self.logger.notice("Listening for Beekeeper on this Mac to pair")
    }

    /// For tests, which can't register a Mach service.
    var endpoint: XPCEndpoint {
        listener.endpoint
    }

    func cancel() {
        listener.cancel()
    }

    /// The requirement is checked against each message's own sender, by its audit token. A process ID
    /// could be reused by another program between the check and the message.
    private static func answer(
        _ message: XPCReceivedMessage,
        requirement: XPCPeerRequirement,
        workflow: LocalPairingWorkflow
    ) -> LocalPairingResult {
        guard message.senderSatisfies(requirement) else {
            return workflow.refuse(.notBeekeeper)
        }
        guard let request = try? message.decode(as: LocalPairingRequest.self) else {
            return workflow.refuse(.invalidRequest)
        }
        return workflow.pair(request)
    }
}
