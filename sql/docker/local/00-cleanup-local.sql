-- ============================================================
-- GlobalBank DB — Docker cleanup: drop user on a local PDB
-- Run as SYS (SYSDBA) on bucharestpdb or clujpdb
-- ============================================================

BEGIN
  EXECUTE IMMEDIATE 'DROP USER BUCHAREST_USER CASCADE';
  DBMS_OUTPUT.PUT_LINE('BUCHAREST_USER dropped.');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -1918 THEN DBMS_OUTPUT.PUT_LINE('BUCHAREST_USER does not exist.');
    ELSE RAISE;
    END IF;
END;
/

SELECT 'Local PDB cleanup complete' AS status FROM DUAL;
