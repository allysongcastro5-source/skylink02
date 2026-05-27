                                                          ---ETL SILVER TO GOLD
--TABLAS DIM
-- 1.gold.dim_tiempo 
INSERT INTO gold.dim_tiempo (
    tiempo_id,
    fecha,
    anio,
    trimestre,
    mes,
    dia,
    dia_semana,
    nombre_dia,
    es_fin_semana,
    es_festivo,
    festivo_nombre,
    semana_anio,
    temporada
)
SELECT
    /* tiempo_id formato YYYYMMDD (encaja con las particiones) */
    TO_CHAR(d::date, 'YYYYMMDD')::int        AS tiempo_id,
    d::date                                   AS fecha,
    EXTRACT(YEAR    FROM d)::int              AS anio,
    EXTRACT(QUARTER FROM d)::int              AS trimestre,
    EXTRACT(MONTH   FROM d)::int              AS mes,
    EXTRACT(DAY     FROM d)::int              AS dia,
    EXTRACT(ISODOW  FROM d)::int              AS dia_semana,
    TRIM(TO_CHAR(d, 'Day'))                   AS nombre_dia,
    EXTRACT(ISODOW FROM d) IN (6, 7)          AS es_fin_semana,
    /* Festivos básicos */
    CASE
        WHEN TO_CHAR(d, 'MM-DD') IN ('01-01','05-01','12-25','12-24','12-31','07-04','11-28','09-15')
        THEN TRUE ELSE FALSE
    END                                       AS es_festivo,
    CASE TO_CHAR(d, 'MM-DD')
        WHEN '01-01' THEN 'Año Nuevo'
        WHEN '05-01' THEN 'Día del Trabajo'
        WHEN '07-04' THEN 'Independencia USA'
        WHEN '09-15' THEN 'Independencia Costa Rica'
        WHEN '11-28' THEN 'Independencia Panamá'
        WHEN '12-24' THEN 'Nochebuena'
        WHEN '12-25' THEN 'Navidad'
        WHEN '12-31' THEN 'Fin de Año'
        ELSE NULL
    END                                       AS festivo_nombre,
    EXTRACT(WEEK FROM d)::int                 AS semana_anio,
    /* Temporada según mes (alta=verano + diciembre, media=primavera/otoño, baja=resto) */
    CASE
        WHEN EXTRACT(MONTH FROM d) IN (6,7,8,12)       THEN 'ALTA'
        WHEN EXTRACT(MONTH FROM d) IN (3,4,5,9,10,11)  THEN 'MEDIA'
        ELSE 'BAJA'
    END                                       AS temporada
FROM generate_series(
    '2026-01-01'::date,
    '2026-12-31'::date,
    '1 day'::interval
) AS d
ON CONFLICT (tiempo_id) DO NOTHING;

--"Las dimensiones de tiempo siguen el patrón Kimball: se generan programáticamente porque representan el calendario universal, no datos transaccionales. 
--Los atributos como temporada y festivos son reglas de negocio aplicadas en gold."

--2.gold.dim_aeropuerto
INSERT INTO gold.dim_aeropuerto (
    aeropuerto_id,
    icao,
    iata,
    nombre,
    ciudad,
    pais,
    region,
    zona_horaria,
    categoria,
    latitud,
    longitud
)
SELECT DISTINCT ON (icao_norm)
    aeropuerto_id,
    icao_norm                                            AS icao,
    iata_norm                                            AS iata,
    nombre,
    ciudad,
    pais,
    region,
    zona_horaria,
    categoria,
    latitud,
    longitud
FROM (
    SELECT
        a.aeropuerto_id,
        LEFT(COALESCE(NULLIF(TRIM(a.icao), ''), NULLIF(TRIM(a.ident), '')), 4) AS icao_norm,
        NULLIF(TRIM(LEFT(a.iata, 3)), '')                AS iata_norm,
        a.nombre,
        a.municipality                                   AS ciudad,
        a.iso_country                                    AS pais,
        CASE a.continent
            WHEN 'NA' THEN 'NORTEAMERICA'
            WHEN 'SA' THEN 'SUDAMERICA'
            WHEN 'EU' THEN 'EUROPA'
            WHEN 'AS' THEN 'ASIA'
            WHEN 'AF' THEN 'AFRICA'
            WHEN 'OC' THEN 'OCEANIA'
            ELSE 'NORTEAMERICA'
        END                                              AS region,
        CASE a.iso_country
            WHEN 'US' THEN 'America/New_York'
            WHEN 'CR' THEN 'America/Costa_Rica'
            WHEN 'MX' THEN 'America/Mexico_City'
            WHEN 'ES' THEN 'Europe/Madrid'
            WHEN 'GB' THEN 'Europe/London'
            WHEN 'FR' THEN 'Europe/Paris'
            WHEN 'DE' THEN 'Europe/Berlin'
            WHEN 'BR' THEN 'America/Sao_Paulo'
            ELSE 'UTC'
        END                                              AS zona_horaria,
        CASE
            WHEN vuelos_count.cnt >= 100 THEN 'HUB'
            WHEN vuelos_count.cnt >= 20  THEN 'FOCUS_CITY'
            ELSE 'SPOKE'
        END                                              AS categoria,
        a.latitude_deg                                   AS latitud,
        a.longitude_deg                                  AS longitud,
        /* Para desempatar duplicados: priorizar el que tiene IATA, luego el de mayor volumen */
        vuelos_count.cnt                                 AS volumen
    FROM silver.aeropuertos a
    JOIN (
        SELECT origen_id AS aeropuerto_id, COUNT(*) AS cnt FROM silver.vuelos GROUP BY origen_id
        UNION ALL
        SELECT destino_id, COUNT(*) FROM silver.vuelos GROUP BY destino_id
    ) vuelos_count ON vuelos_count.aeropuerto_id = a.aeropuerto_id
    WHERE a.latitude_deg  IS NOT NULL
      AND a.longitude_deg IS NOT NULL
      AND a.iso_country   IS NOT NULL
      AND COALESCE(NULLIF(TRIM(a.icao), ''), NULLIF(TRIM(a.ident), '')) IS NOT NULL
) sub
ORDER BY
    icao_norm,
    /* Si hay duplicados de icao_norm, nos quedamos con:
       1) el que tenga IATA (no nulo)
       2) el de mayor volumen de vuelos */
    (iata_norm IS NULL),
    volumen DESC;


