                                                                  --CREATE TABLE IF NOT EXISTS CAPA SILVER
                            -- 1. Aerolineas
CREATE TABLE IF NOT EXISTS silver.aerolineas (
    aerolinea_id int PRIMARY key not null,
    codigo_iata VARCHAR(2) CHECK (char_length(codigo_iata) = 2),
    codigo_icao VARCHAR(3) CHECK (char_length(codigo_icao) = 3) not null,
    nombre TEXT ,
    pais_base VARCHAR(2) CHECK (char_length(pais_base) = 2) not null,
    activa BOOLEAN DEFAULT true
);
COMMENT ON TABLE silver.aerolineas
IS 'Catálogo de aerolíneas con códigos IATA/ICAO y estado operativo. Datos limpios y normalizados para referencia en vuelos.';

ALTER TABLE silver.aerolineas
ALTER COLUMN aerolinea_id
ADD GENERATED ALWAYS AS IDENTITY;
 
 
-- 2. countries
CREATE TABLE IF NOT EXISTS silver.countries (
    country_id INT PRIMARY KEY,
    code CHAR(2) NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL,
    continent CHAR(2),
    wikipedia_link TEXT,
    keywords TEXT
);
COMMENT ON TABLE silver.countries IS
'Tabla catálogo de países obtenida desde countries.csv para procesos ETL y modelado dimensional.';

 
-- 3.regions
CREATE TABLE IF NOT EXISTS silver.regions (
    region_id INT PRIMARY KEY,
    code VARCHAR(10) NOT NULL UNIQUE,
    local_code VARCHAR(20),
    name VARCHAR(150) NOT NULL,
    continent CHAR(2),
    iso_country CHAR(2),
    wikipedia_link TEXT,
    keywords TEXT,
    CONSTRAINT fk_regions_country
    FOREIGN KEY (iso_country) REFERENCES silver.countries(code)
);
COMMENT ON TABLE silver.regions IS
'Tabla catálogo de regiones/provincias/estados obtenida desde regions.csv para procesos ETL y modelado dimensional.';
 
-- 4.aeropuertos
create table silver.aeropuertos (
aeropuerto_id int primary key,
ident varchar(10),
type varchar(20),
nombre text,
latitude_deg decimal (10,6),
longitude_deg decimal (10,6),
elevation_ft int,
continent varchar(5),
iso_country	varchar(2),
iso_region	varchar(10),
municipality text,
scheduled_service varchar(5),
icao varchar(10),
iata varchar(3),
gps_code varchar(10),	
local_code varchar(10),
home_link text,
wikipedia_link text,
keywords text,
country_id int not null references silver.countries(country_id),
region_id int not null references silver.regions(region_id),
ubicacion GEOGRAPHY(POINT, 4326) not null
);

select * from silver.aeropuertos;
COMMENT ON TABLE silver.aeropuertos IS
'Tabla catálogo de aeropuertos obtenida desde airports.csv para procesos ETL y modelado dimensional.';

ALTER TABLE silver.aeropuertos
DROP COLUMN name;
 
-- 5.aerovias
CREATE TABLE IF NOT EXISTS silver.aerovias (
    aerovia_id int PRIMARY key not null,
    designador VARCHAR(10) NOT NULL,
    tipo VARCHAR(10) CHECK (tipo IN ('AWY','JET','RNAV')),
    geometria GEOMETRY(LINESTRINGZ, 4979),
    nivel_min INT CHECK (nivel_min >= 0),
    nivel_max INT CHECK (nivel_max >= nivel_min),
    longitud_nm DECIMAL(8,2) CHECK (longitud_nm > 0) not null
);
COMMENT ON TABLE silver.aerovias
IS 'Red de aerovías (rutas aéreas) con geometría espacial, niveles de vuelo permitidos y longitud. Utilizada para navegación y análisis de trayectorias.';
 
ALTER TABLE silver.aerovias
ALTER COLUMN aerovia_id
ADD GENERATED ALWAYS AS IDENTITY;
 
