-- ============================================================
-- GlobalBank DB — Docker cleanup: drop CLUJ_USER on clujpdb
-- Run as SYS (SYSDBA) on clujpdb
-- ============================================================

BEGIN
  EXECUTE IMMEDIATE 'DROP USER CLUJ_USER CASCADE';
  DBMS_OUTPUT.PUT_LINE('CLUJ_USER dropped.');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -1918 THEN DBMS_OUTPUT.PUT_LINE('CLUJ_USER does not exist.');
    ELSE RAISE;
    END IF;
END;
/

SELECT 'Cluj PDB cleanup complete' AS status FROM DUAL;
