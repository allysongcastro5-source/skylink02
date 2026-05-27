                                                                 --functions_geospatial
--CAPA SILVER

-- Calcula la distancia geoespacial entre dos
-- aeropuertos utilizando PostGIS GEOGRAPHY.
-- Retorna:
-- - Distancia en kilómetros
-- - Distancia en millas náuticas
-- Utiliza:
-- silver.aeropuertos.ubicacion
-- =========================================
--1. Llenar country_id
UPDATE silver.aeropuertos a
SET country_id = c.country_id
FROM silver.countries c
WHERE a.iso_country = c.code
  AND a.country_id IS NULL;

--2. Llenar region_id
UPDATE silver.aeropuertos a
SET region_id = r.region_id
FROM silver.regions r
WHERE a.iso_region = r.code
  AND a.region_id IS NULL;

--3. Construir columna geográfica ubicacion
UPDATE silver.aeropuertos
SET ubicacion =
    ST_SetSRID(
        ST_MakePoint(
            longitude_deg,
            latitude_deg
        ),
        4326
    )::GEOGRAPHY
WHERE ubicacion IS NULL
  AND longitude_deg IS NOT NULL
  AND latitude_deg IS NOT NULL;

--4.FUNCTION
CREATE OR REPLACE FUNCTION silver.fn_distancia_aeropuertos(
    p_aeropuerto_origen INT,
    p_aeropuerto_destino INT
)
RETURNS TABLE (
    aeropuerto_origen INT,
    aeropuerto_destino INT,
    distancia_km NUMERIC,
    distancia_nm NUMERIC
)
LANGUAGE plpgsql
AS
$$
BEGIN
    RETURN QUERY
    SELECT
        ao.aeropuerto_id AS aeropuerto_origen,
        ad.aeropuerto_id AS aeropuerto_destino,
        -- Distancia en kilómetros
        ROUND(
            (
                ST_Distance(
                    ao.ubicacion,
                    ad.ubicacion
                ) / 1000
            )::NUMERIC,
            2
        ) AS distancia_km,
        -- Distancia en millas náuticas
        ROUND(
            (
                ST_Distance(
                    ao.ubicacion,
                    ad.ubicacion
                ) / 1852
            )::NUMERIC,
            2
        ) AS distancia_nm
    FROM silver.aeropuertos ao
    JOIN silver.aeropuertos ad
        ON ad.aeropuerto_id = p_aeropuerto_destino
    WHERE ao.aeropuerto_id = p_aeropuerto_origen;
END;
$$;

COMMENT ON FUNCTION silver.fn_distancia_aeropuertos(INT, INT)
IS 'Calcula la distancia geoespacial entre dos aeropuertos utilizando PostGIS GEOGRAPHY. Retorna la distancia en kilómetros y millas náuticas (NM) a partir de las coordenadas almacenadas en silver.aeropuertos.';

SELECT *
FROM silver.fn_distancia_aeropuertos(12,822);



--2
-- Buscar aeropuerto más cercano
-- utilizando coordenadas geográficas
-- Descripción:
-- Busca el aeropuerto más cercano a unas
-- coordenadas geográficas dadas utilizando
-- PostGIS GEOGRAPHY.
--
-- Parámetros:
-- p_latitud  -> Latitud
-- p_longitud -> Longitud
--
-- Retorna:
-- - aeropuerto_id
-- - nombre
-- - iata
-- - icao
-- - distancia en KM
-- - distancia en NM
-- =========================================
CREATE OR REPLACE FUNCTION silver.fn_aeropuerto_mas_cercano(
    p_latitud DECIMAL,
    p_longitud DECIMAL
)
RETURNS TABLE (
    aeropuerto_id INT,
    nombre TEXT,
    iata VARCHAR(3),
    icao VARCHAR(10),
    distancia_km NUMERIC,
    distancia_nm NUMERIC
)
LANGUAGE plpgsql
AS
$$
BEGIN
    RETURN QUERY
    SELECT
        a.aeropuerto_id,
        a.nombre,
        a.iata,
        a.icao,
        -- Distancia KM
        ROUND(
            (
                ST_Distance(
                    a.ubicacion,
                    ST_SetSRID(
                        ST_MakePoint(
                            p_longitud,
                            p_latitud
                        ),
                        4326
                    )::GEOGRAPHY
                ) / 1000
            )::NUMERIC,
            2
        ) AS distancia_km,
        -- Distancia NM
        ROUND(
            (
                ST_Distance(
                    a.ubicacion,
                    ST_SetSRID(
                        ST_MakePoint(
                            p_longitud,
                            p_latitud
                        ),
                        4326
                    )::GEOGRAPHY
                ) / 1852
            )::NUMERIC,
            2
        ) AS distancia_nm
    FROM silver.aeropuertos a
    WHERE a.ubicacion IS NOT NULL
    ORDER BY
        a.ubicacion <-> ST_SetSRID(
            ST_MakePoint(
                p_longitud,
                p_latitud
            ),
            4326
        )::GEOGRAPHY
    LIMIT 1;
