# proiect.tex — Ce mai rămâne de făcut

## 1. Completează datele personale

În `proiect.tex`, liniile 124–125:
```latex
\textbf{Echipă}: [COMPLETAȚI] \\
\textbf{Grupă}: [COMPLETAȚI] \\
```

## 2. Compilare PDF

Compilează din directorul `docs/` (lstinputlisting folosește căi relative de acolo):
```bash
cd docs
pdflatex proiect.tex   # rulează de 2 ori pentru ToC
```

Necesită MacTeX / texlive-full. Dacă nu e instalat:
```bash
brew install --cask mactex
```

---

## 3. Screenshot-uri necesare

Plasează imaginile în `assets/screenshots/<subfolder>/` față de rădăcina proiectului.

### N2 — Implementare DB (sqlplus / sqlcl terminal)

Conectare rapidă:
```bash
sqlplus GLOBAL_USER/SecurePass123!@//localhost:1521/freepdb1
sqlplus BUCHAREST_USER/SecurePass123!@//localhost:1522/freepdb1
sqlplus CLUJ_USER/SecurePass123!@//localhost:1523/freepdb1
```

| Fișier | Ce să captezi |
|--------|---------------|
| `N2-bd/01-users/01-global-user-created.png` | Output `setup-docker.sh` sau `SELECT 'GLOBAL_USER created OK' FROM DUAL;` pe Central |
| `N2-bd/01-users/02-bucharest-user-created.png` | `SELECT 'BUCHAREST_USER created OK' FROM DUAL;` pe Bucharest |
| `N2-bd/01-users/03-cluj-user-created.png` | `SELECT 'CLUJ_USER created OK' FROM DUAL;` pe Cluj |
| `N2-bd/01-users/04-db-links-verified.png` | `SELECT USER FROM DUAL@BUCHAREST_LINK;` și `SELECT USER FROM DUAL@CLUJ_LINK;` (pe Central) |
| `N2-bd/02-schema/01-central-schema.png` | `SELECT table_name FROM user_tables ORDER BY 1;` pe Central |
| `N2-bd/02-schema/02-bucharest-schema.png` | Același query pe Bucharest |
| `N2-bd/02-schema/03-cluj-schema.png` | Același query pe Cluj |
| `N2-bd/03-populate/01-central-populated.png` | `SELECT COUNT(*) FROM CLIENTI_PROFIL; SELECT COUNT(*) FROM CREDITE;` pe Central |
| `N2-bd/03-populate/02-bucharest-populated.png` | `SELECT COUNT(*) FROM CONTURI_B; SELECT COUNT(*) FROM TRANZACTII_B;` pe Bucharest |
| `N2-bd/03-populate/03-cluj-populated.png` | Același pe Cluj cu CONTURI_C, TRANZACTII_C |
| `N2-bd/04-transparency/01-clienti-global-view.png` | `SELECT ID_Client, Nume, Prenume FROM CLIENTI_GLOBAL;` pe Central |
| `N2-bd/04-transparency/02-s1-insert-global.png` | INSERT via CLIENTI_GLOBAL, apoi `SELECT ID_Client FROM CLIENTI_ID@BUCHAREST_LINK WHERE CNP='...'` și același pe CLUJ_LINK |
| `N2-bd/04-transparency/03-conturi-global-view.png` | `SELECT ID_Cont, IBAN, ID_Sucursala, Nod FROM CONTURI_GLOBAL ORDER BY Nod, ID_Cont;` |
| `N2-bd/04-transparency/04-s2-transfer.png` | INSERT cont cu Sucursala=1, COMMIT; UPDATE SET ID_Sucursala=2, COMMIT; SELECT ... Nod FROM CONTURI_GLOBAL WHERE IBAN='...' |
| `N2-bd/04-transparency/05-app-global-connection.png` | Browser — ruta `/global` |
| `N2-bd/08-replication/01-initial-sync.png` | Output MERGE din `08-replication.sql` (X rows merged) |
| `N2-bd/08-replication/02-s6-replication-trigger.png` | `INSERT INTO TIPURI_CONT VALUES (5,'Pensie',2.5); COMMIT;` pe Central, apoi `SELECT * FROM TIPURI_CONT@BUCHAREST_LINK; SELECT * FROM TIPURI_CONT@CLUJ_LINK;` |
| `N2-bd/05-constraints/01-s4-local-visible-global.png` | INSERT direct în CONTURI_B pe Bucharest, apoi `SELECT COUNT(*) FROM CONTURI_GLOBAL;` pe Central (numărul crește) |
| `N2-bd/05-constraints/02-s5-global-to-both-locals.png` | INSERT via CLIENTI_GLOBAL, verificare `SELECT Nume FROM CLIENTI_ID@BUCHAREST_LINK WHERE CNP='...'` și `@CLUJ_LINK` |
| `N2-bd/06-optimization/01-rule-based-plan.png` | `EXPLAIN PLAN FOR SELECT /*+ RULE */ ...` apoi `SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);` din `06-optimization.sql` |
| `N2-bd/06-optimization/02-cost-based-plan.png` | Același fără hint RULE — planul arată INDEX RANGE SCAN pe IDX_CLIENTI_PROFIL_SCOR și operații REMOTE |

### N3 — Aplicație Flask (browser screenshots)

Pornire app: `cp .env.docker .env && cd app && python app.py`

| Fișier | Rută / acțiune |
|--------|----------------|
| `N3-app/01-local/01-bucharest-view.png` | `/local/bucharest` — lista conturilor |
| `N3-app/01-local/02-add-cont-form.png` | Formularul de adăugare cont (scroll jos pe aceeași pagină) |
| `N3-app/01-local/03-cont-added.png` | După submit — mesaj verde de succes + rândul nou în tabel |
| `N3-app/01-local/04-cluj-view.png` | `/local/cluj` |
| `N3-app/02-global/01-global-view.png` | `/global` — tabelul CLIENTI_GLOBAL și CONTURI_GLOBAL |
| `N3-app/02-global/02-totals-per-branch.png` | Secțiunea de totaluri per sucursală de pe `/global` |
| `N3-app/03-local-to-global/01-form.png` | `/demo/local-to-global` — formularul de insert local |
| `N3-app/03-local-to-global/02-before-after-horizontal.png` | După submit — tabelele before/after CONTURI_B și CONTURI_C |
| `N3-app/03-local-to-global/03-vertical-before-after.png` | Secțiunea de fragmentare verticală (CLIENTI_ID Bucharest / Cluj / CLIENTI_PROFIL Central) |
| `N3-app/03-local-to-global/04-replication-demo.png` | `/demo/replication` după insert — toate 3 noduri cu noul tip |
| `N3-app/04-global-to-local/01-form.png` | `/demo/global-to-local` — formularul Secțiunea A (vertical) |
| `N3-app/04-global-to-local/02-propagation-both-nodes.png` | După submit vertical — CNP vizibil în ambele CLIENTI_ID locale |
| `N3-app/04-global-to-local/03-horizontal-routing.png` | Secțiunea B (horizontal) după insert cu Sucursala=1 — before/after diff |
| `N3-app/04-global-to-local/04-replication-propagation.png` | `/demo/replication` after insert — cele 3 tabele sincronizate |

---

## 4. Diagrame (deja existente — verifică că se compilează)

Fișierele există în `assets/diagrams/`:
- `er-diagram.png`
- `conceptual-diagram.png`

Dacă PDF-ul le afișează cu placeholder albastru, înseamnă că pdflatex nu le găsește —
verifică că compilezi din `docs/` (calea `../assets/diagrams/` trebuie să fie validă).
