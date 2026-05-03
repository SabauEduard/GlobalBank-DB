-- ============================================================
-- GlobalBank DB — T029-T040: Global Views + INSTEAD OF Triggers
-- Run as GLOBAL_USER on bankdb_high
-- NOTE: Requires DB Links (BUCHAREST_LINK, CLUJ_LINK) to be working
-- ============================================================

-- Drop existing triggers and views (idempotent)
BEGIN EXECUTE IMMEDIATE 'DROP TRIGGER trg_iof_tranzactii_global'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TRIGGER trg_iof_conturi_global';    EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TRIGGER trg_iof_clienti_global';    EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP VIEW TRANZACTII_GLOBAL'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP VIEW CONTURI_GLOBAL';    EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP VIEW CLIENTI_GLOBAL';    EXCEPTION WHEN OTHERS THEN NULL; END;
/

-- ============================================================
-- T029: CLIENTI_GLOBAL — vertical fragment reconstruction
-- UNION deduplicates: Bucharest is authoritative; Cluj supplies
-- any clients not yet replicated to Bucharest.
-- ============================================================
CREATE VIEW CLIENTI_GLOBAL AS
SELECT ci.ID_Client, ci.Nume, ci.Prenume, ci.CNP,
       cp.Email, cp.Telefon, cp.Scor_Credit
FROM   CLIENTI_ID@BUCHAREST_LINK ci
JOIN   CLIENTI_PROFIL cp ON ci.ID_Client = cp.ID_Client
UNION
SELECT ci.ID_Client, ci.Nume, ci.Prenume, ci.CNP,
       cp.Email, cp.Telefon, cp.Scor_Credit
FROM   CLIENTI_ID@CLUJ_LINK ci
JOIN   CLIENTI_PROFIL cp ON ci.ID_Client = cp.ID_Client
WHERE  ci.ID_Client NOT IN (
         SELECT ID_Client FROM CLIENTI_ID@BUCHAREST_LINK
       );

-- ============================================================
-- T034: CONTURI_GLOBAL — horizontal fragment reconstruction
-- ============================================================
CREATE VIEW CONTURI_GLOBAL AS
SELECT ID_Cont, IBAN, ID_Tip, Sold, Moneda, ID_Sucursala, ID_Client, 'B' AS Nod
FROM   CONTURI_B@BUCHAREST_LINK
UNION ALL
SELECT ID_Cont, IBAN, ID_Tip, Sold, Moneda, ID_Sucursala, ID_Client, 'C' AS Nod
FROM   CONTURI_C@CLUJ_LINK;

-- ============================================================
-- T035: TRANZACTII_GLOBAL — derived horizontal fragment reconstruction
-- ============================================================
CREATE VIEW TRANZACTII_GLOBAL AS
SELECT ID_Tranzactie, Data, Suma, Tip_Tranzactie, ID_Cont_Sursa, 'B' AS Nod
FROM   TRANZACTII_B@BUCHAREST_LINK
UNION ALL
SELECT ID_Tranzactie, Data, Suma, Tip_Tranzactie, ID_Cont_Sursa, 'C' AS Nod
FROM   TRANZACTII_C@CLUJ_LINK;

-- ============================================================
-- T030/T031/T032: trg_iof_clienti_global
-- INSERT: generate global ID, write to both CLIENTI_ID nodes + CLIENTI_PROFIL
-- UPDATE: propagate name/CNP to both nodes, profile data to Central
-- DELETE: remove from both nodes and Central
-- ============================================================
CREATE OR REPLACE TRIGGER trg_iof_clienti_global
INSTEAD OF INSERT OR UPDATE OR DELETE ON CLIENTI_GLOBAL
FOR EACH ROW
DECLARE
  v_id NUMBER(10);
BEGIN
  IF INSERTING THEN
    v_id := CASE WHEN :NEW.ID_Client IS NOT NULL THEN :NEW.ID_Client
                 ELSE SEQ_CLIENT_GLOBAL.NEXTVAL
            END;
    INSERT INTO CLIENTI_ID@BUCHAREST_LINK (ID_Client, Nume, Prenume, CNP)
      VALUES (v_id, :NEW.Nume, :NEW.Prenume, :NEW.CNP);
    INSERT INTO CLIENTI_ID@CLUJ_LINK (ID_Client, Nume, Prenume, CNP)
      VALUES (v_id, :NEW.Nume, :NEW.Prenume, :NEW.CNP);
    INSERT INTO CLIENTI_PROFIL (ID_Client, Email, Telefon, Scor_Credit)
      VALUES (v_id, :NEW.Email, :NEW.Telefon, NVL(:NEW.Scor_Credit, 500));

  ELSIF UPDATING THEN
    UPDATE CLIENTI_ID@BUCHAREST_LINK
      SET Nume=:NEW.Nume, Prenume=:NEW.Prenume, CNP=:NEW.CNP
      WHERE ID_Client = :OLD.ID_Client;
    UPDATE CLIENTI_ID@CLUJ_LINK
      SET Nume=:NEW.Nume, Prenume=:NEW.Prenume, CNP=:NEW.CNP
      WHERE ID_Client = :OLD.ID_Client;
    UPDATE CLIENTI_PROFIL
      SET Email=:NEW.Email, Telefon=:NEW.Telefon, Scor_Credit=:NEW.Scor_Credit
      WHERE ID_Client = :OLD.ID_Client;

  ELSIF DELETING THEN
    DELETE FROM CLIENTI_ID@BUCHAREST_LINK WHERE ID_Client = :OLD.ID_Client;
    DELETE FROM CLIENTI_ID@CLUJ_LINK     WHERE ID_Client = :OLD.ID_Client;
    DELETE FROM CLIENTI_PROFIL           WHERE ID_Client = :OLD.ID_Client;
  END IF;