END;
$$;

COMMENT ON FUNCTION silver.fn_aeropuerto_mas_cercano(DECIMAL, DECIMAL)
IS 'Busca el aeropuerto más cercano a unas coordenadas geográficas dadas utilizando PostGIS GEOGRAPHY. Retorna información del aeropuerto y la distancia en kilómetros y millas náuticas.';

SELECT *
FROM silver.fn_aeropuerto_mas_cercano(
    9.9939,
    -84.2088
);

--3
-- Validar coordenadas globales
-- son válidas dentro de los rangos
-- globales permitidos.
--
-- Reglas:
-- Latitud  -> entre -90 y 90
-- Longitud -> entre -180 y 180
--
-- Retorna:
-- TRUE  -> Coordenadas válidas
-- FALSE -> Coordenadas inválidas
-- =========================================
CREATE OR REPLACE FUNCTION silver.fn_validar_coordenadas_globales(
    p_latitud DECIMAL,
    p_longitud DECIMAL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS
$$
BEGIN
    RETURN (
        p_latitud BETWEEN -90 AND 90
        AND
        p_longitud BETWEEN -180 AND 180
    );
END;
$$;

COMMENT ON FUNCTION silver.fn_validar_coordenadas_globales(DECIMAL, DECIMAL)
IS 'Valida si unas coordenadas geográficas se encuentran dentro de los rangos globales permitidos para latitud y longitud.';

-- Coordenadas válidas
SELECT silver.fn_validar_coordenadas_globales(
    9.9939,
   -84.2088
);

-- Coordenadas inválidas
SELECT silver.fn_validar_coordenadas_globales(
    120,
   -300
);

--4
-- Descripción:
-- Detecta la desviación de un vuelo respecto
-- a una aerovía utilizando PostGIS.
--
-- Calcula la distancia mínima entre la
-- posición actual del vuelo y la geometría
-- de la aerovía.
--
-- Parámetros:
-- p_latitud
-- p_longitud
-- p_aerovia_id
--
-- Retorna:
-- Distancia de desviación en millas náuticas
-- =========================================
CREATE OR REPLACE FUNCTION silver.fn_detectar_desviacion_ruta(
    p_latitud DECIMAL,
    p_longitud DECIMAL,
    p_aerovia_id INT
)
RETURNS NUMERIC
LANGUAGE plpgsql
AS
$$
DECLARE
    v_desviacion_metros NUMERIC;
    v_desviacion_nm NUMERIC;
BEGIN
    SELECT
        ST_Distance(
            a.geometria::GEOGRAPHY,

            ST_SetSRID(
                ST_MakePoint(
                    p_longitud,
                    p_latitud,
                    0
                ),
                4979
            )::GEOGRAPHY
        )
    INTO v_desviacion_metros
    FROM silver.aerovias a
    WHERE a.aerovia_id = p_aerovia_id;
    -- Conversión metros → millas náuticas
    v_desviacion_nm :=
        ROUND(
            (v_desviacion_metros / 1852)::NUMERIC,
            2
        );
    RETURN v_desviacion_nm;
END;
$$;

COMMENT ON FUNCTION silver.fn_detectar_desviacion_ruta(NUMERIC, NUMERIC, INT)
IS 'Calcula la desviación de una posición aérea respecto a una aerovía utilizando geometrías PostGIS y retorna la distancia en millas náuticas.';

SELECT silver.fn_detectar_desviacion_ruta(
    9.9939,
   -84.2088,
    1
);

--5
-- Detectar ingreso de vuelo a zona NOTAM
CREATE OR REPLACE FUNCTION silver.fn_detectar_ingreso_notam(
    p_latitud NUMERIC,
    p_longitud NUMERIC,
    p_notam_id INT
)
RETURNS TABLE (
    notam_id INT,
    ident VARCHAR,
    dentro_zona BOOLEAN,
    distancia_nm NUMERIC,
    radio_nm INT
)
LANGUAGE plpgsql
AS
$$
BEGIN
    RETURN QUERY
    SELECT
        n.notam_id,
        n.ident,
        (
            ST_DWithin(
                n.coordenada::GEOGRAPHY,

                ST_SetSRID(
                    ST_MakePoint(
                        p_longitud,
                        p_latitud
                    ),
                    4326
                )::GEOGRAPHY,
                n.radio_nm * 1852
            )
        ) AS dentro_zona,
        ROUND(
            (
                ST_Distance(
                    n.coordenada::GEOGRAPHY,

                    ST_SetSRID(
                        ST_MakePoint(
                            p_longitud,
                            p_latitud
                        ),
                        4326
                    )::GEOGRAPHY
                ) / 1852
            )::NUMERIC,
            2
        ) AS distancia_nm,
        n.radio_nm
    FROM silver.notams n
    WHERE n.notam_id = p_notam_id;
END;
$$;

COMMENT ON FUNCTION silver.fn_detectar_ingreso_notam(NUMERIC, NUMERIC, INT)
IS 'Detecta si una coordenada geográfica ingresó dentro del radio de afectación de un NOTAM utilizando funciones espaciales de PostGIS.';

SELECT *
FROM silver.fn_detectar_ingreso_notam(
    9.9939,
   -84.2088,
    1
);

--6
-- FUNCIÓN ANALÍTICA / OPERACIONAL
CREATE OR REPLACE FUNCTION silver.fn_eficiencia_combustible(
    p_vuelo_id INT
)
RETURNS TABLE (
    vuelo_id INT,
    litros_combustible NUMERIC,
    masa_combustible_kg NUMERIC,
    distancia_km NUMERIC,
    eficiencia_kg_km NUMERIC
)
LANGUAGE plpgsql
AS
$$
BEGIN
    RETURN QUERY
    SELECT
        v.vuelo_id,
        c.litros AS litros_combustible,
        c.masa_kg AS masa_combustible_kg,
        ROUND(
            (
                ST_Distance(
                    ao.ubicacion,
                    ad.ubicacion
                ) / 1000
            )::NUMERIC,
            2
        ) AS distancia_km,
        ROUND(
            (
                c.masa_kg /
                NULLIF(
                    (
                        ST_Distance(
                            ao.ubicacion,
                            ad.ubicacion
                        ) / 1000
                    ),
                    0
                )
            )::NUMERIC,
            4
        ) AS eficiencia_kg_km
    FROM silver.vuelos v
    JOIN silver.combustible_carga c
        ON v.vuelo_id = c.vuelo_id
    JOIN silver.aeropuertos ao
        ON v.origen_id = ao.aeropuerto_id
    JOIN silver.aeropuertos ad
        ON v.destino_id = ad.aeropuerto_id
    WHERE v.vuelo_id = p_vuelo_id;
END;
$$;

COMMENT ON FUNCTION silver.fn_eficiencia_combustible(INT)
IS 'Calcula la eficiencia de consumo de combustible de un vuelo utilizando distancia geoespacial entre aeropuertos y masa de combustible cargada. Retorna métricas en kg/km.';

SELECT *
FROM silver.fn_eficiencia_combustible(1);


--7
--  FUNCTION: Verificar si una Coordenada está en una Aerovía 3D
-- Verificar si una Coordenada está
-- en una Aerovía 3D
CREATE OR REPLACE FUNCTION silver.fn_esta_en_aerovia(
    p_latitud NUMERIC,
    p_longitud NUMERIC,
    p_altitud_ft NUMERIC,
    p_aerovia_id INT
)
RETURNS TABLE (
    aerovia_id INT,
    designador VARCHAR,
    dentro_aerovia BOOLEAN,
    distancia_nm NUMERIC,
    nivel_min INT,
    nivel_max INT
)
LANGUAGE plpgsql
AS
$$
BEGIN
    RETURN QUERY
    SELECT
        a.aerovia_id,
        a.designador,
        (
            ST_DWithin(
                a.geometria::GEOGRAPHY,

                ST_SetSRID(
                    ST_MakePoint(
                        p_longitud,
                        p_latitud,
                        p_altitud_ft
                    ),
                    4979
                )::GEOGRAPHY,
                9260
            )
            AND
            (
                p_altitud_ft BETWEEN
                (a.nivel_min * 100)
                AND
                (a.nivel_max * 100)
            )
        ) AS dentro_aerovia,
        ROUND(
            (
                ST_Distance(
                    a.geometria::GEOGRAPHY,

                    ST_SetSRID(
                        ST_MakePoint(
                            p_longitud,
                            p_latitud,
                            p_altitud_ft
                        ),
                        4979
                    )::GEOGRAPHY
                ) / 1852
            )::NUMERIC,
            2
        ) AS distancia_nm,
        a.nivel_min,
        a.nivel_max
    FROM silver.aerovias a
    WHERE a.aerovia_id = p_aerovia_id;
END;
$$;

COMMENT ON FUNCTION silver.fn_esta_en_aerovia(NUMERIC, NUMERIC, NUMERIC, INT)
IS 'Verifica si una coordenada geoespacial 3D se encuentra dentro de una aerovía considerando posición horizontal y niveles de vuelo permitidos.';

SELECT *
FROM silver.fn_esta_en_aerovia(
    9.9939,
   -84.2088,
    35000,
    1
);   



--CAPA GOLD
--1.
-- =========================================================
-- FUNCIÓN: Cálculo de RPK (Revenue Passenger Kilometers)
-- =========================================================
CREATE OR REPLACE FUNCTION gold.fn_calcular_rpk(
    p_pax_count INT,
    p_distancia_km DECIMAL(8,2)
)
RETURNS DECIMAL(12,2) AS $$
BEGIN
    /*
      KPI estándar IATA   
      RPK = Pasajeros transportados × Distancia (km)      
      Mide la demanda real de transporte aéreo
      Benchmark IATA 2025: crecimiento 5.3% vs 2024
    */
    IF p_pax_count IS NULL OR p_distancia_km IS NULL THEN
        RETURN NULL;
    END IF;
    IF p_pax_count < 0 OR p_distancia_km < 0 THEN
        RAISE EXCEPTION
        'RPK: pax_count y distancia_km no pueden ser negativos';
    END IF;
    RETURN ROUND(p_pax_count * p_distancia_km, 2);
END;
$$ LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER;

COMMENT ON FUNCTION gold.fn_calcular_rpk IS
'Calcula RPK (Revenue Passenger Kilometers) = pax × distancia km. KPI estándar IATA para medir demanda real de transporte aéreo de pasajeros.';

SELECT gold.fn_calcular_rpk(144, 1200);  -- Debe dar 172800.00

--2.
-- =========================================================
-- FUNCIÓN: Cálculo de ASK (Available Seat Kilometers)
-- =========================================================
CREATE OR REPLACE FUNCTION gold.fn_calcular_ask(
    p_asientos_ofrecidos INT,
    p_distancia_km DECIMAL(8,2)
)
RETURNS DECIMAL(14,2) AS $$
BEGIN
    /*
      KPI estándar IATA      
      ASK = Asientos disponibles × Distancia (km)     
      Mide la capacidad ofertada por la aerolínea
      Es el denominador del Load Factor y del RASK
    */

    IF p_asientos_ofrecidos IS NULL OR p_distancia_km IS NULL THEN
        RETURN NULL;
    END IF;
    IF p_asientos_ofrecidos <= 0 OR p_distancia_km <= 0 THEN
        RAISE EXCEPTION
        'ASK: asientos y distancia deben ser positivos';
    END IF;
    RETURN ROUND(p_asientos_ofrecidos * p_distancia_km, 2);
END;
$$ LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER;

COMMENT ON FUNCTION gold.fn_calcular_ask IS
'Calcula ASK (Available Seat Kilometers) = asientos × distancia km. KPI estándar IATA que mide la capacidad ofertada. Es el denominador para Load Factor y RASK.';

SELECT gold.fn_calcular_ask(180, 1200);  -- Debe dar 216000.00

--3.
-- =========================================================
-- FUNCIÓN: Cálculo de Load Factor
-- =========================================================
CREATE OR REPLACE FUNCTION gold.fn_calcular_load_factor(
    p_pax_transportados INT,
    p_asientos_ofrecidos INT
)
RETURNS DECIMAL(5,2) AS $$
DECLARE
    v_lf DECIMAL(5,2);
BEGIN
    /*
      KPI estándar IATA      
      LF = (Pax transportados / Asientos ofrecidos) × 100   
      Indicador crítico de eficiencia operativa
      Benchmark IATA 2025: 83.6% global (récord histórico)  
      Interpretación:
        > 85%  : Excelente
        75-85% : Regular
        < 75%  : Bajo (capacidad ociosa)
    */
    IF p_pax_transportados IS NULL OR p_asientos_ofrecidos IS NULL THEN
        RETURN NULL;
    END IF;
    IF p_asientos_ofrecidos = 0 THEN
        RETURN 0;
    END IF;
    v_lf := ROUND(
        (p_pax_transportados::DECIMAL / p_asientos_ofrecidos) * 100,
        2
    );
    -- Validar rango lógico
    IF v_lf > 100 THEN
        RAISE NOTICE
        'LOAD FACTOR ANÓMALO: % %% (pax > asientos)',
        v_lf;
        RETURN 100;
    END IF;
    RETURN v_lf;
END;
$$ LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER;

COMMENT ON FUNCTION gold.fn_calcular_load_factor IS
'Calcula el Load Factor (%) = pax / asientos × 100. KPI crítico de eficiencia operativa. Benchmark IATA 2025: 83.6% promedio global. Devuelve 0 si no hay asientos y máximo 100 si hay anomalías.';

SELECT gold.fn_calcular_load_factor(144, 180);  -- Debe dar 80.00

--4.
-- =========================================================
-- FUNCIÓN: Cálculo de Yield (Revenue por RPK)
-- =========================================================
CREATE OR REPLACE FUNCTION gold.fn_calcular_yield(
    p_revenue_usd DECIMAL(12,2),
    p_rpk DECIMAL(12,2)
)
RETURNS DECIMAL(8,4) AS $$
BEGIN
    /*
      KPI estándar IATA      
      Yield = Revenue de pasajeros / RPK     
      Mide el ingreso promedio generado por cada km volado
      Útil para comparar rentabilidad entre rutas y aerolíneas    
      Benchmark típico:
        LCC          : 0.05 - 0.12 USD/RPK
        Full-Service : 0.15 - 0.30 USD/RPK
    */
    IF p_revenue_usd IS NULL OR p_rpk IS NULL OR p_rpk = 0 THEN
        RETURN NULL;
    END IF;
    IF p_revenue_usd < 0 THEN
        RAISE EXCEPTION
        'YIELD: revenue no puede ser negativo';
    END IF;
    RETURN ROUND(p_revenue_usd / p_rpk, 4);
END;
$$ LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER;

SELECT gold.fn_calcular_yield(15000, 172800);  -- Debe dar 0.0868

COMMENT ON FUNCTION gold.fn_calcular_yield IS
'Calcula Yield = Revenue / RPK (USD por RPK). KPI estándar IATA para análisis de rentabilidad por ruta. Rangos típicos: LCC 0.05-0.12, Full-Service 0.15-0.30.';

--5.
-- =========================================================
-- FUNCIÓN: Cálculo de CTK (Cargo Tonne-Kilometers)
-- =========================================================
CREATE OR REPLACE FUNCTION gold.fn_calcular_ctk(
    p_cargo_kg DECIMAL(12,2),
    p_distancia_km DECIMAL(8,2)
)
RETURNS DECIMAL(14,2) AS $$
BEGIN
    /*
      KPI estándar IATA      
      CTK = Toneladas de carga × Distancia (km)     
      Mide el volumen real de carga transportada
      Benchmark IATA 2025: crecimiento 3.4% vs 2024    
      Conversión: 1 tonelada = 1000 kg
    */
    IF p_cargo_kg IS NULL OR p_distancia_km IS NULL THEN
        RETURN NULL;
    END IF;
    IF p_cargo_kg < 0 OR p_distancia_km < 0 THEN
        RAISE EXCEPTION
        'CTK: cargo_kg y distancia_km no pueden ser negativos';
    END IF;
    -- Convertir kg a toneladas y multiplicar por distancia
    RETURN ROUND((p_cargo_kg / 1000.0) * p_distancia_km, 2);
END;
$$ LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER;

SELECT gold.fn_calcular_ctk(5000, 1200);  -- Debe dar 6000.00 (5 toneladas × 1200 km)

COMMENT ON FUNCTION gold.fn_calcular_ctk IS
'Calcula CTK (Cargo Tonne-Kilometers) = toneladas × distancia km. KPI estándar IATA para demanda de carga aérea. Convierte kg a toneladas (1 ton = 1000 kg).';


















































