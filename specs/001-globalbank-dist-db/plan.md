# Implementation Plan: GlobalBank DB

**Branch**: `001-globalbank-dist-db`
**Created**: 2026-04-25
**Spec**: [spec.md](spec.md) | **Data model**: [data-model.md](data-model.md) | **Research**: [research.md](research.md)

---

## Architecture overview

```
┌─────────────────────────────────────────────┐
│  ATP Instance 1 — Central Node (GLOBAL_USER) │
│                                              │
│  SUCURSALE          CLIENTI_PROFIL           │
│  TIPURI_CONT(master) CREDITE  PLATI_RATE     │
│  LOG_ACCES                                   │
│                                              │
│  Views: CLIENTI_GLOBAL, CONTURI_GLOBAL,      │
│         TRANZACTII_GLOBAL                    │
│  Triggers: INSTEAD OF on global views        │
│            Replication trigger on TIPURI_CONT│
│                                              │
│   DB_LINK: BUCHAREST_LINK ──────────────┐   │
│   DB_LINK: CLUJ_LINK     ──────────┐    │   │
└─────────────────────────────────────│────│───┘
                                      │    │
┌─────────────────────────────────────▼────▼───┐
│  ATP Instance 2 — Local Nodes                │
│                                              │
│  Schema: BUCHAREST_USER    Schema: CLUJ_USER │
│  ──────────────────────    ──────────────── │
│  CLIENTI_ID (copy)         CLIENTI_ID (copy)│
│  CONTURI_B                 CONTURI_C        │
│  TRANZACTII_B              TRANZACTII_C     │
│  CARDURI_B                 CARDURI_C        │
│  ANGAJATI_B                ANGAJATI_C       │
│  ANGAJAT_CLIENT_B          ANGAJAT_CLIENT_C │
│  TIPURI_CONT (slave)       TIPURI_CONT (slave)│
└──────────────────────────────────────────────┘

     Flask App (app.py)
     └── connects to GLOBAL_USER only
         └── /local/bucharest  /local/cluj
             /global
             /demo/local-to-global
             /demo/global-to-local
```

---

## Phase A — Infrastructure setup

**Goal**: Create Oracle users, grant privileges, set up DB Links.

**Files**: `sql/global/00-setup-users.sql`, `sql/global/01-db-links.sql`

### A1 — Create schemas on ATP Instance 2 (run as ADMIN on ATP2)
```sql
-- Create Bucharest schema
CREATE USER BUCHAREST_USER IDENTIFIED BY "<password>";
GRANT CONNECT, RESOURCE TO BUCHAREST_USER;
GRANT CREATE TABLE, CREATE SEQUENCE, CREATE TRIGGER, CREATE VIEW TO BUCHAREST_USER;
GRANT UNLIMITED TABLESPACE TO BUCHAREST_USER;

-- Create Cluj schema
CREATE USER CLUJ_USER IDENTIFIED BY "<password>";
GRANT CONNECT, RESOURCE TO CLUJ_USER;
GRANT CREATE TABLE, CREATE SEQUENCE, CREATE TRIGGER, CREATE VIEW TO CLUJ_USER;
GRANT UNLIMITED TABLESPACE TO CLUJ_USER;
```

### A2 — Create Global schema on ATP Instance 1 (run as ADMIN on ATP1)
```sql
CREATE USER GLOBAL_USER IDENTIFIED BY "<password>";
GRANT CONNECT, RESOURCE TO GLOBAL_USER;
GRANT CREATE TABLE, CREATE SEQUENCE, CREATE TRIGGER, CREATE VIEW,
      CREATE DATABASE LINK TO GLOBAL_USER;
GRANT UNLIMITED TABLESPACE TO GLOBAL_USER;
```

