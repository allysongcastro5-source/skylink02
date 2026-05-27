                                                           --views_normal/materialized.
--CAPA SILVER
                                                        
--  VIEWS Capa Silver


-- 1. Vista Operacional de Vuelos
CREATE OR REPLACE VIEW silver.vw_operacion_vuelos AS
SELECT
    -- Identificadores
    v.vuelo_id,
    v.numero_vuelo,
    -- Aerolínea
    al.nombre AS aerolinea,
    al.codigo_iata,
    al.codigo_icao,
    -- Aeronave
    an.matricula,
    an.tipo AS tipo_aeronave,
    an.estado AS estado_aeronave,
    -- Aeropuertos
    ao.nombre AS aeropuerto_origen,
    ao.iata AS origen_iata,
    ao.icao AS origen_icao,
    ad.nombre AS aeropuerto_destino,
    ad.iata AS destino_iata,
    ad.icao AS destino_icao,
    -- Ruta aérea
    av.designador AS aerovia,
    -- Horarios
    v.salida_programada,
    v.llegada_programada,
    v.salida_real,
    v.llegada_real,
    -- Estado operacional
    v.estado,
    v.motivo_desviacion,
    -- Tiempo de vuelo real
    ROUND(
        EXTRACT(
            EPOCH FROM (
                v.llegada_real - v.salida_real
            )
        ) / 60,
        2
    ) AS duracion_real_min,
    -- Delay salida
    ROUND(
        EXTRACT(
            EPOCH FROM (
                v.salida_real - v.salida_programada
            )
        ) / 60,
        2
    ) AS delay_salida_min,
    -- Delay llegada
    ROUND(
        EXTRACT(
            EPOCH FROM (
                v.llegada_real - v.llegada_programada
            )
        ) / 60,
        2
    ) AS delay_llegada_min,
    -- Total pasajeros
    COUNT(DISTINCT pv.pasajero_id) AS pasajeros_totales,
    -- Equipaje total
    SUM(
        COALESCE(
            pv.equipaje_piezas,
            0
        )
    ) AS equipaje_total_piezas,
    -- Peso equipaje
    SUM(
        COALESCE(
            pv.equipaje_peso_kg,
            0
        )
    ) AS equipaje_total_kg,
    -- Revenue pasajeros
    SUM(
        COALESCE(
            pv.tarifa_usd,
            0
        )
    ) AS revenue_pasajeros_usd,
    -- Carga total
    SUM(
        COALESCE(
            cv.peso_kg,
            0
        )
    ) AS carga_total_kg,
    -- Revenue carga
    SUM(
        COALESCE(
            cv.peso_kg,
            0
        )
    ) AS carga_revenue_estimado
FROM silver.vuelos v
LEFT JOIN silver.aerolineas al
    ON v.aerolinea_id = al.aerolinea_id
LEFT JOIN silver.aeronaves an
    ON v.aeronave_id = an.aeronave_id
LEFT JOIN silver.aeropuertos ao
    ON v.origen_id = ao.aeropuerto_id
LEFT JOIN silver.aeropuertos ad
    ON v.destino_id = ad.aeropuerto_id
LEFT JOIN silver.aerovias av
    ON v.aerovia_id = av.aerovia_id
LEFT JOIN silver.pasajeros_vuelo pv
    ON v.vuelo_id = pv.vuelo_id
LEFT JOIN silver.carga_vuelo cv
    ON v.vuelo_id = cv.vuelo_id
GROUP BY
    v.vuelo_id,
    v.numero_vuelo,
    al.nombre,
    al.codigo_iata,
    al.codigo_icao,
    an.matricula,
    an.tipo,
    an.estado,
    ao.nombre,
    ao.iata,
    ao.icao,
    ad.nombre,
    ad.iata,
    ad.icao,
    av.designador,
    v.salida_programada,
    v.llegada_programada,
    v.salida_real,
    v.llegada_real,
    v.estado,
    v.motivo_desviacion;
    
COMMENT ON VIEW silver.vw_operacion_vuelos
IS 'Vista operacional consolidada de vuelos que integra información de aerolínea, aeronave, aeropuertos, pasajeros, equipaje, carga y métricas operacionales para análisis y monitoreo en tiempo real.';

