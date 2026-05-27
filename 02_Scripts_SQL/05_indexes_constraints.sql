                                                       --INDEXES AND CONSTRAINTS
                        --INDICES CAPA BRONZE 
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

                   --INDICES CAPA SILVER 
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

                         --INDICES CAPA GOLD
---INDICES Dim.GOLD
 
-- DIM_TIEMPO
CREATE INDEX idx_dim_tiempo_anio_mes ON gold.dim_tiempo(anio, mes);
-- DIM_AEROPUERTO
CREATE UNIQUE INDEX idx_dim_aeropuerto_icao ON gold.dim_aeropuerto(icao); 
CREATE UNIQUE INDEX idx_dim_aeropuerto_iata ON gold.dim_aeropuerto(iata); 
-- DIM_AERONAVE
CREATE UNIQUE INDEX idx_dim_aeronave_matricula ON gold.dim_aeronave(matricula); 
CREATE INDEX idx_dim_aeronave_fabricante ON gold.dim_aeronave(fabricante);
-- DIM_RUTA
CREATE INDEX idx_dim_ruta_origen_destino ON gold.dim_ruta(origen_icao, destino_icao);
-- DIM_PASAJERO_SEGMENTO
CREATE INDEX idx_dim_pasajero_segmento ON gold.dim_pasajero_segmento(segmento);

---INDICES hechos.GOLD
CREATE INDEX idx_hechos_vuelo_tiempo ON gold.hechos_vuelo(tiempo_id);
CREATE INDEX idx_hechos_vuelo_ruta ON gold.hechos_vuelo(ruta_id);
CREATE INDEX idx_hechos_vuelo_aeronave ON gold.hechos_vuelo(aeronave_id);
CREATE INDEX idx_hechos_vuelo_delay_code ON gold.hechos_vuelo(delay_code);

CREATE INDEX idx_hechos_pasajero_tiempo ON gold.hechos_pasajero(tiempo_id);
CREATE INDEX idx_hechos_pasajero_ruta ON gold.hechos_pasajero(ruta_id);
CREATE INDEX idx_hechos_pasajero_segmento ON gold.hechos_pasajero(pasajero_id);

CREATE INDEX idx_hechos_carga_tiempo ON gold.hechos_carga(tiempo_id);
CREATE INDEX idx_hechos_carga_ruta ON gold.hechos_carga(ruta_id);

CREATE INDEX idx_hechos_mantenimiento_tiempo ON gold.hechos_mantenimiento(tiempo_id);
CREATE INDEX idx_hechos_mantenimiento_aeronave ON gold.hechos_mantenimiento(aeronave_id);
CREATE INDEX idx_hechos_combustible_tiempo ON gold.hechos_combustible(tiempo_id);

CREATE INDEX idx_hechos_combustible_aeronave ON gold.hechos_combustible(aeronave_id);
CREATE INDEX idx_hechos_combustible_aeropuerto ON gold.hechos_combustible(aeropuerto_id);

CREATE INDEX idx_hechos_tripulacion_tiempo ON gold.hechos_tripulacion(tiempo_id);
CREATE INDEX idx_hechos_tripulacion_rol ON gold.hechos_tripulacion(rol_id);

