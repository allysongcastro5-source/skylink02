                                                              --SECUTIRY_ROLES
      -- Roles
-- Crear rol_admin_aerolinea
do $$
begin
	if not exists (select 1 from pg_roles where rolname = 'rol_admin_aerolinea') then
	create role rol_admin_aerolinea with login password 'Skyylink_Admin_2026!';
	raise notice 'Rol rol_admin_aerolinea creado';
end if;
End$$
 
COMMENT ON role rol_admin_aerolinea
IS 'Acceso Admin a la info'
 
-- Permisos rol_admin_aerolinea
grant all privileges on all tables in schema bronze to rol_admin_aerolinea;
grant all privileges on all tables in schema silver to rol_admin_aerolinea;
grant all privileges on all tables in schema gold to rol_admin_aerolinea;
grant all privileges on all tables in schema audit to rol_admin_aerolinea;
grant usage on schema history to  rol_admin_aerolinea;
grant select on all tables in schema history to rol_admin_aerolinea;
 
 
-- Crear rol_ops_vuelo
do $$
begin
if not exists (select 1 from pg_roles where rolname = 'rol_ops_vuelo') then
	create role rol_ops_vuelo with login password 'Skyylink_OperadorV_2026!';
	raise notice 'Rol rol_ops_vuelo creado';
end if;
End$$
 
COMMENT ON role rol_ops_vuelo
IS 'Acceso como operador de vuelo, total acceso a la informacion de los vuelos'
 
-- Permisos rol_ops_vuelo
grant usage on schema silver to rol_ops_vuelo;
grant select, insert , update on all tables in schema silver to rol_ops_vuelo;
grant usage on schema gold to rol_ops_vuelo;
grant select on all tables in schema gold to rol_ops_vuelo;
grant usage on schema audit to  rol_ops_vuelo;
grant select, insert on audit.log_accesos, audit.cambios_estado_vuelo to  rol_ops_vuelo;
 
-- Crear rol_mantenimiento_mro
do $$
begin
if not exists (select 1 from pg_roles where rolname = 'rol_mantenimiento_mro') then
	create role rol_mantenimiento_mro with login password 'Skyylink_Mantenimiento_2026!';
	raise notice 'Rol rol_mantenimiento_mro creado';
end if;
End$$
 
COMMENT ON role rol_mantenimiento_mro
IS 'Acceso como operador de mantenimiento, puede ver informacion de la aeronave y sus sistemas'
 
 
-- Permisos rol_mantenimiento_mro
grant usage on schema silver to rol_mantenimiento_mro;
grant select, insert , update on silver.mantenimiento_eventos, silver.talleres_mro to rol_mantenimiento_mro;
grant select on silver.aeronaves, silver.motores, silver.vuelos to rol_mantenimiento_mro;
grant usage on schema audit to rol_mantenimiento_mro;
grant select, insert on audit.log_accesos, audit.cambios_estado_vuelo to rol_mantenimiento_mro;
 
-- Crear rol_aduana_pais
do $$
begin
if not exists (select 1 from pg_roles where rolname = 'rol_aduana_pais') then
	create role rol_aduana_pais with login password 'Skyylink_Aduanas_2026!';
	raise notice 'Rol rol_aduana_pais creado';
end if;
End$$
 
COMMENT ON role rol_aduana_pais
IS 'Acceso como aduanas, puede ver temas de vuelos y cargas'
 
-- Permisos rol_aduana_pais
grant usage on schema silver to rol_aduana_pais;
grant select on silver.carga_vuelo, silver.vuelos,silver.aeropuertos to rol_aduana_pais;
grant usage on schema gold to rol_aduana_pais;
grant select on gold.hechos_carga, gold.dim_ruta, gold.dim_aeropuerto to rol_aduana_pais;
 
 
-- Crear rol_aeropuerto_admin
do $$
begin
if not exists (select 1 from pg_roles where rolname = 'rol_aeropuerto_admin') then
	create role rol_aeropuerto_admin with login password 'Skyylink_Aeropuerto_2026!';
	raise notice 'Rol rol_aeropuerto_admin creado';
