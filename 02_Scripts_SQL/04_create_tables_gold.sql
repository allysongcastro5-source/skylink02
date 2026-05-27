                                                           --CREATE TABLE IF NOT EXISTS CAPA GOLD
--1. gold.dim_tiempo
CREATE TABLE IF NOT EXISTS gold.dim_tiempo (
    tiempo_id INT PRIMARY KEY,
    fecha DATE NOT NULL,
    anio INT NOT NULL,
    trimestre INT NOT NULL,
    mes INT NOT NULL,
    dia INT NOT NULL,
    dia_semana INT NOT NULL,
    nombre_dia VARCHAR(10) NOT NULL,
    es_fin_semana BOOLEAN ,
    es_festivo BOOLEAN DEFAULT FALSE,
    festivo_nombre VARCHAR(50),
    semana_anio INT ,
    temporada VARCHAR(10) CHECK (temporada IN ('ALTA','MEDIA','BAJA'))
);
COMMENT ON TABLE gold.dim_tiempo IS
'Dimensión de tiempo utilizada para análisis temporales y agregaciones históricas. Contiene atributos de calendario como año, trimestre, mes, semana, festivos y temporadas operacionales.';

--2. gold.dim_aeropuerto
CREATE TABLE IF NOT EXISTS gold.dim_aeropuerto (
    aeropuerto_id INT PRIMARY KEY,
    icao VARCHAR(4) NOT NULL,
    iata VARCHAR(3),
    nombre TEXT,
    ciudad TEXT,
    pais VARCHAR(2) NOT NULL,
    region VARCHAR(20)  CHECK (region IN ('NORTEAMERICA', 'SUDAMERICA', 'EUROPA', 'ASIA', 'AFRICA', 'OCEANIA')),
    zona_horaria VARCHAR(50),
    categoria VARCHAR(20) CHECK (categoria IN ('HUB', 'FOCUS_CITY', 'SPOKE')),
    latitud DECIMAL(10,6),
    longitud DECIMAL(10,6) 
);
COMMENT ON TABLE gold.dim_aeropuerto IS
'Dimensión de aeropuertos utilizada para análisis geográficos y operacionales. Incluye códigos ICAO/IATA, ubicación, región, categoría operacional y zona horaria.';

--3. gold.dim_aeronave
CREATE TABLE IF NOT EXISTS gold.dim_aeronave (
aeronave_id INT PRIMARY KEY,
matricula VARCHAR(10) NOT NULL,
tipo VARCHAR(10),
fabricante VARCHAR(20) CHECK (fabricante IN ('BOEING','AIRBUS','EMBRAER')),
edad_anios DECIMAL(4,1) CHECK (edad_anios >= 0),  
configuracion_total_asientos INT CHECK (configuracion_total_asientos > 0),
configuracion_clases JSONB,
estado VARCHAR(20) NOT NULL
);
COMMENT ON TABLE gold.dim_aeronave IS
'Dimensión de aeronaves con información descriptiva de flota, fabricante, configuración de asientos, antigüedad y estado operativo para análisis de utilización y eficiencia.';

--4. gold.dim_ruta
CREATE TABLE IF NOT EXISTS gold.dim_ruta (
ruta_id INT PRIMARY KEY,
origen_icao VARCHAR(4) NOT NULL,
destino_icao VARCHAR(4) NOT NULL,
distancia_nm DECIMAL(8,2),
distancia_km DECIMAL(8,2) CHECK (distancia_km > 0),
duracion_estimada_min INT CHECK (duracion_estimada_min > 0),
tipo_ruta VARCHAR(20) CHECK (tipo_ruta IN ('CORTO_HAUL','MEDIO_HAUL','LARGO_HAUL','ULTRA_LARGO')),
mercado VARCHAR(20) CHECK (mercado IN ('DOMESTICO','REGIONAL','INTERCONTINENTAL'))
);
COMMENT ON TABLE gold.dim_ruta IS
'Dimensión de rutas aéreas que representa conexiones origen-destino, distancias, duración estimada y clasificación operacional y comercial de las rutas.';