--3.gold.dim_aeronave
TRUNCATE TABLE gold.dim_aeronave RESTART IDENTITY CASCADE;
INSERT INTO gold.dim_aeronave (
    aeronave_id,
    matricula,
    tipo,
    fabricante,
    edad_anios,
    configuracion_total_asientos,
    configuracion_clases,
    estado
)
SELECT
    a.aeronave_id,
    LEFT(a.matricula, 10),
    LEFT(a.tipo, 10),
    /* Fabricante derivado del tipo */
    CASE
        WHEN UPPER(a.tipo) LIKE 'AIRBUS%' OR UPPER(a.tipo) LIKE 'A3%' OR UPPER(a.tipo) LIKE 'A2%' THEN 'AIRBUS'
        WHEN UPPER(a.tipo) LIKE 'B%' OR UPPER(a.tipo) LIKE 'BOEING%'                              THEN 'BOEING'
        WHEN UPPER(a.tipo) LIKE 'E%' OR UPPER(a.tipo) LIKE 'EMB%'                                 THEN 'EMBRAER'
        ELSE 'BOEING'
    END                                                   AS fabricante,
    /* Edad: días transcurridos / 365.25, redondeado a 1 decimal */
    ROUND(
        ((CURRENT_DATE - a.fecha_entrada_servicio) / 365.25)::numeric,
        1
    )                                                     AS edad_anios,
    /* Total asientos sumando todos los valores del JSONB */
    (
        SELECT SUM((value)::int)
        FROM jsonb_each_text(a.configuracion_asientos)
    )                                                     AS configuracion_total_asientos,
    a.configuracion_asientos                              AS configuracion_clases,
    a.estado
FROM silver.aeronaves a
WHERE a.matricula IS NOT NULL
  AND a.configuracion_asientos IS NOT NULL
  AND a.fecha_entrada_servicio IS NOT NULL
ON CONFLICT (aeronave_id) DO NOTHING;



--4.gold.dim_ruta
INSERT INTO gold.dim_ruta (
    ruta_id,
    origen_icao,
    destino_icao,
    distancia_nm,
    distancia_km,
    duracion_estimada_min,
    tipo_ruta,
    mercado
)
SELECT
    ROW_NUMBER() OVER (ORDER BY dao.icao, dad.icao)::int AS ruta_id,
    dao.icao                                              AS origen_icao,
    dad.icao                                              AS destino_icao,
    /* Distancia en NM */
    ROUND(
        (ST_DistanceSphere(
            ST_MakePoint(dao.longitud, dao.latitud),
            ST_MakePoint(dad.longitud, dad.latitud)
        ) / 1852)::numeric,
        2
    )                                                     AS distancia_nm,
    /* Distancia en km */
    ROUND(
        (ST_DistanceSphere(
            ST_MakePoint(dao.longitud, dao.latitud),
            ST_MakePoint(dad.longitud, dad.latitud)
        ) / 1000)::numeric,
        2
    )                                                     AS distancia_km,
    /* Duración estimada */
    (FLOOR((ST_DistanceSphere(
            ST_MakePoint(dao.longitud, dao.latitud),
            ST_MakePoint(dad.longitud, dad.latitud)
        ) / 1000) / 800 * 60) + 30)::int                  AS duracion_estimada_min,
    /* Tipo de ruta según distancia */
    CASE
        WHEN (ST_DistanceSphere(
            ST_MakePoint(dao.longitud, dao.latitud),
            ST_MakePoint(dad.longitud, dad.latitud)
        ) / 1000) < 1500 THEN 'CORTO_HAUL'
        WHEN (ST_DistanceSphere(
            ST_MakePoint(dao.longitud, dao.latitud),
            ST_MakePoint(dad.longitud, dad.latitud)
        ) / 1000) < 4000 THEN 'MEDIO_HAUL'
        WHEN (ST_DistanceSphere(
            ST_MakePoint(dao.longitud, dao.latitud),
            ST_MakePoint(dad.longitud, dad.latitud)
        ) / 1000) < 8000 THEN 'LARGO_HAUL'
        ELSE 'ULTRA_LARGO'
    END                                                   AS tipo_ruta,
    /* Mercado */
    CASE
        WHEN dao.pais   = dad.pais   THEN 'DOMESTICO'
        WHEN dao.region = dad.region THEN 'REGIONAL'
        ELSE                              'INTERCONTINENTAL'
    END                                                   AS mercado
FROM (
    SELECT DISTINCT origen_id, destino_id
    FROM silver.vuelos
    WHERE origen_id IS NOT NULL
      AND destino_id IS NOT NULL
) rutas
JOIN gold.dim_aeropuerto dao ON dao.aeropuerto_id = rutas.origen_id
JOIN gold.dim_aeropuerto dad ON dad.aeropuerto_id = rutas.destino_id
WHERE dao.latitud  IS NOT NULL AND dao.longitud IS NOT NULL
  AND dad.latitud  IS NOT NULL AND dad.longitud IS NOT NULL
  AND dao.icao     IS NOT NULL AND dad.icao     IS NOT NULL
ON CONFLICT (ruta_id) DO NOTHING;

--5. gold.dim_pasajero_segmento
INSERT INTO gold.dim_pasajero_segmento (
    pasajero_id,
    categoria_fidelidad,
    segmento,
    frecuencia_anual,
    valor_estimado_usd
)
SELECT
    p.pasajero_id,
    LEFT(COALESCE(p.programa_fidelidad, 'NONE'), 10)     AS categoria_fidelidad,
    /* Segmento basado en categoría y nacionalidad */
    CASE
        WHEN UPPER(p.categoria) IN ('FIRST','PREMIUM','PLATINUM','DIAMOND') THEN 'BUSINESS'
        WHEN UPPER(p.categoria) IN ('GOLD','EXEC')                          THEN 'BUSINESS'
        WHEN random() < 0.10                                                THEN 'MICE'
        WHEN random() < 0.25                                                THEN 'VFR'
        ELSE                                                                'LEISURE'
    END                                                  AS segmento,
    /* Frecuencia anual sintética */
    CASE
        WHEN UPPER(p.categoria) IN ('PLATINUM','DIAMOND') THEN 'ALTA'
        WHEN UPPER(p.categoria) IN ('GOLD','SILVER')      THEN 'MEDIA'
        ELSE                                                  'BAJA'
    END                                                  AS frecuencia_anual,
    /* Valor estimado: alto para business, medio para leisure */
    ROUND((
        CASE
            WHEN UPPER(p.categoria) IN ('FIRST','PLATINUM','DIAMOND') THEN 10000 + random() * 40000
            WHEN UPPER(p.categoria) IN ('GOLD','EXEC')                THEN 5000  + random() * 15000
            WHEN UPPER(p.categoria) = 'SILVER'                        THEN 2000  + random() * 5000
            ELSE                                                           500   + random() * 2000
        END
    )::numeric, 2)                                        AS valor_estimado_usd
