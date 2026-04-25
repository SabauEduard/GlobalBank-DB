-- ============================================================
-- GlobalBank DB — T041-T044: Complex Query + Optimization
-- Run as GLOBAL_USER on bankdb_high
-- NOTE: T041-T043 queries require DB Links to be working
-- T044 index creation runs locally (no DB Links needed)
-- ============================================================

-- ============================================================
-- T044 (run first — no DB Links required):
-- Index on CLIENTI_PROFIL.Scor_Credit to accelerate the
-- filter condition in the complex analytical query
-- ============================================================
BEGIN EXECUTE IMMEDIATE 'DROP INDEX idx_clienti_profil_scor'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
CREATE INDEX idx_clienti_profil_scor ON CLIENTI_PROFIL(Scor_Credit);

-- Additional local indexes for join acceleration
BEGIN EXECUTE IMMEDIATE 'DROP INDEX idx_credite_client'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
CREATE INDEX idx_credite_client ON CREDITE(ID_Client);

BEGIN EXECUTE IMMEDIATE 'DROP INDEX idx_plati_credit'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
CREATE INDEX idx_plati_credit ON PLATI_RATE(ID_Credit);

-- ============================================================
-- T041: Complex query (S3) — total transaction amount by clients
-- with Scor_Credit > 700, joining all three global views.
-- ============================================================
SELECT c.ID_Client,
       c.Nume       || ' ' || c.Prenume AS Nume_Complet,
       c.Scor_Credit,
       COUNT(t.ID_Tranzactie)           AS Nr_Tranzactii,
       SUM(t.Suma)                      AS Total_Tranzactat,
       SUM(co.Sold)                     AS Sold_Total
FROM   CLIENTI_GLOBAL    c
JOIN   CONTURI_GLOBAL    co ON c.ID_Client     = co.ID_Client
JOIN   TRANZACTII_GLOBAL t  ON co.ID_Cont      = t.ID_Cont_Sursa
WHERE  c.Scor_Credit > 700
GROUP BY c.ID_Client, c.Nume, c.Prenume, c.Scor_Credit
ORDER BY Total_Tranzactat DESC;

-- ============================================================
-- T042: Rule-based optimizer plan (hint-forced)
-- ============================================================
SELECT /*+ RULE */
       c.ID_Client, c.Scor_Credit,
       COUNT(t.ID_Tranzactie) AS Nr_Tranzactii,
       SUM(t.Suma)            AS Total_Tranzactat
FROM   CLIENTI_GLOBAL    c
JOIN   CONTURI_GLOBAL    co ON c.ID_Client  = co.ID_Client
JOIN   TRANZACTII_GLOBAL t  ON co.ID_Cont   = t.ID_Cont_Sursa
WHERE  c.Scor_Credit > 700
GROUP BY c.ID_Client, c.Scor_Credit
ORDER BY Total_Tranzactat DESC;

-- ============================================================
-- T043: Cost-based optimizer EXPLAIN PLAN
-- ============================================================
EXPLAIN PLAN FOR
  SELECT c.ID_Client, c.Scor_Credit,
         COUNT(t.ID_Tranzactie) AS Nr_Tranzactii,
         SUM(t.Suma)            AS Total_Tranzactat
  FROM   CLIENTI_GLOBAL    c
  JOIN   CONTURI_GLOBAL    co ON c.ID_Client = co.ID_Client
  JOIN   TRANZACTII_GLOBAL t  ON co.ID_Cont  = t.ID_Cont_Sursa
  WHERE  c.Scor_Credit > 700
  GROUP BY c.ID_Client, c.Scor_Credit
  ORDER BY Total_Tranzactat DESC;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- Local-only analytical query (no DB Links — runs against Central data):
SELECT 'Clients with Scor_Credit > 700' AS query_label,
       COUNT(*)                          AS nr_clienti
FROM   CLIENTI_PROFIL
WHERE  Scor_Credit > 700;

SELECT cp.ID_Client, cp.Scor_Credit,
       SUM(c.Suma_Totala) AS Total_Creditat,
       COUNT(c.ID_Credit) AS Nr_Credite
FROM   CLIENTI_PROFIL cp
JOIN   CREDITE        c  ON c.ID_Client = cp.ID_Client
WHERE  cp.Scor_Credit > 700
GROUP BY cp.ID_Client, cp.Scor_Credit
ORDER BY Total_Creditat DESC;
