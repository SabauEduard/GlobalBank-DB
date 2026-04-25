-- ============================================================
-- GlobalBank DB — Docker: Create GLOBAL_USER on central PDB
-- Run as SYS (SYSDBA) on bankdbpdb
-- ============================================================

CREATE USER GLOBAL_USER IDENTIFIED BY "SecurePass123!";

GRANT CONNECT, RESOURCE      TO GLOBAL_USER;
GRANT CREATE TABLE           TO GLOBAL_USER;
GRANT CREATE VIEW            TO GLOBAL_USER;
GRANT CREATE SEQUENCE        TO GLOBAL_USER;
GRANT CREATE TRIGGER         TO GLOBAL_USER;
GRANT CREATE PROCEDURE       TO GLOBAL_USER;
GRANT CREATE DATABASE LINK   TO GLOBAL_USER;
GRANT UNLIMITED TABLESPACE   TO GLOBAL_USER;

-- Allow GLOBAL_USER to create synonyms and query data dictionary
GRANT CREATE SYNONYM         TO GLOBAL_USER;
GRANT SELECT ANY DICTIONARY  TO GLOBAL_USER;

COMMIT;

SELECT 'GLOBAL_USER created OK on bankdbpdb' AS status FROM DUAL;
