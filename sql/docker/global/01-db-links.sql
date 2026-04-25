-- ============================================================
-- GlobalBank DB — Docker: DB Links using standard Oracle syntax
-- Run as GLOBAL_USER on freepdb1 (central container)
--
-- The central container reaches bucharest/cluj by their Docker
-- Compose service names ('bucharest', 'cluj') on port 1521.
-- Both remote containers expose the 'freepdb1' PDB service.
-- ============================================================

-- Drop existing (idempotent)
BEGIN EXECUTE IMMEDIATE 'DROP DATABASE LINK BUCHAREST_LINK'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP DATABASE LINK CLUJ_LINK'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

-- BUCHAREST_LINK
CREATE DATABASE LINK BUCHAREST_LINK
  CONNECT TO BUCHAREST_USER IDENTIFIED BY "SecurePass123!"
  USING '(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=bucharest)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=freepdb1)))';

-- CLUJ_LINK
CREATE DATABASE LINK CLUJ_LINK
  CONNECT TO CLUJ_USER IDENTIFIED BY "SecurePass123!"
  USING '(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=cluj)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=freepdb1)))';

-- Verify both links
SELECT 'BUCHAREST_LINK OK - remote user: ' || USER AS status FROM DUAL@BUCHAREST_LINK;
SELECT 'CLUJ_LINK OK - remote user: '      || USER AS status FROM DUAL@CLUJ_LINK;