### A3 — Create DB Links from ATP1 to ATP2 schemas (run as ADMIN on ATP1)
Using `DBMS_CLOUD_ADMIN.CREATE_DATABASE_LINK` (see research.md Decision 1).
```sql
-- First: create a credential from the ATP2 wallet
BEGIN
  DBMS_CLOUD.CREATE_CREDENTIAL(
    credential_name => 'ATP2_BUCHAREST_CRED',
    username        => 'BUCHAREST_USER',
    password        => '<password>'
  );
END;

-- Create DB Link for Bucharest
BEGIN
  DBMS_CLOUD_ADMIN.CREATE_DATABASE_LINK(
    db_link_name       => 'BUCHAREST_LINK',
    hostname           => 'adb.eu-turin-1.oraclecloud.com',
    port               => '1522',
    service_name       => 'g765c070f2106a4_globalbanklocal_high.adb.oraclecloud.com',
    ssl_server_cert_dn => 'CN=Autonomous Database CA, O=Oracle Corporation Autonomous Database Global Self-signed CA, L=Redwood Shores, ST=California, C=US',
    credential_name    => 'ATP2_BUCHAREST_CRED'
  );
END;

-- Create DB Link for Cluj (same host/instance, different user)
BEGIN
  DBMS_CLOUD_ADMIN.CREATE_DATABASE_LINK(
    db_link_name       => 'CLUJ_LINK',
    hostname           => 'adb.eu-turin-1.oraclecloud.com',
    port               => '1522',
    service_name       => 'g765c070f2106a4_globalbanklocal_high.adb.oraclecloud.com',
    ssl_server_cert_dn => 'CN=Autonomous Database CA, O=Oracle Corporation Autonomous Database Global Self-signed CA, L=Redwood Shores, ST=California, C=US',
    credential_name    => 'ATP2_CLUJ_CRED'
  );
END;
```

### A4 — Cross-schema grants on ATP2 (for replication trigger)
```sql
-- Run as ADMIN on ATP2
GRANT SELECT, INSERT, UPDATE, DELETE ON BUCHAREST_USER.TIPURI_CONT TO CLUJ_USER;
GRANT SELECT, INSERT, UPDATE, DELETE ON CLUJ_USER.TIPURI_CONT TO BUCHAREST_USER;
```

---

## Phase B — OLTP schema & data

**Goal**: Create all tables and seed data on each node.

**Files**: `sql/global/02-schema-central.sql`, `sql/bucharest/01-schema-bucharest.sql`, `sql/cluj/01-schema-cluj.sql`

### B1 — Central node tables
Order: `SUCURSALE` → `TIPURI_CONT` → `CLIENTI_PROFIL` → `CREDITE` → `PLATI_RATE` → `LOG_ACCES`

### B2 — Bucharest node tables
Order: `TIPURI_CONT` (slave) → `CLIENTI_ID` → `CONTURI_B` → `TRANZACTII_B` → `CARDURI_B` → `ANGAJATI_B` → `ANGAJAT_CLIENT_B`

### B3 — Cluj node tables
Same order as Bucharest, with `_C` suffix and Cluj-range sequences.

### B4 — Seed data (run after all tables created)
**Files**: `sql/global/03-populate-central.sql`, `sql/bucharest/02-populate-bucharest.sql`, `sql/cluj/02-populate-cluj.sql`

Minimum seed:
- 2 SUCURSALE rows (ID=1 Bucuresti, ID=2 Cluj)
- 4 TIPURI_CONT rows (replicated identically on all 3 nodes)
- 10 CLIENTI rows (5 per branch, in both CLIENTI_ID copies)
- 10 CONTURI_B rows + 10 CONTURI_C rows
- 20 TRANZACTII_B rows + 20 TRANZACTII_C rows
- 5 CREDITE + 15 PLATI_RATE on Central
- 5 ANGAJATI per branch

---

## Phase C — Transparency layer

**Goal**: Create global views and INSTEAD OF triggers on Central node.

**File**: `sql/global/04-transparency.sql`

### C1 — Global views
```sql
CREATE OR REPLACE VIEW CLIENTI_GLOBAL AS ...    -- see data-model.md
CREATE OR REPLACE VIEW CONTURI_GLOBAL AS ...
CREATE OR REPLACE VIEW TRANZACTII_GLOBAL AS ...
```