SELECT *
FROM silver.vw_operacion_vuelos
LIMIT 20;


-- 2. Vista de Mantenimiento Activo
CREATE OR REPLACE VIEW silver.vw_mantenimiento_activo AS
SELECT
    -- IDs
    me.mant_id,
    me.aeronave_id,
    me.motor_id,
    me.taller_id,
    -- Aeronave
    a.matricula,
    a.tipo AS tipo_aeronave,
    a.estado AS estado_aeronave,
    -- Motor
    mo.modelo AS modelo_motor,
    mo.serial_number,
    mo.horas_acumuladas,
    mo.ciclos_acumulados,
    -- Taller
    tm.nombre AS taller_nombre,
    tm.tipo AS taller_tipo,
    -- Evento mantenimiento
    me.tipo_check,
    me.componente,
    me.descripcion,
    me.tecnico_id,
    -- Fechas
    me.fecha_inicio,
    me.fecha_fin,
    -- Duración mantenimiento
    ROUND(
        EXTRACT(
            EPOCH FROM (
                COALESCE(
                    me.fecha_fin,
                    CURRENT_TIMESTAMP
                ) - me.fecha_inicio
            )
        ) / 3600,
        2
    ) AS duracion_horas,
    -- Costos
    me.costo_usd,
    -- Estado
    me.estado,
    -- Indicador mantenimiento activo
    CASE
        WHEN me.estado IN (
            'OPEN',
            'INPROGRESS'
        )
        THEN TRUE
        ELSE FALSE
    END AS mantenimiento_activo,
    -- Indicador AOG simple
    CASE
        WHEN a.estado = 'MANTENIMIENTO'
         AND me.estado IN (
            'OPEN',
            'INPROGRESS'
         )
        THEN TRUE
        ELSE FALSE
    END AS aeronave_aog
FROM silver.mantenimiento_eventos me
LEFT JOIN silver.aeronaves a
    ON me.aeronave_id = a.aeronave_id
LEFT JOIN silver.motores mo
    ON me.motor_id = mo.motor_id
LEFT JOIN silver.talleres_mro tm
    ON me.taller_id = tm.taller_id
WHERE me.estado IN (
    'OPEN',
    'INPROGRESS',
    'DEFERRED'
);

COMMENT ON VIEW silver.vw_mantenimiento_activo
IS 'Vista operacional de mantenimiento activo de aeronaves y motores. Consolida eventos MRO abiertos, talleres, costos, duración y estado operacional de la flota.';

SELECT *
FROM silver.vw_mantenimiento_activo
ORDER BY fecha_inicio DESC;


-- 3. Vista NOTAMs Activos
CREATE OR REPLACE VIEW silver.vw_notams_activos AS
SELECT
    n.notam_id,
    n.ident,
    n.tipo,
    n.referencia,
    n.raw_text,
    a.aeropuerto_id,
    a.nombre AS aeropuerto_nombre,
    a.iata,
    a.icao,
    a.municipality,
    a.iso_country,
    n.coordenada,
    n.radio_nm,
    n.altura_min,
    n.altura_max,
    n.valido_desde,
    n.valido_hasta,
    ROUND(
        EXTRACT(
            EPOCH FROM (
                n.valido_hasta - CURRENT_TIMESTAMP
            )
        ) / 3600,
        2
    ) AS horas_restantes,
    CASE
        WHEN CURRENT_TIMESTAMP BETWEEN
             n.valido_desde
             AND
             n.valido_hasta
        THEN 'ACTIVO'
        WHEN CURRENT_TIMESTAMP < n.valido_desde
        THEN 'PROGRAMADO'
        ELSE 'EXPIRADO'
    END AS estado_notam,
    CASE
        WHEN CURRENT_TIMESTAMP BETWEEN
             n.valido_desde
             AND
             n.valido_hasta
        THEN TRUE
        ELSE FALSE
    END AS activo
FROM silver.notams n
LEFT JOIN silver.aeropuertos a
    ON n.aeropuerto_id = a.aeropuerto_id;
SELECT
    ident,
    estado_notam,
    activo,
    valido_desde,
    valido_hasta
FROM silver.vw_notams_activos
ORDER BY valido_desde DESC;


