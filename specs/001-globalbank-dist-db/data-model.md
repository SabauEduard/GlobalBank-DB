# Data Model: GlobalBank DB

**Generated**: 2026-04-25

---

## Node topology

| Node | ATP Instance | Schema | Role |
|---|---|---|---|
| Central | ATP Instance 1 | `GLOBAL_USER` | Global views, INSTEAD OF triggers, CLIENTI_PROFIL, CREDITE, PLATI_RATE, LOG_ACCES, SUCURSALE, TIPURI_CONT (master) |
| Bucharest | ATP Instance 2 | `BUCHAREST_USER` | CONTURI_B, TRANZACTII_B, CARDURI_B, ANGAJATI_B, ANGAJAT_CLIENT_B, CLIENTI_ID (copy), TIPURI_CONT (slave) |
| Cluj | ATP Instance 2 | `CLUJ_USER` | CONTURI_C, TRANZACTII_C, CARDURI_C, ANGAJATI_C, ANGAJAT_CLIENT_C, CLIENTI_ID (copy), TIPURI_CONT (slave) |

---

## OLTP Initial Schema (pre-distribution)

These tables represent the unified initial schema. Distribution is applied on top.

### SUCURSALE
```sql
CREATE TABLE SUCURSALE (
    ID_Sucursala  NUMBER(4)     PRIMARY KEY,
    Nume          VARCHAR2(100) NOT NULL,
    Oras          VARCHAR2(50)  NOT NULL,
    Adresa        VARCHAR2(200) NOT NULL,
    CONSTRAINT chk_sucursala_oras CHECK (Oras IN ('Bucuresti', 'Cluj'))
);
```
Node: Central. Seed data: 2 rows (ID=1 Bucuresti, ID=2 Cluj).

---

### TIPURI_CONT
```sql
CREATE TABLE TIPURI_CONT (
    ID_Tip    NUMBER(4)      PRIMARY KEY,
    Denumire  VARCHAR2(50)   NOT NULL UNIQUE,
    Dobanda   NUMBER(5,2)    NOT NULL,
    CONSTRAINT chk_dobanda CHECK (Dobanda >= 0 AND Dobanda <= 100)
);
```
Node: Central (master), Bucharest (slave), Cluj (slave). Seed data: Curent (0%), Economii (3.5%), Depozit (5%), Credit (15%).

---

### CLIENTI_ID (vertical fragment — identification)
```sql
CREATE TABLE CLIENTI_ID (
    ID_Client  NUMBER(10)    PRIMARY KEY,
    Nume       VARCHAR2(100) NOT NULL,
    Prenume    VARCHAR2(100) NOT NULL,
    CNP        CHAR(13)      NOT NULL UNIQUE,
    CONSTRAINT chk_cnp_len CHECK (LENGTH(CNP) = 13)
);
```
Node: Bucharest AND Cluj (both hold all clients — see research Decision 6).
Sequence: `SEQ_CLIENT` — Bucharest: START 1 MAXVALUE 999999; Cluj: START 1000000 MAXVALUE 1999999.

---

### CLIENTI_PROFIL (vertical fragment — profile/risk)
```sql
CREATE TABLE CLIENTI_PROFIL (
    ID_Client    NUMBER(10)    PRIMARY KEY,
    Email        VARCHAR2(150) UNIQUE,
    Telefon      VARCHAR2(15),
    Scor_Credit  NUMBER(3)     DEFAULT 500,
    CONSTRAINT chk_scor CHECK (Scor_Credit BETWEEN 0 AND 999),
    CONSTRAINT chk_email CHECK (Email LIKE '%@%.%')
);
```
Node: Central.

---

