# GlobalBank DB — Analiza Sistemului Distribuit

## N1 — Descrierea modelului conceptual

Sistemul GlobalBank este o bază de date bancară distribuită pe 2 instanțe Oracle ATP Free Tier:

- **ATP1 (Central — bankdb)**: nod coordonator, găzduiește `GLOBAL_USER`; tabele: `SUCURSALE`, `TIPURI_CONT` (master), `CLIENTI_PROFIL`, `CREDITE`, `PLATI_RATE`, `LOG_ACCES`
- **ATP2 (Local — globalbanklocal)**: ambele noduri locale pe aceeași instanță, scheme diferite; `BUCHAREST_USER` (sucursala 1) și `CLUJ_USER` (sucursala 2)

Comunicarea inter-nod se face exclusiv prin **DB Links** (`BUCHAREST_LINK`, `CLUJ_LINK`) create cu `DBMS_CLOUD_ADMIN.CREATE_DATABASE_LINK` (protocol TCPS/mTLS).

---

## N2 — Diagrama entitate-relație (ER)

Entități principale și relații:

```
SUCURSALE (1) ──< CONTURI_B / CONTURI_C >── (N) TIPURI_CONT
CLIENTI_ID (1) ──< CONTURI_B / CONTURI_C
CONTURI_B  (1) ──< TRANZACTII_B
CONTURI_C  (1) ──< TRANZACTII_C
CLIENTI_PROFIL (1) ──< CREDITE (1) ──< PLATI_RATE
ANGAJATI_B / ANGAJATI_C >── ANGAJAT_CLIENT_B / ANGAJAT_CLIENT_C ──< CLIENTI_ID
```

Fragmentarea verticală a clientului: `CLIENTI_ID` (date de identificare — local) + `CLIENTI_PROFIL` (date bancare — central).

---

## N3 — Schema conceptuală globală

Vederea globală expusă prin `GLOBAL_USER`:

| View global          | Surse                                        | Tip fragmentare     |
|---------------------|----------------------------------------------|---------------------|
| `CLIENTI_GLOBAL`    | `CLIENTI_ID@BUCHAREST_LINK` JOIN `CLIENTI_PROFIL` UNION `CLIENTI_ID@CLUJ_LINK` | Verticală |
| `CONTURI_GLOBAL`    | `CONTURI_B@BUCHAREST_LINK` UNION ALL `CONTURI_C@CLUJ_LINK` | Orizontală |
| `TRANZACTII_GLOBAL` | `TRANZACTII_B@BUCHAREST_LINK` UNION ALL `TRANZACTII_C@CLUJ_LINK` | Orizontală |

---

## N4 — Distribuția datelor

| Tabel / Fragment    | Nod           | Criterii de plasare                          |
|--------------------|---------------|----------------------------------------------|
| `SUCURSALE`        | Central        | Date de referință globale                    |
| `TIPURI_CONT`      | Central (master) + ambele noduri (slave) | Replicare simetrică |
| `CLIENTI_PROFIL`   | Central        | Fragmentare verticală — date financiare      |
| `CLIENTI_ID`       | Bucharest + Cluj | Fragmentare verticală — date de identitate (ambele noduri) |
| `CONTURI_B`        | Bucharest      | Fragmentare orizontală — `ID_Sucursala = 1`  |
| `CONTURI_C`        | Cluj           | Fragmentare orizontală — `ID_Sucursala = 2`  |
| `TRANZACTII_B`     | Bucharest      | Derivat din `CONTURI_B` (localitate tranzacție) |
| `TRANZACTII_C`     | Cluj           | Derivat din `CONTURI_C`                      |
| `CREDITE`          | Central        | Date de credit — gestionate central          |

---

## N5 — Algoritmi de fragmentare

### Fragmentare orizontală (CONTURI, TRANZACTII)

**Predicat de selecție**: `ID_Sucursala = 1` → `CONTURI_B`; `ID_Sucursala = 2` → `CONTURI_C`

Algoritm de reconstrucție:
```sql
CONTURI_GLOBAL = UNION ALL (CONTURI_B, CONTURI_C)
```

Verificare completitudine: orice cont are `ID_Sucursala ∈ {1, 2}` → `CONTURI_B ∪ CONTURI_C = CONTURI_GLOBAL`  
Verificare disjuncție: CHECK constraint asigură că `CONTURI_B.ID_Sucursala = 1` și `CONTURI_C.ID_Sucursala = 2`

### Fragmentare verticală (CLIENTI)

**Proiecție**:
- `CLIENTI_ID` = `{ID_Client, Nume, Prenume, CNP}` — pe nodurile locale
- `CLIENTI_PROFIL` = `{ID_Client, Email, Telefon, Scor_Credit}` — pe nodul central

Algoritm de reconstrucție:
```sql
CLIENTI_GLOBAL = CLIENTI_ID JOIN CLIENTI_PROFIL ON ID_Client
```

Verificare completitudine: orice client are rând în ambele relații (FK CLIENTI_PROFIL → CLIENTI_ID)  
Verificare disjuncție: atributele din cele două proiecții sunt disjuncte (+ ID_Client apare în ambele — atribut de legătură)

---

## N6 — Corectitudinea fragmentării

