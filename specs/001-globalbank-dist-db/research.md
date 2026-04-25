# Research Findings: GlobalBank DB

**Generated**: 2026-04-25
**Feeds into**: plan.md

---

## Decision 1: DB Links between ATP instances

**Decision**: Use `DBMS_CLOUD_ADMIN.CREATE_DATABASE_LINK` for ATP-to-ATP links, NOT the classic `CREATE DATABASE LINK` syntax.

**Rationale**: Oracle Autonomous Database (ATP) enforces mTLS by default and does not allow traditional DB Link syntax without additional configuration. The supported approach for ATP-to-ATP links is via `DBMS_CLOUD_ADMIN.CREATE_DATABASE_LINK`, which uses a credential object (created from the target wallet zip) stored in object storage or uploaded directly.

**How to apply**:
```sql
-- On Central (ATP1), run as ADMIN:
BEGIN
  DBMS_CLOUD_ADMIN.CREATE_DATABASE_LINK(
    db_link_name => 'BUCHAREST_LINK',
    hostname     => '<atp2-hostname>',
    port         => '1522',
    service_name => '<localdb_high service>',
    ssl_server_cert_dn => '<ATP2 DN>',
    credential_name => 'ATP2_CREDENTIAL',
    directory_name  => NULL
  );
END;
```
The credential is created from the ATP2 wallet zip via `DBMS_CLOUD.CREATE_CREDENTIAL`.

**Alternatives considered**:
- Traditional `CREATE DATABASE LINK` — rejected: not supported on ATP mTLS without disabling mTLS.
- Single ATP with loopback DB Links — simpler but does not satisfy "2 ATP instances" requirement from spec.
- Use TLS 1-way and disable mTLS on ATP2 — possible but reduces security posture unnecessarily.

---

## Decision 2: Intra-instance DB Links (BUCHAREST_USER ↔ CLUJ_USER)

**Decision**: DB Links between schemas on the same ATP instance (ATP2) also use `DBMS_CLOUD_ADMIN.CREATE_DATABASE_LINK` pointing to the same instance with a different username/credential.

**Rationale**: Even within the same ATP, cross-schema DB Links for Oracle Autonomous DB require the cloud procedure. However, for schemas on the same instance we can also use a simpler synonym or a direct schema-qualified reference (`BUCHAREST_USER.TABLE_NAME`) if both schemas grant SELECT/INSERT/UPDATE/DELETE privileges to each other.

**How to apply**: For transparency triggers on the Central node, all remote access goes through DB Links to BUCHAREST_USER and CLUJ_USER on ATP2. Privilege grants on ATP2:
```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON BUCHAREST_USER.CONTURI_B TO CLUJ_USER;
```
This avoids the need for a DB Link within ATP2 for the replication trigger.

---

## Decision 3: Sequence strategy for global PK uniqueness

**Decision**: Non-overlapping sequence ranges per node (range partitioning of PKs).

**Rationale**: Cross-node sequences via DB Links add a network round-trip on every INSERT. For a course project, non-overlapping ranges are simpler to implement and sufficient to guarantee global uniqueness.

**How to apply**:
- Bucharest sequences: START WITH 1, MAXVALUE 999999
- Cluj sequences: START WITH 1000000, MAXVALUE 1999999
- Central sequences: START WITH 2000000

Each fragment has its own local sequence for each PK column. The range partitioning prevents collision. Document the rationale in the Analysis Report under "Global Uniqueness Constraints".

**Alternatives considered**:
- Global sequence on Central accessed via DB Link — adds latency, single point of failure.
- UUID/GUID — not idiomatic for Oracle course projects.
- Oracle SEQUENCE with ORDER keyword — still requires a shared sequence object somewhere.

---

## Decision 4: TIPURI_CONT replication mechanism

**Decision**: After-statement triggers on the Central node's `TIPURI_CONT` master copy, propagating changes to remote copies via DB Links.

**Rationale**: Oracle Free Tier does not include GoldenGate or Streams. Trigger-based replication is the standard approach for this course. The master copy lives on the Central node; ATP2's schemas (BUCHAREST_USER, CLUJ_USER) maintain slave copies. The trigger fires AFTER each DML on the master and executes the equivalent DML on both slave tables via DB Links.