--6. aeronaves
CREATE TABLE IF NOT EXISTS silver.aeronaves (
aeronave_id int PRIMARY KEY,
    matricula VARCHAR(10) unique not null,
    tipo VARCHAR(20) NOT NULL,
    configuracion_asientos JSONB,
    horas_vuelo_totales DECIMAL(10,2) CHECK (horas_vuelo_totales >= 0),
    estado VARCHAR(20) CHECK (estado IN ('ACTIVO','MANTENIMIENTO','RETIRADO')),
    fecha_entrada_servicio DATE CHECK (fecha_entrada_servicio <= CURRENT_DATE)
);
COMMENT ON TABLE silver.aeronaves
IS 'Inventario de aeronaves con configuración, estado operativo y horas de vuelo acumuladas. Datos limpios para mantenimiento y operaciones.';
 
ALTER TABLE silver.aeronaves
ALTER COLUMN aeronave_id
ADD GENERATED ALWAYS AS IDENTITY;

--7. motores
CREATE TABLE IF NOT EXISTS silver.motores (
    motor_id int PRIMARY KEY,
    aeronave_id int REFERENCES silver.aeronaves(aeronave_id) not null,
    posicion INT,
    modelo VARCHAR(20),
    serial_number VARCHAR(30) not null,
    horas_acumuladas DECIMAL(10,2),
    ciclos_acumulados INT
);
COMMENT ON TABLE silver.motores
IS 'Información de motores asociados a aeronaves, incluyendo posición, modelo y horas/ciclos acumulados para seguimiento técnico.';

ALTER TABLE silver.motores
ALTER COLUMN motor_id
ADD GENERATED ALWAYS AS IDENTITY;

--8. pasajeros
CREATE TABLE IF NOT EXISTS silver.pasajeros (
    pasajero_id int PRIMARY KEY,
    documento VARCHAR(20) not null,
    tipo_doc VARCHAR(30) not null,
    nacionalidad VARCHAR(2),
    nombre TEXT,
    fecha_nacimiento DATE,
    programa_fidelidad VARCHAR(10),
    categoria VARCHAR(30)
);
 
COMMENT ON TABLE silver.pasajeros
IS 'Datos normalizados de pasajeros, incluyendo identificación, nacionalidad y programa de fidelidad.';

ALTER TABLE silver.pasajeros
ALTER COLUMN pasajero_id
ADD GENERATED ALWAYS AS IDENTITY;
 
--9. vuelos
CREATE TABLE IF NOT EXISTS silver.vuelos (
    vuelo_id int PRIMARY KEY,
    numero_vuelo VARCHAR(10) not null not null,
    aerolinea_id int REFERENCES silver.aerolineas(aerolinea_id) not null,
    aeronave_id int REFERENCES silver.aeronaves(aeronave_id) not null,
    origen_id int REFERENCES silver.aeropuertos(aeropuerto_id) not null,
    destino_id int REFERENCES silver.aeropuertos(aeropuerto_id) not null,
    aerovia_id int REFERENCES silver.aerovias(aerovia_id) not null,
    salida_programada TIMESTAMPTZ not null,
    llegada_programada TIMESTAMPTZ not null,
    salida_real TIMESTAMPTZ,
    llegada_real TIMESTAMPTZ,
    estado VARCHAR(30) CHECK (estado IN ('SCHED','ACTIVE','LANDED','CANCEL','DIVERTED')),
    motivo_desviacion TEXT
);
COMMENT ON TABLE silver.vuelos
IS 'Entidad central de vuelos con planificación y ejecución (horarios programados y reales), aeronave, ruta y estado operativo.';
 
ALTER TABLE silver.vuelos
ADD CONSTRAINT chk_vuelos_fechas
CHECK (llegada_programada >= salida_programada);

ALTER TABLE silver.vuelos
ALTER COLUMN vuelo_id
ADD GENERATED ALWAYS AS IDENTITY;

