# Feature Specification: GlobalBank DB — Distributed Banking Database System

**Branch**: `001-globalbank-dist-db`
**Created**: 2026-04-25
**Status**: Draft

---

## Overview

GlobalBank DB is a distributed database system for a fictional financial institution operating across two geographic locations (Bucharest and Cluj). The system distributes, fragments, replicates, and synchronizes data across three Oracle Cloud database nodes, while providing a unified front-end application that transparently manages both local and global data operations.

This project fulfills the requirements of the "Metode de Optimizare și Distribuire în Baze de Date" (MODBD) course, academic year 2025–2026.

---

## Goals

- Demonstrate a fully functional distributed Oracle database with horizontal fragmentation, derived horizontal fragmentation, vertical fragmentation, and replication across 3 nodes.
- Produce a complete Analysis Report (Modul Analiză, N1) covering ER diagrams, fragmentation justification, constraints list, and an optimized complex query.
- Implement the Back-End (Modul Implementare Baze de Date, N2) using Oracle Cloud: create schemas, fragments, global views, INSTEAD OF triggers, synchronization mechanisms, integrity constraints, and query optimization.
- Implement the Front-End Application (Modul Implementare Aplicație, N3) that manages local and global data, and demonstrates LMD propagation in both directions between local and global nodes.
- Deliver all required submission artifacts on time.

---

## Actors

| Actor | Description |
|---|---|
| **Bank Manager** | Views consolidated global data (balances, statistics across all branches) |
| **Bank Teller (Bucharest)** | Manages transactions and accounts for the Bucharest branch |
| **Bank Teller (Cluj)** | Manages transactions and accounts for the Cluj branch |
| **Database Administrator** | Configures distribution, nodes, links, views, and synchronization |
| **Examiner** | Reviews correctness of distribution, constraints, transparency, and optimization |

---

## User Scenarios & Testing

### S1 — Teller inserts a new client globally
A teller uses the application's global module to add a new client. The system stores identification data (Nume, Prenume, CNP) on the local node determined by branch, and profile data (Email, Telefon, Scor_Credit) on the central node. Querying the global view returns the complete reconstructed record.

### S2 — Account transfer between branches
A teller moves an account from the Bucharest branch to the Cluj branch. The system deletes the row from `CONTURI_B` and inserts it into `CONTURI_C`, keeping all dependent transactions consistent via cascading derived fragmentation rules.

### S3 — Complex analytical query
The Bank Manager queries the total amount transacted by clients with a credit score above 700. This query joins fragments across all nodes and is optimized with both rule-based and cost-based execution plans.

### S4 — Local LMD visible at global level
A teller performs a local INSERT/UPDATE/DELETE on a Bucharest fragment. The Bank Manager immediately sees the updated data through the global view without any additional synchronization step.

### S5 — Global LMD propagates to local nodes
The Bank Manager performs an INSERT on the global `CLIENTI_GLOBAL` view. The INSTEAD OF trigger routes identification data to the appropriate local node and profile data to the central node. Both local nodes reflect the change.

### S6 — Replicated catalog reads
Any node queries `TIPURI_CONT` locally without network round-trips. An update to the catalog on one node propagates to all nodes via the synchronization mechanism.

---

## Functional Requirements

### FR-DB — Database Infrastructure

**FR-DB-01**: The system shall use 2 Oracle Cloud ATP instances: Instance 1 hosts the Central/Global node (`GLOBAL_USER` schema); Instance 2 hosts two local schemas (`BUCHAREST_USER`, `CLUJ_USER`) simulating the Bucharest and Cluj nodes. The Central node connects to both local schemas via Oracle Database Links.

**FR-DB-02**: Each database instance shall have a dedicated schema user with appropriate privileges for local fragment management.

**FR-DB-03**: The system shall maintain an OLTP initial schema with at least 10 independent entities normalized to 3NF, including at least one many-to-many relationship.

### FR-FRAG — Fragmentation