--4
-- Vista anonimizada de pasajeros
CREATE OR REPLACE VIEW silver.vw_pasajeros_anonimos AS
SELECT
    pasajero_id,
    -- Documento oculto
    '***MASKED***' AS documento,
    -- Tipo documento oculto
    '***' AS tipo_doc,
    -- Nombre anonimizado
    'PASAJERO ANONIMO' AS nombre,
    -- Datos permitidos para análisis
    nacionalidad,
    categoria,
    programa_fidelidad,
    -- Edad aproximada sin exponer fecha exacta
    EXTRACT(
        YEAR FROM AGE(CURRENT_DATE, fecha_nacimiento)
    ) AS edad_aproximada
FROM silver.pasajeros;

COMMENT ON VIEW silver.vw_pasajeros_anonimos
IS 'Vista anonimizada de pasajeros para análisis comercial y operacional sin exponer información sensible o identificable.';

GRANT SELECT
ON silver.vw_pasajeros_anonimos
TO rol_revenue_mgmt;

SELECT *
FROM silver.vw_pasajeros_anonimos
LIMIT 20;

--CAPA GOLD

--1
CREATE OR REPLACE VIEW gold.vw_puntualidad_vuelos AS
SELECT
    t.anio,
    t.mes,
    COUNT(*) AS vuelos_totales,
    SUM(
        CASE
            WHEN hv.delay_min <= 15 THEN 1
            ELSE 0
        END
    ) AS vuelos_puntuales,
    ROUND(
        (
            SUM(
                CASE
                    WHEN hv.delay_min <= 15 THEN 1
                    ELSE 0
                END
            )::NUMERIC
            / COUNT(*)
        ) * 100,
        2
    ) AS otp_pct
FROM gold.hechos_vuelo hv
JOIN gold.dim_tiempo t
    ON hv.tiempo_id = t.tiempo_id
GROUP BY
    t.anio,
    t.mes;

COMMENT ON VIEW gold.vw_puntualidad_vuelos
IS 'Vista analítica utilizada para medir el indicador OTP (On Time Performance) de vuelos por año y mes. Permite evaluar puntualidad operacional, eficiencia de itinerarios y desempeño de operaciones aeronáuticas.';
 
select * from gold.vw_puntualidad_vuelos
 
 
--2
CREATE OR REPLACE VIEW gold.vw_aeronave_posicion_tiempo_real AS
SELECT
    sub.vuelo_id,
    v.numero_vuelo,
    v.aeronave_id,
    sub.timestamp_utc,
    sub.coordenada,
    sub.velocidad_nudos,
    sub.heading,
    sub.fase_vuelo
FROM (
    SELECT
        pv.*,
        ROW_NUMBER() OVER (
            PARTITION BY pv.vuelo_id
            ORDER BY pv.timestamp_utc DESC
        ) AS rn
    FROM silver.posicionamiento_vuelo pv
) sub
JOIN silver.vuelos v
    ON sub.vuelo_id = v.vuelo_id
WHERE sub.rn = 1;
 
COMMENT ON VIEW gold.vw_aeronave_posicion_tiempo_real IS
'Vista en tiempo real que muestra la última posición registrada de cada aeronave en vuelo, incluyendo coordenadas, velocidad, heading y fase de vuelo actual.';
 
SELECT *
FROM gold.vw_aeronave_posicion_tiempo_real;

 
--3
CREATE VIEW gold.vw_vuelo_estado_completo AS
SELECT
    v.vuelo_id,
    v.numero_vuelo,
    al.nombre AS aerolinea,
    COALESCE(
        NULLIF(ao.iata, ''),
        NULLIF(ao.icao, ''),
        ao.ident
    ) AS origen,
    COALESCE(
        NULLIF(ad.iata, ''),
        NULLIF(ad.icao, ''),
        ad.ident
    ) AS destino,
    v.estado,
    v.salida_programada,
    v.llegada_programada,
    v.salida_real,
    v.llegada_real,
    pos.timestamp_utc AS ultima_actualizacion,
    pos.coordenada,
    pos.velocidad_nudos,
    pos.fase_vuelo,
    tv.rol,
    tv.duty_start,
    tv.duty_end
