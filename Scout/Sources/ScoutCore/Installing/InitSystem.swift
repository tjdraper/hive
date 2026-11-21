#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// What runs Scout as a service: systemd on almost every distribution, OpenRC on Alpine.
enum InitSystem: Equatable {
    case systemd
    case openRC

    /// The one this server was started with. Nil for any other, which can run `hive-scout run` itself.
    static func running(in layout: InstallLayout, tools: ServerTools) -> Self? {
        // systemd's own test of whether it started the server (`sd_booted`).
        if isDirectory(layout.onDisk("/run/systemd/system")) { return .systemd }
        if isDirectory(layout.onDisk("/run/openrc")), tools.find("openrc-run") != nil { return .openRC }
        return nil
    }

    func servicePath(in layout: InstallLayout) -> String {
        switch self {
        case .systemd: layout.systemdUnit
        case .openRC: layout.openRCScript
        }
    }

    /// The service file and the mode it's written with.
    func serviceFile(for layout: InstallLayout) -> (text: String, mode: mode_t) {
        switch self {
        case .systemd: (Self.systemdUnit(for: layout), 0o644)
        case .openRC: (Self.openRCScript(for: layout), 0o755)
        }
    }

    private static func isDirectory(_ path: String) -> Bool {
        var status = stat()
        return stat(path, &status) == 0 && status.st_mode & S_IFMT == S_IFDIR
    }

    /// Everything but what Scout reads, and its state folder, which it writes.
    private static let lockdown = """
        # Not ProtectHome=yes, which hides /home and gives a separate /home filesystem the wrong
        # figures, and not ProtectProc=invisible, which hides the processes Scout reports.
        NoNewPrivileges=yes
        ProtectSystem=strict
        ProtectHome=read-only
        PrivateTmp=yes
        PrivateDevices=yes
        CapabilityBoundingSet=
        AmbientCapabilities=
        ProtectKernelTunables=yes
        ProtectKernelModules=yes
        ProtectKernelLogs=yes
        ProtectControlGroups=yes
        ProtectClock=yes
        ProtectHostname=yes
        RestrictNamespaces=yes
        RestrictRealtime=yes
        RestrictSUIDSGID=yes
        LockPersonality=yes
        MemoryDenyWriteExecute=yes
        SystemCallArchitectures=native
        RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
        UMask=0077
        """

    private static func systemdUnit(for layout: InstallLayout) -> String {
        let runtimeName = layout.runtimeDirectory.dropFirst("/run/".count)
        return """
            # Written by hive-scout install, which replaces it when run again.
            [Unit]
            Description=Hive Scout, sending this server's metrics to Hive
            After=network-online.target
            Wants=network-online.target

            [Service]
            ExecStart=\(layout.binary) run --state-directory \(layout.stateDirectory) --runtime-directory \(layout.runtimeDirectory)
            ExecReload=/bin/kill -HUP $MAINPID
            User=\(InstallLayout.user)
            Group=\(InstallLayout.user)
            Restart=on-failure
            RestartSec=10
            # Scout exits with 78 when it hasn't enrolled, which starting again can't fix.
            RestartPreventExitStatus=78
            RuntimeDirectory=\(runtimeName)
            RuntimeDirectoryMode=0700

            CPUQuota=5%
            MemoryMax=64M
            Nice=10
            IOSchedulingClass=idle

            \(lockdown)
            ReadWritePaths=\(layout.stateDirectory)

            [Install]
            WantedBy=multi-user.target

            """
    }

    private static func openRCScript(for layout: InstallLayout) -> String {
        let user = InstallLayout.user
        return """
            #!/sbin/openrc-run
            # Written by hive-scout install, which replaces it when run again.

            description="Hive Scout, sending this server's metrics to Hive"
            extra_started_commands="reload"
            description_reload="Read Scout's enrollment again and connect to Hive at once"

            command="\(layout.binary)"
            command_args="run --state-directory \(layout.stateDirectory) --runtime-directory \(layout.runtimeDirectory)"
            command_user="\(user):\(user)"
            supervisor="supervise-daemon"
            respawn_delay=10
            respawn_max=0
            error_logger="logger -t \(user) -p daemon.notice"

            no_new_privs="yes"
            supervise_daemon_args="--nicelevel 10 --ionice 3"
            rc_cgroup_settings="
            cpu.max 5000 100000
            memory.max 67108864
            "

            depend() {
                after net
                # Turns on the controllers that rc_cgroup_settings needs, where the server can.
                want cgroups
            }

            start_pre() {
                checkpath --directory --owner \(user):\(user) --mode 0700 \(layout.runtimeDirectory)
            }

            reload() {
                ebegin "Reloading ${RC_SVCNAME}"
                supervise-daemon "${RC_SVCNAME}" --signal HUP
                eend $?
            }

            """
    }
}