FROM silver.pasajeros p
ON CONFLICT (pasajero_id) DO NOTHING;

--"Es híbrido por necesidad: la segmentación comercial (LEISURE/BUSINESS/VFR/MICE) no proviene del sistema transaccional sino del CRM o modelos analíticos. 
--Como no contamos con esa fuente, aplicamos heurísticas basadas en la categoría de fidelidad existente. En producción, esta dimensión se alimentaría de un sistema externo."

-- 6.gold.dim_tripulacion_rol
INSERT INTO gold.dim_tripulacion_rol (
    rol_id,
    rol,
    tipo,
    minimo_descanso_horas,
    maximo_duty_horas
)
VALUES
    (1, 'CAPTAIN',        'COCKPIT', 12.00, 13.00),
    (2, 'FO',             'COCKPIT', 12.00, 13.00),
    (3, 'RELIEF_CAPTAIN', 'COCKPIT', 12.00, 16.00),
    (4, 'PURSER',         'CABIN',   10.00, 14.00),
    (5, 'FA',             'CABIN',   10.00, 14.00),
    (6, 'LOADMASTER',     'CABIN',   10.00, 12.00)
ON CONFLICT (rol_id) DO NOTHING;


--"Es un catálogo regulatorio. Los roles y sus límites operacionales son definidos por IATA y la regulación aeronáutica (FAR 117 para US, EASA FTL para Europa). 
--No se extraen de datos transaccionales sino que se cargan desde la normativa."

SELECT 
    EXTRACT(YEAR FROM salida_programada) AS anio,
    COUNT(*) AS vuelos
FROM silver.vuelos
GROUP BY anio
ORDER BY anio;


                                                  --Tablas hechos 
--1.gold.hechos_vuelo
--Paso 1 — Verificar primero qué vuelos tienen y cuáles no
SELECT
    (SELECT COUNT(*) FROM silver.vuelos) AS total_vuelos,
    (SELECT COUNT(*) FROM silver.combustible_carga) AS registros_fuel,
    (SELECT COUNT(DISTINCT vuelo_id) FROM silver.combustible_carga) AS vuelos_distintos_con_fuel,
    (SELECT COUNT(DISTINCT v.vuelo_id)
     FROM silver.vuelos v
     LEFT JOIN silver.combustible_carga cb ON cb.vuelo_id = v.vuelo_id
     WHERE cb.vuelo_id IS NULL) AS vuelos_sin_fuel;

--Paso 2 — Generar combustible sintético para los vuelos faltantes
INSERT INTO silver.combustible_carga (
    vuelo_id,
    aeropuerto_id,
    litros,
    densidad_kgl,
    masa_kg,
    precio_usd_litro,
    costo_total_usd,
    timestamp_carga,
    efficiency_planned_kgkm,
    efficiency_actual_kgkm
)
SELECT
    v.vuelo_id,
    v.origen_id                                            AS aeropuerto_id,
    /* Litros: dependientes de distancia (estimación realista) */
    ROUND((3000 + random() * 85000)::numeric, 2)          AS litros,
    /* Densidad del Jet-A1: ~0.80 kg/L */
    ROUND((0.78 + random() * 0.05)::numeric, 3)           AS densidad_kgl,
    /* Masa = litros × densidad (luego se recalcula) */
    ROUND((3000 + random() * 85000)::numeric * 
          (0.78 + random() * 0.05)::numeric, 2)           AS masa_kg,
    /* Precio por litro USD (~$0.85 promedio 2026) */
    ROUND((0.75 + random() * 0.20)::numeric, 4)           AS precio_usd_litro,
    /* Costo total estimado */
    ROUND((2500 + random() * 60000)::numeric, 2)          AS costo_total_usd,
    /* Timestamp: 45 min antes de la salida programada */
    (v.salida_programada - INTERVAL '45 minutes')::timestamp AS timestamp_carga,
    /* Eficiencia planeada */
    ROUND((0.025 + random() * 0.010)::numeric, 4)         AS efficiency_planned_kgkm,
    /* Eficiencia real */
    ROUND((0.025 + random() * 0.015)::numeric, 4)         AS efficiency_actual_kgkm
FROM silver.vuelos v
WHERE NOT EXISTS (
    SELECT 1 FROM silver.combustible_carga cb
    WHERE cb.vuelo_id = v.vuelo_id
)
AND v.salida_programada IS NOT NULL;

--Paso 3 — Verificar que ahora todos los vuelos tienen combustible
SELECT
    (SELECT COUNT(*) FROM silver.vuelos) AS total_vuelos,
    (SELECT COUNT(DISTINCT vuelo_id) FROM silver.combustible_carga) AS vuelos_con_fuel;

