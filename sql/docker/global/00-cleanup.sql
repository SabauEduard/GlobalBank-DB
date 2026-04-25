-- ============================================================
-- GlobalBank DB — Docker cleanup: drop GLOBAL_USER on central PDB
-- Run as SYS (SYSDBA) on bankdbpdb
-- ============================================================

BEGIN
  EXECUTE IMMEDIATE 'DROP USER GLOBAL_USER CASCADE';
  DBMS_OUTPUT.PUT_LINE('GLOBAL_USER dropped.');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -1918 THEN DBMS_OUTPUT.PUT_LINE('GLOBAL_USER does not exist, skipping.');
    ELSE RAISE;
    END IF;
END;
/

SELECT 'Central (bankdbpdb) cleanup complete' AS status FROM DUAL;