### CONTURI_B (horizontal fragment — Bucharest)
```sql
CREATE TABLE CONTURI_B (
    ID_Cont      NUMBER(10)    PRIMARY KEY,
    IBAN         VARCHAR2(34)  NOT NULL UNIQUE,
    ID_Tip       NUMBER(4)     NOT NULL,
    Sold         NUMBER(15,2)  DEFAULT 0,
    Moneda       VARCHAR2(3)   DEFAULT 'RON',
    ID_Sucursala NUMBER(4)     DEFAULT 1 NOT NULL,
    ID_Client    NUMBER(10)    NOT NULL,
    CONSTRAINT chk_conturi_b_suc  CHECK (ID_Sucursala = 1),
    CONSTRAINT chk_moneda_b       CHECK (Moneda IN ('RON','EUR','USD')),
    CONSTRAINT chk_sold_b         CHECK (Sold >= 0),
    CONSTRAINT fk_conturi_b_tip   FOREIGN KEY (ID_Tip) REFERENCES TIPURI_CONT(ID_Tip)
);
```
Node: Bucharest. Sequence: `SEQ_CONT_B` START 1 MAXVALUE 999999.

---

### CONTURI_C (horizontal fragment — Cluj)
```sql
CREATE TABLE CONTURI_C (
    ID_Cont      NUMBER(10)    PRIMARY KEY,
    IBAN         VARCHAR2(34)  NOT NULL UNIQUE,
    ID_Tip       NUMBER(4)     NOT NULL,
    Sold         NUMBER(15,2)  DEFAULT 0,
    Moneda       VARCHAR2(3)   DEFAULT 'RON',
    ID_Sucursala NUMBER(4)     DEFAULT 2 NOT NULL,
    ID_Client    NUMBER(10)    NOT NULL,
    CONSTRAINT chk_conturi_c_suc  CHECK (ID_Sucursala = 2),
    CONSTRAINT chk_moneda_c       CHECK (Moneda IN ('RON','EUR','USD')),
    CONSTRAINT chk_sold_c         CHECK (Sold >= 0),
    CONSTRAINT fk_conturi_c_tip   FOREIGN KEY (ID_Tip) REFERENCES TIPURI_CONT(ID_Tip)
);
```
Node: Cluj. Sequence: `SEQ_CONT_C` START 1000000 MAXVALUE 1999999.

---

### TRANZACTII_B (derived horizontal fragment)
```sql
CREATE TABLE TRANZACTII_B (
    ID_Tranzactie  NUMBER(10)    PRIMARY KEY,
    Data           DATE          DEFAULT SYSDATE NOT NULL,
    Suma           NUMBER(15,2)  NOT NULL,
    Tip_Tranzactie VARCHAR2(20)  NOT NULL,
    ID_Cont_Sursa  NUMBER(10)    NOT NULL,
    CONSTRAINT chk_tranz_b_suma  CHECK (Suma > 0),
    CONSTRAINT chk_tranz_b_tip   CHECK (Tip_Tranzactie IN ('DEBIT','CREDIT','TRANSFER')),
    CONSTRAINT fk_tranz_b_cont   FOREIGN KEY (ID_Cont_Sursa) REFERENCES CONTURI_B(ID_Cont)
);
```
Node: Bucharest. Sequence: `SEQ_TRANZ_B` START 1 MAXVALUE 999999.

---

### TRANZACTII_C (derived horizontal fragment)
```sql
CREATE TABLE TRANZACTII_C (
    ID_Tranzactie  NUMBER(10)    PRIMARY KEY,
    Data           DATE          DEFAULT SYSDATE NOT NULL,
    Suma           NUMBER(15,2)  NOT NULL,
    Tip_Tranzactie VARCHAR2(20)  NOT NULL,
    ID_Cont_Sursa  NUMBER(10)    NOT NULL,
    CONSTRAINT chk_tranz_c_suma  CHECK (Suma > 0),
    CONSTRAINT chk_tranz_c_tip   CHECK (Tip_Tranzactie IN ('DEBIT','CREDIT','TRANSFER')),
    CONSTRAINT fk_tranz_c_cont   FOREIGN KEY (ID_Cont_Sursa) REFERENCES CONTURI_C(ID_Cont)
);
```
Node: Cluj. Sequence: `SEQ_TRANZ_C` START 1000000 MAXVALUE 1999999.

