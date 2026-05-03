from flask import Flask, render_template, request, redirect, url_for, flash
from db import (
    get_global_conn, get_bucharest_conn, get_cluj_conn,
    get_branch_conn, query, execute,
)

app = Flask(__name__)
app.secret_key = 'globalbank-dev'

BRANCHES = {
    'bucharest': {'label': 'Bucuresti', 'id_sucursala': 1},
    'cluj':      {'label': 'Cluj',      'id_sucursala': 2},
}


# ── Home ────────────────────────────────────────────────────────────────────

@app.route('/')
def index():
    return render_template('index.html')


# ── FR-APP-01: Local node view ───────────────────────────────────────────────

@app.route('/local/<branch>')
def local_view(branch):
    if branch not in BRANCHES:
        return 'Unknown branch', 404
    meta = BRANCHES[branch]
    suffix = 'B' if branch == 'bucharest' else 'C'

    conn = get_branch_conn(branch)
    try:
        conturi    = query(conn, f'SELECT * FROM CONTURI_{suffix} ORDER BY ID_Cont')
        tranzactii = query(conn, f'SELECT * FROM TRANZACTII_{suffix} ORDER BY Data DESC FETCH FIRST 20 ROWS ONLY')
        clienti    = query(conn, 'SELECT * FROM CLIENTI_ID ORDER BY ID_Client')
    finally:
        conn.close()

    return render_template('local.html',
                           branch=branch, meta=meta, suffix=suffix,
                           conturi=conturi, tranzactii=tranzactii, clienti=clienti)


@app.route('/local/<branch>/cont/add', methods=['POST'])
def add_cont(branch):
    if branch not in BRANCHES:
        return 'Unknown branch', 404
    meta = BRANCHES[branch]
    suffix = 'B' if branch == 'bucharest' else 'C'
    seq   = f'SEQ_CONT_{suffix}'

    conn = get_branch_conn(branch)
    try:
        execute(conn,
            f"""INSERT INTO CONTURI_{suffix}
                  (ID_Cont, IBAN, ID_Tip, Sold, Moneda, ID_Sucursala, ID_Client)
                VALUES ({seq}.NEXTVAL, :iban, :id_tip, :sold, :moneda, :suc, :client)""",
            {
                'iban':   request.form['iban'],
                'id_tip': int(request.form['id_tip']),
                'sold':   float(request.form.get('sold', 0)),
                'moneda': request.form.get('moneda', 'RON'),
                'suc':    meta['id_sucursala'],
                'client': int(request.form['id_client']),
            })
        flash('Cont adaugat cu succes.', 'success')
    except Exception as e:
        flash(f'Eroare: {e}', 'danger')
    finally:
        conn.close()
    return redirect(url_for('local_view', branch=branch))


@app.route('/local/<branch>/cont/<int:cont_id>/delete', methods=['POST'])
def delete_cont(branch, cont_id):
    if branch not in BRANCHES:
        return 'Unknown branch', 404
    suffix = 'B' if branch == 'bucharest' else 'C'
    conn = get_branch_conn(branch)
    try:
        execute(conn, f'DELETE FROM CONTURI_{suffix} WHERE ID_Cont = :id', {'id': cont_id})
        flash('Cont sters.', 'success')
    except Exception as e:
        flash(f'Eroare: {e}', 'danger')
    finally:
        conn.close()
    return redirect(url_for('local_view', branch=branch))


@app.route('/local/<branch>/tranzactie/add', methods=['POST'])
def add_tranzactie(branch):
    if branch not in BRANCHES:
        return 'Unknown branch', 404
    suffix = 'B' if branch == 'bucharest' else 'C'
    seq   = f'SEQ_TRANZ_{suffix}'
    conn = get_branch_conn(branch)
    try:
        execute(conn,
            f"""INSERT INTO TRANZACTII_{suffix}
                  (ID_Tranzactie, Data, Suma, Tip_Tranzactie, ID_Cont_Sursa)
                VALUES ({seq}.NEXTVAL, SYSDATE, :suma, :tip, :cont)""",
            {
                'suma': float(request.form['suma']),
                'tip':  request.form['tip_tranzactie'],
                'cont': int(request.form['id_cont']),
            })
        flash('Tranzactie adaugata.', 'success')
    except Exception as e:
        flash(f'Eroare: {e}', 'danger')
    finally:
        conn.close()
    return redirect(url_for('local_view', branch=branch))


# ── FR-APP-02: Global view ───────────────────────────────────────────────────

