                                                                  --CREATE TABLE IF NOT EXISTS CAPA BRONZE
 -- 1. UUID PRIMARY KEY DEFAULT gen_random_uuid(),
CREATE TABLE IF NOT EXISTS bronze.raw_adsb_positions (
    adsb_id BIGSERIAL PRIMARY KEY,
    icao24 TEXT,
    ubicacion geography(POINT, 4326),  -- lon/lat juntos
    altitud_pies FLOAT,               
    velocidad_nudos FLOAT,
    heading FLOAT,
    timestamp_utc TIMESTAMP,
    raw_json JSONB,
    fecha_ingesta TIMESTAMPTZ default now(),
    fuente varchar(50) default 'ADS-B Exchange'
);

COMMENT ON TABLE bronze.raw_adsb_positions IS 'Tecnología de posicionamiento de aeronaves. JSON para compatibilidad dinámica.';
SELECT obj_description('bronze.raw_adsb_positions'::regclass);

--2. bronze.raw_flight_plans
CREATE TABLE IF NOT EXISTS bronze.raw_flight_plans (
    plan_id BIGSERIAL PRIMARY KEY,
    callsign TEXT,
    origen_icao TEXT,
    destino_icao TEXT,
    aerovia TEXT,
    niveles TEXT,
    eta TIMESTAMP,
    raw_xml xml,
    fecha_ingesta TIMESTAMPTZ default now()
);

COMMENT ON TABLE bronze.raw_flight_plans IS 'Planes de vuelo ICAO formato xml crudo.';
SELECT obj_description('bronze.raw_flight_plans'::regclass);

--3.bronze.raw_reservations
CREATE TABLE IF NOT EXISTS bronze.raw_reservations (
    reserva_id BIGSERIAL PRIMARY KEY,
    pnr TEXT,
    pasajero_json JSONB,
    vuelos_json JSONB,
    clase TEXT,
    tarifa_usd NUMERIC(10,2),
    estado TEXT,
    timestamp_utc TIMESTAMP,
    fecha_ingesta TIMESTAMPTZ default now()
);


COMMENT ON TABLE bronze.raw_reservations IS 'Datos crudos de reservas de pasajeros (PNR). Incluye información del pasajero y vuelos en formato JSON, clase, tarifa y estado.';
SELECT obj_description('bronze.raw_reservations'::regclass);

--4.bronze.raw_boarding
CREATE TABLE IF NOT EXISTS bronze.raw_boarding (
    boarding_id BIGSERIAL PRIMARY KEY,
    pnr TEXT,
    vuelo_id TEXT,
    asiento TEXT,
    gate TEXT,
    grupo_embarque TEXT,
    timestamp_utc TIMESTAMP,
    fecha_ingesta TIMESTAMPTZ default now()
);

COMMENT ON TABLE bronze.raw_boarding IS 'Datos crudos del proceso de embarque. Contiene información de asiento puerta grupo de embarque y relación con el vuelo.'; 


--5.bronze.raw_baggage
CREATE TABLE IF NOT EXISTS bronze.raw_baggage (
    baggage_id  BIGSERIAL PRIMARY KEY,
    tag_id TEXT,
    pnr TEXT,
    vuelo_id TEXT,
    aeropuerto TEXT,
    evento TEXT,
    timestamp_utc TIMESTAMPTZ,
    fecha_ingesta TIMESTAMPTZ default now()
);

ALTER TABLE bronze.raw_baggage
RENAME COLUMN pnr_id TO pnr;



COMMENT ON TABLE bronze.raw_baggage IS 'Informacion de equipaje asociados a un vuelo. Incluye tracking por aeropuerto, tipo de evento y timestamp.';
SELECT obj_description('bronze.raw_baggage'::regclass);

--6.bronze.raw_cargo
CREATE TABLE IF NOT EXISTS bronze.raw_cargo (
    awb TEXT PRIMARY KEY,
    vuelo_id TEXT,
    tipo_carga TEXT,
    peso_kg FLOAT,
    volumen_m3 FLOAT,
    origen TEXT,
    destino TEXT,
    fecha_ingesta TIMESTAMPTZ default now(),
    declaracion_json JSONB
 
);
COMMENT ON TABLE bronze.raw_cargo IS 'Datos crudos de carga aérea. Incluye tipo de carga, peso, volumen, origen, destino y declaración en formato JSON.';
 
