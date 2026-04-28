-- connect as sysdba
CONNECT sys/confluent123 AS SYSDBA
-- enable goldengate replication
ALTER SYSTEM SET enable_goldengate_replication=TRUE SCOPE=BOTH;
-- List redos
set lines 200
COLUMN MEMBER FORMAT A40
COLUMN MEMBERS FORMAT 999
SELECT a.group#,b.member,a.members, a.bytes/1024/1024 as MB, a.status FROM v$log a,v$logfile b WHERE a.group# = b.group#;
-- Change Redo log size
alter database add logfile group 4  '/opt/oracle/oradata/XE/redo04.log' size 2G;
alter database add logfile group 5  '/opt/oracle/oradata/XE/redo05.log' size 2G;
alter database add logfile group 6  '/opt/oracle/oradata/XE/redo06.log' size 2G;
-- switch to new group
alter system switch logfile;
alter system switch logfile;
alter system switch logfile;
-- disable old
alter system archive log group 1;
alter system archive log group 2;
alter system archive log group 3;
-- drop old
execute sys. dbms_lock. sleep(60);
ALTER DATABASE DROP LOGFILE GROUP 1; 
ALTER DATABASE DROP LOGFILE GROUP 2;
ALTER DATABASE DROP LOGFILE GROUP 3;
-- List redos
set lines 200
COLUMN MEMBER FORMAT A40
COLUMN MEMBERS FORMAT 999
SELECT a.group#,b.member,a.members, a.bytes/1024/1024 as MB, a.status FROM v$log a,v$logfile b WHERE a.group# = b.group#;
-- change SGA and PGA, for XE
#alter system set sga_target=1G scope=spfile sid='*';
#ALTER SYSTEM SET pga_aggregate_limit=2G SCOPE=BOTH;
-- Enable archive log
shutdown immediate
startup mount
alter database archivelog;
alter database open;
ALTER SESSION SET CONTAINER=cdb$root;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER SESSION SET CONTAINER=XEPDB1;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
-- Made Logging asynchronous
ALTER SYSTEM SET commit_logging = 'BATCH' CONTAINER=ALL;
ALTER SYSTEM SET commit_wait = 'NOWAIT' CONTAINER=ALL;
exit;