FROM silver.vuelos v
JOIN silver.aerolineas al
    ON v.aerolinea_id = al.aerolinea_id
JOIN silver.aeropuertos ao
    ON v.origen_id = ao.aeropuerto_id
JOIN silver.aeropuertos ad
    ON v.destino_id = ad.aeropuerto_id
LEFT JOIN gold.vw_aeronave_posicion_tiempo_real pos
    ON v.vuelo_id = pos.vuelo_id
LEFT JOIN silver.tripulacion_vuelo tv
    ON v.vuelo_id = tv.vuelo_id;

SELECT *
FROM gold.vw_vuelo_estado_completo;

COMMENT ON VIEW gold.vw_vuelo_estado_completo IS
'Vista operacional consolidada que integra información completa del vuelo, incluyendo estado actual, horarios programados y reales, posición de aeronave, aeropuertos de origen/destino y tripulación asignada.';

 
--4
CREATE VIEW gold.vw_conexion_pasajero AS
SELECT
    p.pasajero_id,
    p.nombre,
    pv.pnr,
    v.numero_vuelo,
    COALESCE(
        NULLIF(ao.iata, ''),
        NULLIF(ao.icao, ''),
        ao.ident
    ) AS origen, 
    COALESCE(
        NULLIF(ad.iata, ''),
        NULLIF(ad.icao, ''),
        ad.ident
    ) AS destino, 
    v.llegada_programada,
    LEAD(v.numero_vuelo)
    OVER (
        PARTITION BY p.pasajero_id
        ORDER BY v.salida_programada
    ) AS siguiente_vuelo
FROM silver.pasajeros p 
JOIN silver.pasajeros_vuelo pv
    ON p.pasajero_id = pv.pasajero_id
JOIN silver.vuelos v
    ON pv.vuelo_id = v.vuelo_id
JOIN silver.aeropuertos ao
    ON v.origen_id = ao.aeropuerto_id
JOIN silver.aeropuertos ad
    ON v.destino_id = ad.aeropuerto_id;
 
COMMENT ON VIEW gold.vw_conexion_pasajero IS
'Vista analítica utilizada para identificar conexiones de pasajeros en tránsito, mostrando vuelos actuales y próximos vuelos programados según el itinerario cronológico del pasajero.'; 

SELECT *
FROM gold.vw_conexion_pasajero;
 
--5
CREATE VIEW gold.vw_equipaje_trazabilidad AS
SELECT
    e.tag_id,
    e.estado,
    e.ubicacion_actual,
    e.timestamp_ultimo_evento,
    v.numero_vuelo,
    COALESCE(
        NULLIF(ao.iata, ''),
        NULLIF(ao.icao, ''),
        ao.ident
    ) AS origen,
    COALESCE(
        NULLIF(ad.iata, ''),
        NULLIF(ad.icao, ''),
        ad.ident
    ) AS destino
FROM silver.equipaje e
JOIN silver.vuelos v
    ON e.vuelo_id = v.vuelo_id
JOIN silver.aeropuertos ao
    ON v.origen_id = ao.aeropuerto_id
JOIN silver.aeropuertos ad
    ON v.destino_id = ad.aeropuerto_id;
 
COMMENT ON VIEW gold.vw_equipaje_trazabilidad IS
'Vista de trazabilidad de equipaje que permite monitorear el recorrido completo de cada maleta desde check-in hasta entrega final, incluyendo ubicación actual, estado y vuelo asociado.';
 
SELECT *
FROM gold.vw_equipaje_trazabilidad;
 
 
--6
CREATE OR REPLACE VIEW gold.vw_carga_aduanera_pendiente AS
SELECT
    c.awb,
    c.tipo,
    c.peso_kg,
    c.origen,
    c.destino,
    c.declaracion_aduanera
FROM silver.carga_vuelo c
WHERE c.declaracion_aduanera IS NOT NULL;
 
COMMENT ON VIEW gold.vw_carga_aduanera_pendiente IS
'Vista logística utilizada para monitorear carga aérea pendiente de liberación aduanera, incluyendo información de guía aérea, peso, origen, destino y estado de declaración aduanera.';
 
SELECT *
FROM gold.vw_carga_aduanera_pendiente;
 

