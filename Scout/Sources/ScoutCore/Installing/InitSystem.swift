#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// What runs Scout as a service: systemd on almost every distribution, OpenRC on Alpine, launchd on a Mac.
enum InitSystem: Equatable {
    case systemd
    case openRC
    case launchd

    /// The one this server was started with. Nil for any other, which can run `hive-scout run` itself.
    static func running(in layout: InstallLayout, tools: ServerTools) -> Self? {
        if layout.system == .mac { return tools.find("launchctl") != nil ? .launchd : nil }
        // systemd's own test of whether it started the server (`sd_booted`).
        if isDirectory(layout.onDisk("/run/systemd/system")) { return .systemd }
        if isDirectory(layout.onDisk("/run/openrc")), tools.find("openrc-run") != nil { return .openRC }
        return nil
    }

    func servicePath(in layout: InstallLayout) -> String {
        switch self {
        case .systemd: layout.systemdUnit
        case .openRC: layout.openRCScript
        case .launchd: layout.launchDaemon
        }
    }

    /// The service file and the mode it's written with.
    func serviceFile(for layout: InstallLayout) -> (text: String, mode: mode_t) {
        switch self {
        case .systemd: (Self.systemdUnit(for: layout), 0o644)
        case .openRC: (Self.openRCScript(for: layout), 0o755)
        case .launchd: (Self.launchDaemon(for: layout), 0o644)
        }
    }

    /// The service as `launchctl` names it.
    static let launchdTarget = "system/\(InstallLayout.launchdLabel)"

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
            User=\(layout.user)
            Group=\(layout.user)
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
        let user = layout.user
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

    /// Started as root, since on a Mac only root can read other users' processes. `run` keeps root only
    /// to take samples, and hands them to a process of its own that drops to Scout's user before doing
    /// anything else. launchd can't cap memory or CPU as systemd does; a background process gets the
    /// lowest CPU and I/O priority instead.
    private static func launchDaemon(for layout: InstallLayout) -> String {
        let arguments = [layout.binary, "run", "--state-directory", layout.stateDirectory, "--runtime-directory", layout.runtimeDirectory]
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <!-- Written by hive-scout install, which replaces it when run again. -->
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(InstallLayout.launchdLabel)</string>
                <key>ProgramArguments</key>
                <array>
            \(arguments.map { "        <string>\($0)</string>" }.joined(separator: "\n"))
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <true/>
                <key>ThrottleInterval</key>
                <integer>10</integer>
                <key>ProcessType</key>
                <string>Background</string>
                <key>Nice</key>
                <integer>10</integer>
                <key>Umask</key>
                <integer>63</integer>
            </dict>
            </plist>

            """
    }
}