### C2 — INSTEAD OF trigger: CLIENTI_GLOBAL
```sql
CREATE OR REPLACE TRIGGER trg_iof_clienti_global
INSTEAD OF INSERT OR UPDATE OR DELETE ON CLIENTI_GLOBAL
FOR EACH ROW
DECLARE
BEGIN
  IF INSERTING THEN
    -- Write identification to both local nodes
    INSERT INTO CLIENTI_ID@BUCHAREST_LINK(ID_Client, Nume, Prenume, CNP)
      VALUES(:NEW.ID_Client, :NEW.Nume, :NEW.Prenume, :NEW.CNP);
    INSERT INTO CLIENTI_ID@CLUJ_LINK(ID_Client, Nume, Prenume, CNP)
      VALUES(:NEW.ID_Client, :NEW.Nume, :NEW.Prenume, :NEW.CNP);
    -- Write profile to Central
    INSERT INTO CLIENTI_PROFIL(ID_Client, Email, Telefon, Scor_Credit)
      VALUES(:NEW.ID_Client, :NEW.Email, :NEW.Telefon, :NEW.Scor_Credit);

  ELSIF UPDATING THEN
    UPDATE CLIENTI_ID@BUCHAREST_LINK
      SET Nume=:NEW.Nume, Prenume=:NEW.Prenume, CNP=:NEW.CNP
      WHERE ID_Client=:OLD.ID_Client;
    UPDATE CLIENTI_ID@CLUJ_LINK
      SET Nume=:NEW.Nume, Prenume=:NEW.Prenume, CNP=:NEW.CNP
      WHERE ID_Client=:OLD.ID_Client;
    UPDATE CLIENTI_PROFIL
      SET Email=:NEW.Email, Telefon=:NEW.Telefon, Scor_Credit=:NEW.Scor_Credit
      WHERE ID_Client=:OLD.ID_Client;

  ELSIF DELETING THEN
    DELETE FROM CLIENTI_ID@BUCHAREST_LINK WHERE ID_Client=:OLD.ID_Client;
    DELETE FROM CLIENTI_ID@CLUJ_LINK     WHERE ID_Client=:OLD.ID_Client;
    DELETE FROM CLIENTI_PROFIL           WHERE ID_Client=:OLD.ID_Client;
  END IF;
END;
```

### C3 — INSTEAD OF trigger: CONTURI_GLOBAL
Route by `ID_Sucursala`: 1 → Bucharest, 2 → Cluj.

```sql
CREATE OR REPLACE TRIGGER trg_iof_conturi_global
INSTEAD OF INSERT OR UPDATE OR DELETE ON CONTURI_GLOBAL
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    IF :NEW.ID_Sucursala = 1 THEN
      INSERT INTO CONTURI_B@BUCHAREST_LINK VALUES(...);
    ELSE
      INSERT INTO CONTURI_C@CLUJ_LINK VALUES(...);
    END IF;
  ELSIF UPDATING THEN
    IF :NEW.ID_Sucursala = 1 THEN
      UPDATE CONTURI_B@BUCHAREST_LINK SET ... WHERE ID_Cont=:OLD.ID_Cont;
    ELSE
      UPDATE CONTURI_C@CLUJ_LINK SET ... WHERE ID_Cont=:OLD.ID_Cont;
    END IF;
  ELSIF DELETING THEN
    DELETE FROM CONTURI_B@BUCHAREST_LINK WHERE ID_Cont=:OLD.ID_Cont;
    DELETE FROM CONTURI_C@CLUJ_LINK     WHERE ID_Cont=:OLD.ID_Cont;
  END IF;
END;
```

---

## Phase D — Replication

**Goal**: Keep TIPURI_CONT synchronized across all 3 nodes.

**File**: `sql/global/05-replication.sql`

### D1 — Replication trigger on Central
After DML on master `TIPURI_CONT`, propagate to both slave copies via DB Links (see research.md Decision 4).

### D2 — Initial sync
On first deploy, after Central has seed data, run:
```sql
INSERT INTO TIPURI_CONT@BUCHAREST_LINK SELECT * FROM TIPURI_CONT;
INSERT INTO TIPURI_CONT@CLUJ_LINK      SELECT * FROM TIPURI_CONT;
COMMIT;
```

---

## Phase E — Integrity constraints

**Goal**: Enforce all constraint categories required by N1/N2.

**File**: `sql/global/06-constraints.sql`