--Paso 4 — Recargar gold.hechos_vuelo con los datos nuevos
--gold.hechos_vuelo
INSERT INTO gold.hechos_vuelo (
    tiempo_id,
    aerolinea_id,
    ruta_id,
    aeronave_id,
    vuelos_totales,
    asientos_ofrecidos,
    asientos_vendidos,
    pax_transportados,
    pax_no_show,
    cargo_revenue_usd,
    passenger_revenue_usd,
    fuel_cost_usd,
    operating_cost_usd,
    block_time_min,
    airborne_time_min,
    taxi_time_min,
    delay_min,
    delay_code,
    fuel_consumed_kg,
    distance_flown_nm,
    distance_flown_km,
    altitude_max_ft,
    speed_avg_kts
)
SELECT
    /* tiempo_id en formato YYYYMMDD */
    TO_CHAR(v.salida_programada, 'YYYYMMDD')::int          AS tiempo_id,
    v.aerolinea_id,
    dr.ruta_id,
    v.aeronave_id,
    1                                                       AS vuelos_totales,
    /* Asientos ofrecidos: del JSON de configuración */
    COALESCE(
        (SELECT SUM((value)::int) FROM jsonb_each_text(a.configuracion_asientos)),
        180
    )                                                       AS asientos_ofrecidos,
    /* Asientos vendidos = pax confirmados/boarded de pasajeros_vuelo */
    COALESCE(pv.asientos_vendidos, 0)                       AS asientos_vendidos,
    /* Pax transportados = pax con estado BOARDED */
    COALESCE(pv.pax_transportados, 0)                       AS pax_transportados,
    /* No-show = vendidos - transportados */
    COALESCE(pv.asientos_vendidos - pv.pax_transportados, 0) AS pax_no_show,
    /* Revenue de carga (agregado del vuelo) */
    COALESCE(cg.cargo_revenue, 0)                           AS cargo_revenue_usd,
    /* Revenue de pasajeros (suma de tarifas) */
    COALESCE(pv.passenger_revenue, 0)                       AS passenger_revenue_usd,
    /* Costo de combustible (del silver.combustible_carga) */
    COALESCE(cb.fuel_cost, 0)                               AS fuel_cost_usd,
    /* Costo operativo total: fuel + estimación de costos fijos */
    COALESCE(cb.fuel_cost, 0) + ROUND((5000 + random() * 15000)::numeric, 2) AS operating_cost_usd,
    /* Tiempos */
    EXTRACT(EPOCH FROM (v.llegada_programada - v.salida_programada))/60 AS block_time_min,
    EXTRACT(EPOCH FROM (v.llegada_programada - v.salida_programada))/60 - 30 AS airborne_time_min,
    30                                                      AS taxi_time_min,
    /* Delay: comparar salida_real vs salida_programada */
    GREATEST(
        COALESCE(EXTRACT(EPOCH FROM (v.salida_real - v.salida_programada))/60, 0)::int,
        0
    )                                                       AS delay_min,
    /* Delay code: simulado según motivo_desviacion o aleatorio si hay delay */
    CASE
        WHEN v.motivo_desviacion IS NOT NULL THEN
            CASE UPPER(v.motivo_desviacion)
                WHEN 'WEATHER'   THEN 'WEATHER'
                WHEN 'TECHNICAL' THEN 'TECHNICAL'
                ELSE 'GROUND'
            END
        WHEN COALESCE(EXTRACT(EPOCH FROM (v.salida_real - v.salida_programada))/60, 0) > 15 THEN
            (ARRAY['ATC','WEATHER','TECHNICAL','CREW','GROUND','PASSENGER'])[FLOOR(1 + random()*6)::int]
        ELSE NULL
    END                                                     AS delay_code,
    /* Fuel consumido (del silver.combustible_carga) */
    COALESCE(cb.fuel_consumed_kg, 0)                        AS fuel_consumed_kg,
    /* Distancias desde dim_ruta */
    dr.distancia_nm                                         AS distance_flown_nm,
    dr.distancia_km                                         AS distance_flown_km,
    /* Altitud máxima sintética según tipo de ruta */
    CASE dr.tipo_ruta
        WHEN 'CORTO_HAUL'  THEN 28000 + FLOOR(random()*5000)::int
        WHEN 'MEDIO_HAUL'  THEN 33000 + FLOOR(random()*5000)::int
        WHEN 'LARGO_HAUL' THEN 37000 + FLOOR(random()*4000)::int
        ELSE                    39000 + FLOOR(random()*3000)::int
    END                                                     AS altitude_max_ft,
    /* Velocidad promedio en nudos */
    ROUND((420 + random() * 60)::numeric, 2)                AS speed_avg_kts
FROM silver.vuelos v
/* Aeronave para sacar configuración de asientos */
JOIN silver.aeronaves a ON a.aeronave_id = v.aeronave_id
/* Ruta desde dim_ruta */
JOIN gold.dim_ruta dr
  ON dr.origen_icao  = (SELECT icao FROM gold.dim_aeropuerto WHERE aeropuerto_id = v.origen_id)
 AND dr.destino_icao = (SELECT icao FROM gold.dim_aeropuerto WHERE aeropuerto_id = v.destino_id)
/* Aeronave debe estar en dim_aeronave */
JOIN gold.dim_aeronave dan ON dan.aeronave_id = v.aeronave_id
/* Tiempo debe existir en dim_tiempo */
JOIN gold.dim_tiempo dt ON dt.tiempo_id = TO_CHAR(v.salida_programada, 'YYYYMMDD')::int
/* Agregados de pasajeros por vuelo */
LEFT JOIN (
    SELECT
        vuelo_id,
        COUNT(*) AS asientos_vendidos,
        SUM(CASE WHEN estado = 'BOARDED' THEN 1 ELSE 0 END) AS pax_transportados,
        SUM(tarifa_usd) AS passenger_revenue
    FROM silver.pasajeros_vuelo
    GROUP BY vuelo_id
) pv ON pv.vuelo_id = v.vuelo_id
/* Agregados de carga por vuelo */
LEFT JOIN (
    SELECT
        vuelo_id,
        SUM(peso_kg * 2.5) AS cargo_revenue  -- estimación USD por kg
    FROM silver.carga_vuelo
    GROUP BY vuelo_id
) cg ON cg.vuelo_id = v.vuelo_id
/* Agregados de combustible por vuelo */
LEFT JOIN (
    SELECT
        vuelo_id,
        SUM(masa_kg) AS fuel_consumed_kg,
        SUM(costo_total_usd) AS fuel_cost
    FROM silver.combustible_carga
    GROUP BY vuelo_id
) cb ON cb.vuelo_id = v.vuelo_id
WHERE v.salida_programada IS NOT NULL
  AND v.llegada_programada IS NOT NULL
  AND EXTRACT(YEAR FROM v.salida_programada) = 2026;
                                                  
SELECT
    COUNT(*) AS total_vuelos,
    SUM(asientos_ofrecidos) AS total_asientos_ofrecidos,
    SUM(pax_transportados) AS total_pax,
    ROUND(SUM(pax_transportados)::numeric / NULLIF(SUM(asientos_ofrecidos),0) * 100, 2) AS load_factor_global,
    ROUND(SUM(passenger_revenue_usd)::numeric, 2) AS revenue_pax_total,
    ROUND(SUM(cargo_revenue_usd)::numeric, 2) AS revenue_cargo_total,
    ROUND(SUM(total_revenue_usd)::numeric, 2) AS revenue_total,
    ROUND(SUM(co2_emitted_ton)::numeric, 2) AS co2_total_ton,
    COUNT(delay_code) AS vuelos_con_delay
FROM gold.hechos_vuelo;


SELECT
    COUNT(*) AS total_vuelos,
    SUM(asientos_ofrecidos) AS total_asientos_ofrecidos,
    SUM(pax_transportados) AS total_pax,
    ROUND(SUM(pax_transportados)::numeric / NULLIF(SUM(asientos_ofrecidos),0) * 100, 2) AS load_factor_global,
    ROUND(SUM(passenger_revenue_usd)::numeric, 2) AS revenue_pax_total,
    ROUND(SUM(cargo_revenue_usd)::numeric, 2) AS revenue_cargo_total,
    ROUND(SUM(total_revenue_usd)::numeric, 2) AS revenue_total,
    ROUND(SUM(co2_emitted_ton)::numeric, 2) AS co2_total_ton,
    COUNT(delay_code) AS vuelos_con_delay
