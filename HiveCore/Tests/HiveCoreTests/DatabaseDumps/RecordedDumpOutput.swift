import Foundation

/// Output recorded from the dump tools against the test server's databases (`Scripts/test-server.sh`),
/// shortened where it was long.
enum RecordedDumpOutput {
    static let mysqlBeginning = """
    /*M!999999\\- enable the sandbox mode */
    -- MariaDB dump 10.20-11.8.9-MariaDB, for debian-linux-gnu (aarch64)
    --
    -- Host: localhost    Database: site
    -- ------------------------------------------------------
    -- Server version\t11.8.9-MariaDB-ubu2404

    /*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
    /*!40101 SET NAMES utf8mb4 */;
    INSERT INTO `entries` VALUES
    (1,'Entry 1','Body of entry 1. ','2026-01-01 00:01:00'),
    (2,'Entry 2','Body of entry 2. ','2026-01-01 00:02:00');

    """

    static let mysqlEnding = """
    /*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
    /*M!100616 SET NOTE_VERBOSITY=@OLD_NOTE_VERBOSITY */;

    -- Dump completed on 2026-11-06 19:36:33

    """

    static let mysqlDump = Data((mysqlBeginning + mysqlEnding).utf8)
    /// Stopped part way, as when the connection drops, without the closing comment.
    static let mysqlDumpCut = Data(mysqlBeginning.utf8)

    /// The start of a pg_dump custom format archive.
    static let postgresDump = Data([
        0x50, 0x47, 0x44, 0x4D, 0x50, 0x01, 0x10, 0x00, 0x04, 0x08, 0x01, 0x01, 0x00, 0x02, 0x00, 0x00,
        0x00, 0x00, 0x25, 0x00, 0x00, 0x00, 0x00, 0x13, 0x00, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00,
    ])

    static let mysqlWrongPassword = """
    mysqldump: Got error: 1045: Access denied for user 'site'@'localhost' (using password: YES) when trying to connect

    """
    static let mariadbWrongPassword = """
    mariadb-dump: Got error: 1045: "Access denied for user 'site'@'localhost' (using password: YES)" when trying to connect

    """
    static let postgresWrongPassword = """
    pg_dump: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  password authentication failed for user "site"

    """
    /// Postgres answers an unknown user the same way, rather than saying it doesn't exist.
    static let postgresUnknownUser = """
    pg_dump: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  password authentication failed for user "nobody"

    """
    /// A user without privileges on other databases is refused before MySQL says whether one exists.
    static let mysqlOtherDatabase = """
    mysqldump: Got error: 1044: Access denied for user 'site'@'%' to database 'nosuch' when selecting the database

    """
    /// For a user with privileges on every database.
    static let mysqlUnknownDatabase = """
    mariadb-dump: Got error: 1049: "Unknown database 'nosuch'" when selecting the database

    """
    static let postgresUnknownDatabase = """
    pg_dump: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  database "nosuch" does not exist

    """
    /// A routine owned by another user.
    static let mysqlInsufficientPrivileges = """
    mysqldump: site has insufficient privileges to SHOW CREATE FUNCTION `entry_title`!

    """
    static let mysqlUnreachable = """
    mysqldump: Got error: 2002: Can't connect to local MySQL server through socket '/nonexistent' (2) when trying to connect

    """
    static let postgresUnreachable = """
    pg_dump: error: connection to server at "127.0.0.1", port 1 failed: Connection refused
    \tIs the server running on that host and accepting TCP/IP connections?

    """
    static let mysqlToolMissing = "Hive: no mariadb-dump or mysqldump\n"
    static let postgresToolMissing = "sh: line 1: exec: pg_dump: not found\n"
    static let noSuchContainer = """
    Error response from daemon: No such container: 1111111111111111111111111111111111111111111111111111111111111111

    """
}