--5. gold.dim_pasajero_segmento
CREATE TABLE IF NOT EXISTS gold.dim_pasajero_segmento (
pasajero_id INT PRIMARY KEY,
categoria_fidelidad VARCHAR(10),
segmento VARCHAR(20) CHECK (segmento IN ('LEISURE','BUSINESS','VFR','MICE')),
frecuencia_anual VARCHAR(10),
valor_estimado_usd DECIMAL(10,2)
);
COMMENT ON TABLE gold.dim_pasajero_segmento IS
'Dimensión analítica de segmentación de pasajeros, utilizada para análisis comerciales, fidelización, comportamiento de viaje y valor estimado del cliente.';

--6.gold.dim_tripulacion_rol
CREATE TABLE IF NOT EXISTS gold.dim_tripulacion_rol (
rol_id INT PRIMARY KEY,
rol VARCHAR(20),
tipo VARCHAR(10) CHECK (tipo IN ('COCKPIT','CABIN')),
minimo_descanso_horas DECIMAL(4,2) CHECK (minimo_descanso_horas >= 0),
maximo_duty_horas DECIMAL(4,2) CHECK (maximo_duty_horas >= 0)
);
COMMENT ON TABLE gold.dim_tripulacion_rol IS
'Dimensión de roles de tripulación utilizada para análisis operacionales y regulatorios. Incluye clasificación de roles, límites de duty y requisitos mínimos de descanso.';


-- 1. gold.hechos_vuelo
CREATE TABLE IF NOT EXISTS gold.hechos_vuelo (
hecho_id BIGSERIAL,
tiempo_id INT NOT NULL REFERENCES gold.dim_tiempo(tiempo_id),
aerolinea_id INT,
ruta_id INT REFERENCES gold.dim_ruta(ruta_id),
aeronave_id INT REFERENCES gold.dim_aeronave(aeronave_id),
    -- Métricas KPI Pasajeros
vuelos_totales INT DEFAULT 1,
asientos_ofrecidos INT,
asientos_vendidos INT,
pax_transportados INT,
pax_no_show INT DEFAULT 0,
    -- Métricas KPI Carga
cargo_revenue_usd DECIMAL(12,2),
passenger_revenue_usd DECIMAL(12,2),
total_revenue_usd DECIMAL(12,2),
    -- Métricas KPI Costos
fuel_cost_usd DECIMAL(12,2),
operating_cost_usd DECIMAL(12,2),
    -- Métricas KPI Tiempo
block_time_min DECIMAL(8,2),
airborne_time_min DECIMAL(8,2),
taxi_time_min DECIMAL(8,2),
delay_min INT DEFAULT 0,
delay_code VARCHAR(20) CHECK (delay_code IN ('ATC', 'WEATHER', 'TECHNICAL', 'CREW', 'GROUND', 'PASSENGER', 'SECURITY')),
    -- Métricas KPI Vuelo
fuel_consumed_kg DECIMAL(10,2),
co2_emitted_ton DECIMAL(8,2),
distance_flown_nm DECIMAL(8,2),
distance_flown_km DECIMAL(8,2),
altitude_max_ft INT,
speed_avg_kts DECIMAL(6,2),
    PRIMARY KEY (hecho_id, tiempo_id)
)
PARTITION BY RANGE (tiempo_id);


-- 2. gold.hechos_pasajero
CREATE TABLE IF NOT EXISTS gold.hechos_pasajero (
hecho_id BIGSERIAL,
tiempo_id INT NOT NULL REFERENCES gold.dim_tiempo(tiempo_id),
ruta_id INT REFERENCES gold.dim_ruta(ruta_id),
pasajero_id INT REFERENCES gold.dim_pasajero_segmento(pasajero_id),
    -- Métricas KPI
pax_count INT DEFAULT 0,
revenue_pax_km NUMERIC(12,2),
yield_usd_rpk NUMERIC(8,4),
load_factor_pct NUMERIC(5,2),
baggage_count INT DEFAULT 0,
baggage_weight_kg NUMERIC(7,2),
baggage_lost_count INT DEFAULT 0,
upgrade_count INT DEFAULT 0,
downgrade_count INT DEFAULT 0,
special_assistance_count INT DEFAULT 0,
PRIMARY KEY (hecho_id, tiempo_id)
)
PARTITION BY RANGE (tiempo_id);