--7.bronze.raw_engine_sensors
CREATE TABLE IF NOT EXISTS bronze.raw_engine_sensors (
    sensor_id BIGSERIAL PRIMARY KEY,
    engine_id TEXT,
    n1_pct FLOAT,
    n2_pct FLOAT,
    egt_c FLOAT,
    fuel_flow_kgh FLOAT,
    vibration FLOAT,
    timestamp_utc TIMESTAMP,
    fecha_ingesta TIMESTAMPTZ default now()
);
COMMENT ON TABLE bronze.raw_engine_sensors IS 'Lecturas crudas de sensores de motores de aeronaves. Incluye métricas como N1, N2, EGT, flujo de combustible y vibración.';
 
 --8. bronze.raw_maintenance
CREATE TABLE IF NOT EXISTS bronze.raw_maintenance (
    evento_id BIGSERIAL PRIMARY KEY,
    aeronave_id TEXT,
    componente TEXT,
    accion TEXT,
    taller_id TEXT,
    tecnico_id TEXT,
    horas_aeronave FLOAT,
    timestamp_utc TIMESTAMP,
    fecha_ingesta TIMESTAMPTZ default now()
);
COMMENT ON TABLE bronze.raw_maintenance IS 'Eventos crudos de mantenimiento de aeronaves. Contiene información de componentes, acciones realizadas, técnico, taller y horas de uso.';

--9.bronze.raw_fuel
CREATE TABLE IF NOT EXISTS bronze.raw_fuel (
    fuel_id BIGSERIAL PRIMARY KEY,
    vuelo_id TEXT,
    aeropuerto_icao TEXT,
    litros FLOAT,
    densidad_kgl FLOAT,
    precio_usd NUMERIC(10,2),
    timestamp_utc TIMESTAMP,
    fecha_ingesta TIMESTAMPTZ default now()
);
COMMENT ON TABLE bronze.raw_fuel IS 'Datos crudos de abastecimiento de combustible por vuelo y aeropuerto. Incluye volumen, densidad y costo en USD.';

 --10. bronze.raw_crew 
CREATE TABLE IF NOT EXISTS bronze.raw_crew (
    roster_id BIGSERIAL PRIMARY KEY,
    vuelo_id TEXT,
    crew_id TEXT,
    rol TEXT,
    report_time TIMESTAMP,
    duty_hours FLOAT,
    fecha_ingesta TIMESTAMPTZ default now()
);
COMMENT ON TABLE bronze.raw_crew IS 'Datos crudos de asignación de tripulación por vuelo. Incluye rol, tiempo de reporte y horas de servicio.';         

--INDICES PARA CAPA BRONZE(Busquedas rapidas en crudos)
CREATE INDEX idx_adsb_timestamp ON bronze.raw_adsb_positions (timestamp_utc);
 -- En la capa bronze se implementan índices mínimos para no afectar la velocidad de ingesta de datos crudos

CREATE INDEX IF NOT EXISTS idx_bronze_flight_plans_callsing ON bronze.raw_flight_plans (callsign);
CREATE INDEX IF NOT EXISTS idx_bronze_reservations_pnr ON bronze.raw_reservations (pnr);
CREATE INDEX IF NOT EXISTS idx_bronze_boarding_vuelo ON bronze.raw_boarding (vuelo_id);
CREATE INDEX IF NOT EXISTS idx_bronze_cargo_awb ON bronze.raw_cargo (awb);
CREATE INDEX IF NOT EXISTS idx_bronze_fuel_vuelo ON bronze.raw_fuel (vuelo_id);
CREATE INDEX IF NOT EXISTS idx_bronze_maintenance_aeronave ON bronze.raw_maintenance (aeronave_id);

--GIN para busqueda en JSON crudo 
CREATE INDEX IF NOT EXISTS idx_bronze_adsb_json ON bronze.raw_adsb_positions using GIN (raw_json);
CREATE INDEX IF NOT EXISTS idx_bronze_boarding_json ON bronze.raw_boarding using GIN (raw_json);

--Mensaje confirmacion
do $$
begin
	raise notice 'Capa Bronze creada: 10 tablas raw configuradas';
    raise notice 'Tablas: raw_adbs_positions, raw_flight_plans, raw_reservation, raw_boarding, raw_baggage, raw_cargo, raw_engine_sensors, raw_maintenance, raw_fuel, raw_crew';
end $$;








































                                                                  