@app.route('/global')
def global_view():
    try:
        conn = get_global_conn()
        clienti = query(conn, 'SELECT * FROM CLIENTI_GLOBAL ORDER BY ID_Client')
        conturi = query(conn, 'SELECT * FROM CONTURI_GLOBAL ORDER BY ID_Sucursala, ID_Cont')
        totals  = query(conn,
            """SELECT ID_Sucursala,
                      COUNT(*)    AS nr_conturi,
                      SUM(Sold)   AS sold_total
               FROM   CONTURI_GLOBAL
               GROUP BY ID_Sucursala
               ORDER BY ID_Sucursala""")
        conn.close()
        db_links_ok = True
    except Exception as e:
        clienti, conturi, totals = [], [], []
        db_links_ok = False
        flash(f'DB Links inactive: {e}', 'warning')

    return render_template('global.html',
                           clienti=clienti, conturi=conturi,
                           totals=totals, db_links_ok=db_links_ok)


# ── FR-APP-03: Local → Global transparency demo ──────────────────────────────

@app.route('/demo/local-to-global', methods=['GET', 'POST'])
def demo_local_to_global():
    # Horizontal fragment (CONTURI) demo state
    before_b, before_c, after_b, after_c = [], [], [], []
    inserted = None

    # Vertical fragment (CLIENTI_ID) demo state
    cl_b_before, cl_b_after = [], []
    cl_c_before, cl_c_after = [], []
    cl_global_before, cl_global_after = [], []
    inserted_client = None

    demo_type = request.form.get('demo_type') if request.method == 'POST' else None

    if request.method == 'POST' and demo_type == 'horizontal':
        branch = request.form['branch']
        suffix = 'B' if branch == 'bucharest' else 'C'
        meta   = BRANCHES[branch]
        seq    = f'SEQ_CONT_{suffix}'

        cb = get_bucharest_conn()
        cc = get_cluj_conn()
        before_b = query(cb, 'SELECT ID_Cont, IBAN, ID_Sucursala, Sold FROM CONTURI_B ORDER BY ID_Cont')
        before_c = query(cc, 'SELECT ID_Cont, IBAN, ID_Sucursala, Sold FROM CONTURI_C ORDER BY ID_Cont')

        conn = get_branch_conn(branch)
        try:
            execute(conn,
                f"""INSERT INTO CONTURI_{suffix}
                      (ID_Cont, IBAN, ID_Tip, Sold, Moneda, ID_Sucursala, ID_Client)
                    VALUES ({seq}.NEXTVAL, :iban, 1, :sold, 'RON', :suc, :client)""",
                {
                    'iban':   request.form['iban'],
                    'sold':   float(request.form.get('sold', 0)),
                    'suc':    meta['id_sucursala'],
                    'client': int(request.form['id_client']),
                })
            inserted = {'branch': branch, 'iban': request.form['iban']}
        except Exception as e:
            flash(f'Eroare insert cont local: {e}', 'danger')
        finally:
            conn.close()

        after_b = query(cb, 'SELECT ID_Cont, IBAN, ID_Sucursala, Sold FROM CONTURI_B ORDER BY ID_Cont')
        after_c = query(cc, 'SELECT ID_Cont, IBAN, ID_Sucursala, Sold FROM CONTURI_C ORDER BY ID_Cont')
        cb.close()
        cc.close()

    elif request.method == 'POST' and demo_type == 'clienti':
        branch = request.form['branch']
        suffix = 'B' if branch == 'bucharest' else 'C'
        seq    = f'SEQ_CLIENT_{suffix}'
        cnp    = request.form['cnp']
        params = {'nume': request.form['nume'], 'prenume': request.form['prenume'], 'cnp': cnp}

        cb = get_bucharest_conn()
        cc = get_cluj_conn()
        cg = get_global_conn()

        cl_b_before = query(cb, 'SELECT ID_Client, Nume, Prenume, CNP FROM CLIENTI_ID ORDER BY ID_Client')
        cl_c_before = query(cc, 'SELECT ID_Client, Nume, Prenume, CNP FROM CLIENTI_ID ORDER BY ID_Client')
        try:
            cl_global_before = query(cg, 'SELECT ID_Client, Nume, Prenume, Scor_Credit FROM CLIENTI_GLOBAL ORDER BY ID_Client')
        except Exception:
            cl_global_before = []

        conn = get_branch_conn(branch)
        try:
            v_id = query(conn, f'SELECT {seq}.NEXTVAL AS nid FROM DUAL')[0]['nid']
            row  = {'id': v_id, **params}
            sql  = 'INSERT INTO CLIENTI_ID (ID_Client, Nume, Prenume, CNP) VALUES (:id, :nume, :prenume, :cnp)'
            # CLIENTI_ID is replicated on both local nodes — write to both directly
            execute(cb, sql, row)
            execute(cc, sql, row)
            # Profile fragment lives only on Central
            execute(cg,
                'INSERT INTO CLIENTI_PROFIL (ID_Client, Email, Telefon, Scor_Credit) VALUES (:id, :email, :tel, :scor)',
                {'id': v_id, 'email': request.form.get('email', ''), 'tel': request.form.get('telefon', ''),
                 'scor': int(request.form.get('scor_credit', 500))})
            inserted_client = {'branch': branch, 'cnp': cnp, 'id': v_id, 'suffix': suffix}
        except Exception as e:
            flash(f'Eroare insert client: {e}', 'danger')
        finally:
            conn.close()

        cl_b_after = query(cb, 'SELECT ID_Client, Nume, Prenume, CNP FROM CLIENTI_ID ORDER BY ID_Client')
        cl_c_after = query(cc, 'SELECT ID_Client, Nume, Prenume, CNP FROM CLIENTI_ID ORDER BY ID_Client')
        try:
            cl_global_after = query(cg, 'SELECT ID_Client, Nume, Prenume, Scor_Credit FROM CLIENTI_GLOBAL ORDER BY ID_Client')
        except Exception:
            cl_global_after = []
        cb.close()
        cc.close()
        cg.close()

    # Clients list for the horizontal form dropdown
    try:
        conn = get_bucharest_conn()
        clienti = query(conn, 'SELECT ID_Client, Nume, Prenume FROM CLIENTI_ID ORDER BY ID_Client')
        conn.close()
    except Exception:
        clienti = []

    # Static display: current vertical fragmentation state
    clienti_b, clienti_c, clienti_profil = [], [], []
    try:
        cb = get_bucharest_conn()
        clienti_b = query(cb, 'SELECT ID_Client, Nume, Prenume, CNP FROM CLIENTI_ID ORDER BY ID_Client')
        cb.close()
    except Exception:
        pass
    try:
        cc = get_cluj_conn()
        clienti_c = query(cc, 'SELECT ID_Client, Nume, Prenume, CNP FROM CLIENTI_ID ORDER BY ID_Client')
        cc.close()
    except Exception:
        pass
    try:
        cg = get_global_conn()
        clienti_profil = query(cg, 'SELECT ID_Client, Email, Telefon, Scor_Credit FROM CLIENTI_PROFIL ORDER BY ID_Client')
        cg.close()
    except Exception:
        pass

    return render_template('demo_ltog.html',
                           branches=BRANCHES,
                           clienti=clienti,
                           before_b=before_b, before_c=before_c,
                           after_b=after_b,   after_c=after_c,
                           inserted=inserted,
                           clienti_b=clienti_b, clienti_c=clienti_c,
                           clienti_profil=clienti_profil,
                           cl_b_before=cl_b_before, cl_b_after=cl_b_after,
                           cl_c_before=cl_c_before, cl_c_after=cl_c_after,
                           cl_global_before=cl_global_before, cl_global_after=cl_global_after,
                           inserted_client=inserted_client)


