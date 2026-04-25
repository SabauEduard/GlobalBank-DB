# Task Breakdown: GlobalBank DB — Distributed Banking Database System

**Branch**: `001-globalbank-dist-db`
**Created**: 2026-04-25
**Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md) | **Data model**: [data-model.md](data-model.md)

**Total tasks**: 52
**User stories**: S1–S6 (from spec.md scenarios) + FR-APP
**MVP scope**: Phase 1 + Phase 2 + US1 + US2 (functional distributed DB with client/account transparency)

---

## User Story Map

| Story | Scenario | FR coverage | Phase |
|---|---|---|---|
| US1 | S1 — Insert client globally | FR-FRAG-03, FR-TRANS-01, FR-TRANS-03 | 3 |
| US2 | S2 — Account transfer between branches | FR-FRAG-01, FR-TRANS-02, FR-TRANS-03 | 4 |
| US3 | S3 — Complex analytical query + optimization | FR-FRAG-02, FR-OPT-01–03 | 5 |
| US4 | S4/S5 — LMD propagation (local↔global) | FR-TRANS-03, FR-TRANS-04 | 6 |
| US5 | S6 — Replicated catalog | FR-REP-01, FR-REP-02 | 7 |
| US6 | FR-APP-01–04 — Flask application | FR-APP-01–04 | 8 |

---

## Phase 1 — Infrastructure Setup

**Goal**: Oracle users created, privileges granted, DB Links operational.
**Files**: `sql/global/00-setup-global-user.sql`, `sql/global/01-db-links.sql`, `sql/bucharest/00-setup-bucharest.sql`, `sql/cluj/00-setup-cluj.sql`

- [x] T001 Create `GLOBAL_USER` schema on ATP1 with required privileges in `sql/global/00-setup-global-user.sql`
- [x] T002 Create `BUCHAREST_USER` schema on ATP2 with required privileges in `sql/bucharest/00-setup-bucharest.sql`
- [x] T003 [P] Create `CLUJ_USER` schema on ATP2 with required privileges in `sql/cluj/00-setup-cluj.sql`
- [x] T004 Grant cross-schema privileges on ATP2 (`BUCHAREST_USER` ↔ `CLUJ_USER`) in `sql/bucharest/00-setup-bucharest.sql`
- [x] T005 Create ATP2 credentials (`ATP2_BUCHAREST_CRED`, `ATP2_CLUJ_CRED`) on ATP1 using `DBMS_CLOUD.CREATE_CREDENTIAL` in `sql/global/01-db-links.sql`
- [x] T006 Create `BUCHAREST_LINK` DB Link on ATP1 using `DBMS_CLOUD_ADMIN.CREATE_DATABASE_LINK` in `sql/global/01-db-links.sql`
- [x] T007 Create `CLUJ_LINK` DB Link on ATP1 using `DBMS_CLOUD_ADMIN.CREATE_DATABASE_LINK` in `sql/global/01-db-links.sql`
- [x] T008 Verify both DB Links with `SELECT 1 FROM DUAL@BUCHAREST_LINK` and `SELECT 1 FROM DUAL@CLUJ_LINK` in `sql/global/01-db-links.sql`

---

## Phase 2 — OLTP Schema & Seed Data (Foundational)

**Goal**: All tables, sequences, and seed data in place on all three nodes. Blocks all user story phases.
**Files**: `sql/global/02-schema-central.sql`, `sql/bucharest/01-schema-bucharest.sql`, `sql/cluj/01-schema-cluj.sql`, `sql/global/03-populate-central.sql`, `sql/bucharest/02-populate-bucharest.sql`, `sql/cluj/02-populate-cluj.sql`

### Central node tables (run as GLOBAL_USER on ATP1)
- [x] T009 Create `SUCURSALE` table + seed 2 rows (Bucuresti ID=1, Cluj ID=2) in `sql/global/02-schema-central.sql`
- [x] T010 Create `TIPURI_CONT` table (master) + seed 4 rows in `sql/global/02-schema-central.sql`
- [x] T011 Create `CLIENTI_PROFIL` table + sequence `SEQ_CLIENT_GLOBAL` in `sql/global/02-schema-central.sql`
- [x] T012 [P] Create `CREDITE` table + sequence `SEQ_CREDIT` in `sql/global/02-schema-central.sql`
- [x] T013 [P] Create `PLATI_RATE` table + sequence `SEQ_PLATA` in `sql/global/02-schema-central.sql`
- [x] T014 [P] Create `LOG_ACCES` table + sequence `SEQ_LOG` in `sql/global/02-schema-central.sql`