--7
CREATE OR REPLACE VIEW gold.vw_tripulacion_horas_duty AS
SELECT
    crew_id,
    COUNT(vuelo_id) AS vuelos_asignados,
    SUM(horas_vuelo_duty) AS horas_totales_duty,
    AVG(descanso_horas) AS descanso_promedio,
    BOOL_AND(descanso_minimo_cumple)
        AS cumple_regulacion
FROM silver.tripulacion_vuelo
GROUP BY crew_id;
 
 
COMMENT ON VIEW gold.vw_tripulacion_horas_duty IS
'Vista operacional utilizada para consolidar horas duty y horas de vuelo acumuladas por tripulante, permitiendo validar cumplimiento regulatorio aeronáutico y control de fatiga operacional.';
 
SELECT *
FROM gold.vw_tripulacion_horas_duty;

 
-- VISTAS MATERIALIZADA
 --1
CREATE MATERIALIZED VIEW gold.mv_mantenimiento_predictivo AS
SELECT
    es.engine_id,
    AVG(es.egt_c) AS temperatura_promedio,
    AVG(es.vibration) AS vibracion_promedio,
    AVG(es.fuel_flow_kgh) AS combustible_promedio,
    MAX(es.timestamp_utc) AS ultimo_sensor,
    COUNT(*) AS total_lecturas,
    CASE
        WHEN AVG(es.vibration) > 5
            OR AVG(es.egt_c) > 900
        THEN 'REQUIERE_INSPECCION'
 
        ELSE 'OPERACION_NORMAL'
    END AS estado_predictivo
FROM silver.engine_sensors es
GROUP BY es.engine_id;
 
select * from gold.mv_mantenimiento_predictivo
 
COMMENT ON MATERIALIZED VIEW gold.mv_mantenimiento_predictivo
IS 'Vista materializada utilizada para análisis predictivo de motores aeronáuticos basado en sensores IoT y telemetría operacional.';
 
--2 mv_demanda_carga_por_ruta
CREATE MATERIALIZED VIEW gold.mv_demanda_carga_por_ruta AS
SELECT
    r.origen_icao,
    r.destino_icao,
    t.anio,
    t.mes,
    COUNT(hc.hecho_id) AS total_envios,
    SUM(hc.cargo_weight_kg) AS peso_total_kg,
    SUM(hc.cargo_volume_m3) AS volumen_total_m3,
    SUM(hc.cargo_revenue_usd) AS revenue_total_usd,
    AVG(hc.yield_usd_kgkm) AS promedio_yield,
    SUM(hc.perishable_count) AS carga_perecible,
    SUM(hc.dangerous_goods_count) AS carga_peligrosa,
    SUM(hc.customs_hold_count) AS retenciones_aduana
FROM gold.hechos_carga hc
JOIN gold.dim_ruta r ON hc.ruta_id = r.ruta_id
JOIN gold.dim_tiempo t  ON hc.tiempo_id = t.tiempo_id
GROUP BY
    r.origen_icao,
    r.destino_icao,
    t.anio,
    t.mes;
 
select * from gold.mv_demanda_carga_por_ruta
 
COMMENT ON MATERIALIZED VIEW gold.mv_demanda_carga_por_ruta IS
'Vista materializada analítica que consolida métricas de demanda de carga aérea por ruta origen-destino. Incluye volumen transportado, peso total, revenue generado, yield promedio y tipos de carga, permitiendo análisis comerciales y operacionales para planificación logística y optimización de rutas. Refrescada diariamente para consumo del área de carga comercial.';
 
REFRESH MATERIALIZED VIEW gold.mv_demanda_carga_por_ruta;
 
CREATE INDEX if not exists idx_mv_demanda_ruta
ON gold.mv_demanda_carga_por_ruta
(origen_icao, destino_icao, anio, mes);

--3
CREATE MATERIALIZED VIEW gold.mv_eficiencia_combustible_flota AS
SELECT
    da.tipo AS tipo_aeronave,
    da.fabricante,
    dt.anio,
    dt.mes,
    COUNT(hc.hecho_id) AS total_operaciones,
    SUM(hc.fuel_consumed_kg) AS combustible_total_kg,
    AVG(hc.efficiency_kg_km) AS eficiencia_promedio_kg_km,
    AVG(hc.co2_per_pax_km) AS co2_promedio_pax_km,
    AVG(hc.alternative_fuel_pct) AS promedio_saf_pct,
    SUM(hc.fuel_cost_total_usd) AS costo_total_combustible_usd
