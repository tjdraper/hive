-- Sample data for Postgres: a table of rows, a view and a function, so a restored dump can be
-- checked for each. Run once, when the database container first starts.
--
-- The password is a test value. It holds a space, both quotes, a backslash, `$` and `#`, so a dump
-- only works if Hive passes it on untouched.
CREATE ROLE site LOGIN PASSWORD 'Hive t3st: "double" ''single'' \back $HOME #hash';
CREATE DATABASE blog OWNER site;

\connect blog site

CREATE TABLE entries (
    id INT PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    body TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL
);

INSERT INTO entries (id, title, body, created_at)
SELECT n, 'Entry ' || n, repeat('Body of entry ' || n || '. ', 20), TIMESTAMP '2026-01-01' + n * INTERVAL '1 minute'
FROM generate_series(1, 2500) AS n;

CREATE VIEW recent_entries AS SELECT id, title FROM entries WHERE id > 2400;

CREATE FUNCTION entry_title(entry INT) RETURNS VARCHAR(100) LANGUAGE sql STABLE
AS $$ SELECT title FROM entries WHERE id = entry $$;