-- ===========================================================
-- PARTICIONES PARA gold.hechos_pasajero
-- ===========================================================
CREATE TABLE IF NOT EXISTS gold.hechos_pasajero_2026_01 PARTITION OF gold.hechos_pasajero FOR VALUES FROM (20260101) TO (20260201);
CREATE TABLE IF NOT EXISTS gold.hechos_pasajero_2026_02 PARTITION OF gold.hechos_pasajero FOR VALUES FROM (20260201) TO (20260301);
CREATE TABLE IF NOT EXISTS gold.hechos_pasajero_2026_03 PARTITION OF gold.hechos_pasajero FOR VALUES FROM (20260301) TO (20260401);
CREATE TABLE IF NOT EXISTS gold.hechos_pasajero_2026_04 PARTITION OF gold.hechos_pasajero FOR VALUES FROM (20260401) TO (20260501);
CREATE TABLE IF NOT EXISTS gold.hechos_pasajero_2026_05 PARTITION OF gold.hechos_pasajero FOR VALUES FROM (20260501) TO (20260601);
CREATE TABLE IF NOT EXISTS gold.hechos_pasajero_2026_06 PARTITION OF gold.hechos_pasajero FOR VALUES FROM (20260601) TO (20260701);
CREATE TABLE IF NOT EXISTS gold.hechos_pasajero_2026_07 PARTITION OF gold.hechos_pasajero FOR VALUES FROM (20260701) TO (20260801);
CREATE TABLE IF NOT EXISTS gold.hechos_pasajero_2026_08 PARTITION OF gold.hechos_pasajero FOR VALUES FROM (20260801) TO (20260901);
CREATE TABLE IF NOT EXISTS gold.hechos_pasajero_2026_09 PARTITION OF gold.hechos_pasajero FOR VALUES FROM (20260901) TO (20261001);
CREATE TABLE IF NOT EXISTS gold.hechos_pasajero_2026_10 PARTITION OF gold.hechos_pasajero FOR VALUES FROM (20261001) TO (20261101);
CREATE TABLE IF NOT EXISTS gold.hechos_pasajero_2026_11 PARTITION OF gold.hechos_pasajero FOR VALUES FROM (20261101) TO (20261201);
CREATE TABLE IF NOT EXISTS gold.hechos_pasajero_2026_12 PARTITION OF gold.hechos_pasajero FOR VALUES FROM (20261201) TO (20270101);
CREATE TABLE IF NOT EXISTS gold.hechos_pasajero_default PARTITION OF gold.hechos_pasajero DEFAULT;

-- ===========================================================
-- PARTICIONES PARA gold.hechos_carga
-- ===========================================================
CREATE TABLE IF NOT EXISTS gold.hechos_carga_2026_01 PARTITION OF gold.hechos_carga FOR VALUES FROM (20260101) TO (20260201);
CREATE TABLE IF NOT EXISTS gold.hechos_carga_2026_02 PARTITION OF gold.hechos_carga FOR VALUES FROM (20260201) TO (20260301);
CREATE TABLE IF NOT EXISTS gold.hechos_carga_2026_03 PARTITION OF gold.hechos_carga FOR VALUES FROM (20260301) TO (20260401);
CREATE TABLE IF NOT EXISTS gold.hechos_carga_2026_04 PARTITION OF gold.hechos_carga FOR VALUES FROM (20260401) TO (20260501);
CREATE TABLE IF NOT EXISTS gold.hechos_carga_2026_05 PARTITION OF gold.hechos_carga FOR VALUES FROM (20260501) TO (20260601);
CREATE TABLE IF NOT EXISTS gold.hechos_carga_2026_06 PARTITION OF gold.hechos_carga FOR VALUES FROM (20260601) TO (20260701);
CREATE TABLE IF NOT EXISTS gold.hechos_carga_2026_07 PARTITION OF gold.hechos_carga FOR VALUES FROM (20260701) TO (20260801);
CREATE TABLE IF NOT EXISTS gold.hechos_carga_2026_08 PARTITION OF gold.hechos_carga FOR VALUES FROM (20260801) TO (20260901);
CREATE TABLE IF NOT EXISTS gold.hechos_carga_2026_09 PARTITION OF gold.hechos_carga FOR VALUES FROM (20260901) TO (20261001);
CREATE TABLE IF NOT EXISTS gold.hechos_carga_2026_10 PARTITION OF gold.hechos_carga FOR VALUES FROM (20261001) TO (20261101);
CREATE TABLE IF NOT EXISTS gold.hechos_carga_2026_11 PARTITION OF gold.hechos_carga FOR VALUES FROM (20261101) TO (20261201);
CREATE TABLE IF NOT EXISTS gold.hechos_carga_2026_12 PARTITION OF gold.hechos_carga FOR VALUES FROM (20261201) TO (20270101);
CREATE TABLE IF NOT EXISTS gold.hechos_carga_default PARTITION OF gold.hechos_carga DEFAULT;