# ── FR-APP-04: Global → Local fragmentation demo ─────────────────────────────

@app.route('/demo/global-to-local', methods=['GET', 'POST'])
def demo_global_to_local():
    result_b, result_c, inserted_cnp = [], [], None
    horiz_before_b, horiz_before_c = [], []
    horiz_after_b,  horiz_after_c  = [], []
    inserted_iban = None
    db_links_ok = True

    demo_type = request.form.get('demo_type', 'vertical') if request.method == 'POST' else None

    if request.method == 'POST' and demo_type == 'vertical':
        cnp = request.form['cnp']
        try:
            conn = get_global_conn()
            execute(conn,
                """INSERT INTO CLIENTI_GLOBAL
                     (Nume, Prenume, CNP, Email, Telefon, Scor_Credit)
                   VALUES (:nume, :prenume, :cnp, :email, :tel, :scor)""",
                {
                    'nume':    request.form['nume'],
                    'prenume': request.form['prenume'],
                    'cnp':     cnp,
                    'email':   request.form['email'],
                    'tel':     request.form.get('telefon', ''),
                    'scor':    int(request.form.get('scor_credit', 500)),
                })
            conn.close()
            inserted_cnp = cnp

            # Verify propagation to both local nodes
            cb = get_bucharest_conn()
            cc = get_cluj_conn()
            result_b = query(cb, 'SELECT * FROM CLIENTI_ID WHERE CNP = :cnp', {'cnp': cnp})
            result_c = query(cc, 'SELECT * FROM CLIENTI_ID WHERE CNP = :cnp', {'cnp': cnp})
            cb.close()
            cc.close()
        except Exception as e:
            db_links_ok = False
            flash(f'Eroare (DB Links necesare): {e}', 'danger')

    elif request.method == 'POST' and demo_type == 'horizontal':
        iban = request.form['iban']
        id_suc = int(request.form['id_sucursala'])
        try:
            cb = get_bucharest_conn()
            cc = get_cluj_conn()
            horiz_before_b = query(cb, 'SELECT ID_Cont, IBAN, ID_Sucursala, Sold FROM CONTURI_B ORDER BY ID_Cont')
            horiz_before_c = query(cc, 'SELECT ID_Cont, IBAN, ID_Sucursala, Sold FROM CONTURI_C ORDER BY ID_Cont')

            conn = get_global_conn()
            execute(conn,
                """INSERT INTO CONTURI_GLOBAL
                     (IBAN, ID_Tip, Sold, Moneda, ID_Sucursala, ID_Client)
                   VALUES (:iban, 1, :sold, 'RON', :suc, :client)""",
                {
                    'iban':   iban,
                    'sold':   float(request.form.get('sold', 0)),
                    'suc':    id_suc,
                    'client': int(request.form['id_client']),
                })
            conn.close()
            inserted_iban = iban

            horiz_after_b = query(cb, 'SELECT ID_Cont, IBAN, ID_Sucursala, Sold FROM CONTURI_B ORDER BY ID_Cont')
            horiz_after_c = query(cc, 'SELECT ID_Cont, IBAN, ID_Sucursala, Sold FROM CONTURI_C ORDER BY ID_Cont')
            cb.close()
            cc.close()
        except Exception as e:
            db_links_ok = False
            flash(f'Eroare (DB Links necesare): {e}', 'danger')

    # Clients list for horizontal form (bucharest node)
    clienti_global = []
    try:
        cg = get_global_conn()
        clienti_global = query(cg, 'SELECT ID_Client, Nume, Prenume FROM CLIENTI_GLOBAL ORDER BY ID_Client FETCH FIRST 20 ROWS ONLY')
        cg.close()
    except Exception:
        pass

    return render_template('demo_gtol.html',
                           db_links_ok=db_links_ok,
                           result_b=result_b, result_c=result_c,
                           inserted_cnp=inserted_cnp,
                           clienti_global=clienti_global,
                           horiz_before_b=horiz_before_b, horiz_before_c=horiz_before_c,
                           horiz_after_b=horiz_after_b,   horiz_after_c=horiz_after_c,
                           inserted_iban=inserted_iban)