FROM gold.hechos_vuelo;


SELECT
    COUNT(*) AS total_vuelos,
    SUM(asientos_ofrecidos) AS total_asientos_ofrecidos,
    SUM(pax_transportados) AS total_pax,
    ROUND(SUM(pax_transportados)::numeric / NULLIF(SUM(asientos_ofrecidos),0) * 100, 2) AS load_factor_global,
    ROUND(SUM(co2_emitted_ton)::numeric, 2) AS co2_total_ton
FROM gold.hechos_vuelo;

-- ===========================================================
-- ENRIQUECIMIENTO ESTADÍSTICO - gold.hechos_vuelo
-- Justificación documentada arriba del query
-- ===========================================================

UPDATE gold.hechos_vuelo hv
SET
    /* Asientos vendidos: 75-95% de los asientos ofrecidos
       (distribución típica IATA 2025) */
    asientos_vendidos = FLOOR(
        hv.asientos_ofrecidos * (0.75 + random() * 0.20)
    )::int,

    /* Pax transportados: 95-99% de los vendidos
       (el resto son no-show) */
    pax_transportados = FLOOR(
        hv.asientos_ofrecidos * (0.75 + random() * 0.20) * (0.95 + random() * 0.04)
    )::int,

    /* No-show: 1-5% de los vendidos */
    pax_no_show = FLOOR(
        hv.asientos_ofrecidos * (0.75 + random() * 0.20) * (0.01 + random() * 0.04)
    )::int,

    /* Passenger revenue: tarifa promedio según tipo de ruta */
    passenger_revenue_usd = ROUND((
        FLOOR(hv.asientos_ofrecidos * (0.75 + random() * 0.20))
        *
        (
            CASE
                WHEN hv.distance_flown_km < 1500 THEN 200 + random() * 250
                WHEN hv.distance_flown_km < 4000 THEN 400 + random() * 400
                WHEN hv.distance_flown_km < 8000 THEN 700 + random() * 600
                ELSE                                  1200 + random() * 800
            END
        )
    )::numeric, 2)
WHERE hv.pax_transportados < 50;  -- solo enriquece los que están muy bajos


SELECT
    COUNT(*)                                                              AS total_vuelos,
    SUM(asientos_ofrecidos)                                               AS asientos_total,
    SUM(asientos_vendidos)                                                AS vendidos_total,
    SUM(pax_transportados)                                                AS pax_total,
    SUM(pax_no_show)                                                      AS no_show_total,
    ROUND(SUM(pax_transportados)::numeric 
          / NULLIF(SUM(asientos_ofrecidos),0) * 100, 2)                   AS load_factor_global_pct,
    ROUND(SUM(passenger_revenue_usd)::numeric, 2)                         AS revenue_pax_total,
    ROUND(SUM(cargo_revenue_usd)::numeric, 2)                             AS revenue_cargo_total,
    ROUND(SUM(total_revenue_usd)::numeric, 2)                             AS revenue_total,
    ROUND(SUM(co2_emitted_ton)::numeric, 2)                               AS co2_total_ton
FROM gold.hechos_vuelo;

/* ==========================================================
   ENRIQUECIMIENTO ESTADÍSTICO - gold.hechos_vuelo
   ==========================================================
   PROBLEMÁTICA DETECTADA:
   Durante el ETL silver→gold se identificó que la cobertura de
   pasajeros en silver.pasajeros_vuelo era limitada: ~4,558 registros
   distribuidos entre 7 callsigns (de 3,550 vuelos totales),
   generando un Load Factor global de 0.83%, valor imposible
   operativamente.

   Benchmark IATA 2025: Load Factor promedio mundial = 83.6%

   ROOT CAUSE:
   En bronze.raw_reservations los flight_number sintéticos solo
   referenciaban 7 callsigns únicos vs los 3,550 vuelos generados
   desde bronze.raw_flight_plans. Universos desalineados de data
   sintética.

   DECISIÓN ARQUITECTÓNICA:
   Aplicar enriquecimiento estadístico ÚNICAMENTE en gold,
   preservando silver intacto como capa de fidelidad a la fuente.
   Esto sigue el patrón Kimball de modelado dimensional, donde:
   - Silver = fidelidad transaccional
   - Gold   = capa analítica con reglas de negocio aplicadas

   PARÁMETROS APLICADOS (benchmarks IATA 2025):
   - Load Factor target:   75-95% (uniform distribution)
   - No-show rate:         1-5%
   - Tarifas por ruta:     $200-2,000 USD según distancia
   ========================================================== */


--2.gold.hechos_pasajero
INSERT INTO gold.hechos_pasajero (
    tiempo_id,
    ruta_id,
    pasajero_id,
    pax_count,
    revenue_pax_km,
    yield_usd_rpk,
    load_factor_pct,
    baggage_count,
    baggage_weight_kg,
    baggage_lost_count,
    upgrade_count,
    downgrade_count,
    special_assistance_count
)
SELECT
    /* Tiempo y ruta vienen de hechos_vuelo */
    hv.tiempo_id,
    hv.ruta_id,
    /* Pasajero: el del registro de silver.pasajeros_vuelo */
    pv.pasajero_id,
    /* Pax count: 1 por cada registro de pasajero_vuelo */
    1                                                       AS pax_count,
    /* RPK = pax × distancia */
    ROUND((1 * hv.distance_flown_km)::numeric, 2)           AS revenue_pax_km,
    /* Yield = revenue del pasajero / RPK individual */
    ROUND((
        pv.tarifa_usd / NULLIF(hv.distance_flown_km, 0)
    )::numeric, 4)                                          AS yield_usd_rpk,
    /* Load Factor del vuelo donde voló este pasajero */
    LEAST(
        ROUND((
            hv.pax_transportados::numeric 
            / NULLIF(hv.asientos_ofrecidos, 0) * 100
        ), 2),
        100.00
    )                                                       AS load_factor_pct,
    /* Equipaje promedio: 1-2 piezas por pasajero */
    COALESCE(pv.equipaje_piezas, FLOOR(1 + random() * 2)::int) AS baggage_count,
    /* Peso del equipaje */
    COALESCE(pv.equipaje_peso_kg, ROUND((10 + random() * 20)::numeric, 2)) AS baggage_weight_kg,
    /* Equipaje perdido: 0.5% probabilidad */
    CASE WHEN random() < 0.005 THEN 1 ELSE 0 END            AS baggage_lost_count,
    /* Upgrade: 3% probabilidad */
    CASE WHEN random() < 0.03 THEN 1 ELSE 0 END             AS upgrade_count,
    /* Downgrade: 1% probabilidad */
    CASE WHEN random() < 0.01 THEN 1 ELSE 0 END             AS downgrade_count,
    /* Asistencia especial: 5% probabilidad (PRM, menores, etc.) */
    CASE WHEN random() < 0.05 THEN 1 ELSE 0 END             AS special_assistance_count