--10. posicionamiento_vuelo
CREATE TABLE IF NOT EXISTS silver.posicionamiento_vuelo (
    posicion_id BIGSERIAL PRIMARY key not null,
    vuelo_id int REFERENCES silver.vuelos(vuelo_id) not null,
    timestamp_utc TIMESTAMPTZ not null,
    coordenada GEOGRAPHY(POINTZ, 4979),
    velocidad_nudos DECIMAL(6,2),
    heading DECIMAL(5,2),
    fase_vuelo VARCHAR(30) CHECK (fase_vuelo IN ('TAXI','TAKEOFF','CLIMB','CRUISE','DESCENT','APPROACH','LANDING')),
    aerovia_cercana_id int REFERENCES silver.aerovias(aerovia_id) not null,
    desviacion_nm DECIMAL(6,2)
);
 
COMMENT ON TABLE silver.posicionamiento_vuelo
IS 'Datos de posicionamiento de vuelos en el tiempo, incluyendo coordenadas, velocidad, fase de vuelo y relación con aerovías.';

-- 11. pasajeros_vuelo
CREATE TABLE IF NOT EXISTS silver.pasajeros_vuelo (
    pv_id BIGSERIAL PRIMARY key not null,
    vuelo_id int REFERENCES silver.vuelos(vuelo_id) not null,
    pasajero_id int REFERENCES silver.pasajeros(pasajero_id) not null,
    pnr VARCHAR(10),
    clase VARCHAR(5),
    asiento VARCHAR(5) not null,
    tarifa_usd DECIMAL(10,2),
    estado VARCHAR(30) CHECK (estado IN ('CONFIRMED','CHECKED','BOARDED','NOSHOW')),
    equipaje_piezas INT,
    equipaje_peso_kg DECIMAL(5,2)
);
 
COMMENT ON TABLE silver.pasajeros_vuelo
IS 'Relación entre pasajeros y vuelos, incluyendo clase, asiento, estado de viaje y datos de equipaje.';

 
-- 12. equipaje
CREATE TABLE IF NOT EXISTS silver.equipaje (
    equipaje_id int PRIMARY key not null,
    tag_id VARCHAR(20) ,
    pnr_id BIGINT not null,
	vuelo_id int REFERENCES silver.vuelos(vuelo_id) not null,
    peso_kg DECIMAL(5,2) CHECK (peso_kg >= 0),
    tipo VARCHAR(20) CHECK (tipo IN ('NORMAL','FRAGIL','DEPORTIVO','INSTRUMENTO')),
    estado VARCHAR(20) CHECK (estado IN ('CHECKED','LOADED','TRANSFER','UNLOADED','DELIVERED','LOST')),  
    ubicacion_actual VARCHAR(50),
    timestamp_ultimo_evento TIMESTAMPTZ
);

ALTER TABLE silver.equipaje
RENAME COLUMN pnr_id TO pnr;

ALTER TABLE silver.equipaje
ALTER COLUMN pnr TYPE VARCHAR(10);


COMMENT ON TABLE silver.equipaje
IS 'Trazabilidad de equipaje por vuelo y pasajero, incluyendo estado, tipo, peso y última ubicación registrada.';
 
ALTER TABLE silver.equipaje
ALTER COLUMN equipaje_id
ADD GENERATED ALWAYS AS IDENTITY; 

-- 13. carga_vuelo
CREATE TABLE IF NOT EXISTS silver.carga_vuelo (
    carga_id int PRIMARY key not null,
	vuelo_id int REFERENCES silver.vuelos(vuelo_id) not null,
    awb VARCHAR(20) NOT null ,
    shipper TEXT,
    consignee TEXT,
    tipo VARCHAR(20) CHECK (tipo IN   ('GENERAL','PERECIBLE','PELIGROSA','VALORADA','ANIMALES')),
    peso_kg DECIMAL(8,2) CHECK (peso_kg >= 0),
    volumen_m3 DECIMAL(6,2) CHECK (volumen_m3 >= 0),
    origen VARCHAR(4),
    destino VARCHAR(4),
    temperatura_req VARCHAR(10),
    declaracion_aduanera JSONB
);
COMMENT ON TABLE silver.carga_vuelo
IS 'Información de carga aérea por vuelo, incluyendo tipo, peso, volumen, origen, destino y requisitos especiales.';

