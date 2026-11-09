-- Sample data for MariaDB and MySQL: a table of rows, a view, a trigger, a stored procedure, a
-- function and an event, so a restored dump can be checked for each. Run once, when a database
-- container first starts, and by the SSH container for its own MariaDB.
--
-- The password is a test value. It holds a space, both quotes, a backslash, `$` and `#`, so a dump
-- only works if Hive passes it on untouched.
CREATE USER 'site'@'%' IDENTIFIED BY 'Hive t3st: "double" ''single'' \\back $HOME #hash';
-- Run in the database it fills, which each server names differently so one job can dump them all.
SET @grant_site = CONCAT('GRANT ALL ON `', DATABASE(), '`.* TO ''site''@''%''');
PREPARE grant_site FROM @grant_site;
EXECUTE grant_site;
DEALLOCATE PREPARE grant_site;

CREATE TABLE entries (
    id INT PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    body TEXT NOT NULL,
    created_at DATETIME NOT NULL
);

-- 50 × 50 rows, since both servers stop a recursive query after 1000 steps.
INSERT INTO entries (id, title, body, created_at)
WITH RECURSIVE fifty (n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM fifty WHERE n < 50),
numbers (n) AS (SELECT (a.n - 1) * 50 + b.n FROM fifty a CROSS JOIN fifty b)
SELECT n, CONCAT('Entry ', n), REPEAT(CONCAT('Body of entry ', n, '. '), 20), '2026-01-01' + INTERVAL n MINUTE
FROM numbers;

CREATE TABLE entry_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    entry_id INT NOT NULL
);

CREATE VIEW recent_entries AS SELECT id, title FROM entries WHERE id > 2400;

CREATE TRIGGER log_entry AFTER INSERT ON entries FOR EACH ROW INSERT INTO entry_log (entry_id) VALUES (NEW.id);

-- Owned by the site's user, as an app's own routines are. A user can only dump the routines it owns
-- unless it has extra privileges.
DELIMITER //
CREATE DEFINER = 'site'@'%' PROCEDURE entry_count(OUT total INT)
BEGIN
    SELECT COUNT(*) INTO total FROM entries;
END//
CREATE DEFINER = 'site'@'%' FUNCTION entry_title(entry INT) RETURNS VARCHAR(100) DETERMINISTIC READS SQL DATA
BEGIN
    RETURN (SELECT title FROM entries WHERE id = entry);
END//
DELIMITER ;

CREATE EVENT tidy_entry_log ON SCHEDULE EVERY 1 DAY DISABLE DO DELETE FROM entry_log;
