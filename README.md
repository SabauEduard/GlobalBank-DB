# GlobalBank DB

Distributed Oracle database system for the MODBD course (FMI Unibuc, 2025-2026).  
Demonstrates horizontal fragmentation, vertical fragmentation, replication, distributed transparency, and optimization across **3 separate Oracle 19c databases** connected via DB Links.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  CENTRAL NODE  (bankdbpdb / ATP1)                           │
│  Schema: GLOBAL_USER                                        │
│                                                             │
│  Tables:  SUCURSALE, TIPURI_CONT (master), CLIENTI_PROFIL   │
│           CREDITE, PLATI_RATE, LOG_ACCES                    │
│  Views:   CLIENTI_GLOBAL, CONTURI_GLOBAL, TRANZACTII_GLOBAL │
│  Triggers: INSTEAD OF (routing), replication                │
│                                                             │
│       DB Link: BUCHAREST_LINK          DB Link: CLUJ_LINK   │
└──────────────┬──────────────────────────────┬───────────────┘
               │                              │
               ▼                              ▼
┌──────────────────────────┐   ┌──────────────────────────────┐
│  BUCHAREST NODE          │   │  CLUJ NODE                   │
│  (bucharestpdb / ATP2)   │   │  (clujpdb / ATP2)            │
│  Schema: BUCHAREST_USER  │   │  Schema: CLUJ_USER           │
│                          │   │                              │
│  CLIENTI_ID  (IDs 1–999k)│   │  CLIENTI_ID  (IDs 1M–2M)    │
│  CONTURI_B   (sucursala=1│   │  CONTURI_C   (sucursala=2)   │
│  TRANZACTII_B            │   │  TRANZACTII_C                │
│  CARDURI_B, ANGAJATI_B   │   │  CARDURI_C, ANGAJATI_C       │
│  TIPURI_CONT (slave copy)│   │  TIPURI_CONT (slave copy)    │
└──────────────────────────┘   └──────────────────────────────┘
```

### Fragmentation types

| Type | Relation | How |
|---|---|---|
| Horizontal | `CONTURI`, `TRANZACTII` | Rows split by `ID_Sucursala` (1=Bucharest, 2=Cluj) |
| Vertical | `CLIENTI` | Identity columns on local nodes, profile on central |
| Derived | `TRANZACTII` | Follows the `CONTURI` fragment it belongs to |
| Replication | `TIPURI_CONT` | Master on central; AFTER trigger syncs to both slaves |

---

## Deployment options

### Option A — Docker (3 separate local Oracle 19c instances)

Best for local development. Works on **ARM (Apple Silicon) and x86/x64**.

### Option B — Oracle ATP Free Tier (cloud)

Two free-tier Autonomous Transaction Processing instances on Oracle Cloud.

---

## Option A: Docker Setup

Uses **`gvenzl/oracle-free:23-slim`** (Oracle 23ai Free) — native ARM64 + x86/x64, no build required.  
Three separate Oracle instances each with their own `freepdb1` PDB.

### Prerequisites

| Tool | Notes |
|---|---|
| Docker Desktop | [docker.com](https://www.docker.com/) — Engine 20+ |
| SQLcl | For `setup-docker.sh`. Download from [oracle.com/sqldeveloper](https://www.oracle.com/database/sqldeveloper/technologies/sqlcl/) |

> **Docker disk space**: Each Oracle XE container needs ~3-4 GB. If Docker is low on disk, go to  
> Docker Desktop → Settings → Resources → Virtual disk limit and increase it, or run `docker volume prune` to remove unused volumes from other projects.

> **Non-ARM (Intel/AMD x86-64)**: No changes needed — `gvenzl/oracle-free:23-slim` is a multi-arch image and works on x86-64 out of the box. Just run the same commands below.

### Step 1 — Pull the image (if not already available)

```bash
docker pull gvenzl/oracle-free:23-slim
```

### Step 2 — Start all 3 containers

```bash
docker compose -f docker/docker-compose.yml up -d
```

| Container | Host port | PDB service | Schema |
|---|---|---|---|
| `globalbank-central` | 1521 | freepdb1 | GLOBAL_USER |
| `globalbank-bucharest` | 1522 | freepdb1 | BUCHAREST_USER |
| `globalbank-cluj` | 1523 | freepdb1 | CLUJ_USER |

Wait for all 3 to reach **healthy** status (~60-90 s):
```bash
docker ps
# STATUS: Up X seconds (healthy)
```

### Step 3 — Run the database setup

```bash
bash scripts/setup-docker.sh
```

This will:
- Create `GLOBAL_USER`, `BUCHAREST_USER`, `CLUJ_USER` on their respective containers
- Create DB Links (`BUCHAREST_LINK`, `CLUJ_LINK`) via Docker network (`bucharest:1521`, `cluj:1521`)
- Create all tables, sequences, views, INSTEAD OF triggers, seed data
- Create indexes, cross-node FK triggers, and replication trigger

### Step 4 — Run the Flask app

```bash
cp .env.docker .env
cd app
pip install -r requirements.txt
python app.py
# Open http://localhost:5000
```

### Connecting manually

```bash
# Central (GLOBAL_USER)
sqlplus GLOBAL_USER/SecurePass123!@//localhost:1521/freepdb1

# Bucharest
sqlplus BUCHAREST_USER/SecurePass123!@//localhost:1522/freepdb1

# Cluj
sqlplus CLUJ_USER/SecurePass123!@//localhost:1523/freepdb1

# SYS on any container
sqlplus sys/Admin#DB1@//localhost:1521/freepdb1 as sysdba
```

### Stopping / resetting

```bash
# Stop containers (data persists in named volumes)
docker compose -f docker/docker-compose.yml down

# Full reset (destroys all Oracle data)
docker compose -f docker/docker-compose.yml down -v
# Then: docker compose up -d && bash scripts/setup-docker.sh
```

### Optional: Oracle 19c EE (if you want 19c specifically)

If you have the Oracle 19c zip and sufficient Docker disk space, you can build it:

```bash
# Place LINUX.ARM64_1919000_db_home.zip (ARM) or LINUX.X64_193000_db_home.zip (x86) in project root
bash scripts/build-oracle-image.sh
```

Then update `docker-compose.yml`: change `image: gvenzl/oracle-free:23-slim` to `oracle/database:19.3.0-ee`  
and add `ORACLE_SID: bankdb`, `ORACLE_PDB: bankdbpdb` env vars. Update `01-db-links.sql` and `.env.docker` accordingly.

---

## Option B: Oracle ATP Free Tier Setup

### Prerequisites

- Two free Oracle ATP instances: `bankdb` (central) and `globalbanklocal` (local)
- Wallets downloaded and placed as configured in `.env`
- SQLcl installed

### Step 1 — Configure `.env`

Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
# Edit: wallet paths, TNS aliases, passwords, LOCAL_TLS_DSN
```

### Step 2 — Run the master setup script

```bash
bash scripts/setup-all.sh
```

Phases: cleanup → users → DB Links (via `DBMS_CLOUD_ADMIN`) → schema → seed data → views/triggers/indexes/replication.

### Step 3 — Run the Flask app

```bash
cd app && python app.py
```

---

## Flask Application

Start at `http://localhost:5000` after running setup.

| Route | Description |
|---|---|
| `/` | Home — architecture overview |
| `/local/bucharest` | Bucharest node: CONTURI_B, TRANZACTII_B, CLIENTI_ID |
| `/local/cluj` | Cluj node: CONTURI_C, TRANZACTII_C, CLIENTI_ID |
| `/global` | Unified view: CLIENTI_GLOBAL, CONTURI_GLOBAL, totals by branch |
| `/demo/local-to-global` | Horizontal fragmentation demo: direct local insert → visible in CONTURI_GLOBAL; vertical structure display |
| `/demo/global-to-local` | A. Vertical: INSERT via CLIENTI_GLOBAL → propagates to both CLIENTI_ID nodes; B. Horizontal routing: INSERT via CONTURI_GLOBAL → routed by ID_Sucursala |
| `/demo/replication` | Replication demo: INSERT TIPURI_CONT on master → trigger syncs to both slave nodes |

---

## Project Structure

```
GlobalBank-DB/
├── app/
│   ├── app.py              Flask application (all routes)
│   ├── db.py               Connection helper (Docker + ATP modes)
│   ├── requirements.txt    Flask, python-oracledb
│   ├── static/style.css
│   └── templates/          base, index, local, global, demo_*.html
│
├── sql/
│   ├── global/             Central node SQL (run as GLOBAL_USER on ATP1)
│   │   ├── 00-cleanup.sql           Drop GLOBAL_USER + credentials
│   │   ├── 00-setup-global-user.sql Create GLOBAL_USER + grants
│   │   ├── 01-db-links.sql          ATP DB Links (DBMS_CLOUD_ADMIN)
│   │   ├── 01b-db-links-global-user.sql
│   │   ├── 02-schema-central.sql    SUCURSALE, TIPURI_CONT, CLIENTI_PROFIL, ...
│   │   ├── 03-populate-central.sql  Seed: 10 clients, 5 credits, ...
│   │   ├── 04-transparency.sql      CLIENTI_GLOBAL, CONTURI_GLOBAL views + INSTEAD OF triggers
│   │   ├── 05-constraints.sql       Cross-node FK triggers, integrity checks
│   │   ├── 06-optimization.sql      Complex query, EXPLAIN PLAN, index
│   │   ├── 07-cross-node-fk.sql     CREDITE FK cross-node enforcement
│   │   └── 08-replication.sql       TIPURI_CONT replication trigger + seed sync
│   │
│   ├── bucharest/          Bucharest node SQL (run as BUCHAREST_USER on ATP2)
│   │   ├── 00-setup-bucharest.sql
│   │   ├── 01-schema-bucharest.sql  CLIENTI_ID, CONTURI_B, TRANZACTII_B, ...
│   │   └── 02-populate-bucharest.sql
│   │
│   ├── cluj/               Cluj node SQL (run as CLUJ_USER on ATP2)
│   │   ├── 00-setup-cluj.sql
│   │   ├── 01-schema-cluj.sql       CLIENTI_ID, CONTURI_C, TRANZACTII_C, ...
│   │   └── 02-populate-cluj.sql
│   │
│   ├── docker/             Docker-specific overrides (standard Oracle DB Links)
│   │   ├── global/         00-cleanup.sql, 00-setup-global-user.sql, 01-db-links.sql
│   │   └── local/          00-cleanup-local.sql, 00-cleanup-cluj.sql
│   │
│   └── local/              ATP cleanup scripts
│       └── 00-cleanup-local.sql
│
├── docker/
│   └── docker-compose.yml  3 Oracle 19c containers + shared network
│
├── scripts/
│   ├── build-oracle-image.sh   Clone oracle/docker-images, copy zip, build image
│   ├── setup-docker.sh         Full Docker DB setup (all phases)
│   ├── setup-all.sh            Full ATP setup (all phases)
│   └── build-sursa.sh          Concatenate all SQL + app source for submission
│
├── docs/
│   ├── proiect.tex             LaTeX submission document (all 3 grading modules)
│   └── analiza-outline.md      Analysis outline (N1 requirements)
│
├── specs/001-globalbank-dist-db/
│   ├── spec.md, plan.md, tasks.md, data-model.md, research.md
│   └── checklists/requirements.md
│
├── .env.example            ATP environment template
├── .env.docker             Docker environment (copy to .env)
└── .gitignore
```

---

## Database Design Highlights

### Global uniqueness via sequence ranges

```
Bucharest: IDs 1 – 999,999
Cluj:      IDs 1,000,001 – 1,999,999
Central:   IDs 2,000,001+
```

No coordination required — each node generates locally-unique IDs.

### INSTEAD OF triggers (transparency)

```sql
-- INSERT via CLIENTI_GLOBAL → writes to 3 places atomically
INSERT INTO CLIENTI_GLOBAL (Nume, Prenume, CNP, Email, Telefon, Scor_Credit)
VALUES ('Ion', 'Popescu', '1900101400001', 'ion@bank.ro', '0700000001', 750);
-- TRG_IOF_CLIENTI_GLOBAL writes:
--   CLIENTI_ID@BUCHAREST_LINK  (ID columns)
--   CLIENTI_ID@CLUJ_LINK       (ID columns)
--   CLIENTI_PROFIL             (profile columns)
```

### Replication trigger

```sql
-- INSERT on master TIPURI_CONT → trigger fires:
--   INSERT INTO TIPURI_CONT@BUCHAREST_LINK
--   INSERT INTO TIPURI_CONT@CLUJ_LINK
```

---

## Grading targets (MODBD IF 2025-2026)

| Module | Score | Notes |
|---|---|---|
| N1 — Analysis | 10/10 | All 9 sections covered in `docs/proiect.tex` |
| N2 — DB Implementation | 10/10 | All 6 scenarios verified (S1–S6) |
| N3 — Application | ~8/10 | All 3 fragment types demonstrated in UI |

> N = (N1 + N2 + N3) / 3 · Eligibility requires N1 ≥ 5 and N2 ≥ 5.
