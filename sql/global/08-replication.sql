-- ============================================================
-- GlobalBank DB — T028, T049-T050: TIPURI_CONT Replication
-- Run as GLOBAL_USER on bankdb_high
-- NOTE: Requires DB Links (BUCHAREST_LINK, CLUJ_LINK) to be working
-- ============================================================

-- Drop existing trigger (idempotent)
BEGIN EXECUTE IMMEDIATE 'DROP TRIGGER trg_replicate_tipuri_cont'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

-- ============================================================
-- T028: Initial sync — push existing TIPURI_CONT master data
-- to both slave nodes (idempotent via MERGE)
-- ============================================================
MERGE INTO TIPURI_CONT@BUCHAREST_LINK dst
USING TIPURI_CONT src ON (dst.ID_Tip = src.ID_Tip)
WHEN MATCHED     THEN UPDATE SET dst.Denumire = src.Denumire, dst.Dobanda = src.Dobanda
WHEN NOT MATCHED THEN INSERT (ID_Tip, Denumire, Dobanda) VALUES (src.ID_Tip, src.Denumire, src.Dobanda);

MERGE INTO TIPURI_CONT@CLUJ_LINK dst
USING TIPURI_CONT src ON (dst.ID_Tip = src.ID_Tip)
WHEN MATCHED     THEN UPDATE SET dst.Denumire = src.Denumire, dst.Dobanda = src.Dobanda
WHEN NOT MATCHED THEN INSERT (ID_Tip, Denumire, Dobanda) VALUES (src.ID_Tip, src.Denumire, src.Dobanda);

COMMIT;

-- ============================================================
-- T049: trg_replicate_tipuri_cont
-- After any DML on the Central master TIPURI_CONT,
-- propagate the change to both slave copies via DB Links.
-- ============================================================
CREATE OR REPLACE TRIGGER trg_replicate_tipuri_cont
AFTER INSERT OR UPDATE OR DELETE ON TIPURI_CONT
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    INSERT INTO TIPURI_CONT@BUCHAREST_LINK (ID_Tip, Denumire, Dobanda)
      VALUES (:NEW.ID_Tip, :NEW.Denumire, :NEW.Dobanda);
    INSERT INTO TIPURI_CONT@CLUJ_LINK (ID_Tip, Denumire, Dobanda)
      VALUES (:NEW.ID_Tip, :NEW.Denumire, :NEW.Dobanda);

  ELSIF UPDATING THEN
    UPDATE TIPURI_CONT@BUCHAREST_LINK
      SET Denumire = :NEW.Denumire, Dobanda = :NEW.Dobanda
      WHERE ID_Tip = :OLD.ID_Tip;
    UPDATE TIPURI_CONT@CLUJ_LINK
      SET Denumire = :NEW.Denumire, Dobanda = :NEW.Dobanda
      WHERE ID_Tip = :OLD.ID_Tip;

  ELSIF DELETING THEN
    DELETE FROM TIPURI_CONT@BUCHAREST_LINK WHERE ID_Tip = :OLD.ID_Tip;
    DELETE FROM TIPURI_CONT@CLUJ_LINK     WHERE ID_Tip = :OLD.ID_Tip;
  END IF;
END;
/

-- ============================================================
-- T050: Verify S6 — insert a new account type on Central,
-- confirm it appears on both slave nodes
-- ============================================================
-- INSERT INTO TIPURI_CONT VALUES (5, 'Pensie', 2.50);
-- COMMIT;
-- SELECT ID_Tip, Denumire, Dobanda FROM TIPURI_CONT;
-- SELECT ID_Tip, Denumire, Dobanda FROM TIPURI_CONT@BUCHAREST_LINK;
-- SELECT ID_Tip, Denumire, Dobanda FROM TIPURI_CONT@CLUJ_LINK;
-- ROLLBACK;