**FR-FRAG-01**: The `CONTURI` table shall be horizontally fragmented into `CONTURI_B` (Bucharest, `ID_Sucursala = 1`) stored on the Bucharest node, and `CONTURI_C` (Cluj, `ID_Sucursala = 2`) stored on the Cluj node. Fragmentation algorithm steps shall be documented in the Analysis Report.

**FR-FRAG-02**: The `TRANZACTII` table shall be derived-horizontally fragmented based on the branch of the source account, producing `TRANZACTII_B` and `TRANZACTII_C` co-located with their parent `CONTURI` fragments.

**FR-FRAG-03**: The `CLIENTI` table shall be vertically fragmented into `CLIENTI_ID` (ID_Client, Nume, Prenume, CNP — identification data, stored on Local nodes) and `CLIENTI_PROFIL` (ID_Client, Email, Telefon, Scor_Credit — marketing/risk data, stored on Central node). Vertical fragmentation algorithm steps shall be documented.

**FR-FRAG-04**: Correctness of all fragmentations shall be verified via completeness, reconstruction, and disjointness conditions.

### FR-REP — Replication

**FR-REP-01**: The `TIPURI_CONT` table shall be fully replicated on all three nodes to avoid network round-trips for catalog lookups.

**FR-REP-02**: Updates to `TIPURI_CONT` on any node shall be synchronized to all other nodes within a single session (synchronous replication via triggers or materialized view refresh).

### FR-TRANS — Transparency

**FR-TRANS-01**: The Global node shall expose a `CLIENTI_GLOBAL` view that reconstructs the full CLIENTI record by joining `CLIENTI_ID` (local nodes via DB Link) and `CLIENTI_PROFIL` (central node).

**FR-TRANS-02**: The Global node shall expose a `CONTURI_GLOBAL` view that unions `CONTURI_B` and `CONTURI_C` via DB Links.

**FR-TRANS-03**: INSTEAD OF triggers on all global views shall route INSERT, UPDATE, and DELETE operations to the correct fragment/node transparently.

**FR-TRANS-04**: The application shall connect only to the Global node and operate as if data were not distributed.

### FR-CONSTR — Integrity Constraints

**FR-CONSTR-01**: Each fragment shall enforce local primary key constraints.

**FR-CONSTR-02**: Global uniqueness of primary keys across horizontal fragments shall be guaranteed (documented with optimization rationale).

**FR-CONSTR-03**: Global uniqueness for vertical fragment columns (CNP in CLIENTI_ID shall be globally unique; constraint strategy documented).

**FR-CONSTR-04**: Foreign key constraints shall be defined at local level and, where relations span different DB nodes, enforced via application-level or trigger-based mechanisms.

**FR-CONSTR-05**: Validation constraints (CHECK) shall be applied locally and documented for cross-node cases.

### FR-OPT — Query Optimization

**FR-OPT-01**: The complex query "total amount transacted by clients with credit score above 700" shall be executed and documented with the rule-based optimizer execution plan (RULE hint).

**FR-OPT-02**: The same query shall be documented with the cost-based optimizer execution plan (EXPLAIN PLAN / DBMS_XPLAN).

**FR-OPT-03**: At least one optimization suggestion shall be applied (e.g., index creation, query rewrite, semi-join) and the resulting plan documented.

### FR-APP — Front-End Application

**FR-APP-01**: The application shall include a **Local Management Module** for each branch, allowing tellers to INSERT, UPDATE, and DELETE data on the local node's fragments (CONTURI, TRANZACTII, CARDURI, CREDITE, PLATI_RATE, ANGAJATI specific to their branch).

**FR-APP-02**: The application shall include a **Global View Module** allowing the Bank Manager to query `CLIENTI_GLOBAL`, `CONTURI_GLOBAL`, and aggregated statistics across all branches.

**FR-APP-03**: The application shall demonstrate that local LMD operations on fragments (horizontal, vertical, replicated) are immediately visible at the global level.

**FR-APP-04**: The application shall demonstrate that global LMD operations (through global views and INSTEAD OF triggers) propagate correctly to the appropriate local fragments and replicated tables.

---

## Data Model — Key Entities