# ── Demo: Replication ────────────────────────────────────────────────────────

@app.route('/demo/replication', methods=['GET', 'POST'])
def demo_replication():
    master_rows, slave_b, slave_c = [], [], []
    after_master, after_b, after_c = [], [], []
    inserted = None
    db_links_ok = True

    def _load_all():
        m, b, c = [], [], []
        try:
            cg = get_global_conn()
            m = query(cg, 'SELECT ID_Tip, Denumire, Dobanda FROM TIPURI_CONT ORDER BY ID_Tip')
            cg.close()
        except Exception as e:
            flash(f'Eroare conexiune globala: {e}', 'warning')
        try:
            cb = get_bucharest_conn()
            b = query(cb, 'SELECT ID_Tip, Denumire, Dobanda FROM TIPURI_CONT ORDER BY ID_Tip')
            cb.close()
        except Exception:
            pass
        try:
            cc = get_cluj_conn()
            c = query(cc, 'SELECT ID_Tip, Denumire, Dobanda FROM TIPURI_CONT ORDER BY ID_Tip')
            cc.close()
        except Exception:
            pass
        return m, b, c

    master_rows, slave_b, slave_c = _load_all()

    if request.method == 'POST':
        try:
            cg = get_global_conn()
            execute(cg,
                """INSERT INTO TIPURI_CONT (ID_Tip, Denumire, Dobanda)
                   VALUES ((SELECT NVL(MAX(ID_Tip), 0) + 1 FROM TIPURI_CONT),
                           :den, :rata)""",
                {
                    'den':  request.form['denumire'],
                    'rata': float(request.form.get('dobanda', 0)),
                })
            cg.close()
            inserted = request.form['denumire']
        except Exception as e:
            repl_error = str(e)
            if 'ORA-' in repl_error and ('LINK' in repl_error.upper() or '12541' in repl_error or '02019' in repl_error):
                flash(f'Triggerul a inserat pe master, dar replicarea a esuat (DB Link inactiv): {e}', 'warning')
                db_links_ok = False
            else:
                flash(f'Eroare insert master: {e}', 'danger')
                db_links_ok = False

        after_master, after_b, after_c = _load_all()

    return render_template('demo_replication.html',
                           db_links_ok=db_links_ok,
                           master_rows=master_rows, slave_b=slave_b, slave_c=slave_c,
                           after_master=after_master, after_b=after_b, after_c=after_c,
                           inserted=inserted)


if __name__ == '__main__':
    app.run(debug=True, port=5000)
