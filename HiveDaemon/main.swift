import Darwin
import Foundation
import HiveCore
import os

#if DEBUG
let launchMode = DaemonLaunchMode.developmentAgent
#else
let launchMode = DaemonLaunchMode.systemDaemon
#endif

switch CommandLine.arguments.dropFirst().first {
case nil:
    DaemonStart.run(mode: launchMode)
case "reset-user":
    ResetUserCommand.run(mode: launchMode)
default:
    FileHandle.standardError.write(Data("usage: sudo HiveDaemon reset-user\n".utf8))
    exit(EX_USAGE)
}