ALTER TABLE silver.carga_vuelo
ALTER COLUMN carga_id
ADD GENERATED ALWAYS AS IDENTITY;
 
 
-- 14. tripulacion_vuelo
CREATE TABLE IF NOT EXISTS silver.tripulacion_vuelo (
    crew_id int not null PRIMARY key,
	vuelo_id int REFERENCES silver.vuelos(vuelo_id) not null,
    rol VARCHAR(20) CHECK (rol IN ('CAPTAIN','FO','RELIEF_CAPTAIN','PURSER','FA','LOADMASTER')),
    report_time TIMESTAMPTZ not null,
    duty_start TIMESTAMPTZ not null,
    duty_end TIMESTAMPTZ not null,
    horas_vuelo_duty DECIMAL(4,2) CHECK (horas_vuelo_duty >= 0),
    descanso_horas DECIMAL(4,2) CHECK (descanso_horas >= 0),
    descanso_minimo_requerido DECIMAL(4,2) CHECK (descanso_minimo_requerido >= 0),
    descanso_minimo_cumple BOOLEAN CHECK (duty_end >= duty_start)
);
COMMENT ON TABLE silver.tripulacion_vuelo
IS 'Asignación de tripulación a vuelos con control de tiempos de servicio, descanso y cumplimiento de regulaciones.';

ALTER TABLE silver.tripulacion_vuelo
ALTER COLUMN crew_id
ADD GENERATED ALWAYS AS IDENTITY;
 
 
-- 15. talleres_mro
CREATE TABLE IF NOT EXISTS silver.talleres_mro (
    taller_id int PRIMARY KEY,
    nombre TEXT NOT NULL,
    aeropuerto_id int REFERENCES silver.aeropuertos(aeropuerto_id) not null,
    tipo VARCHAR(20) CHECK (tipo IN ('LINE','HANGAR','ENGINE','COMPONENT')),
    capacidad_aeronaves INT CHECK (capacidad_aeronaves >= 0),
    certificaciones TEXT[],
    activo BOOLEAN DEFAULT TRUE
);
COMMENT ON TABLE silver.talleres_mro
IS 'Catálogo de talleres de mantenimiento (MRO) con capacidad, certificaciones y ubicación.';
 
ALTER TABLE silver.talleres_mro
ALTER COLUMN taller_id
ADD GENERATED ALWAYS AS IDENTITY;
 
-- 16. silver.mantenimiento_evento
CREATE TABLE IF NOT EXISTS silver.mantenimiento_eventos (
    mant_id int PRIMARY key not null,
    aeronave_id int REFERENCES silver.aeronaves (aeronave_id) not null,
    motor_id int REFERENCES silver.motores(motor_id) not null,
    tipo_check VARCHAR(10) CHECK (tipo_check IN ('A','B','C','D','LINE')),
    componente VARCHAR(50) not null,
    descripcion TEXT,
    taller_id int references silver.talleres_mro (taller_id),
    tecnico_id int not null,
    horas_aeronave DECIMAL(10,2) CHECK (horas_aeronave >= 0),
    fecha_inicio TIMESTAMPTZ not null,
    fecha_fin TIMESTAMPTZ,
    costo_usd DECIMAL(12,2) CHECK (costo_usd >= 0),
    estado VARCHAR(20) CHECK (estado IN ('OPEN','INPROGRESS','CLOSED','DEFERRED'))
); 
COMMENT ON TABLE silver.mantenimiento_eventos
IS 'Eventos de mantenimiento (MRO) de aeronaves y motores, incluyendo tipo de chequeo, costos, tiempos y estado.';
ALTER TABLE silver.mantenimiento_eventos
ADD CONSTRAINT chk_mantenimiento_fechas
CHECK (fecha_fin >= fecha_inicio);

ALTER TABLE silver.mantenimiento_eventos
ALTER COLUMN mant_id
ADD GENERATED ALWAYS AS IDENTITY;
 