END;
/

-- ============================================================
-- T036/T037: trg_iof_conturi_global
-- INSERT:  route by ID_Sucursala (1=Bucharest, 2=Cluj)
-- UPDATE:  in-place update on the same fragment (Sold, IBAN, etc.)
-- DELETE:  cascade-delete children then parent from correct fragment
-- ============================================================
CREATE OR REPLACE TRIGGER trg_iof_conturi_global
INSTEAD OF INSERT OR UPDATE OR DELETE ON CONTURI_GLOBAL
FOR EACH ROW
DECLARE
  v_id     NUMBER(10);
  v_cnt    NUMBER(1);
BEGIN
  IF INSERTING THEN
    -- Global IBAN uniqueness: check both fragments before inserting
    SELECT COUNT(*) INTO v_cnt
    FROM (
      SELECT IBAN FROM CONTURI_B@BUCHAREST_LINK WHERE IBAN = :NEW.IBAN
      UNION ALL
      SELECT IBAN FROM CONTURI_C@CLUJ_LINK       WHERE IBAN = :NEW.IBAN
    ) WHERE ROWNUM = 1;
    IF v_cnt > 0 THEN
      RAISE_APPLICATION_ERROR(-20001,
        'IBAN ' || :NEW.IBAN || ' already exists globally (unicitate globala IBAN)');
    END IF;

    IF :NEW.ID_Sucursala = 1 THEN
      SELECT SEQ_CONT_B.NEXTVAL@BUCHAREST_LINK INTO v_id FROM DUAL;
      INSERT INTO CONTURI_B@BUCHAREST_LINK
        (ID_Cont, IBAN, ID_Tip, Sold, Moneda, ID_Sucursala, ID_Client)
        VALUES (v_id, :NEW.IBAN, :NEW.ID_Tip, NVL(:NEW.Sold, 0),
                NVL(:NEW.Moneda, 'RON'), 1, :NEW.ID_Client);
    ELSIF :NEW.ID_Sucursala = 2 THEN
      SELECT SEQ_CONT_C.NEXTVAL@CLUJ_LINK INTO v_id FROM DUAL;
      INSERT INTO CONTURI_C@CLUJ_LINK
        (ID_Cont, IBAN, ID_Tip, Sold, Moneda, ID_Sucursala, ID_Client)
        VALUES (v_id, :NEW.IBAN, :NEW.ID_Tip, NVL(:NEW.Sold, 0),
                NVL(:NEW.Moneda, 'RON'), 2, :NEW.ID_Client);
    END IF;

  ELSIF UPDATING THEN
    IF :OLD.ID_Sucursala = 1 THEN
      UPDATE CONTURI_B@BUCHAREST_LINK
        SET IBAN=:NEW.IBAN, ID_Tip=:NEW.ID_Tip, Sold=:NEW.Sold, Moneda=:NEW.Moneda
        WHERE ID_Cont = :OLD.ID_Cont;
    ELSE
      UPDATE CONTURI_C@CLUJ_LINK
        SET IBAN=:NEW.IBAN, ID_Tip=:NEW.ID_Tip, Sold=:NEW.Sold, Moneda=:NEW.Moneda
        WHERE ID_Cont = :OLD.ID_Cont;
    END IF;

  ELSIF DELETING THEN
    IF :OLD.ID_Sucursala = 1 THEN
      DELETE FROM TRANZACTII_B@BUCHAREST_LINK WHERE ID_Cont_Sursa = :OLD.ID_Cont;
      DELETE FROM CARDURI_B@BUCHAREST_LINK    WHERE ID_Cont       = :OLD.ID_Cont;
      DELETE FROM CONTURI_B@BUCHAREST_LINK    WHERE ID_Cont       = :OLD.ID_Cont;
    ELSE
      DELETE FROM TRANZACTII_C@CLUJ_LINK WHERE ID_Cont_Sursa = :OLD.ID_Cont;
      DELETE FROM CARDURI_C@CLUJ_LINK    WHERE ID_Cont       = :OLD.ID_Cont;
      DELETE FROM CONTURI_C@CLUJ_LINK    WHERE ID_Cont       = :OLD.ID_Cont;
    END IF;
  END IF;
END;
/