**Completitudine**: 
- Orizontală: `CHECK(ID_Sucursala=1)` pe CONTURI_B și `CHECK(ID_Sucursala=2)` pe CONTURI_C garantează că orice cont este reprezentat exact o dată
- Verticală: trigger `trg_iof_clienti_global` la INSERT scrie simultan în `CLIENTI_ID` (ambele noduri) și `CLIENTI_PROFIL`

**Reconstrucție**: Vederile `CLIENTI_GLOBAL`, `CONTURI_GLOBAL`, `TRANZACTII_GLOBAL` reconstruiesc datele originale fără pierdere de informație

**Disjuncție**: 
- Orizontală: garantată prin CHECK constraints pe fragmentele locale
- Verticală: `CLIENTI_ID.CNP` UNIQUE + `CLIENTI_PROFIL.Email` UNIQUE

---

## N7 — Replicare

### Obiect replicat: `TIPURI_CONT`

- **Master**: `GLOBAL_USER.TIPURI_CONT` pe ATP1
- **Slave 1**: `BUCHAREST_USER.TIPURI_CONT` pe ATP2
- **Slave 2**: `CLUJ_USER.TIPURI_CONT` pe ATP2

**Mecanism**: Trigger `TRG_REPLICATE_TIPURI_CONT` (AFTER INSERT OR UPDATE OR DELETE pe master) propagă modificările la ambele slave prin DB Links

**Sincronizare inițială**: `MERGE INTO TIPURI_CONT@BUCHAREST_LINK USING TIPURI_CONT ...` (în `sql/global/08-replication.sql`)

**Tip replicare**: asincronă, tranzacțională, single-master (ATP1 → ATP2)

---

## N8 — Schemele locale

### Schema Bucharest (BUCHAREST_USER pe ATP2)
```
TIPURI_CONT, CLIENTI_ID, CONTURI_B, TRANZACTII_B, CARDURI_B, ANGAJATI_B, ANGAJAT_CLIENT_B
```
Secvențe: `SEQ_CLIENT_B` (1–999999), `SEQ_CONT_B` (1–999999), `SEQ_TRANZ_B` (1–999999)

### Schema Cluj (CLUJ_USER pe ATP2)
```
TIPURI_CONT, CLIENTI_ID, CONTURI_C, TRANZACTII_C, CARDURI_C, ANGAJATI_C, ANGAJAT_CLIENT_C
```
Secvențe: `SEQ_CLIENT_C` (1000001–1999999), `SEQ_CONT_C` (1000001–1999999), `SEQ_TRANZ_C` (1000001–1999999)

Rangurile non-suprapuse garantează **unicitate globală** fără coordonare centralizată.

---

## N9 — Constrângeri de integritate

### Locale (DDL, în cadrul aceleiași scheme)
| Tip         | Exemple                                                       |
|-------------|---------------------------------------------------------------|
| PRIMARY KEY | Toate tabelele — `ID_*` columns                              |
| FOREIGN KEY | `CONTURI_B.ID_Tip → TIPURI_CONT`, `CONTURI_B.ID_Client → CLIENTI_ID` |
| CHECK       | `CONTURI_B: ID_Sucursala=1`, `TIPURI_CONT: Dobanda BETWEEN 0 AND 100`, `Tip_Tranzactie IN (...)` |
| UNIQUE      | `IBAN`, `CNP`, `Denumire_Sucursala`, `Email`                 |

### Cross-nod (simulate prin triggere — Oracle nu suportă FK inter-instance)
| Trigger                         | Constrângere simulată                                 |
|---------------------------------|-------------------------------------------------------|
| `TRG_BEF_INS_CREDITE`          | `CREDITE.ID_Client` trebuie să existe în `CLIENTI_ID@BUCHAREST_LINK` |
| `TRG_IOF_CONTURI_GLOBAL`       | Validare inline: `ID_Client` exist pe nodul destinație |

---

## N10 — Interogare complexă distribuită (S3)

```sql
SELECT c.ID_Client, c.Nume || ' ' || c.Prenume AS Nume_Complet, c.Scor_Credit,
       COUNT(t.ID_Tranzactie) AS Nr_Tranzactii,
       SUM(t.Suma)            AS Total_Tranzactat,
       SUM(co.Sold)           AS Sold_Total
FROM   CLIENTI_GLOBAL c
JOIN   CONTURI_GLOBAL co ON c.ID_Client = co.ID_Client
JOIN   TRANZACTII_GLOBAL t ON co.ID_Cont = t.ID_Cont_Sursa
WHERE  c.Scor_Credit > 700
GROUP BY c.ID_Client, c.Nume, c.Prenume, c.Scor_Credit
ORDER BY Total_Tranzactat DESC;
```

**Rezultat**: 6 clienți cu Scor_Credit > 700; primul: Stan Elena (900) cu Total_Tranzactat=13500 RON

**EXPLAIN PLAN**: indexul `IDX_CLIENTI_PROFIL_SCOR` este utilizat (INDEX RANGE SCAN, cost=1); accese REMOTE la `BUCHAREST_LINK` și `CLUJ_LINK` sunt vizibile explicit în plan

**Optimizare aplicată**: `CREATE INDEX idx_clienti_profil_scor ON CLIENTI_PROFIL(Scor_Credit)` → reduce costul filtrului `Scor_Credit > 700` de la FULL TABLE SCAN la INDEX RANGE SCAN