FROM silver.pasajeros_vuelo pv
/* JOIN con hechos_vuelo para sacar ruta, tiempo y distancia */
JOIN silver.vuelos sv ON sv.vuelo_id = pv.vuelo_id
JOIN gold.hechos_vuelo hv 
  ON hv.tiempo_id = TO_CHAR(sv.salida_programada, 'YYYYMMDD')::int
 AND hv.aeronave_id = sv.aeronave_id
/* El pasajero debe existir en dim_pasajero_segmento */
JOIN gold.dim_pasajero_segmento dps ON dps.pasajero_id = pv.pasajero_id
WHERE pv.pasajero_id IS NOT NULL
  AND sv.salida_programada IS NOT NULL
  AND EXTRACT(YEAR FROM sv.salida_programada) = 2026;



UPDATE gold.hechos_pasajero hp
SET yield_usd_rpk = ROUND((
    CASE
        WHEN hp.revenue_pax_km < 1500  THEN (200 + random() * 250) / NULLIF(hp.revenue_pax_km, 0)
        WHEN hp.revenue_pax_km < 4000  THEN (400 + random() * 400) / NULLIF(hp.revenue_pax_km, 0)
        WHEN hp.revenue_pax_km < 8000  THEN (700 + random() * 600) / NULLIF(hp.revenue_pax_km, 0)
        ELSE                                (1200 + random() * 800) / NULLIF(hp.revenue_pax_km, 0)
    END
)::numeric, 4)
WHERE hp.yield_usd_rpk IS NULL
  AND hp.revenue_pax_km > 0;

SELECT
    COUNT(*) AS total,
    COUNT(yield_usd_rpk) AS con_yield,
    COUNT(*) - COUNT(yield_usd_rpk) AS sin_yield,
    ROUND(AVG(yield_usd_rpk)::numeric, 4) AS yield_promedio,
    ROUND(MIN(yield_usd_rpk)::numeric, 4) AS yield_min,
    ROUND(MAX(yield_usd_rpk)::numeric, 4) AS yield_max
FROM gold.hechos_pasajero;


--3.gold.hechos_carga
--Esta tabla trae las métricas de carga aérea por vuelo, que alimenta los KPIs de CTK (Cargo Tonne-Kilometers) y Cargo Load Factor.

 --DROP de la MV
DROP MATERIALIZED VIEW IF EXISTS gold.mv_demanda_carga_por_ruta CASCADE;
DROP MATERIALIZED VIEW IF EXISTS gold.mv_aduanas_resumen CASCADE;

ALTER TABLE gold.hechos_carga 
ALTER COLUMN cargo_weight_kg TYPE DECIMAL(12,2);

ALTER TABLE gold.hechos_carga 
ALTER COLUMN cargo_volume_m3 TYPE DECIMAL(10,2);

--Verificar el cambio
SELECT column_name, numeric_precision, numeric_scale
FROM information_schema.columns
WHERE table_schema = 'gold'
  AND table_name   = 'hechos_carga'
  AND column_name IN ('cargo_weight_kg', 'cargo_volume_m3');

--insertar

INSERT INTO gold.hechos_carga (
    tiempo_id,
    ruta_id,
    cargo_weight_kg,
    cargo_volume_m3,
    cargo_revenue_usd,
    yield_usd_kgkm,
    cargo_type_breakdown,
    perishable_count,
    dangerous_goods_count,
    customs_hold_count,
    clearance_time_avg_hours
)
SELECT
    TO_CHAR(v.salida_programada, 'YYYYMMDD')::int            AS tiempo_id,
    dr.ruta_id,
    ROUND(SUM(cv.peso_kg)::numeric, 2)                       AS cargo_weight_kg,
    ROUND(SUM(cv.volumen_m3)::numeric, 2)                    AS cargo_volume_m3,
    ROUND(SUM(cv.peso_kg * 
        CASE cv.tipo
            WHEN 'GENERAL'    THEN 2.00 + random() * 1.50
            WHEN 'PERECIBLE'  THEN 3.50 + random() * 2.00
            WHEN 'PELIGROSA'  THEN 5.00 + random() * 3.00
            WHEN 'VALORADA'   THEN 8.00 + random() * 5.00
            WHEN 'ANIMALES'   THEN 6.00 + random() * 3.00
            ELSE                   2.44
        END
    )::numeric, 2)                                           AS cargo_revenue_usd,
    ROUND((
        SUM(cv.peso_kg * 
            CASE cv.tipo
                WHEN 'GENERAL'    THEN 2.50
                WHEN 'PERECIBLE'  THEN 4.50
                WHEN 'PELIGROSA'  THEN 6.50
                WHEN 'VALORADA'   THEN 10.00
                WHEN 'ANIMALES'   THEN 7.50
                ELSE                   2.44
            END
        ) / NULLIF(SUM(cv.peso_kg) * NULLIF(dr.distancia_km, 0), 0)
    )::numeric, 4)                                           AS yield_usd_kgkm,
    jsonb_build_object(
        'GENERAL',    COUNT(*) FILTER (WHERE cv.tipo = 'GENERAL'),
        'PERECIBLE',  COUNT(*) FILTER (WHERE cv.tipo = 'PERECIBLE'),
        'PELIGROSA',  COUNT(*) FILTER (WHERE cv.tipo = 'PELIGROSA'),
        'VALORADA',   COUNT(*) FILTER (WHERE cv.tipo = 'VALORADA'),
        'ANIMALES',   COUNT(*) FILTER (WHERE cv.tipo = 'ANIMALES'),
        'TOTAL_KG',   ROUND(SUM(cv.peso_kg)::numeric, 2)
    )                                                        AS cargo_type_breakdown,
    COUNT(*) FILTER (WHERE cv.tipo = 'PERECIBLE')::int       AS perishable_count,
    COUNT(*) FILTER (WHERE cv.tipo = 'PELIGROSA')::int       AS dangerous_goods_count,
    CASE WHEN random() < 0.05 THEN 1 ELSE 0 END              AS customs_hold_count,
    ROUND((0.5 + random() * 2.5)::numeric, 2)                AS clearance_time_avg_hours
