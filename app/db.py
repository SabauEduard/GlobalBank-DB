"""Oracle connection helper — thin mode (no Oracle Client required).

Supports two modes via DB_MODE env var:
  docker  — plain TCP connections to local Docker containers
  atp     — mTLS wallet connections to Oracle ATP Free Tier (default)
"""

import os
import oracledb
from dotenv import load_dotenv

load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '..', '.env'))

_MODE = os.environ.get('DB_MODE', 'atp')


def _connect_plain(user, password, dsn):
    return oracledb.connect(user=user, password=password, dsn=dsn)


def _connect_wallet(user, password, dsn, wallet_dir, wallet_password=None):
    wallet_dir = os.path.expandvars(wallet_dir)
    kwargs = {
        'user': user,
        'password': password,
        'dsn': dsn,
        'config_dir': wallet_dir,
        'wallet_location': wallet_dir,
    }
    if wallet_password:
        kwargs['wallet_password'] = wallet_password
    return oracledb.connect(**kwargs)


def get_global_conn():
    """Connect as GLOBAL_USER on the central node."""
    if _MODE == 'docker':
        return _connect_plain(
            user=os.environ['GLOBAL_SCHEMA_USER'],
            password=os.environ['GLOBAL_SCHEMA_PASSWORD'],
            dsn=os.environ['GLOBAL_DSN'],
        )
    return _connect_wallet(
        user=os.environ['GLOBAL_SCHEMA_USER'],
        password=os.environ['GLOBAL_SCHEMA_PASSWORD'],
        dsn=os.environ['GLOBAL_TNS_ALIAS'],
        wallet_dir=os.environ['GLOBAL_WALLET_DIR'],
        wallet_password=os.environ.get('WALLET_PASSWORD'),
    )


def get_bucharest_conn():
    """Connect as BUCHAREST_USER on the Bucharest fragment node."""
    if _MODE == 'docker':
        return _connect_plain(
            user=os.environ['BUCHAREST_SCHEMA_USER'],
            password=os.environ['BUCHAREST_SCHEMA_PASSWORD'],
            dsn=os.environ['BUCHAREST_DSN'],
        )
    tls_dsn = os.environ.get('LOCAL_TLS_DSN')
    if tls_dsn:
        return _connect_plain(
            user=os.environ['BUCHAREST_SCHEMA_USER'],
            password=os.environ['BUCHAREST_SCHEMA_PASSWORD'],
            dsn=tls_dsn,
        )
    return _connect_wallet(
        user=os.environ['BUCHAREST_SCHEMA_USER'],
        password=os.environ['BUCHAREST_SCHEMA_PASSWORD'],
        dsn=os.environ['LOCAL_TNS_ALIAS'],
        wallet_dir=os.environ['LOCAL_WALLET_DIR'],
        wallet_password=os.environ.get('LOCAL_WALLET_PASSWORD'),
    )


def get_cluj_conn():
    """Connect as CLUJ_USER on the Cluj fragment node."""
    if _MODE == 'docker':
        return _connect_plain(
            user=os.environ['CLUJ_SCHEMA_USER'],
            password=os.environ['CLUJ_SCHEMA_PASSWORD'],
            dsn=os.environ['CLUJ_DSN'],
        )
    tls_dsn = os.environ.get('LOCAL_TLS_DSN')
    if tls_dsn:
        return _connect_plain(
            user=os.environ['CLUJ_SCHEMA_USER'],
            password=os.environ['CLUJ_SCHEMA_PASSWORD'],
            dsn=tls_dsn,
        )
    return _connect_wallet(
        user=os.environ['CLUJ_SCHEMA_USER'],
        password=os.environ['CLUJ_SCHEMA_PASSWORD'],
        dsn=os.environ['LOCAL_TNS_ALIAS'],
        wallet_dir=os.environ['LOCAL_WALLET_DIR'],
        wallet_password=os.environ.get('LOCAL_WALLET_PASSWORD'),
    )


def get_branch_conn(branch):
    if branch == 'bucharest':
        return get_bucharest_conn()
    elif branch == 'cluj':
        return get_cluj_conn()
    raise ValueError(f'Unknown branch: {branch}')


def query(conn, sql, params=None):
    """Return list of dicts from a SELECT query."""
    with conn.cursor() as cur:
        cur.execute(sql, params or [])
        cols = [d[0].lower() for d in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]


def execute(conn, sql, params=None):
    """Execute a DML statement and commit."""
    with conn.cursor() as cur:
        cur.execute(sql, params or [])
    conn.commit()
