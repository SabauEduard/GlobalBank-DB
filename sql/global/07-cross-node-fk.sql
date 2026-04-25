-- ============================================================
-- GlobalBank DB — T045: Cross-Node FK Enforcement Triggers
-- Run as GLOBAL_USER on bankdb_high
-- NOTE: Requires DB Links (BUCHAREST_LINK) to be working
-- ============================================================

-- Drop existing trigger (idempotent)
BEGIN EXECUTE IMMEDIATE 'DROP TRIGGER trg_bef_ins_credite'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

-- ============================================================
-- T045: BEFORE INSERT on CREDITE — verify ID_Client exists
-- in local CLIENTI_ID (cross-node FK from Central to ATP2)
-- ============================================================
CREATE OR REPLACE TRIGGER trg_bef_ins_credite
BEFORE INSERT ON CREDITE
FOR EACH ROW
DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM   CLIENTI_ID@BUCHAREST_LINK
  WHERE  ID_Client = :NEW.ID_Client;
  IF v_count = 0 THEN
    RAISE_APPLICATION_ERROR(-20001,
      'ID_Client ' || :NEW.ID_Client || ' nu exista in CLIENTI_ID');
  END IF;
END;
/