-- 17. combustible_carga
CREATE TABLE IF NOT EXISTS silver.combustible_carga (
    comb_id int PRIMARY key not null,
    vuelo_id int REFERENCES silver.vuelos(vuelo_id) not null,
    aeropuerto_id int REFERENCES silver.aeropuertos(aeropuerto_id) not null,
    litros DECIMAL(10,2) CHECK (litros > 0),
    densidad_kgl DECIMAL(5,3) CHECK (densidad_kgl > 0),
    masa_kg DECIMAL(10,2) CHECK (masa_kg > 0),
    precio_usd_litro DECIMAL(6,4) CHECK (precio_usd_litro >= 0),
    costo_total_usd DECIMAL(12,2) CHECK (costo_total_usd >= 0),
    timestamp_carga TIMESTAMPTZ not null,
    efficiency_planned_kgkm DECIMAL(6,4),
    efficiency_actual_kgkm DECIMAL(6,4)
);
COMMENT ON TABLE silver.combustible_carga
IS 'Registros de carga de combustible por vuelo, incluyendo volumen, masa, costos y métricas de eficiencia.';
 
ALTER TABLE silver.combustible_carga
ALTER COLUMN comb_id
ADD GENERATED ALWAYS AS IDENTITY;
 
-- 18. notams
CREATE TABLE IF NOT EXISTS silver.notams (
    notam_id int PRIMARY KEY,
    ident VARCHAR(20) not null,
    aeropuerto_id int REFERENCES silver.aeropuertos(aeropuerto_id) not null,
    tipo CHAR(1) CHECK (tipo IN ('N','D','R','C')),
    referencia TEXT,
    coordenada GEOGRAPHY(POINT, 4326),
    radio_nm INT CHECK (radio_nm >= 0),
    altura_min INT,
    altura_max INT CHECK (altura_max >= altura_min),
    valido_desde TIMESTAMPTZ,
    valido_hasta TIMESTAMPTZ CHECK (valido_hasta >= valido_desde),
	raw_text TEXT
);
COMMENT ON TABLE silver.notams
IS 'NOTAMs (avisos a navegantes aéreos) con restricciones operativas, ubicación geográfica y periodo de validez.';

ALTER TABLE silver.notams
ALTER COLUMN notam_id
ADD GENERATED ALWAYS AS IDENTITY;
 
 
-- 19.engine_sensors
CREATE TABLE IF NOT EXISTS silver.engine_sensors (
    sensor_id BIGSERIAL PRIMARY key not null,
    engine_id TEXT not null,
    n1_pct FLOAT,
    n2_pct FLOAT,
    egt_c FLOAT,
    fuel_flow_kgh FLOAT,
    vibration FLOAT,
    timestamp_utc TIMESTAMP
);
COMMENT ON TABLE silver.engine_sensors
IS 'Capa silver: data de los sensores de los motores';
 
--20. runways
create table silver.runways (
id int,
airport_ref	varchar(10),
airport_ident int,
length_ft int,
width_ft int,
surface	varchar(20),
lighted	varchar(5),
closed	varchar(5),
le_ident varchar(10),
le_latitude_deg	decimal (10,6),
le_longitude_deg decimal (10,6),
le_elevation_ft int,
le_heading_degT	decimal (5,1),
le_displaced_threshold_ft int,
he_ident varchar (20),
he_latitude_deg	decimal (10,6),
he_longitude_deg decimal (10,6),
he_elevation_ft	int,
he_heading_degT	decimal (5,1),
he_displaced_threshold_ft int
);
COMMENT ON TABLE silver.runways
IS 'Catalago de runways en la capa silver';

select * from silver.runways;

-- ID original del dataset
ALTER TABLE silver.runways
ALTER COLUMN id TYPE BIGINT;