-- ============================================================
-- TRANZACTII_GLOBAL INSTEAD OF trigger
-- Routing: ID_Cont_Sursa < 1000000 → Bucharest; else Cluj
-- ============================================================
CREATE OR REPLACE TRIGGER trg_iof_tranzactii_global
INSTEAD OF INSERT OR UPDATE OR DELETE ON TRANZACTII_GLOBAL
FOR EACH ROW
DECLARE
  v_id NUMBER(10);
BEGIN
  IF INSERTING THEN
    IF :NEW.ID_Cont_Sursa < 1000000 THEN
      SELECT SEQ_TRANZ_B.NEXTVAL@BUCHAREST_LINK INTO v_id FROM DUAL;
      INSERT INTO TRANZACTII_B@BUCHAREST_LINK
        (ID_Tranzactie, Data, Suma, Tip_Tranzactie, ID_Cont_Sursa)
        VALUES (v_id, NVL(:NEW.Data, SYSDATE), :NEW.Suma, :NEW.Tip_Tranzactie, :NEW.ID_Cont_Sursa);
    ELSE
      SELECT SEQ_TRANZ_C.NEXTVAL@CLUJ_LINK INTO v_id FROM DUAL;
      INSERT INTO TRANZACTII_C@CLUJ_LINK
        (ID_Tranzactie, Data, Suma, Tip_Tranzactie, ID_Cont_Sursa)
        VALUES (v_id, NVL(:NEW.Data, SYSDATE), :NEW.Suma, :NEW.Tip_Tranzactie, :NEW.ID_Cont_Sursa);
    END IF;

  ELSIF UPDATING THEN
    IF :OLD.ID_Cont_Sursa < 1000000 THEN
      UPDATE TRANZACTII_B@BUCHAREST_LINK
        SET Data=:NEW.Data, Suma=:NEW.Suma, Tip_Tranzactie=:NEW.Tip_Tranzactie
        WHERE ID_Tranzactie = :OLD.ID_Tranzactie;
    ELSE
      UPDATE TRANZACTII_C@CLUJ_LINK
        SET Data=:NEW.Data, Suma=:NEW.Suma, Tip_Tranzactie=:NEW.Tip_Tranzactie
        WHERE ID_Tranzactie = :OLD.ID_Tranzactie;
    END IF;

  ELSIF DELETING THEN
    IF :OLD.ID_Cont_Sursa < 1000000 THEN
      DELETE FROM TRANZACTII_B@BUCHAREST_LINK WHERE ID_Tranzactie = :OLD.ID_Tranzactie;
    ELSE
      DELETE FROM TRANZACTII_C@CLUJ_LINK WHERE ID_Tranzactie = :OLD.ID_Tranzactie;
    END IF;
  END IF;
END;
/

-- ============================================================
-- T033: Verify S1 — insert new client via CLIENTI_GLOBAL
-- ============================================================
INSERT INTO CLIENTI_GLOBAL (Nume, Prenume, CNP, Email, Telefon, Scor_Credit)
VALUES ('Test', 'Global', '1990101400999', 'test.global@bank.ro', '0799000001', 650);
SELECT ID_Client, Nume, Prenume, Scor_Credit FROM CLIENTI_GLOBAL
  WHERE CNP = '1990101400999';
-- Verify both nodes received the row:
SELECT ID_Client FROM CLIENTI_ID@BUCHAREST_LINK WHERE CNP = '1990101400999';
SELECT ID_Client FROM CLIENTI_ID@CLUJ_LINK     WHERE CNP = '1990101400999';
ROLLBACK;

-- ============================================================
-- T040: Verify S2 — horizontal transparency via INSERT routing
-- The user works only with CONTURI_GLOBAL; the trigger routes
-- each row to the correct physical fragment automatically.
-- ============================================================
-- Insert one account per branch via the unified global view:
INSERT INTO CONTURI_GLOBAL (IBAN, ID_Tip, Sold, Moneda, ID_Sucursala, ID_Client)
VALUES ('RO49GLOBTEST00000000001', 1, 1000, 'RON', 1, 1);
INSERT INTO CONTURI_GLOBAL (IBAN, ID_Tip, Sold, Moneda, ID_Sucursala, ID_Client)
VALUES ('RO49GLOBTEST00000000002', 1, 2500, 'RON', 2, 1);
COMMIT;
-- Both rows are visible via the unified view; Nod shows physical location:
SELECT ID_Cont, IBAN, Sold, ID_Sucursala, Nod FROM CONTURI_GLOBAL
  WHERE IBAN IN ('RO49GLOBTEST00000000001', 'RO49GLOBTEST00000000002');
-- Update Sold on the Bucharest account without knowing it lives in CONTURI_B:
UPDATE CONTURI_GLOBAL SET Sold = 1500
  WHERE IBAN = 'RO49GLOBTEST00000000001';
COMMIT;
-- Confirm the update was applied to the correct fragment:
SELECT ID_Cont, IBAN, Sold, Nod FROM CONTURI_GLOBAL
  WHERE IBAN = 'RO49GLOBTEST00000000001';
-- Cleanup test data:
DELETE FROM CONTURI_GLOBAL
  WHERE IBAN IN ('RO49GLOBTEST00000000001', 'RO49GLOBTEST00000000002');
COMMIT;