### E1 — Local uniqueness
Already defined inline in table DDL (PRIMARY KEY, UNIQUE, CHECK on each fragment).

### E2 — Global uniqueness across horizontal fragments (CONTURI)
Enforced by non-overlapping sequence ranges (IDs 1–999999 for B, 1000000–1999999 for C) — no two rows across fragments can share an ID_Cont. Document this strategy in the Analysis Report.

### E3 — Global uniqueness for vertical fragments (CNP)
CNP has a UNIQUE constraint on each CLIENTI_ID table. Since both nodes hold all clients, the same CNP will appear in both nodes (same row replicated). No conflict. The global uniqueness of CNP = uniqueness on either node. Document this.

### E4 — Cross-node foreign keys
| FK | Implementation |
|---|---|
| CONTURI.ID_Client → CLIENTI | Enforced via BEFORE INSERT trigger on CONTURI_B checking existence in CLIENTI_ID |
| CREDITE.ID_Client → CLIENTI | BEFORE INSERT trigger on CREDITE checking CLIENTI_ID@BUCHAREST_LINK |
| ANGAJAT_CLIENT.ID_Client → CLIENTI | Local FK (CLIENTI_ID is on same node) |

**File**: `sql/global/07-cross-node-fk-triggers.sql`

### E5 — CHECK constraints (cross-node validation)
- `Sold >= 0` enforced locally on CONTURI_B/C.
- `Scor_Credit BETWEEN 0 AND 999` enforced locally on CLIENTI_PROFIL.
- Document that local CHECKs together guarantee global data integrity.

---

## Phase F — Query optimization

**Goal**: Satisfy N2 requirement 7 — document the complex query with both optimizer plans.

**File**: `sql/global/08-optimization.sql`

### The complex query (S3 from spec)
```sql
-- Total amount transacted by clients with credit score above 700
SELECT ci.ID_Client, ci.Nume, ci.Prenume,
       SUM(t.Suma) AS Total_Tranzactionat
FROM   CLIENTI_GLOBAL ci
JOIN   CONTURI_GLOBAL  co ON co.ID_Client = ci.ID_Client
JOIN   TRANZACTII_GLOBAL t ON t.ID_Cont_Sursa = co.ID_Cont
WHERE  ci.Scor_Credit > 700
GROUP  BY ci.ID_Client, ci.Nume, ci.Prenume
ORDER  BY Total_Tranzactionat DESC;
```

### F1 — Rule-based plan
```sql
SELECT /*+ RULE */ ci.ID_Client, ... (full query above)
-- Capture output; explain the join order Oracle's rule-based optimizer chose
```

### F2 — Cost-based plan
```sql
EXPLAIN PLAN FOR (full query);
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- Capture and document each step
```

### F3 — Optimization applied
Create indexes to improve the plan:
```sql
-- On CLIENTI_PROFIL for Scor_Credit filter
CREATE INDEX idx_clienti_profil_scor ON CLIENTI_PROFIL(Scor_Credit);

-- On CONTURI_B/C for ID_Client join
CREATE INDEX idx_conturi_b_client ON CONTURI_B(ID_Client) @BUCHAREST_LINK;
CREATE INDEX idx_conturi_c_client ON CONTURI_C(ID_Client) @CLUJ_LINK;
```
Re-run EXPLAIN PLAN, compare, document improvement.

---

## Phase G — Flask application

**Goal**: Implement `app/app.py` satisfying FR-APP-01 through FR-APP-04.

**Files**: `app/app.py`, `app/templates/*.html`, `app/static/style.css`

### G1 — Connection helper
```python
# app/db.py
import oracledb, os
from functools import lru_cache

@lru_cache(maxsize=1)
def get_connection():
    return oracledb.connect(
        user=os.environ["GLOBAL_SCHEMA_USER"],
        password=os.environ["GLOBAL_SCHEMA_PASSWORD"],
        dsn=os.environ["GLOBAL_TNS_ALIAS"],
        config_dir=os.environ["GLOBAL_WALLET_DIR"],
        wallet_location=os.environ["GLOBAL_WALLET_DIR"],
        wallet_password=os.environ["WALLET_PASSWORD"]
    )
```