end if;
End$$
 
COMMENT ON role rol_aeropuerto_admin
IS 'Acceso como administrador de aeropuerto, acceso a temas de vuelos y aeropuertos'
 
-- Permisos rol_aeropuerto_admin
grant usage on schema silver to rol_aeropuerto_admin;
grant select on silver.vuelos, silver.aeropuertos, silver.pasajeros to rol_aeropuerto_admin;
grant select on silver.pasajeros, silver.equipaje, silver.posicionamiento_vuelo to rol_aeropuerto_admin;
grant usage on schema gold to rol_aeropuerto_admin;
grant select on all tables in schema gold to rol_aeropuerto_admin;
 
-- Crear rol_revenue_mgmt
do $$
begin
if not exists (select 1 from pg_roles where rolname = 'rol_revenue_mgmt') then
	create role rol_revenue_mgmt with login password 'Skyylink_Ventas_2026!';
	raise notice 'Rol rol_revenue_mgmt creado';
end if;
End$$
 
COMMENT ON role rol_revenue_mgmt
IS 'Acceso como gerencia financiera, acceso a ganancias'
 
-- Permisos rol_revenue_mgmt
grant usage on schema gold to rol_revenue_mgmt;
grant select on gold.hechos_vuelo, gold.hechos_pasajero, gold.hechos_carga to rol_revenue_mgmt;
grant select on gold.dim_ruta, gold.dim_tiempo, gold.dim_aeronave to rol_revenue_mgmt;
 
-- Crear rol_api_publica
do $$
begin
if not exists (select 1 from pg_roles where rolname = 'rol_api_publica') then
	create role rol_api_publica with login password 'Skyylink_Public_2026!';
	raise notice 'Rol rol_api_publica creado';
end if;
End$$
 
COMMENT ON role rol_api_publica
IS 'API de acceso publica, consultas generales, info personal restringida o enmascarada'
 
-- Permisos rol_api_publica
 
GRANT USAGE ON SCHEMA silver TO rol_api_publica;
GRANT SELECT on silver.vuelos, silver.aeropuertos, silver.aerolineas TO rol_api_publica;
GRANT SELECT on silver.posicionamiento_vuelo TO rol_api_publica;
GRANT USAGE ON SCHEMA gold TO rol_api_publica;
GRANT SELECT on gold.hechos_vuelo, gold.dim_ruta TO rol_api_publica;

CREATE OR REPLACE FUNCTION security.fn_encrypt_sensitive_data()
RETURNS TRIGGER AS
$$
BEGIN
    IF TG_TABLE_NAME = 'pasajeros' THEN
IF NEW.email_encrypted IS NULL
           AND NEW.nombre IS NOT NULL THEN
            NEW.email_encrypted :=
                security.fn_encrypt(NEW.nombre);
        END IF;
    END IF;
    RETURN NEW;
END;
$$
LANGUAGE plpgsql;

-- audit
CREATE OR REPLACE FUNCTION audit.fn_audit_sensitive_access()
RETURNS TRIGGER AS
$$
BEGIN
    INSERT INTO audit.log_accesos (usuario,schema_name,tabla_name,operacion,registros_afectados)
    VALUES (current_user,TG_TABLE_SCHEMA,TG_TABLE_NAME,TG_OP,1);
    RETURN NEW;
END;
$$
LANGUAGE plpgsql;
 
-- aplicar a tablas con datos sensibles
DROP TRIGGER IF EXISTS trg_audit_pasajeros ON silver.pasajeros;
CREATE TRIGGER trg_audit_pasajeros
AFTER INSERT OR UPDATE OR DELETE
ON silver.pasajeros
FOR EACH ROW
EXECUTE FUNCTION audit.fn_audit_sensitive_access();
                                                        