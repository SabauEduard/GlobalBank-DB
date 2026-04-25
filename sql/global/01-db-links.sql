-- ============================================================
-- GlobalBank DB — T005-T008: DB Links from ATP1 to ATP2
-- Run as ADMIN on bankdb_high
-- ============================================================

-- Drop existing links (idempotent)
BEGIN DBMS_CLOUD_ADMIN.DROP_DATABASE_LINK(db_link_name => 'BUCHAREST_LINK'); EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN DBMS_CLOUD_ADMIN.DROP_DATABASE_LINK(db_link_name => 'CLUJ_LINK'); EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN DBMS_CLOUD.DROP_CREDENTIAL(credential_name => 'ATP2_BUCHAREST_CRED'); EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN DBMS_CLOUD.DROP_CREDENTIAL(credential_name => 'ATP2_CLUJ_CRED'); EXCEPTION WHEN OTHERS THEN NULL; END;
/

-- T005: Create credentials
BEGIN
  DBMS_CLOUD.CREATE_CREDENTIAL(
    credential_name => 'ATP2_BUCHAREST_CRED',
    username        => 'BUCHAREST_USER',
    password        => 'SecurePass123!'
  );
END;
/

BEGIN
  DBMS_CLOUD.CREATE_CREDENTIAL(
    credential_name => 'ATP2_CLUJ_CRED',
    username        => 'CLUJ_USER',
    password        => 'SecurePass123!'
  );
END;
/

-- T006: Create BUCHAREST_LINK (owned by ADMIN)
BEGIN
  DBMS_CLOUD_ADMIN.CREATE_DATABASE_LINK(
    db_link_name       => 'BUCHAREST_LINK',
    hostname           => 'adb.eu-turin-1.oraclecloud.com',
    port               => '1521',
    service_name       => 'g765c070f2106a4_globalbanklocal_high.adb.oraclecloud.com',
    ssl_server_cert_dn => 'CN=adb.eu-turin-1.oraclecloud.com,O=Oracle Corporation,L=Redwood City,ST=California,C=US',
    credential_name    => 'ATP2_BUCHAREST_CRED'
  );
END;
/

-- T007: Create CLUJ_LINK (owned by ADMIN)
BEGIN
  DBMS_CLOUD_ADMIN.CREATE_DATABASE_LINK(
    db_link_name       => 'CLUJ_LINK',
    hostname           => 'adb.eu-turin-1.oraclecloud.com',
    port               => '1521',
    service_name       => 'g765c070f2106a4_globalbanklocal_high.adb.oraclecloud.com',
    ssl_server_cert_dn => 'CN=adb.eu-turin-1.oraclecloud.com,O=Oracle Corporation,L=Redwood City,ST=California,C=US',
    credential_name    => 'ATP2_CLUJ_CRED'
  );
END;
/

-- T008: Verify both links work (as ADMIN)
SELECT 'BUCHAREST_LINK OK - user: ' || USER AS status FROM DUAL@BUCHAREST_LINK;
SELECT 'CLUJ_LINK OK - user: '      || USER AS status FROM DUAL@CLUJ_LINK;
