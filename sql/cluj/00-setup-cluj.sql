-- ============================================================
-- GlobalBank DB — T003+T004: Create CLUJ_USER on ATP2
-- Run as ADMIN on globalbanklocal_high
-- ============================================================

-- Create schema user
CREATE USER CLUJ_USER IDENTIFIED BY "SecurePass123!";

GRANT CONNECT, RESOURCE    TO CLUJ_USER;
GRANT CREATE TABLE         TO CLUJ_USER;
GRANT CREATE VIEW          TO CLUJ_USER;
GRANT CREATE SEQUENCE      TO CLUJ_USER;
GRANT CREATE TRIGGER       TO CLUJ_USER;
GRANT CREATE PROCEDURE     TO CLUJ_USER;
GRANT UNLIMITED TABLESPACE TO CLUJ_USER;

COMMIT;

-- T004: Cross-schema grant (ATP2 shared instance only — skipped on Docker)
-- On ATP2: GRANT SELECT, INSERT, UPDATE, DELETE ON BUCHAREST_USER.TIPURI_CONT TO CLUJ_USER;
-- On Docker: not needed — each node is a separate database; replication uses DB Links.

SELECT 'CLUJ_USER created OK' AS status FROM DUAL;
