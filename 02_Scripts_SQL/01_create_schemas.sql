--Creacion de extensiones requeridas 
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";          -- generar UUID v4
CREATE EXTENSION IF NOT EXISTS "hstore";             -- pares clave/valor (NO-SQL)
CREATE EXTENSION IF NOT EXISTS "btree_gin";          -- índices híbridos
CREATE EXTENSION IF NOT EXISTS "pg_trgm";            -- búsqueda fuzzy
CREATE EXTENSION IF NOT EXISTS "postgis";            -- geoespacial
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements"; -- auditoría de queries
CREATE EXTENSION IF NOT EXISTS "pgcrypto";           -- criptografía nativa
CREATE EXTENSION IF NOT EXISTS "pg_cron";            -- manejo de procesos automatizacados mediante JOB de base de datos



CREATE EXTENSION IF NOT exists "pgrouting";          -- optimizacion rutas 
CREATE EXTENSION IF NOT exists "timescaledb";        -- series temporales 

CREATE EXTENSION IF NOT exists  "postgis_sfcgal";
CREATE EXTENSION IF NOT exists "postgis_topology";
CREATE EXTENSION IF NOT exists "postgis_raster";
CREATE EXTENSION IF NOT exists  "pg_partman";


--CREATE SCHEMA
CREATE SCHEMA IF NOT EXISTS create_schema;
CREATE SCHEMA IF NOT EXISTS bronze;
COMMENT ON SCHEMA bronze IS
'Capa Bronze del Data Warehouse aeronáutico. Contiene datos crudos e históricos provenientes de múltiples sistemas fuente, almacenados sin transformación para auditoría, trazabilidad y procesos ETL.';

CREATE SCHEMA IF NOT EXISTS silver; 
COMMENT ON SCHEMA silver
IS 'Capa silver: datos limpios, normalizados y validados provenientes de la capa bronze, listos para análisis y consumo.';

CREATE SCHEMA IF NOT EXISTS gold;
COMMENT ON SCHEMA gold IS
'Capa Gold del Data Warehouse aeronáutico. Contiene modelos dimensionales, tablas de hechos y dimensiones optimizadas para análisis de negocio, KPIs operacionales, reporting y herramientas de Business Intelligence.';

CREATE SCHEMA IF NOT EXISTS audit;
COMMENT ON SCHEMA audit IS
'Esquema de auditoría y monitoreo del Data Warehouse aeronáutico. Contiene registros históricos, bitácoras, trazabilidad de cambios, alertas operacionales y mecanismos de control para garantizar integridad, seguridad y cumplimiento regulatorio.';

CREATE SCHEMA IF NOT EXISTS History;
COMMENT ON SCHEMA history IS
'Esquema histórico del Data Warehouse aeronáutico. Almacena versiones históricas de datos, snapshots y registros de cambios para análisis temporal, trazabilidad y conservación de información operacional.';

CREATE SCHEMA IF NOT EXISTS Security;
COMMENT ON SCHEMA security IS
'Esquema de seguridad del Data Warehouse aeronáutico. Contiene roles, políticas de acceso, configuraciones de permisos, controles de autenticación y mecanismos de protección de datos sensibles y operacionales.';