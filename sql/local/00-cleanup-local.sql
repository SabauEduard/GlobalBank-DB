-- ============================================================
-- GlobalBank DB — Local Cleanup (run as ADMIN on globalbanklocal / ATP2)
-- Drops both BUCHAREST_USER and CLUJ_USER and all their objects
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

SELECT 'ATP2 cleanup complete' AS status FROM DUAL;