ALTER TABLE silver.runways
ALTER COLUMN airport_ref TYPE BIGINT
USING airport_ref::BIGINT;
-- Código/identificador del aeropuerto
-- Puede traer valores alfanuméricos:
-- 00A, 00AK, KJFK, etc.
ALTER TABLE silver.runways
ALTER COLUMN airport_ident TYPE VARCHAR(10);
-- Longitud de pista
ALTER TABLE silver.runways
ALTER COLUMN length_ft TYPE NUMERIC(8,2);
-- Ancho de pista
ALTER TABLE silver.runways
ALTER COLUMN width_ft TYPE NUMERIC(8,2);
-- Tipo de superficie
ALTER TABLE silver.runways
ALTER COLUMN surface TYPE TEXT;
-- Convierte 0/1 a boolean
ALTER TABLE silver.runways
ALTER COLUMN lighted TYPE BOOLEAN
USING (lighted::INT::BOOLEAN);
-- Convierte 0/1 a boolean
ALTER TABLE silver.runways
ALTER COLUMN closed TYPE BOOLEAN
USING (closed::INT::BOOLEAN);
-- Identificador cabecera izquierda
ALTER TABLE silver.runways
ALTER COLUMN le_ident TYPE VARCHAR(10);
-- Coordenada izquierda latitud
ALTER TABLE silver.runways
ALTER COLUMN le_latitude_deg TYPE DECIMAL(10,6);
-- Coordenada izquierda longitud
ALTER TABLE silver.runways
ALTER COLUMN le_longitude_deg TYPE DECIMAL(10,6);
-- Elevación izquierda
ALTER TABLE silver.runways
ALTER COLUMN le_elevation_ft TYPE INT;
-- Heading izquierdo
ALTER TABLE silver.runways
ALTER COLUMN le_heading_degT TYPE NUMERIC(6,2);
-- Threshold izquierdo
ALTER TABLE silver.runways
ALTER COLUMN le_displaced_threshold_ft TYPE INT;
-- Identificador cabecera derecha
ALTER TABLE silver.runways
ALTER COLUMN he_ident TYPE VARCHAR(10);
-- Coordenada derecha latitud
ALTER TABLE silver.runways
ALTER COLUMN he_latitude_deg TYPE DECIMAL(10,6);
-- Coordenada derecha longitud
ALTER TABLE silver.runways
ALTER COLUMN he_longitude_deg TYPE DECIMAL(10,6);
-- Elevación derecha
ALTER TABLE silver.runways
ALTER COLUMN he_elevation_ft TYPE INT;
-- Heading derecho
ALTER TABLE silver.runways
ALTER COLUMN he_heading_degT TYPE NUMERIC(6,2);
-- Threshold derecho
ALTER TABLE silver.runways
ALTER COLUMN he_displaced_threshold_ft TYPE INT;
 
-- 21.navaids_raw
CREATE TABLE IF NOT EXISTS silver.navaids_raw (
    -- ID original del dataset
    id BIGINT,
    -- Identificador del waypoint/navaid
    filename TEXT,
    ident TEXT,
    name TEXT,
    type TEXT,
    -- Frecuencia
    frequency_khz BIGINT,
    -- Coordenadas principales
    latitude_deg DECIMAL(12,8),
    longitude_deg DECIMAL(12,8),
    -- Elevación
    elevation_ft INT,
    -- País y región
    iso_country TEXT,
    iso_region TEXT,
    -- Información DME
    dme_frequency_khz BIGINT,
    dme_channel TEXT,
    dme_latitude_deg DECIMAL(12,8),
    dme_longitude_deg DECIMAL(12,8),
    dme_elevation_ft INT,
    -- Variaciones magnéticas
    slaved_variation_deg DECIMAL(10,5),
    magnetic_variation_deg DECIMAL(10,5),
    -- Información operacional
    usageType TEXT,
    power TEXT,
    -- Aeropuerto asociado
    associated_airport TEXT

);


