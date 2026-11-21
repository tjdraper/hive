@testable import ScoutCore
import Testing

struct ServiceAndRuleTextTests {
    private let layout = InstallLayout.server

    private static let systemdUnit = """
        # Written by hive-scout install, which replaces it when run again.
        [Unit]
        Description=Hive Scout, sending this server's metrics to Hive
        After=network-online.target
        Wants=network-online.target

        [Service]
        ExecStart=/usr/local/bin/hive-scout run --state-directory /var/lib/hive-scout --runtime-directory /run/hive-scout
        ExecReload=/bin/kill -HUP $MAINPID
        User=hive-scout
        Group=hive-scout
        Restart=on-failure
        RestartSec=10
        # Scout exits with 78 when it hasn't enrolled, which starting again can't fix.
        RestartPreventExitStatus=78
        RuntimeDirectory=hive-scout
        RuntimeDirectoryMode=0700

        CPUQuota=5%
        MemoryMax=64M
        Nice=10
        IOSchedulingClass=idle

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
        ReadWritePaths=/var/lib/hive-scout

        [Install]
        WantedBy=multi-user.target

        """

    @Test("The systemd unit runs Scout as its own user, with its caps, locked down but for its state folder")
    func systemdUnit() {
        #expect(InitSystem.systemd.serviceFile(for: layout).text == Self.systemdUnit)
    }

    @Test("The OpenRC script supervises Scout as its own user, with the caps OpenRC can express, and reloads with SIGHUP")
    func openRCScript() {
        #expect(InitSystem.openRC.serviceFile(for: layout).text == """
            #!/sbin/openrc-run
            # Written by hive-scout install, which replaces it when run again.

            description="Hive Scout, sending this server's metrics to Hive"
            extra_started_commands="reload"
            description_reload="Read Scout's enrollment again and connect to Hive at once"

            command="/usr/local/bin/hive-scout"
            command_args="run --state-directory /var/lib/hive-scout --runtime-directory /run/hive-scout"
            command_user="hive-scout:hive-scout"
            supervisor="supervise-daemon"
            respawn_delay=10
            respawn_max=0
            error_logger="logger -t hive-scout -p daemon.notice"

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
                checkpath --directory --owner hive-scout:hive-scout --mode 0700 /run/hive-scout
            }

            reload() {
                ebegin "Reloading ${RC_SVCNAME}"
                supervise-daemon "${RC_SVCNAME}" --signal HUP
                eend $?
            }

            """)
    }

    @Test("The sudo rule lets one user run only Scout's management command as root, without a terminal")
    func sudoRule() throws {
        let user = try #require(SSHUserName("deploy"))
        #expect(ManagementRule.sudo.text(for: user, binary: layout.binary) == """
            # Written by hive-scout install --ssh-user, and removed by hive-scout uninstall.
            Defaults!/usr/local/bin/hive-scout !requiretty
            deploy ALL=(root) NOPASSWD: /usr/local/bin/hive-scout manage

            """)
    }

    @Test("The doas rule lets one user run only Scout's management command as root")
    func doasRule() throws {
        let user = try #require(SSHUserName("web_01.ops"))
        #expect(ManagementRule.doas.text(for: user, binary: layout.binary) == """
            # Written by hive-scout install --ssh-user, and removed by hive-scout uninstall.
            permit nopass web_01.ops as root cmd /usr/local/bin/hive-scout args manage

            """)
    }

    @Test(
        "A name outside POSIX's portable user name pattern, or one sudo reads as an alias or keyword, is refused",
        arguments: ["deploy user", "#1000", "ALL", "ADMINS_2", "Defaults", "Cmnd_Alias", "-deploy", "", "deploy\n", "a:b", "dé",
                    String(repeating: "a", count: 33)]
    )
    func refusedNames(name: String) {
        #expect(SSHUserName(name) == nil)
    }

    @Test("Portable names are accepted, including capitals beside other letters", arguments: ["deploy", "web-01", "_svc", "a.b", "Admin"])
    func acceptedNames(name: String) {
        #expect(SSHUserName(name)?.text == name)
    }
}