### Bucharest node tables (run as BUCHAREST_USER on ATP2)
- [x] T015 Create `TIPURI_CONT` slave table + `CLIENTI_ID` table + sequence `SEQ_CLIENT_B` (START 1) in `sql/bucharest/01-schema-bucharest.sql`
- [x] T016 Create `CONTURI_B` table + sequence `SEQ_CONT_B` (START 1) in `sql/bucharest/01-schema-bucharest.sql`
- [x] T017 Create `TRANZACTII_B` table + sequence `SEQ_TRANZ_B` (START 1) in `sql/bucharest/01-schema-bucharest.sql`
- [x] T018 [P] Create `CARDURI_B` table in `sql/bucharest/01-schema-bucharest.sql`
- [x] T019 [P] Create `ANGAJATI_B` table in `sql/bucharest/01-schema-bucharest.sql`
- [x] T020 [P] Create `ANGAJAT_CLIENT_B` table in `sql/bucharest/01-schema-bucharest.sql`

### Cluj node tables (run as CLUJ_USER on ATP2)
- [x] T021 [P] Create `TIPURI_CONT` slave table + `CLIENTI_ID` table + sequence `SEQ_CLIENT_C` (START 1000000) in `sql/cluj/01-schema-cluj.sql`
- [x] T022 [P] Create `CONTURI_C` table + sequence `SEQ_CONT_C` (START 1000000) in `sql/cluj/01-schema-cluj.sql`
- [x] T023 [P] Create `TRANZACTII_C` table + sequence `SEQ_TRANZ_C` (START 1000000) in `sql/cluj/01-schema-cluj.sql`
- [x] T024 [P] Create `CARDURI_C`, `ANGAJATI_C`, `ANGAJAT_CLIENT_C` tables in `sql/cluj/01-schema-cluj.sql`

### Seed data
- [x] T025 Populate Central node: 10 CLIENTI_PROFIL rows, 5 CREDITE, 15 PLATI_RATE, 5 LOG_ACCES in `sql/global/03-populate-central.sql`
- [x] T026 [P] Populate Bucharest: 10 CLIENTI_ID rows, 10 CONTURI_B, 20 TRANZACTII_B, 5 CARDURI_B, 5 ANGAJATI_B, 5 ANGAJAT_CLIENT_B in `sql/bucharest/02-populate-bucharest.sql`
- [x] T027 [P] Populate Cluj: 10 CLIENTI_ID rows, 10 CONTURI_C, 20 TRANZACTII_C, 5 CARDURI_C, 5 ANGAJATI_C, 5 ANGAJAT_CLIENT_C in `sql/cluj/02-populate-cluj.sql`
- [x] T028 [P] Sync TIPURI_CONT slaves: `MERGE INTO TIPURI_CONT@BUCHAREST_LINK/CLUJ_LINK` in `sql/global/08-replication.sql`

---

## Phase 3 — US1: Client Insert Globally (Vertical Fragmentation)

**Goal**: `CLIENTI_GLOBAL` view reconstructs full client; INSTEAD OF trigger routes INSERT to correct fragments.
**Test criteria**: `INSERT INTO CLIENTI_GLOBAL VALUES(...)` → identification data appears in both `CLIENTI_ID@BUCHAREST_LINK` and `CLIENTI_ID@CLUJ_LINK`; profile data appears in `CLIENTI_PROFIL`. ✅ VERIFIED
**Files**: `sql/global/04-transparency.sql`

- [x] T029 [US1] Create `CLIENTI_GLOBAL` view (JOIN `CLIENTI_ID@BUCHAREST_LINK` + `CLIENTI_PROFIL`, UNION dedup) in `sql/global/04-transparency.sql`
- [x] T030 [US1] Create `INSTEAD OF INSERT` branch of `trg_iof_clienti_global` trigger: write to both `CLIENTI_ID@BUCHAREST_LINK`, `CLIENTI_ID@CLUJ_LINK`, and `CLIENTI_PROFIL` in `sql/global/04-transparency.sql`
- [x] T031 [US1] Add `INSTEAD OF UPDATE` branch to `trg_iof_clienti_global`: propagate Nume/Prenume/CNP to both local nodes, Email/Telefon/Scor_Credit to Central in `sql/global/04-transparency.sql`
- [x] T032 [US1] Add `INSTEAD OF DELETE` branch to `trg_iof_clienti_global`: delete from both `CLIENTI_ID` nodes and `CLIENTI_PROFIL` in `sql/global/04-transparency.sql`
- [x] T033 [US1] Verify S1 scenario: INSERT a new client via `CLIENTI_GLOBAL`, SELECT from view to confirm reconstruction in `sql/global/04-transparency.sql`