-- ===========================================================
-- PARTICIONES PARA gold.hechos_mantenimiento
-- ===========================================================
CREATE TABLE IF NOT EXISTS gold.hechos_mantenimiento_2026_01 PARTITION OF gold.hechos_mantenimiento FOR VALUES FROM (20260101) TO (20260201);
CREATE TABLE IF NOT EXISTS gold.hechos_mantenimiento_2026_02 PARTITION OF gold.hechos_mantenimiento FOR VALUES FROM (20260201) TO (20260301);
CREATE TABLE IF NOT EXISTS gold.hechos_mantenimiento_2026_03 PARTITION OF gold.hechos_mantenimiento FOR VALUES FROM (20260301) TO (20260401);
CREATE TABLE IF NOT EXISTS gold.hechos_mantenimiento_2026_04 PARTITION OF gold.hechos_mantenimiento FOR VALUES FROM (20260401) TO (20260501);
CREATE TABLE IF NOT EXISTS gold.hechos_mantenimiento_2026_05 PARTITION OF gold.hechos_mantenimiento FOR VALUES FROM (20260501) TO (20260601);
CREATE TABLE IF NOT EXISTS gold.hechos_mantenimiento_2026_06 PARTITION OF gold.hechos_mantenimiento FOR VALUES FROM (20260601) TO (20260701);
CREATE TABLE IF NOT EXISTS gold.hechos_mantenimiento_2026_07 PARTITION OF gold.hechos_mantenimiento FOR VALUES FROM (20260701) TO (20260801);
CREATE TABLE IF NOT EXISTS gold.hechos_mantenimiento_2026_08 PARTITION OF gold.hechos_mantenimiento FOR VALUES FROM (20260801) TO (20260901);
CREATE TABLE IF NOT EXISTS gold.hechos_mantenimiento_2026_09 PARTITION OF gold.hechos_mantenimiento FOR VALUES FROM (20260901) TO (20261001);
CREATE TABLE IF NOT EXISTS gold.hechos_mantenimiento_2026_10 PARTITION OF gold.hechos_mantenimiento FOR VALUES FROM (20261001) TO (20261101);
CREATE TABLE IF NOT EXISTS gold.hechos_mantenimiento_2026_11 PARTITION OF gold.hechos_mantenimiento FOR VALUES FROM (20261101) TO (20261201);
CREATE TABLE IF NOT EXISTS gold.hechos_mantenimiento_2026_12 PARTITION OF gold.hechos_mantenimiento FOR VALUES FROM (20261201) TO (20270101);
CREATE TABLE IF NOT EXISTS gold.hechos_mantenimiento_default PARTITION OF gold.hechos_mantenimiento DEFAULT;

