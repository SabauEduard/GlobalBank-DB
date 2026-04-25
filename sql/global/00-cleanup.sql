-- ============================================================
-- GlobalBank DB — Full Cleanup (run as ADMIN on bankdb / ATP1)
-- Drops GLOBAL_USER and all credentials/DB Links owned by it
-- ============================================================

-- Drop credentials first (owned by GLOBAL_USER, CASCADE handles them,
-- but explicit drop avoids ORA-20000 on re-create)
BEGIN
  DBMS_CLOUD.DROP_CREDENTIAL('ATP2_BUCHAREST_CRED');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  DBMS_CLOUD.DROP_CREDENTIAL('ATP2_CLUJ_CRED');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- Drop GLOBAL_USER and all its objects (tables, views, triggers, sequences, DB Links)
BEGIN
  EXECUTE IMMEDIATE 'DROP USER GLOBAL_USER CASCADE';
  DBMS_OUTPUT.PUT_LINE('GLOBAL_USER dropped.');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -1918 THEN
      DBMS_OUTPUT.PUT_LINE('GLOBAL_USER does not exist, skipping.');
    ELSE RAISE;
    END IF;
END;
/

SELECT 'ATP1 cleanup complete' AS status FROM DUAL;