INSERT INTO silver.waypoints (
    waypoint_id,
    source_id,
    ident,
    nombre,
    tipo,
    frecuencia_khz,
    latitud_deg,
    longitud_deg,
    elevacion_ft,
    ubicacion,
    iso_country,
    region_code,
    dme_frequency_khz,
    dme_channel,
    dme_latitud_deg,
    dme_longitud_deg,
    dme_elevation_ft,
    slaved_variation_deg,
    magnetic_variation_deg,
    usage_type,
    power,
    associated_airport,
    fuente_archivo
)
SELECT DISTINCT ON (ident)
    ROW_NUMBER() OVER () AS waypoint_id, 
    id AS source_id,
    LEFT(ident,10), 
    LEFT(name,100),
    type AS tipo,
    -- Limpieza frecuencia principal
    CASE
        WHEN frequency_khz >= 0
        THEN frequency_khz
        ELSE NULL
    END AS frecuencia_khz,
    latitude_deg,
    longitude_deg,
    elevation_ft,
    -- Construcción geography
    CASE
        WHEN longitude_deg IS NOT NULL
         AND latitude_deg IS NOT NULL
        THEN ST_SetSRID(
                ST_MakePoint(
                    longitude_deg,
                    latitude_deg,
                    COALESCE(elevation_ft,0)
                ),
                4979
             )::GEOGRAPHY
        ELSE NULL
    END AS ubicacion,
    iso_country,
    iso_region AS region_code,
    -- Limpieza DME frecuencia
    CASE
        WHEN dme_frequency_khz >= 0
        THEN dme_frequency_khz
        ELSE NULL
    END AS dme_frequency_khz,
    LEFT(dme_channel,10),
    dme_latitude_deg,
    dme_longitude_deg, 
    dme_elevation_ft,
    slaved_variation_deg,
    magnetic_variation_deg, 
    LEFT(usageType,10), 
    LEFT(power,20),
    LEFT(associated_airport,10),
    LEFT(filename,100)
FROM silver.navaids_raw
WHERE type IN (
    'VOR',
    'VOR-DME',
    'DME',
    'NDB',
    'NDB-DME',
    'TACAN',
    'INT'
)
 
ORDER BY ident, id;

--22.waypoints
CREATE TABLE IF NOT EXISTS silver.waypoints (
    waypoint_id int PRIMARY KEY,
    source_id INT,
    ident VARCHAR(10) UNIQUE NOT NULL,
    nombre VARCHAR(100),
    tipo VARCHAR(20) CHECK (tipo IN ('VOR','VOR-DME', 'DME', 'NDB','NDB-DME', 'TACAN', 'INT')),
    frecuencia_khz INT CHECK (frecuencia_khz >= 0),
    latitud_deg DECIMAL(10,8) CHECK (latitud_deg BETWEEN -90 AND 90),
    longitud_deg DECIMAL(11,8) CHECK ( longitud_deg BETWEEN -180 AND 180 ),
    elevacion_ft INT,
    ubicacion GEOGRAPHY(POINTZ, 4979),
    iso_country CHAR(2),
    region_code VARCHAR(10),
    dme_frequency_khz INT CHECK (dme_frequency_khz >= 0),
    dme_channel VARCHAR(10),
    dme_latitud_deg DECIMAL(10,6)CHECK (dme_latitud_deg BETWEEN -90 AND 90),
    dme_longitud_deg DECIMAL(11,6) CHECK (dme_longitud_deg BETWEEN -180 AND 180),
    dme_elevation_ft INT,
    slaved_variation_deg DECIMAL(6,3),
    magnetic_variation_deg DECIMAL(6,3),
    usage_type VARCHAR(10),
    power VARCHAR(20),
    associated_airport VARCHAR(10),
    fuente_archivo VARCHAR(100),
    CONSTRAINT fk_waypoints_country FOREIGN KEY (iso_country) REFERENCES silver.countries(code),
    CONSTRAINT fk_waypoints_region FOREIGN KEY (region_code) REFERENCES silver.regions(code)
);


-- =========================================
-- FOREIGN KEY -> countries
-- =========================================

ALTER TABLE silver.waypoints
ADD CONSTRAINT fk_waypoints_country
FOREIGN KEY (iso_country)
REFERENCES silver.countries(code);


-- =========================================
-- FOREIGN KEY -> regions
-- =========================================

ALTER TABLE silver.waypoints
ADD CONSTRAINT fk_waypoints_region
FOREIGN KEY (region_code)
REFERENCES silver.regions(code);
select * from silver.waypoints;
COMMENT ON TABLE silver.runways
IS 'Tabla que almacena waypoints aeronáuticos utilizados como puntos de referencia geográfica para navegación aérea';  


--  INDEX Capa Silver

