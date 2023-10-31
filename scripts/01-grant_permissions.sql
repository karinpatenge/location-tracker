-- In Local DB or DBCS: Run as SYS or SYSTEM 
grant aq_administrator_role, create job, manage scheduler to testuser;

grant execute on dbms_aq to testuser;
grant execute on dbms_aqadm to testuser;
grant select_catalog_role to testuser;


-- In Autonomous DB: Run as ADMIN
grant aq_administrator_role, create job, manage scheduler to testuser;

grant execute on dbms_aq to testuser;
grant execute on dbms_aqadm to testuser;
grant execute on dbms_lock to testuser;
grant execute on dbms_aqin to testuser;
grant execute on dbms_aqjms to testuser;
grant select_catalog_role to testuser;
