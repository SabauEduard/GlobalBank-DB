-- ============================================================
-- GlobalBank DB — DB Links owned by GLOBAL_USER on ATP1
-- Run as GLOBAL_USER on bankdb_high
-- NOTE: Links will compile but fail at USE time until TLS is
--       enabled on ATP2 (OCI Console → globalbanklocal → Edit →
--       Network → Allow both TLS and mTLS Authentication)
-- ============================================================

-- Drop existing (idempotent)
BEGIN DBMS_CLOUD_ADMIN.DROP_DATABASE_LINK(db_link_name => 'BUCHAREST_LINK'); EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN DBMS_CLOUD_ADMIN.DROP_DATABASE_LINK(db_link_name => 'CLUJ_LINK'); EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN DBMS_CLOUD.DROP_CREDENTIAL(credential_name => 'ATP2_BUCHAREST_CRED'); EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN DBMS_CLOUD.DROP_CREDENTIAL(credential_name => 'ATP2_CLUJ_CRED'); EXCEPTION WHEN OTHERS THEN NULL; END;
/

-- Credentials
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

-- BUCHAREST_LINK
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

-- CLUJ_LINK
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

-- Verify links exist (creation OK even before TLS is enabled)
SELECT DB_LINK, USERNAME, HOST FROM USER_DB_LINKS ORDER BY DB_LINK;

-- Test connectivity (will fail with ORA-28759 until TLS is enabled on ATP2)
-- SELECT 'BUCHAREST_LINK' AS link, USER AS remote_user FROM DUAL@BUCHAREST_LINK;
-- SELECT 'CLUJ_LINK'      AS link, USER AS remote_user FROM DUAL@CLUJ_LINK;