---

## Phase 4 — US2: Account Transfer / Horizontal Fragmentation

**Goal**: `CONTURI_GLOBAL` and `TRANZACTII_GLOBAL` views + INSTEAD OF triggers route by `ID_Sucursala`.
**Test criteria**: INSERT with `ID_Sucursala=1` lands in `CONTURI_B@BUCHAREST_LINK`; UPDATE changing `ID_Sucursala` moves the row between fragments. ✅ VERIFIED
**Files**: `sql/global/04-transparency.sql`, `sql/global/05-constraints.sql`

- [x] T034 [US2] Create `CONTURI_GLOBAL` view (UNION ALL `CONTURI_B@BUCHAREST_LINK`, `CONTURI_C@CLUJ_LINK`) in `sql/global/04-transparency.sql`
- [x] T035 [US2] Create `TRANZACTII_GLOBAL` view (UNION ALL both fragment links) in `sql/global/04-transparency.sql`
- [x] T036 [US2] Create `trg_iof_conturi_global` INSTEAD OF trigger: route INSERT/UPDATE/DELETE by `ID_Sucursala` in `sql/global/04-transparency.sql`
- [x] T037 [US2] Implement account transfer (S2): UPDATE `ID_Sucursala` via `CONTURI_GLOBAL` — trigger deletes from old fragment, inserts into new in `sql/global/04-transparency.sql`
- [x] T038 [US2] Add cross-node FK enforcement trigger: BEFORE INSERT on `CONTURI_B` verify `ID_Client` exists in `CLIENTI_ID` in `sql/global/05-constraints.sql`
- [x] T039 [US2] [P] Document global uniqueness strategy (sequence ranges) in comment block in `sql/global/05-constraints.sql`
- [x] T040 [US2] Verify S2 scenario: transfer an account, confirm row moved between fragments in `sql/global/04-transparency.sql`

---

## Phase 5 — US3: Complex Query + Optimization

**Goal**: Complex query across all fragments with cost-based execution plan, plus applied optimization.
**Test criteria**: Query returns correct totals (6 clients, Stan Elena first); EXPLAIN PLAN shows IDX_CLIENTI_PROFIL_SCOR used. ✅ VERIFIED
**Files**: `sql/global/06-optimization.sql`

- [x] T041 [US3] Write complex query (S3): total transacted by clients with Scor_Credit > 700, joining `CLIENTI_GLOBAL`, `CONTURI_GLOBAL`, `TRANZACTII_GLOBAL` in `sql/global/06-optimization.sql`
- [x] T042 [US3] Capture rule-based plan: run query with `/*+ RULE */` hint in `sql/global/06-optimization.sql`
- [x] T043 [US3] Capture cost-based plan: run `EXPLAIN PLAN FOR` + `DBMS_XPLAN.DISPLAY` in `sql/global/06-optimization.sql`
- [x] T044 [US3] Apply optimization: create `idx_clienti_profil_scor ON CLIENTI_PROFIL(Scor_Credit)`, confirmed index used in EXPLAIN PLAN in `sql/global/06-optimization.sql`

---

## Phase 6 — US4: LMD Propagation Verification + Integrity Constraints

**Goal**: All integrity constraints in place (local + cross-node); LMD propagation verified in both directions. ✅ VERIFIED
**Files**: `sql/global/05-constraints.sql`, `sql/global/07-cross-node-fk.sql`

- [x] T045 [US4] Add cross-node FK trigger for `CREDITE.ID_Client`: BEFORE INSERT on `CREDITE` verify client exists in `CLIENTI_ID@BUCHAREST_LINK` in `sql/global/07-cross-node-fk.sql`
- [x] T046 [US4] [P] Document all 5 constraint categories (PK, FK, CHECK, UNIQUE, cross-node) in `sql/global/05-constraints.sql`
- [x] T047 [US4] Verify S4 scenario: INSERT directly into `CONTURI_B@BUCHAREST_LINK`, then SELECT from `CONTURI_GLOBAL` to confirm visibility in `sql/global/05-constraints.sql`
- [x] T048 [US4] Verify S5 scenario: INSERT via `CLIENTI_GLOBAL` trigger, then SELECT from both `CLIENTI_ID@BUCHAREST_LINK` and `CLIENTI_ID@CLUJ_LINK` to confirm propagation in `sql/global/05-constraints.sql`

