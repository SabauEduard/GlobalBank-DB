-- ============================================================
-- GlobalBank DB — T038-T039, T046-T048: Integrity Constraints
-- Run as GLOBAL_USER on bankdb_high
-- ============================================================

-- ============================================================
-- T039/T046: Constraint categories present in this schema
-- ============================================================
-- 1. PRIMARY KEY: Every table has a PK (ID_* columns)
--    Example: CONTURI_B.ID_Cont PRIMARY KEY
--
-- 2. FOREIGN KEY (local, within fragment):
--    CONTURI_B.ID_Tip  → TIPURI_CONT.ID_Tip      (local on ATP2)
--    CONTURI_B.ID_Client → CLIENTI_ID.ID_Client  (local on ATP2)
--    PLATI_RATE.ID_Credit → CREDITE.ID_Credit    (local on ATP1)
--
-- 3. CHECK constraints (domain integrity):
--    CONTURI_B: ID_Sucursala = 1 (fragment purity)
--    CONTURI_C: ID_Sucursala = 2 (fragment purity)
--    TRANZACTII: Tip_Tranzactie IN ('DEBIT','CREDIT','TRANSFER')
--    TIPURI_CONT: Dobanda BETWEEN 0 AND 100
--    CLIENTI_PROFIL: Scor_Credit BETWEEN 0 AND 999
--
-- 4. UNIQUE: IBAN, CNP, Denumire, Email — each is globally unique
--
-- 5. Cross-node FK (enforced via triggers, not DDL — cross-instance):
--    CREDITE.ID_Client  → CLIENTI_ID on local nodes  (see T045)
--    CONTURI.ID_Client  → CLIENTI_ID on local nodes  (validated in INSTEAD OF trigger)
-- ============================================================

-- ============================================================
-- T038: Cross-node FK for CONTURI — validated inline in
-- trg_iof_conturi_global (04-transparency.sql).
-- As an additional safety net, enforce locally for direct inserts:
-- this trigger runs on CONTURI_GLOBAL (global view layer).
-- Direct inserts to CONTURI_B/C on ATP2 are protected by the
-- local FK: CONTURI_B.ID_Client → CLIENTI_ID.ID_Client
-- ============================================================

-- ============================================================
-- T047: Verify S4 — local INSERT visible via global view
-- ============================================================
-- Insert directly into Bucharest local fragment
INSERT INTO CONTURI_B@BUCHAREST_LINK
  (ID_Cont, IBAN, ID_Tip, Sold, Moneda, ID_Sucursala, ID_Client)
VALUES (SEQ_CONT_B.NEXTVAL@BUCHAREST_LINK,
        'RO49GLOBVERIF00000001', 1, 500.00, 'RON', 1, 1);
COMMIT;
-- Verify it appears in the global view
SELECT ID_Cont, IBAN, Nod FROM CONTURI_GLOBAL
  WHERE IBAN = 'RO49GLOBVERIF00000001';
-- Clean up
DELETE FROM CONTURI_B@BUCHAREST_LINK WHERE IBAN = 'RO49GLOBVERIF00000001';
COMMIT;

-- ============================================================
-- T048: Verify S5 — INSERT via CLIENTI_GLOBAL propagates to both nodes
-- ============================================================
INSERT INTO CLIENTI_GLOBAL (Nume, Prenume, CNP, Email, Telefon, Scor_Credit)
VALUES ('Verif', 'Test', '5000101410001', 'verif.test@bank.ro', '0700000001', 700);
COMMIT;
-- Confirm presence in both local CLIENTI_ID tables
SELECT ID_Client, Nume FROM CLIENTI_ID@BUCHAREST_LINK WHERE CNP = '5000101410001';
SELECT ID_Client, Nume FROM CLIENTI_ID@CLUJ_LINK     WHERE CNP = '5000101410001';
-- Clean up
DELETE FROM CLIENTI_GLOBAL WHERE CNP = '5000101410001';
COMMIT;