--indices compuestos
CREATE INDEX IF NOT EXISTS idx_vuelos_aerolinea ON silver.vuelos (aerolinea_id);
CREATE INDEX IF NOT EXISTS idx_vuelos_aeronave ON silver.vuelos (aeronave_id);
CREATE INDEX IF NOT EXISTS idx_vuelos_origen_fecha ON silver.vuelos (origen_id, salida_programada);
CREATE INDEX IF NOT EXISTS idx_vuelos_estado ON silver.vuelos (estado);
CREATE INDEX IF NOT EXISTS idx_tripulacion_crew_fecha ON silver.tripulacion_vuelo (crew_id, duty_start);
CREATE INDEX IF NOT EXISTS idx_tripulacion_vuelo ON silver.tripulacion_vuelo (vuelo_id);
CREATE INDEX IF NOT EXISTS idx_pasajeros_pnr ON silver.pasajeros_vuelo (pnr);
CREATE INDEX IF NOT EXISTS idx_pasajeros_vuelo ON silver.pasajeros_vuelo (vuelo_id);
CREATE INDEX IF NOT EXISTS idx_equipaje_tag ON silver.equipaje (tag_id);
CREATE INDEX IF NOT EXISTS idx_equipaje_vuelo ON silver.equipaje (vuelo_id);
CREATE INDEX IF NOT EXISTS idx_carga_awb ON silver.carga_vuelo (awb);
CREATE INDEX IF NOT EXISTS idx_carga_vuelo ON silver.carga_vuelo (vuelo_id);
CREATE INDEX IF NOT EXISTS idx_combustible_vuelo_fecha ON silver.combustible_carga (vuelo_id, timestamp_carga);
CREATE INDEX IF NOT EXISTS idx_mantenimiento_aeronave_fecha ON silver.mantenimiento_eventos (aeronave_id, fecha_inicio);
CREATE INDEX IF NOT EXISTS idx_mantenimiento_estado ON silver.mantenimiento_eventos (estado);
CREATE INDEX IF NOT EXISTS idx_posicion_vuelo_fecha ON silver.posicionamiento_vuelo (vuelo_id, timestamp_utc);

-- Indice para sensores                                   -- Índice principal temporal
CREATE INDEX idx_engine_sensors_timestamp ON silver.engine_sensors(timestamp_utc);
 -- Índice por motor
CREATE INDEX idx_engine_sensors_engine ON silver.engine_sensors(engine_id);
-- Índice compuesto tiempo + motor
CREATE INDEX idx_engine_sensors_time_engine ON silver.engine_sensors(timestamp_utc, engine_id);
-- Utilizamos GIST para indexar datos geoespaciales, permitiendo hacer consultas eficientes de proximidad y ubicación.
CREATE INDEX IF NOT EXISTS idx_posicion_geo ON silver.posicionamiento_vuelo USING GIST (coordenada);
CREATE INDEX IF NOT EXISTS idx_aeropuerto_geo ON silver.aeropuertos USING GIST (ubicacion);
CREATE INDEX IF NOT EXISTS idx_aerovia_geo ON silver.aerovias USING GIST (geometria);
CREATE INDEX IF NOT EXISTS idx_notams_aeropuerto_fecha ON silver.notams (aeropuerto_id, valido_desde);
CREATE INDEX IF NOT EXISTS idx_notams_geo ON silver.notams USING GIST (coordenada);
CREATE INDEX IF NOT EXISTS idx_aeronave_matricula ON silver.aeronaves (matricula);
CREATE INDEX IF NOT EXISTS idx_motor_aeronave ON silver.motores (aeronave_id);
CREATE INDEX IF NOT EXISTS idx_pasajero_doc ON silver.pasajeros (documento);
 
-- Se implementa un índice compuesto en origen y fecha para optimizar consultas analíticas, además de índices individuales en claves de relación.
--Se priorizaran columnas usadas en joins y filtros frecuentes como vuelo_id, crew_id, pnr y fechas, optimizando consultas analíticas en la capa silver
 
--Los índices se implementaron principalmente en la capa silver, donde se realizan joins y consultas analíticas. En bronze se mantuvieron lo minimo para no afectar la ingesta de datos crudos















