---

## Phase 7 — US5: Replication

**Goal**: `TIPURI_CONT` changes on Central automatically propagate to both slave copies. ✅ VERIFIED
**Files**: `sql/global/08-replication.sql`

- [x] T049 [US5] Create `trg_replicate_tipuri_cont` AFTER INSERT OR UPDATE OR DELETE trigger on Central's `TIPURI_CONT`, propagating to both slave nodes via DB Links in `sql/global/08-replication.sql`
- [x] T050 [US5] Verify S6 scenario: INSERT a new account type on Central, SELECT from both slave nodes to confirm replication in `sql/global/08-replication.sql`

---

## Phase 8 — US6: Flask Application

**Goal**: All 4 FR-APP requirements implemented with working routes and templates.
**Test criteria**: All routes load and perform DB operations correctly. ✅ VERIFIED (all routes tested)
**Files**: `app/app.py`, `app/db.py`, `app/templates/*.html`, `app/static/style.css`, `app/requirements.txt`

- [x] T051 [US6] Create `app/requirements.txt` (flask, python-oracledb) and `app/db.py` connection helper (thin mode, TLS for ATP2, mTLS for ATP1) in `app/db.py`
- [x] T052 [US6] Create `app/templates/base.html` with navbar linking all 4 modules in `app/templates/base.html`
- [x] T053 [US6] [P] Implement `/local/<branch>` route (FR-APP-01): display + add/delete CONTURI and TRANZACTII for the selected branch in `app/app.py` + `app/templates/local.html`
- [x] T054 [US6] [P] Implement `/global` route (FR-APP-02): display `CLIENTI_GLOBAL`, `CONTURI_GLOBAL`, total balance per branch in `app/app.py` + `app/templates/global.html`
- [x] T055 [US6] Implement `/demo/local-to-global` route (FR-APP-03): form to insert into a local fragment, then show before/after on `CONTURI_GLOBAL` in `app/app.py` + `app/templates/demo_ltog.html`
- [x] T056 [US6] Implement `/demo/global-to-local` route (FR-APP-04): form to insert via `CLIENTI_GLOBAL`, then show resulting rows in both `CLIENTI_ID@BUCHAREST_LINK` and `CLIENTI_ID@CLUJ_LINK` in `app/app.py` + `app/templates/demo_gtol.html`
- [x] T057 [US6] Add `app/static/style.css` minimal styling; verify all 4 routes load and perform DB operations correctly in `app/static/style.css`

---

## Final Phase — Polish & Submission

**Files**: `docs/`, submission zip

- [x] T058 Write analysis report outline in `docs/analiza-outline.md` covering all 10 requirements (model description, ER, conceptual schema, distribution, fragmentation algorithms, correctness, replication, local schemas, constraints, complex query)
- [x] T059 [P] Create `NumeEchipa_Nume_Prenume_Echipa.txt` with team members and task assignments
- [x] T060 [P] Create source concatenation script `scripts/build-sursa.sh` that cats all SQL files into `NumeEchipa_Nume_Prenume_Sursa.txt`

---

## Dependency Graph

```
T001–T008 (Phase 1: Infrastructure)
    └── T009–T028 (Phase 2: Schema + Data)
            ├── T029–T033 (Phase 3: US1 — CLIENTI vertical fragmentation)
            ├── T034–T040 (Phase 4: US2 — CONTURI horizontal fragmentation)
            │       └── T041–T044 (Phase 5: US3 — Complex query, needs data + views)
            │               └── T045–T048 (Phase 6: US4 — Constraints + LMD verification)
            └── T049–T050 (Phase 7: US5 — Replication, parallel with Phase 3/4)
T001–T050 (all DB work)
    └── T051–T057 (Phase 8: US6 — Flask app, needs all DB objects)
            └── T058–T060 (Final: Submission packaging)
```

## STATUS: ALL TASKS COMPLETE ✅

All 60 tasks implemented and verified on Oracle ATP Free Tier (2026-04-25).