-- 3. gold.hechos_mantenimiento
CREATE TABLE IF NOT EXISTS gold.hechos_mantenimiento (
hecho_id BIGSERIAL,
tiempo_id INT NOT NULL REFERENCES gold.dim_tiempo(tiempo_id),
aeronave_id INT REFERENCES gold.dim_aeronave(aeronave_id),
    -- KPIs
events_count INT DEFAULT 0,
man_hours NUMERIC(6,2),
cost_labor_usd NUMERIC(10,2),
cost_parts_usd NUMERIC(10,2),
cost_total_usd NUMERIC(10,2),
aog_hours NUMERIC(6,2),
delay_caused_min INT DEFAULT 0,
deferrals_count INT DEFAULT 0,
component_changes_count INT DEFAULT 0,
PRIMARY KEY (hecho_id, tiempo_id)
)
PARTITION BY RANGE (tiempo_id);


-- 4. gold.hechos_carga
CREATE TABLE IF NOT EXISTS gold.hechos_carga (
    hecho_id BIGSERIAL,
    tiempo_id INT NOT NULL
        REFERENCES gold.dim_tiempo(tiempo_id),
    ruta_id INT
        REFERENCES gold.dim_ruta(ruta_id),
    -- Métricas KPI
    cargo_weight_kg DECIMAL(6,2),
    cargo_volume_m3 DECIMAL(6,2),
    cargo_revenue_usd DECIMAL(12,2),
    yield_usd_kgkm DECIMAL(6,4),
    cargo_type_breakdown JSONB,
    perishable_count INT DEFAULT 0,
    dangerous_goods_count INT DEFAULT 0,
    customs_hold_count INT DEFAULT 0,

    clearance_time_avg_hours DECIMAL(6,2),

    PRIMARY KEY (hecho_id, tiempo_id)
)
PARTITION BY RANGE (tiempo_id);

-- 5. gold.hechos_combustible
CREATE TABLE IF NOT EXISTS gold.hechos_combustible (
    hecho_id BIGSERIAL,
    tiempo_id INT NOT NULL
        REFERENCES gold.dim_tiempo(tiempo_id),
    aeropuerto_id INT
        REFERENCES gold.dim_aeropuerto(aeropuerto_id),
    aeronave_id INT
        REFERENCES gold.dim_aeronave(aeronave_id),
    fuel_uplift_kg DECIMAL(10,2)
        CHECK (fuel_uplift_kg >= 0),
    fuel_consumed_kg DECIMAL(10,2)
        CHECK (fuel_consumed_kg >= 0),
    fuel_price_avg_usd_kg DECIMAL(6,4)
        CHECK (fuel_price_avg_usd_kg >= 0),
    fuel_cost_total_usd DECIMAL(12,2)
        CHECK (fuel_cost_total_usd >= 0),
    efficiency_kg_km DECIMAL(6,4)
        CHECK (efficiency_kg_km >= 0),
    efficiency_variation_pct DECIMAL(5,2),
    co2_per_pax_km DECIMAL(6,4)
        CHECK (co2_per_pax_km >= 0),
    alternative_fuel_pct DECIMAL(5,2)
        CHECK (alternative_fuel_pct BETWEEN 0 AND 100),

    PRIMARY KEY (hecho_id, tiempo_id)
)
PARTITION BY RANGE (tiempo_id);