---

### CARDURI_B / CARDURI_C
```sql
CREATE TABLE CARDURI_B (
    ID_Card        NUMBER(10)   PRIMARY KEY,
    Numar_Card     CHAR(16)     NOT NULL UNIQUE,
    Data_Expirare  DATE         NOT NULL,
    Status         VARCHAR2(10) DEFAULT 'ACTIV',
    ID_Cont        NUMBER(10)   NOT NULL,
    CONSTRAINT chk_card_b_status CHECK (Status IN ('ACTIV','BLOCAT','EXPIRAT')),
    CONSTRAINT fk_card_b_cont    FOREIGN KEY (ID_Cont) REFERENCES CONTURI_B(ID_Cont)
);
CREATE TABLE CARDURI_C ( ... same structure, FK → CONTURI_C ... );
```
Node: co-located with respective CONTURI fragment.

---

### ANGAJATI_B / ANGAJATI_C
```sql
CREATE TABLE ANGAJATI_B (
    ID_Angajat   NUMBER(10)    PRIMARY KEY,
    Nume         VARCHAR2(100) NOT NULL,
    Functie      VARCHAR2(50)  NOT NULL,
    Salariu      NUMBER(10,2)  NOT NULL,
    ID_Sucursala NUMBER(4)     DEFAULT 1 NOT NULL,
    CONSTRAINT chk_ang_b_suc  CHECK (ID_Sucursala = 1),
    CONSTRAINT chk_ang_b_sal  CHECK (Salariu > 0)
);
CREATE TABLE ANGAJATI_C ( ... same structure with ID_Sucursala DEFAULT 2 ... );
```

---

### ANGAJAT_CLIENT_B / ANGAJAT_CLIENT_C (M:N junction)
```sql
CREATE TABLE ANGAJAT_CLIENT_B (
    ID_Angajat     NUMBER(10)   NOT NULL,
    ID_Client      NUMBER(10)   NOT NULL,
    Rol            VARCHAR2(30) DEFAULT 'GESTIONAR',
    Data_Asignare  DATE         DEFAULT SYSDATE,
    CONSTRAINT pk_ac_b PRIMARY KEY (ID_Angajat, ID_Client),
    CONSTRAINT fk_ac_b_ang  FOREIGN KEY (ID_Angajat) REFERENCES ANGAJATI_B(ID_Angajat),
    CONSTRAINT fk_ac_b_cli  FOREIGN KEY (ID_Client)  REFERENCES CLIENTI_ID(ID_Client)
);
```

---

### CREDITE
```sql
CREATE TABLE CREDITE (
    ID_Credit    NUMBER(10)   PRIMARY KEY,
    Suma_Totala  NUMBER(15,2) NOT NULL,
    Rata_Lunara  NUMBER(10,2) NOT NULL,
    ID_Client    NUMBER(10)   NOT NULL,
    CONSTRAINT chk_credit_suma CHECK (Suma_Totala > 0),
    CONSTRAINT chk_credit_rata CHECK (Rata_Lunara > 0)
);
```
Node: Central. FK to CLIENTI_PROFIL.ID_Client (cross-node; enforced via trigger).

---

### PLATI_RATE
```sql
CREATE TABLE PLATI_RATE (
    ID_Plata    NUMBER(10)   PRIMARY KEY,
    Data_Plata  DATE         DEFAULT SYSDATE NOT NULL,
    Suma        NUMBER(10,2) NOT NULL,
    ID_Credit   NUMBER(10)   NOT NULL,
    CONSTRAINT chk_plata_suma CHECK (Suma > 0),
    CONSTRAINT fk_plata_credit FOREIGN KEY (ID_Credit) REFERENCES CREDITE(ID_Credit)
);
```
Node: Central.

---