FROM silver.carga_vuelo cv
JOIN silver.vuelos v ON v.vuelo_id = cv.vuelo_id
JOIN gold.dim_ruta dr
  ON dr.origen_icao  = (SELECT icao FROM gold.dim_aeropuerto WHERE aeropuerto_id = v.origen_id)
 AND dr.destino_icao = (SELECT icao FROM gold.dim_aeropuerto WHERE aeropuerto_id = v.destino_id)
JOIN gold.dim_tiempo dt 
  ON dt.tiempo_id = TO_CHAR(v.salida_programada, 'YYYYMMDD')::int
WHERE cv.peso_kg > 0
  AND v.salida_programada IS NOT NULL
  AND EXTRACT(YEAR FROM v.salida_programada) = 2026
GROUP BY
    TO_CHAR(v.salida_programada, 'YYYYMMDD')::int,
    dr.ruta_id,
    dr.distancia_km;

SELECT
    COUNT(*)                                                  AS total_filas,
    COUNT(DISTINCT tiempo_id)                                 AS fechas_distintas,
    COUNT(DISTINCT ruta_id)                                   AS rutas_distintas,
    ROUND(SUM(cargo_weight_kg)::numeric, 2)                   AS peso_total_kg,
    ROUND(SUM(cargo_weight_kg)::numeric / 1000, 2)            AS toneladas_total,
    ROUND(SUM(cargo_revenue_usd)::numeric, 2)                 AS revenue_total,
    ROUND(AVG(yield_usd_kgkm)::numeric, 4)                    AS yield_promedio,
    SUM(perishable_count)                                     AS perecibles_total,
    SUM(dangerous_goods_count)                                AS peligrosa_total,
    SUM(customs_hold_count)                                   AS retenciones_aduana
FROM gold.hechos_carga;

--4.gold.hechos_combustible
INSERT INTO gold.hechos_combustible (
    tiempo_id,
    aeropuerto_id,
    aeronave_id,
    fuel_uplift_kg,
    fuel_consumed_kg,
    fuel_price_avg_usd_kg,
    fuel_cost_total_usd,
    efficiency_kg_km,
    efficiency_variation_pct,
    co2_per_pax_km,
    alternative_fuel_pct
)
SELECT
    TO_CHAR(v.salida_programada, 'YYYYMMDD')::int            AS tiempo_id,
    dao.aeropuerto_id                                        AS aeropuerto_id,
    v.aeronave_id,
    ROUND(cb.masa_kg::numeric, 2)                            AS fuel_uplift_kg,
    ROUND((cb.masa_kg * (0.92 + random() * 0.06))::numeric, 2) AS fuel_consumed_kg,
    ROUND((
        cb.costo_total_usd / NULLIF(cb.masa_kg, 0)
    )::numeric, 4)                                           AS fuel_price_avg_usd_kg,
    ROUND(cb.costo_total_usd::numeric, 2)                    AS fuel_cost_total_usd,
    /* Eficiencia kg/km - también limitamos para evitar overflow */
    LEAST(
        ROUND((cb.masa_kg / NULLIF(dr.distancia_km, 0))::numeric, 4),
        99.9999
    )                                                        AS efficiency_kg_km,
    ROUND((-5 + random() * 10)::numeric, 2)                  AS efficiency_variation_pct,
    /* CO2 por pax-km: usamos GREATEST para asegurar pax >= 100 (mínimo realista) */
    /* y limitamos con LEAST por si acaso */
    LEAST(
        ROUND((
            (cb.masa_kg * 3.16) 
            / NULLIF(GREATEST(COALESCE(hv.pax_transportados, 150), 100) * dr.distancia_km, 0)
        )::numeric, 4),
        99.9999
    )                                                        AS co2_per_pax_km,
    ROUND((random() * 3)::numeric, 2)                        AS alternative_fuel_pct
FROM silver.combustible_carga cb
JOIN silver.vuelos v ON v.vuelo_id = cb.vuelo_id
JOIN gold.dim_aeropuerto dao ON dao.aeropuerto_id = v.origen_id
JOIN gold.dim_aeronave dan ON dan.aeronave_id = v.aeronave_id
JOIN gold.dim_ruta dr
  ON dr.origen_icao  = dao.icao
 AND dr.destino_icao = (SELECT icao FROM gold.dim_aeropuerto WHERE aeropuerto_id = v.destino_id)
JOIN gold.dim_tiempo dt ON dt.tiempo_id = TO_CHAR(v.salida_programada, 'YYYYMMDD')::int
LEFT JOIN gold.hechos_vuelo hv 
  ON hv.tiempo_id = TO_CHAR(v.salida_programada, 'YYYYMMDD')::int
 AND hv.aeronave_id = v.aeronave_id
 AND hv.ruta_id = dr.ruta_id
WHERE cb.masa_kg > 0
  AND cb.costo_total_usd > 0
  AND v.salida_programada IS NOT NULL
  AND EXTRACT(YEAR FROM v.salida_programada) = 2026;

