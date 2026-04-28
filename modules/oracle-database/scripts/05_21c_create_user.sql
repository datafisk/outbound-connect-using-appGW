-- Create Users
ALTER SESSION SET CONTAINER = CDB$ROOT;
CREATE USER c##ggadmin IDENTIFIED BY "Confluent12!"
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users
  CONTAINER=ALL;
GRANT CREATE SESSION, SET CONTAINER TO c##ggadmin CONTAINER=ALL;
grant dba to C##GGADMIN  CONTAINER=ALL;
BEGIN
   DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE(
      grantee                 => 'C##GGADMIN',
      privilege_type          => 'CAPTURE',
      grant_select_privileges => TRUE,
      container               => 'ALL');
END;
/
-- The following example creates a common user named c##cfltuser in a CDB
CREATE USER c##cfltuser IDENTIFIED BY "Confluent12!"
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users
  CONTAINER=ALL;
GRANT CREATE SESSION, SET CONTAINER TO c##cfltuser CONTAINER=ALL;
GRANT SELECT_CATALOG_ROLE TO c##cfltuser CONTAINER=ALL;
GRANT FLASHBACK ANY TABLE TO c##cfltuser CONTAINER=ALL;
GRANT SELECT ANY TABLE TO c##cfltuser CONTAINER=ALL;
GRANT LOCK ANY TABLE TO c##cfltuser CONTAINER=ALL;