| Entity | Node(s) | Strategy |
|---|---|---|
| SUCURSALE | Central | Single table |
| CLIENTI_ID | Bucharest / Cluj | Vertical fragment (identification) |
| CLIENTI_PROFIL | Central | Vertical fragment (profile/risk) |
| CONTURI_B | Bucharest | Horizontal fragment (`ID_Sucursala=1`) |
| CONTURI_C | Cluj | Horizontal fragment (`ID_Sucursala=2`) |
| TRANZACTII_B | Bucharest | Derived horizontal fragment |
| TRANZACTII_C | Cluj | Derived horizontal fragment |
| CARDURI | Bucharest / Cluj | Co-located with CONTURI fragments |
| ANGAJATI | Bucharest / Cluj | Co-located with branch |
| TIPURI_CONT | All nodes | Full replication |
| CREDITE | Central | Single table |
| PLATI_RATE | Central | Single table |
| LOG_ACCES | Central | Single table |

---

## Non-Functional Requirements

**NFR-01**: The system uses **2 Oracle Cloud ATP Free Tier instances**: ATP Instance 1 acts as the Central/Global node (one schema: `GLOBAL_USER`); ATP Instance 2 hosts two schemas (`BUCHAREST_USER`, `CLUJ_USER`) simulating the two local nodes. DB Links are created from the Central node to both local schemas. All code must use wallet-based connections (`TNS_ADMIN=~/.oracle/wallet`), following the same pattern as the prior SBD project.

**NFR-01a**: The front-end application is a **Python + Flask web application** — simple UI sufficient to demonstrate all 4 front-end requirements with screenshots. Connects exclusively to the Global node.

**NFR-02**: All code must be original (no plagiarism, no AI-generated sections submitted as-is per course rules). All code must be demonstrated as having been run in Oracle via screenshots.

**NFR-03**: All mandatory analysis items (items marked *obligatoriu* in the requirements PDF) must be addressed to achieve N1 >= 5 and N2 >= 5, which are eligibility thresholds for the exam defense.

**NFR-04**: The project must be submitted at least one week before the exam date via the official submission form.

---

## Assumptions

- 2 Oracle Cloud ATP Free Tier instances are used: Instance 1 = Central node (`GLOBAL_USER`); Instance 2 = two local schemas (`BUCHAREST_USER`, `CLUJ_USER`). DB Links connect Central → Bucharest and Central → Cluj.
- Front-end is Python + Flask (simple web UI). Connects only to the Global node; distribution is fully transparent to the app.
- Team has 2 members; task split is not tracked in the spec.
- The initial OLTP schema reuses the banking schema concept (customers, accounts, transactions) consistent with prior coursework.
- "Synchronous replication" for TIPURI_CONT is implemented via Oracle triggers on the master node that write to remote nodes via DB Links (acceptable given the learning context, vs. Oracle Streams/GoldenGate which require Enterprise Edition).

---

## Success Criteria

- N1 (Analysis) >= 5/10: All mandatory analysis items covered; ER diagram has 10+ entities, 1+ M:N relationship, FN3; all fragmentation fragments obtained; local schemas created; all 4 constraint categories documented.
- N2 (Back-End) >= 5/10: Databases, users, fragments, and data created and populated; at least transparency for vertical and horizontal fragments implemented; integrity constraints enforced; query optimization documented.
- N3 (Front-End): Application demonstrates all 4 front-end requirements (local management, global view, local→global visibility, global→local propagation).
- Final grade N = (N1 + N2 + N3) / 3 >= 5 and exam defense passed.
- All 5 submission files produced correctly named per convention `NumeEchipa_Nume_Prenume_*`.
- Complete project file contains all SQL/PL/SQL as text (not images) with Oracle execution screenshots.

---

## Out of Scope

- Oracle GoldenGate or Streams for replication (requires Enterprise Edition).
- Real multi-region network deployment (simulated with schemas/DB Links on Oracle Cloud).
- Mobile or web-deployed application (a desktop/CLI application is sufficient).
- Performance benchmarking beyond what is required for the optimization module.