FROM gold.hechos_combustible hc
JOIN gold.dim_aeronave da ON hc.aeronave_id = da.aeronave_id
JOIN gold.dim_tiempo dt ON hc.tiempo_id = dt.tiempo_id
GROUP BY
    da.tipo,
    da.fabricante,
    dt.anio,
    dt.mes;

REFRESH MATERIALIZED VIEW gold.mv_eficiencia_combustible_flota;

select * from gold.mv_eficiencia_combustible_flota

COMMENT ON MATERIALIZED VIEW gold.mv_eficiencia_combustible_flota IS
'Vista materializada analítica que consolida métricas de eficiencia de combustible y emisiones CO2 por tipo de aeronave y fabricante. Incluye consumo total de combustible, eficiencia kg/km, emisiones promedio por pasajero-km y porcentaje de combustible sostenible (SAF), soportando análisis de sostenibilidad, eficiencia operacional y reporting regulatorio para IATA.';

CREATE INDEX idx_mv_eficiencia_flota
ON gold.mv_eficiencia_combustible_flota
(tipo_aeronave, fabricante, anio, mes);

--4
CREATE MATERIALIZED VIEW gold.mv_seguridad_operacional AS
SELECT
    dt.anio,
    dt.mes,
    dt.trimestre,
    COUNT(DISTINCT hv.hecho_id) AS total_vuelos,
    -- Fatiga operacional
    SUM(ht.fatigue_events) AS eventos_fatiga,
    -- Vuelos desviados
    COUNT(
        DISTINCT CASE
            WHEN sv.estado = 'DIVERTED'
            THEN sv.vuelo_id
        END
    ) AS vuelos_desviados,
    -- Cancelaciones
    COUNT(
        DISTINCT CASE
            WHEN sv.estado = 'CANCEL'
            THEN sv.vuelo_id
        END
    ) AS vuelos_cancelados,
    -- Desviaciones geoespaciales
    COUNT(
        DISTINCT CASE
            WHEN spv.desviacion_nm > 50
            THEN spv.posicion_id
        END
    ) AS desviaciones_ruta_criticas,
    -- Delays operacionales críticos
    COUNT(
        DISTINCT CASE
            WHEN hv.delay_min > 120
            THEN hv.hecho_id
        END
    ) AS incidentes_operacionales,
    AVG(ht.crew_pairing_efficiency_pct)
        AS eficiencia_tripulacion_pct
FROM gold.dim_tiempo dt
LEFT JOIN gold.hechos_vuelo hv ON dt.tiempo_id = hv.tiempo_id
LEFT JOIN gold.hechos_tripulacion ht ON dt.tiempo_id = ht.tiempo_id
LEFT JOIN silver.vuelos sv ON sv.estado IN ('DIVERTED', 'CANCEL')
LEFT JOIN silver.posicionamiento_vuelo spv ON spv.vuelo_id = sv.vuelo_id
GROUP BY
    dt.anio,
    dt.mes,
    dt.trimestre;

REFRESH MATERIALIZED VIEW gold.mv_seguridad_operacional;
 
select * from gold.mv_seguridad_operacional
 
 
COMMENT ON MATERIALIZED VIEW gold.mv_seguridad_operacional IS
'Vista materializada analítica orientada a monitoreo de seguridad operacional aérea. Consolida indicadores de fatiga de tripulación, incidentes operacionales, desviaciones de ruta, vuelos desviados y cancelaciones por período temporal, permitiendo análisis de riesgo, cumplimiento regulatorio y supervisión operacional por parte de áreas de seguridad y organismos reguladores.';
 
CREATE INDEX if not exists idx_mv_seguridad_operacional ON gold.mv_seguridad_operacional (anio, mes, trimestre);