**How to apply**:
```sql
CREATE OR REPLACE TRIGGER trg_replicate_tipuri_cont
AFTER INSERT OR UPDATE OR DELETE ON TIPURI_CONT
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    INSERT INTO TIPURI_CONT@BUCHAREST_LINK VALUES (:NEW.ID_Tip, :NEW.Denumire, :NEW.Dobanda);
    INSERT INTO TIPURI_CONT@CLUJ_LINK     VALUES (:NEW.ID_Tip, :NEW.Denumire, :NEW.Dobanda);
  ELSIF UPDATING THEN
    UPDATE TIPURI_CONT@BUCHAREST_LINK SET Denumire=:NEW.Denumire, Dobanda=:NEW.Dobanda WHERE ID_Tip=:NEW.ID_Tip;
    UPDATE TIPURI_CONT@CLUJ_LINK     SET Denumire=:NEW.Denumire, Dobanda=:NEW.Dobanda WHERE ID_Tip=:NEW.ID_Tip;
  ELSIF DELETING THEN
    DELETE FROM TIPURI_CONT@BUCHAREST_LINK WHERE ID_Tip=:OLD.ID_Tip;
    DELETE FROM TIPURI_CONT@CLUJ_LINK     WHERE ID_Tip=:OLD.ID_Tip;
  END IF;
END;
```

**Alternatives considered**:
- Materialized Views with REFRESH ON COMMIT — requires Enterprise Edition features for commit-level refresh.
- Manual refresh scripts — not synchronous, fails FR-REP-02.

---

## Decision 5: Python Flask + python-oracledb (thin mode)

**Decision**: Use `python-oracledb` in **thin mode** (no Oracle Instant Client required) with wallet-based connection.

**Rationale**: Thin mode works without any Oracle Client installation, which simplifies deployment. Wallet-based connection is already proven in the SBD project. The app connects exclusively to GLOBAL_USER on ATP1.

**How to apply**:
```python
import oracledb

connection = oracledb.connect(
    user="GLOBAL_USER",
    password=os.environ["GLOBAL_SCHEMA_PASSWORD"],
    dsn=os.environ["GLOBAL_TNS_ALIAS"],
    config_dir=os.environ["GLOBAL_WALLET_DIR"],
    wallet_location=os.environ["GLOBAL_WALLET_DIR"],
    wallet_password=os.environ["WALLET_PASSWORD"]
)
```
Flask routes cover: local CRUD (per branch), global view queries, LMD propagation demo pages.

**Alternatives considered**:
- `cx_Oracle` (thick mode) — requires Oracle Instant Client, heavier setup.
- Direct REST/ORDS API — requires ORDS configuration on ATP, adds complexity.
- SQLAlchemy + oracledb — adds abstraction layer not needed for a demo app.

---

## Decision 6: INSTEAD OF trigger routing strategy

**Decision**: Route DML on `CLIENTI_GLOBAL` and `CONTURI_GLOBAL` views using `INSTEAD OF` triggers on the Central node. Routing key for CLIENTI is a parameter in the INSERT (branch ID); routing key for CONTURI is `ID_Sucursala`.

**Rationale**: `INSTEAD OF` triggers intercept DML on views and redirect it. For CONTURI, the routing is deterministic: `ID_Sucursala = 1` → Bucharest, `= 2` → Cluj. For CLIENTI, the trigger receives the full row and always writes identification columns to BOTH local nodes (each local node stores clients associated with its branch), and profile columns to the Central node.

**Note on CLIENTI routing**: Since CLIENTI are not inherently bound to one branch (a client can have accounts at both), CLIENTI_ID is replicated to both local nodes, and CLIENTI_PROFIL stays on Central. This simplifies the join in `CLIENTI_GLOBAL` (UNION on both locals, single join to Central).

**Alternatives considered**:
- Route CLIENTI by branch of first account — requires a lookup, adds complexity and circular dependency.
- Store CLIENTI_ID only on the relevant branch local node — cleaner but makes global queries harder when client is present in only one fragment.

---

## Decision 7: Flask application structure

**Decision**: Single-file Flask app (`app/app.py`) with Jinja2 templates, organized around 4 pages matching the 4 front-end requirements.

**Pages**:
1. `/local/<branch>` — Local Management (CRUD for CONTURI, TRANZACTII per branch)
2. `/global` — Global View (CLIENTI_GLOBAL, CONTURI_GLOBAL, statistics)
3. `/demo/local-to-global` — Show local LMD effect on global view (S4)
4. `/demo/global-to-local` — Show global LMD propagation to local fragments (S5)

**Rationale**: Minimal surface area. Each page is a self-contained demo suitable for screenshots. No authentication needed (demo app).