### G2 — Routes

| Route | FR | Description |
|---|---|---|
| `GET /` | — | Home / navigation |
| `GET/POST /local/bucharest` | FR-APP-01 | CRUD for CONTURI_B, TRANZACTII_B (via global view) |
| `GET/POST /local/cluj` | FR-APP-01 | CRUD for CONTURI_C, TRANZACTII_C |
| `GET /global` | FR-APP-02 | Display CLIENTI_GLOBAL, CONTURI_GLOBAL, stats |
| `GET /demo/local-to-global` | FR-APP-03 | Insert into a local fragment, show result in global view |
| `POST /demo/local-to-global` | FR-APP-03 | Execute the insert and display both before/after |
| `GET /demo/global-to-local` | FR-APP-04 | Insert via global view, show propagation to local fragments |
| `POST /demo/global-to-local` | FR-APP-04 | Execute the global INSERT, show local node state |

### G3 — Templates structure
```
app/templates/
  base.html          — navbar, common layout
  index.html         — home page with module links
  local.html         — local CRUD table with add/delete form
  global.html        — read-only global stats tables
  demo_ltog.html     — local→global demo with side-by-side before/after
  demo_gtol.html     — global→local demo with side-by-side before/after
```

---

## Phase H — Analysis report content

**Goal**: Produce the `_Analiza.docx` file (N1 module).

**File**: `docs/analiza-outline.md`

The report covers (mapped to PDF requirements):

1. (0.25p) Model description and application objectives
2. (1p) ER diagram (Mermaid → rendered image) + conceptual schema
3. (0.25p) Distribution description: 2 ATP instances, 3 logical nodes
4. (3p) Fragmentation justification:
   - Horizontal primary (CONTURI): min-term predicates, algorithm steps, fragments obtained
   - Horizontal derived (TRANZACTII): semi-join derivation
   - Vertical (CLIENTI): attribute affinity matrix, algorithm steps
5. (1p) Fragmentation correctness (completeness, disjointness, reconstruction for each)
6. (0.5p) Replication decision (TIPURI_CONT: catalog, read-heavy, small table)
7. (0.75p) Local conceptual schemas (Bucharest node schema, Cluj node schema)
8. (2p) Constraints list (all 4 categories: uniqueness, PK, FK, validation)
9. (0.25p) Complex query natural language + optimization techniques (index, rule vs cost)

---

## Phase I — Submission packaging

**Goal**: Produce all 5 required submission files.

### Files to produce
| File | Content |
|---|---|
| `NumeEchipa_Nume_Prenume_Proiect.docx` | Complete project: all SQL as text + screenshots |
| `NumeEchipa_Nume_Prenume_Echipa.txt` | Team members and tasks |
| `NumeEchipa_Nume_Prenume_Analiza.docx` | Analysis report (N1) |
| `NumeEchipa_Nume_Prenume_Sursa.txt` | All SQL/PL-SQL source (concatenation of sql/ files) |
| `NumeEchipa_Nume_Prenume_Aplicatie.docx` | Application screenshots with explanations |

### Source concatenation script
```bash
cat sql/global/*.sql sql/bucharest/*.sql sql/cluj/*.sql > NumeEchipa_Sursa.txt
```

---

## Implementation order (dependency-aware)

```
A (Infrastructure) 
  → B (Schema + data) 
    → C (Transparency views + triggers) 
    → D (Replication) 
    → E (Constraints) 
      → F (Optimization — needs data to run EXPLAIN PLAN)
        → G (Flask app — needs all DB objects)
          → H (Analysis report — documents everything)
            → I (Submission packaging)
```

---

## Risk register

| Risk | Mitigation |
|---|---|
| DBMS_CLOUD_ADMIN not available on Free Tier | Fall back to single ATP with loopback DB Links; same SQL logic applies |
| DB Link latency makes INSTEAD OF triggers slow in demo | Use local views with direct schema access for demo screenshots; document the approach |
| Flask thin mode wallet connection issues | Use thick mode with Oracle Instant Client as fallback (same as SBD project) |
| mTLS issues between ATP instances | Disable mTLS on ATP2 (TLS 1-way) as fallback; acceptable for academic environment |