--5 mv_aduanas_resumen
CREATE MATERIALIZED VIEW gold.mv_aduanas_resumen AS
SELECT
    dt.anio,
    dt.mes,
    dr.origen_icao,
    dr.destino_icao,
    dr.mercado,
    COUNT(hc.hecho_id) AS total_operaciones_carga,
    SUM(hc.cargo_weight_kg) AS peso_total_kg,
    SUM(hc.cargo_revenue_usd) AS revenue_total_usd,
    AVG(hc.clearance_time_avg_hours) AS promedio_despacho_horas,
    SUM(hc.customs_hold_count) AS total_retenciones_aduana,
    SUM(hc.perishable_count) AS mercancia_perecible,
    SUM(hc.dangerous_goods_count) AS mercancia_peligrosa,
    AVG(hc.yield_usd_kgkm)  AS yield_promedio_kgkm
FROM gold.hechos_carga hc
JOIN gold.dim_ruta dr ON hc.ruta_id = dr.ruta_id
JOIN gold.dim_tiempo dt ON hc.tiempo_id = dt.tiempo_id
GROUP BY
    dt.anio,
    dt.mes,
    dr.origen_icao,
    dr.destino_icao,
    dr.mercado;
 
REFRESH MATERIALIZED VIEW gold.mv_aduanas_resumen;
 
select * from gold.mv_aduanas_resumen
 
 
COMMENT ON MATERIALIZED VIEW gold.mv_aduanas_resumen IS
'Vista materializada analítica para monitoreo aduanero y logístico de carga aérea internacional. Consolida métricas de mercancías transportadas por ruta y período, incluyendo peso, revenue, tiempos promedio de despacho, retenciones aduaneras y tipos de carga especial, soportando análisis regulatorios y operacionales para administraciones de aduanas.';

--6
CREATE MATERIALIZED VIEW gold.mv_puntualidad_por_aeropuerto
AS
SELECT
    da.aeropuerto_id,
    da.iata,
    da.icao,
    da.nombre AS aeropuerto_nombre,
    da.ciudad,
    da.pais,
    dt.anio,
    dt.mes,
    COUNT(hv.hecho_id)
        AS vuelos_totales,
    -- Vuelos puntuales
    -- <= 15 minutos retraso
    COUNT(*) FILTER (
        WHERE hv.delay_min <= 15
    ) AS vuelos_puntuales,
    -- Vuelos demorados
    COUNT(*) FILTER (
        WHERE hv.delay_min > 15
    ) AS vuelos_demorados,
    -- OTP %
    ROUND(
        (
            COUNT(*) FILTER (
                WHERE hv.delay_min <= 15
            )::NUMERIC
            /
            NULLIF(
                COUNT(hv.hecho_id),
                0
            )
        ) * 100,
        2
    ) AS otp_pct,
    -- Delay promedio
    ROUND(
        AVG(hv.delay_min)::NUMERIC,
        2
    ) AS delay_promedio_min,
    -- Revenue asociado
    ROUND(
        SUM(hv.total_revenue_usd)::NUMERIC,
        2
    ) AS revenue_total_usd,
    -- Emisiones CO2
    ROUND(
        SUM(hv.co2_emitted_ton)::NUMERIC,
        2
    ) AS co2_emitido_ton
FROM gold.hechos_vuelo hv
JOIN gold.dim_tiempo dt
    ON hv.tiempo_id = dt.tiempo_id
JOIN gold.dim_ruta dr
    ON hv.ruta_id = dr.ruta_id
JOIN gold.dim_aeropuerto da
    ON da.icao = dr.origen_icao
GROUP BY
    da.aeropuerto_id,
    da.iata,
    da.icao,
    da.nombre,
    da.ciudad,
    da.pais,
    dt.anio,
    dt.mes
ORDER BY
    dt.anio DESC,
    dt.mes DESC,
    otp_pct DESC;
 
REFRESH MATERIALIZED VIEW gold.mv_puntualidad_por_aeropuerto;
 
SELECT *
FROM gold.mv_puntualidad_por_aeropuerto
 
COMMENT ON MATERIALIZED VIEW gold.mv_puntualidad_por_aeropuerto IS
'Vista materializada analítica que calcula métricas OTP (On-Time Performance) por aeropuerto y período mensual. Evalúa puntualidad operacional, retrasos promedio, volumen de vuelos, revenue asociado y emisiones CO2 para soporte de administraciones aeroportuarias, operaciones aeronáuticas y métricas regulatorias de performance operacional.';
 
