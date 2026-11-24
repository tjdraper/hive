import Foundation

/// The Scout workflows, built from the API's stores like the rest.
extension HiveAPI {
    var scouts: ScoutStore {
        ScoutStore(database: servers.store.database)
    }

    var metricsRemoval: MetricsRemovalWorkflow {
        MetricsRemovalWorkflow(scouts: scouts, sessions: signIn.sessions, now: signIn.now)
    }

    var metricsState: ServerMetricsStateReader {
        ServerMetricsStateReader(scouts: scouts, metrics: metrics, carriedScoutVersion: carriedScout?.version)
    }

    var enrollmentWindow: EnrollmentWindowWorkflow {
        EnrollmentWindowWorkflow(
            hiveID: hiveID,
            pin: pin,
            settings: settingsStore,
            database: servers.store.database,
            windows: enrollmentWindows,
            isRestarting: { [restart] in restart.isRequested },
            now: signIn.now
        )
    }

    var scoutEnrollment: ScoutEnrollmentWorkflow {
        ScoutEnrollmentWorkflow(
            hiveID: hiveID,
            scouts: scouts,
            windows: enrollmentWindows,
            sessions: signIn.sessions,
            limiter: pairingLimiter,
            isRestarting: { [restart] in restart.isRequested },
            now: signIn.now
        )
    }

    var scoutManagement: ScoutManagementWorkflow {
        ScoutManagementWorkflow(
            targets: connectionTest.targets,
            ssh: connectionTest.ssh,
            carried: carriedScout,
            settings: settingsStore,
            database: servers.store.database,
            windows: enrollmentWindow,
            metricsRemoval: metricsRemoval,
            now: signIn.now
        )
    }

    /// With devices' challenges and lockouts, since they share the routes.
    var scoutSignIn: ScoutSignInWorkflow {
        ScoutSignInWorkflow(
            hiveID: hiveID,
            scouts: scouts,
            sessions: signIn.sessions,
            challenges: signIn.challenges,
            addressLimiter: signIn.addressLimiter,
            scoutLimiter: signIn.deviceLimiter,
            now: signIn.now
        )
    }
}