-- ===========================================================
-- PARTICIONES PARA gold.hechos_combustible
-- ===========================================================
CREATE TABLE IF NOT EXISTS gold.hechos_combustible_2026_01 PARTITION OF gold.hechos_combustible FOR VALUES FROM (20260101) TO (20260201);
CREATE TABLE IF NOT EXISTS gold.hechos_combustible_2026_02 PARTITION OF gold.hechos_combustible FOR VALUES FROM (20260201) TO (20260301);
CREATE TABLE IF NOT EXISTS gold.hechos_combustible_2026_03 PARTITION OF gold.hechos_combustible FOR VALUES FROM (20260301) TO (20260401);
CREATE TABLE IF NOT EXISTS gold.hechos_combustible_2026_04 PARTITION OF gold.hechos_combustible FOR VALUES FROM (20260401) TO (20260501);
CREATE TABLE IF NOT EXISTS gold.hechos_combustible_2026_05 PARTITION OF gold.hechos_combustible FOR VALUES FROM (20260501) TO (20260601);
CREATE TABLE IF NOT EXISTS gold.hechos_combustible_2026_06 PARTITION OF gold.hechos_combustible FOR VALUES FROM (20260601) TO (20260701);
CREATE TABLE IF NOT EXISTS gold.hechos_combustible_2026_07 PARTITION OF gold.hechos_combustible FOR VALUES FROM (20260701) TO (20260801);
CREATE TABLE IF NOT EXISTS gold.hechos_combustible_2026_08 PARTITION OF gold.hechos_combustible FOR VALUES FROM (20260801) TO (20260901);
CREATE TABLE IF NOT EXISTS gold.hechos_combustible_2026_09 PARTITION OF gold.hechos_combustible FOR VALUES FROM (20260901) TO (20261001);
CREATE TABLE IF NOT EXISTS gold.hechos_combustible_2026_10 PARTITION OF gold.hechos_combustible FOR VALUES FROM (20261001) TO (20261101);
CREATE TABLE IF NOT EXISTS gold.hechos_combustible_2026_11 PARTITION OF gold.hechos_combustible FOR VALUES FROM (20261101) TO (20261201);
CREATE TABLE IF NOT EXISTS gold.hechos_combustible_2026_12 PARTITION OF gold.hechos_combustible FOR VALUES FROM (20261201) TO (20270101);
CREATE TABLE IF NOT EXISTS gold.hechos_combustible_default PARTITION OF gold.hechos_combustible DEFAULT;

-- ===========================================================
-- PARTICIONES PARA gold.hechos_tripulacion
-- ===========================================================
CREATE TABLE IF NOT EXISTS gold.hechos_tripulacion_2026_01 PARTITION OF gold.hechos_tripulacion FOR VALUES FROM (20260101) TO (20260201);
CREATE TABLE IF NOT EXISTS gold.hechos_tripulacion_2026_02 PARTITION OF gold.hechos_tripulacion FOR VALUES FROM (20260201) TO (20260301);
CREATE TABLE IF NOT EXISTS gold.hechos_tripulacion_2026_03 PARTITION OF gold.hechos_tripulacion FOR VALUES FROM (20260301) TO (20260401);
CREATE TABLE IF NOT EXISTS gold.hechos_tripulacion_2026_04 PARTITION OF gold.hechos_tripulacion FOR VALUES FROM (20260401) TO (20260501);
CREATE TABLE IF NOT EXISTS gold.hechos_tripulacion_2026_05 PARTITION OF gold.hechos_tripulacion FOR VALUES FROM (20260501) TO (20260601);
CREATE TABLE IF NOT EXISTS gold.hechos_tripulacion_2026_06 PARTITION OF gold.hechos_tripulacion FOR VALUES FROM (20260601) TO (20260701);
CREATE TABLE IF NOT EXISTS gold.hechos_tripulacion_2026_07 PARTITION OF gold.hechos_tripulacion FOR VALUES FROM (20260701) TO (20260801);
CREATE TABLE IF NOT EXISTS gold.hechos_tripulacion_2026_08 PARTITION OF gold.hechos_tripulacion FOR VALUES FROM (20260801) TO (20260901);
CREATE TABLE IF NOT EXISTS gold.hechos_tripulacion_2026_09 PARTITION OF gold.hechos_tripulacion FOR VALUES FROM (20260901) TO (20261001);
CREATE TABLE IF NOT EXISTS gold.hechos_tripulacion_2026_10 PARTITION OF gold.hechos_tripulacion FOR VALUES FROM (20261001) TO (20261101);
CREATE TABLE IF NOT EXISTS gold.hechos_tripulacion_2026_11 PARTITION OF gold.hechos_tripulacion FOR VALUES FROM (20261101) TO (20261201);
CREATE TABLE IF NOT EXISTS gold.hechos_tripulacion_2026_12 PARTITION OF gold.hechos_tripulacion FOR VALUES FROM (20261201) TO (20270101);
CREATE TABLE IF NOT EXISTS gold.hechos_tripulacion_default PARTITION OF gold.hechos_tripulacion DEFAULT;












