CREATE index if not exists idx_mv_otp_aeropuerto ON gold.mv_puntualidad_por_aeropuerto(aeropuerto_id);
CREATE index if not exists  idx_mv_otp_anio_mes ON gold.mv_puntualidad_por_aeropuerto(anio, mes);
CREATE index if not exists  idx_mv_otp_pct ON gold.mv_puntualidad_por_aeropuerto(otp_pct);
 
 
--7
CREATE MATERIALIZED VIEW gold.mv_ocupacion_por_ruta
AS
SELECT
    dr.ruta_id,
    dr.origen_icao,
    dr.destino_icao,
    dr.tipo_ruta,
    dr.mercado,
    dt.anio,
    dt.mes,
    COUNT(hv.hecho_id)
        AS vuelos_operados,
    SUM(hv.asientos_ofrecidos)
        AS asientos_ofrecidos,
    SUM(hv.asientos_vendidos)
        AS asientos_vendidos,
    SUM(hv.pax_transportados)
        AS pasajeros_transportados,
    -- Distancia total volada
    ROUND(
        SUM(hv.distance_flown_km)::NUMERIC,
        2
    ) AS distancia_total_km,
    -- ASK
    -- Available Seat Kilometer
    ROUND(
        SUM(
            hv.asientos_ofrecidos
            *
            hv.distance_flown_km
        )::NUMERIC,
        2
    ) AS ask_total,
    -- RPK
    -- Revenue Passenger Kilometer
    ROUND(
        SUM(
            hv.pax_transportados
            *
            hv.distance_flown_km
        )::NUMERIC,
        2
    ) AS rpk_total,
    -- Load Factor
    ROUND(
        (
            SUM(
                hv.pax_transportados
                *
                hv.distance_flown_km
            )::NUMERIC
            /
            NULLIF(
                SUM(
                    hv.asientos_ofrecidos
                    *
                    hv.distance_flown_km
                ),
                0
            )
        ) * 100,
        2
    ) AS load_factor_pct,
    -- Revenue pasajeros
    ROUND(
        SUM(hv.passenger_revenue_usd)::NUMERIC,
        2
    ) AS passenger_revenue_usd,
    -- Revenue total
    ROUND(
        SUM(hv.total_revenue_usd)::NUMERIC,
        2
    ) AS total_revenue_usd,
    -- Yield promedio
    -- Revenue / RPK
    ROUND(
        SUM(hv.passenger_revenue_usd)
        /
        NULLIF(
            SUM(
                hv.pax_transportados
                *
                hv.distance_flown_km
            ),
            0
        ),
        4
    ) AS yield_usd_rpk
FROM gold.hechos_vuelo hv
JOIN gold.dim_ruta dr
    ON hv.ruta_id = dr.ruta_id
JOIN gold.dim_tiempo dt
    ON hv.tiempo_id = dt.tiempo_id
GROUP BY
    dr.ruta_id,
    dr.origen_icao,
    dr.destino_icao,
    dr.tipo_ruta,
    dr.mercado,
    dt.anio,
    dt.mes
ORDER BY
    dt.anio DESC,
    dt.mes DESC,
    load_factor_pct DESC;
 
REFRESH MATERIALIZED VIEW gold.mv_ocupacion_por_ruta;
 
SELECT *
FROM gold.mv_ocupacion_por_ruta
 

COMMENT ON MATERIALIZED VIEW gold.mv_ocupacion_por_ruta IS
'Vista materializada analítica que calcula métricas de ocupación y capacidad operacional por ruta y período mensual. Incluye indicadores IATA como ASK, RPK y Load Factor, además de revenue y yield promedio, permitiendo análisis de Revenue Management, planificación comercial y optimización de rutas aeronáuticas.';
 
 
CREATE index if not exists idx_mv_ocupacion_ruta ON gold.mv_ocupacion_por_ruta(ruta_id);
CREATE index if not exists idx_mv_ocupacion_periodo ON gold.mv_ocupacion_por_ruta(anio, mes);
CREATE index if not exists idx_mv_ocupacion_load_factor ON gold.mv_ocupacion_por_ruta(load_factor_pct);












































