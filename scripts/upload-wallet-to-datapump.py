"""
Upload the ATP2 wallet (cwallet.sso) to DATA_PUMP_DIR on ATP1 via UTL_FILE.
This unblocks DBMS_CLOUD_ADMIN DB Links (ORA-28759 fix).

Run as: python3 scripts/upload-wallet-to-datapump.py
"""

import os
import sys
import oracledb
from pathlib import Path

base = Path(__file__).resolve().parent.parent

# Load .env first so $HOME-based paths are available
env_file = base / '.env'
if env_file.exists():
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            os.environ.setdefault(k.strip(), v.strip())

wallet_atp1 = Path(os.path.expandvars(
    os.environ.get('GLOBAL_WALLET_DIR', str(Path.home() / '.oracle/wallet'))))
wallet_atp2 = Path(os.path.expandvars(
    os.environ.get('LOCAL_WALLET_DIR', str(Path.home() / '.oracle/wallet_local'))))

# Connection params for GLOBAL_USER on ATP1
user      = os.environ['GLOBAL_SCHEMA_USER']
password  = os.environ['GLOBAL_SCHEMA_PASSWORD']
dsn       = os.environ['GLOBAL_TNS_ALIAS']
wallet_pw = os.environ.get('WALLET_PASSWORD')

# Read the ATP2 wallet file (binary)
sso_file = wallet_atp2 / 'cwallet.sso'
if not sso_file.exists():
    print(f'ERROR: wallet file not found: {sso_file}')
    sys.exit(1)

wallet_bytes = sso_file.read_bytes()
print(f'Wallet file: {sso_file} ({len(wallet_bytes)} bytes)')

# Connect to GLOBAL_USER on ATP1 and write wallet to DATA_PUMP_DIR
print(f'Connecting as {user}@{dsn} ...')
conn = oracledb.connect(
    user=user,
    password=password,
    dsn=dsn,
    config_dir=str(wallet_atp1),
    wallet_location=str(wallet_atp1),
    wallet_password=wallet_pw,
)
print('Connected.')

with conn.cursor() as cur:
    cur.execute("""
        DECLARE
          v_file  UTL_FILE.FILE_TYPE;
          v_data  RAW(32767) := :wallet_bytes;
        BEGIN
          v_file := UTL_FILE.FOPEN('DATA_PUMP_DIR', 'cwallet.sso', 'wb', 32767);
          UTL_FILE.PUT_RAW(v_file, v_data, TRUE);
          UTL_FILE.FCLOSE(v_file);
          DBMS_OUTPUT.PUT_LINE('Written: ' || UTL_RAW.LENGTH(v_data) || ' bytes');
        END;
    """, wallet_bytes=wallet_bytes)

conn.commit()
conn.close()
print('cwallet.sso written to DATA_PUMP_DIR on ATP1.')
print('Re-test DB Links: SELECT 1 FROM DUAL@BUCHAREST_LINK')