### LOG_ACCES
```sql
CREATE TABLE LOG_ACCES (
    ID_Log     NUMBER(10)    PRIMARY KEY,
    Utilizator VARCHAR2(50)  NOT NULL,
    Data_Ora   TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    Actiune    VARCHAR2(200) NOT NULL
);
```
Node: Central.

---

## Global Views (on Central node)

### CLIENTI_GLOBAL
```sql
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
WHERE  ci.ID_Client NOT IN (SELECT ID_Client FROM CLIENTI_ID@BUCHAREST_LINK);
```
Note: clients exist in both local nodes; use UNION with deduplication by ID_Client.

### CONTURI_GLOBAL
```sql
CREATE VIEW CONTURI_GLOBAL AS
SELECT ID_Cont, IBAN, ID_Tip, Sold, Moneda, ID_Sucursala, ID_Client, 'B' AS Nod
FROM   CONTURI_B@BUCHAREST_LINK
UNION ALL
SELECT ID_Cont, IBAN, ID_Tip, Sold, Moneda, ID_Sucursala, ID_Client, 'C' AS Nod
FROM   CONTURI_C@CLUJ_LINK;
```

### TRANZACTII_GLOBAL
```sql
CREATE VIEW TRANZACTII_GLOBAL AS
SELECT ID_Tranzactie, Data, Suma, Tip_Tranzactie, ID_Cont_Sursa, 'B' AS Nod
FROM   TRANZACTII_B@BUCHAREST_LINK
UNION ALL
SELECT ID_Tranzactie, Data, Suma, Tip_Tranzactie, ID_Cont_Sursa, 'C' AS Nod
FROM   TRANZACTII_C@CLUJ_LINK;
```

---

## Fragmentation correctness conditions

### CONTURI (horizontal primary)
- **Completeness**: `CONTURI = CONTURI_B ∪ CONTURI_C` — every row has `ID_Sucursala ∈ {1,2}` (CHECK constraint ensures assignment)
- **Disjointness**: `CONTURI_B ∩ CONTURI_C = ∅` — ID_Sucursala=1 and ID_Sucursala=2 are mutually exclusive
- **Reconstruction**: `CONTURI_GLOBAL = CONTURI_B ∪ CONTURI_C` via UNION ALL view

### TRANZACTII (horizontal derived)
- **Completeness**: every transaction references a source account; every account is in exactly one fragment
- **Disjointness**: FK constraints guarantee no transaction row appears in both fragments
- **Reconstruction**: `TRANZACTII_GLOBAL` UNION ALL view

### CLIENTI (vertical)
- **Completeness**: all attributes of CLIENTI = CLIENTI_ID attributes ∪ CLIENTI_PROFIL attributes
- **Disjointness**: ID_Client is the only overlapping column (join key); all other columns are exclusive
- **Reconstruction**: `CLIENTI_GLOBAL` reconstructs via JOIN on ID_Client

---

## Sequences summary

| Sequence | Node | START | MAXVALUE | Used for |
|---|---|---|---|---|
| SEQ_CLIENT_B | Bucharest | 1 | 999999 | CLIENTI_ID.ID_Client |
| SEQ_CLIENT_C | Cluj | 1000000 | 1999999 | CLIENTI_ID.ID_Client |
| SEQ_CONT_B | Bucharest | 1 | 999999 | CONTURI_B.ID_Cont |
| SEQ_CONT_C | Cluj | 1000000 | 1999999 | CONTURI_C.ID_Cont |
| SEQ_TRANZ_B | Bucharest | 1 | 999999 | TRANZACTII_B.ID_Tranzactie |
| SEQ_TRANZ_C | Cluj | 1000000 | 1999999 | TRANZACTII_C.ID_Tranzactie |
| SEQ_CREDIT | Central | 2000000 | 9999999 | CREDITE.ID_Credit |
| SEQ_PLATA | Central | 2000000 | 9999999 | PLATI_RATE.ID_Plata |
| SEQ_LOG | Central | 1 | 99999999 | LOG_ACCES.ID_Log |