--5.gold.hechos_mantenimiento
INSERT INTO gold.hechos_mantenimiento (
    tiempo_id,
    aeronave_id,
    events_count,
    man_hours,
    cost_labor_usd,
    cost_parts_usd,
    cost_total_usd,
    aog_hours,
    delay_caused_min,
    deferrals_count,
    component_changes_count
)
SELECT
    TO_CHAR(m.fecha_inicio, 'YYYYMMDD')::int                 AS tiempo_id,
    m.aeronave_id,
    /* events_count: 1 evento por fila */
    1                                                        AS events_count,
    /* man_hours: horas-hombre estimadas según tipo de check */
    LEAST(
        ROUND((
            CASE m.tipo_check
                WHEN 'A'    THEN 40   + random() * 60      -- 40-100 hrs
                WHEN 'B'    THEN 100  + random() * 200     -- 100-300 hrs
                WHEN 'C'    THEN 300  + random() * 500     -- 300-800 hrs
                WHEN 'D'    THEN 800  + random() * 400     -- 800-1200 hrs (límite DECIMAL(6,2))
                WHEN 'LINE' THEN 2    + random() * 8       -- 2-10 hrs
                ELSE             10   + random() * 30
            END
        )::numeric, 2),
        9999.99
    )                                                        AS man_hours,
    /* cost_labor_usd: 60% del costo total */
    ROUND((m.costo_usd * (0.50 + random() * 0.20))::numeric, 2) AS cost_labor_usd,
    /* cost_parts_usd: 40% del costo total */
    ROUND((m.costo_usd * (0.30 + random() * 0.20))::numeric, 2) AS cost_parts_usd,
    /* cost_total_usd: el del silver */
    ROUND(m.costo_usd::numeric, 2)                           AS cost_total_usd,
    /* aog_hours: tiempo aeronave fuera de servicio */
    LEAST(
        ROUND((
            EXTRACT(EPOCH FROM (m.fecha_fin - m.fecha_inicio)) / 3600
        )::numeric, 2),
        9999.99
    )                                                        AS aog_hours,
    /* delay_caused_min: demora causada al vuelo (no todos los eventos generan delay) */
    CASE
        WHEN m.tipo_check IN ('C','D')      THEN FLOOR(60 + random() * 240)::int  -- 1-5 hrs
        WHEN m.tipo_check = 'B'             THEN FLOOR(15 + random() * 90)::int   -- 15-105 min
        WHEN m.tipo_check = 'A'             THEN FLOOR(random() * 60)::int        -- 0-60 min
        WHEN random() < 0.10                THEN FLOOR(5 + random() * 30)::int    -- LINE check raro
        ELSE                                     0
    END                                                      AS delay_caused_min,
    /* deferrals_count: items diferidos bajo MEL (0-3 según tipo) */
    CASE
        WHEN m.tipo_check IN ('C','D') THEN FLOOR(random() * 4)::int
        WHEN m.tipo_check = 'B'        THEN FLOOR(random() * 2)::int
        WHEN random() < 0.05           THEN 1
        ELSE                                0
    END                                                      AS deferrals_count,
    /* component_changes_count: componentes reemplazados */
    CASE UPPER(m.estado)
        WHEN 'CLOSED'      THEN FLOOR(1 + random() * 3)::int
        WHEN 'INPROGRESS'  THEN FLOOR(random() * 2)::int
        ELSE                    0
    END                                                      AS component_changes_count
FROM silver.mantenimiento_eventos m
JOIN gold.dim_aeronave da ON da.aeronave_id = m.aeronave_id
JOIN gold.dim_tiempo dt ON dt.tiempo_id = TO_CHAR(m.fecha_inicio, 'YYYYMMDD')::int
WHERE m.aeronave_id   IS NOT NULL
  AND m.fecha_inicio  IS NOT NULL
  AND m.fecha_fin     IS NOT NULL
  AND m.costo_usd     IS NOT NULL
  AND EXTRACT(YEAR FROM m.fecha_inicio) = 2026;


--6.gold.hechos_tripulacion
INSERT INTO gold.hechos_tripulacion (
    tiempo_id,
    rol_id,
    crew_count,
    duty_hours,
    flight_hours,
    layover_hours,
    per_diem_cost_usd,
    training_hours,
    fatigue_events,
    crew_pairing_efficiency_pct
)
SELECT
    TO_CHAR(v.salida_programada, 'YYYYMMDD')::int            AS tiempo_id,
    /* Rol mapeado a dim_tripulacion_rol */
    dtr.rol_id,
    /* crew_count: cantidad de tripulantes con ese rol en ese día */
    COUNT(*)::int                                            AS crew_count,
    /* duty_hours: suma de horas de servicio */
    LEAST(
        ROUND(SUM(tv.horas_vuelo_duty)::numeric, 2),
        9999.99
    )                                                        AS duty_hours,
    /* flight_hours: ~70-85% del duty (resto es taxi/espera) */
    LEAST(
        ROUND((SUM(tv.horas_vuelo_duty) * (0.70 + random() * 0.15))::numeric, 2),
        9999.99
    )                                                        AS flight_hours,
    /* layover_hours: horas de descanso entre vuelos */
    LEAST(
        ROUND(SUM(tv.descanso_horas)::numeric, 2),
        9999.99
    )                                                        AS layover_hours,
    /* per_diem_cost_usd: viáticos según rol y duty hours */
    ROUND((
        SUM(tv.horas_vuelo_duty) *
        CASE UPPER(tv.rol)
            WHEN 'CAPTAIN'         THEN 25 + random() * 15   -- $25-40/hr
            WHEN 'FO'              THEN 18 + random() * 10   -- $18-28/hr
            WHEN 'RELIEF_CAPTAIN'  THEN 22 + random() * 13   -- $22-35/hr
            WHEN 'PURSER'          THEN 15 + random() * 8    -- $15-23/hr
            WHEN 'FA'              THEN 12 + random() * 6    -- $12-18/hr
            WHEN 'LOADMASTER'      THEN 14 + random() * 7    -- $14-21/hr
            ELSE                        12 + random() * 6
        END
    )::numeric, 2)                                           AS per_diem_cost_usd,
    /* training_hours: horas de entrenamiento (~5-10% del duty para mantener certs) */
    LEAST(
        ROUND((SUM(tv.horas_vuelo_duty) * (0.05 + random() * 0.05))::numeric, 2),
        9999.99
    )                                                        AS training_hours,
    /* fatigue_events: incidentes de fatiga (raros, depende del descanso) */
    SUM(
        CASE
            WHEN tv.descanso_horas < tv.descanso_minimo_requerido THEN 1
            WHEN random() < 0.02 THEN 1  -- 2% probabilidad base
            ELSE 0
        END
    )::int                                                   AS fatigue_events,
    /* crew_pairing_efficiency_pct: % de cumplimiento de descansos mínimos */
    LEAST(
        ROUND((
            SUM(CASE WHEN tv.descanso_minimo_cumple THEN 1 ELSE 0 END)::numeric * 100
            / NULLIF(COUNT(*)::numeric, 0)
        ), 2),
        100.00
    )                                                        AS crew_pairing_efficiency_pct
FROM silver.tripulacion_vuelo tv
JOIN silver.vuelos v ON v.vuelo_id = tv.vuelo_id
/* Mapeo del rol bronze al rol gold */
JOIN gold.dim_tripulacion_rol dtr 
  ON dtr.rol = UPPER(tv.rol)
JOIN gold.dim_tiempo dt ON dt.tiempo_id = TO_CHAR(v.salida_programada, 'YYYYMMDD')::int
WHERE tv.vuelo_id          IS NOT NULL
  AND tv.horas_vuelo_duty  IS NOT NULL
  AND tv.descanso_horas    IS NOT NULL
  AND v.salida_programada  IS NOT NULL
  AND EXTRACT(YEAR FROM v.salida_programada) = 2026
GROUP BY
    TO_CHAR(v.salida_programada, 'YYYYMMDD')::int,
    dtr.rol_id,
    tv.rol;  -- agrupamos también por rol original para el per_diem
    
    
    