-- 6. gold.hechos_tripulacion
CREATE TABLE IF NOT EXISTS gold.hechos_tripulacion (
    hecho_id BIGSERIAL,
    tiempo_id INT NOT NULL
        REFERENCES gold.dim_tiempo(tiempo_id),
    rol_id INT
        REFERENCES gold.dim_tripulacion_rol(rol_id),
    -- Métricas KPIs
    crew_count INT DEFAULT 0
        CHECK (crew_count >= 0),
    duty_hours DECIMAL(6,2)
        CHECK (duty_hours >= 0),
    flight_hours DECIMAL(6,2)
        CHECK (flight_hours >= 0),
    layover_hours DECIMAL(6,2)
        CHECK (layover_hours >= 0),
    per_diem_cost_usd DECIMAL(10,2)
        CHECK (per_diem_cost_usd >= 0),
    training_hours DECIMAL(6,2)
        CHECK (training_hours >= 0),
    fatigue_events INT DEFAULT 0
        CHECK (fatigue_events >= 0),
    crew_pairing_efficiency_pct DECIMAL(5,2)
        CHECK (
            crew_pairing_efficiency_pct BETWEEN 0 AND 100
        ),
   PRIMARY KEY (hecho_id, tiempo_id)
)
PARTITION BY RANGE (tiempo_id);

-- =========================================
--  INDEX Capa gold
-- =========================================

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


-- PARTICIONES PARA gold.hechos_pasajero
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

-- PARTICIONES PARA gold.hechos_carga
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

-- PARTICIONES PARA gold.hechos_mantenimiento
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

-- PARTICIONES PARA gold.hechos_combustible
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

-- PARTICIONES PARA gold.hechos_tripulacion
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


--  PARTICIONES                                                      
CREATE TABLE IF NOT EXISTS gold.hechos_vuelo_2026_01
PARTITION OF gold.hechos_vuelo
FOR VALUES FROM (20260101) TO (20260201);
 
CREATE TABLE IF NOT EXISTS gold.hechos_vuelo_2026_02
PARTITION OF gold.hechos_vuelo
FOR VALUES FROM (20260201) TO (20260301);
 
CREATE TABLE IF NOT EXISTS gold.hechos_vuelo_2026_03
PARTITION OF gold.hechos_vuelo
FOR VALUES FROM (20260301) TO (20260401);
 
CREATE TABLE IF NOT EXISTS gold.hechos_vuelo_2026_04
PARTITION OF gold.hechos_vuelo
FOR VALUES FROM (20260401) TO (20260501);
 
CREATE TABLE IF NOT EXISTS gold.hechos_vuelo_2026_05
PARTITION OF gold.hechos_vuelo
FOR VALUES FROM (20260501) TO (20260601);
 
CREATE TABLE IF NOT EXISTS gold.hechos_vuelo_2026_06
PARTITION OF gold.hechos_vuelo
FOR VALUES FROM (20260601) TO (20260701);
 
CREATE TABLE IF NOT EXISTS gold.hechos_vuelo_2026_07
PARTITION OF gold.hechos_vuelo
FOR VALUES FROM (20260701) TO (20260801);
 
CREATE TABLE IF NOT EXISTS gold.hechos_vuelo_2026_08
PARTITION OF gold.hechos_vuelo
FOR VALUES FROM (20260801) TO (20260901);
 
CREATE TABLE IF NOT EXISTS gold.hechos_vuelo_2026_09
PARTITION OF gold.hechos_vuelo
FOR VALUES FROM (20260901) TO (20261001);
 
CREATE TABLE IF NOT EXISTS gold.hechos_vuelo_2026_10
PARTITION OF gold.hechos_vuelo
FOR VALUES FROM (20261001) TO (20261101);
 
CREATE TABLE IF NOT EXISTS gold.hechos_vuelo_2026_11
PARTITION OF gold.hechos_vuelo
FOR VALUES FROM (20261101) TO (20261201);
 
CREATE TABLE IF NOT EXISTS gold.hechos_vuelo_2026_12
PARTITION OF gold.hechos_vuelo
FOR VALUES FROM (20261201) TO (20270101);
 
-- PARTICION DEFAULT 
CREATE TABLE IF NOT EXISTS gold.hechos_vuelo_default
PARTITION OF gold.hechos_vuelo
DEFAULT;                               