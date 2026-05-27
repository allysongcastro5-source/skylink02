                                                              ---ETL Bronze to Silver
--ETL silver.aerolineas
ALTER TABLE silver.aerolineas
DROP CONSTRAINT IF EXISTS aerolineas_codigo_iata_check,
DROP CONSTRAINT IF EXISTS aerolineas_codigo_icao_check,
DROP CONSTRAINT IF EXISTS aerolineas_pais_base_check;


ALTER TABLE silver.aerolineas
ADD CONSTRAINT aerolineas_codigo_iata_check
CHECK (
    codigo_iata IS NULL
    OR char_length(trim(codigo_iata)) <= 2
),
ADD CONSTRAINT aerolineas_codigo_icao_check
CHECK (
    codigo_icao IS NULL
    OR char_length(trim(codigo_icao)) <= 3
),
ADD CONSTRAINT aerolineas_pais_base_check
CHECK (
    pais_base IS NULL
    OR char_length(trim(pais_base)) <= 2
);

INSERT INTO silver.aerolineas (
    codigo_iata,
    codigo_icao,
    nombre,
    pais_base,
    activa
)
SELECT DISTINCT
    LEFT(callsign,2) AS codigo_iata,
    LEFT(callsign,3) AS codigo_icao,
    CASE LEFT(callsign,3)
        WHEN 'AVA' THEN 'Avianca'
        WHEN 'DAL' THEN 'Delta Air Lines'
        WHEN 'UAL' THEN 'United Airlines'
        WHEN 'AAL' THEN 'American Airlines'
        WHEN 'IBE' THEN 'Iberia'
        WHEN 'AFR' THEN 'Air France'
        WHEN 'KLM' THEN 'KLM'
        WHEN 'BAW' THEN 'British Airways'
        WHEN 'CMP' THEN 'Copa Airlines'
        WHEN 'JBU' THEN 'JetBlue'
        WHEN 'QTR' THEN 'Qatar Airways'
        WHEN 'ACA' THEN 'Air Canada'
        WHEN 'SWA' THEN 'Southwest Airlines'
        WHEN 'VOI' THEN 'Volaris'
        WHEN 'JAL' THEN 'Japan Airlines'
        ELSE 'Unknown Airline'
    END AS nombre,
    CASE LEFT(callsign,3)
        WHEN 'AVA' THEN 'CO'
        WHEN 'DAL' THEN 'US'
        WHEN 'UAL' THEN 'US'
        WHEN 'AAL' THEN 'US'
        WHEN 'IBE' THEN 'ES'
        WHEN 'AFR' THEN 'FR'
        WHEN 'KLM' THEN 'NL'
        WHEN 'BAW' THEN 'GB'
        WHEN 'CMP' THEN 'PA'
        WHEN 'JBU' THEN 'US'
        WHEN 'QTR' THEN 'QA'
        WHEN 'ACA' THEN 'CA'
        WHEN 'SWA' THEN 'US'
        WHEN 'VOI' THEN 'MX'
        WHEN 'JAL' THEN 'JP'
        ELSE 'UN'
    END AS pais_base,
    TRUE
FROM bronze.raw_flight_plans
WHERE callsign IS NOT null
  AND trim(callsign) <> '';
--aeronaves 
INSERT INTO silver.aeronaves (
    matricula,
    tipo,
    configuracion_asientos,
    horas_vuelo_totales,
    estado,
    fecha_entrada_servicio
)
SELECT
    /* =========================================
       Matrícula
       ========================================= */
    'TI-' || LPAD(gs::text,4,'0'),
    /* =========================================
       Tipo aeronave
       ========================================= */
    CASE
        WHEN random() < 0.25 THEN 'Airbus A320'
        WHEN random() < 0.50 THEN 'B737-800'
        WHEN random() < 0.75 THEN 'Airbus A330'
        ELSE 'B787-9'
    END,
    /* =========================================
       Configuración asientos JSONB
       ========================================= */
    CASE
        WHEN random() < 0.25 THEN
            '{"economy":180}'::jsonb
        WHEN random() < 0.50 THEN
            '{"business":16,"economy":150}'::jsonb
        WHEN random() < 0.75 THEN
            '{"business":24,"economy":220}'::jsonb
        ELSE
            '{"business":30,"economy":260}'::jsonb
    END,
    /* =========================================
       Horas vuelo
       ========================================= */
    ROUND((500 + random()*60000)::numeric,2),
    /* =========================================
       Estado
       ========================================= */
    CASE
        WHEN random() < 0.85 THEN 'ACTIVO'
        WHEN random() < 0.95 THEN 'MANTENIMIENTO'
        ELSE 'RETIRADO'
    END,
    /* =========================================
       Fecha entrada servicio
       ========================================= */
    CURRENT_DATE - FLOOR(random()*5000)::int
FROM generate_series(1,100) AS gs;


----ETL silver.aerovias
INSERT INTO silver.aerovias (
    designador,
    tipo,
    geometria,
    nivel_min,
    nivel_max,
    longitud_nm
)
SELECT
    /* =========================================
       Designador ATS
       ========================================= */
    CASE
        WHEN random() < 0.33 THEN 'UL'
        WHEN random() < 0.66 THEN 'Q'
        ELSE 'Y'
    END
    || FLOOR(100 + random()*900)::int,
    /* =========================================
       Tipo aerovía
       ========================================= */
    CASE
        WHEN random() < 0.33 THEN 'AWY'
        WHEN random() < 0.66 THEN 'JET'
        ELSE 'RNAV'
    END,
    /* =========================================
       Geometría LINESTRINGZ
       ========================================= */
    ST_GeomFromText(
        'LINESTRING Z(' ||
        (-180 + random()*360) || ' ' ||
        (-90 + random()*180) || ' ' ||
        (20000 + random()*20000) ||
        ',' ||
        (-180 + random()*360) || ' ' ||
        (-90 + random()*180) || ' ' ||
        (20000 + random()*20000)
        || ')',
        4979
    ),
    /* =========================================
       Nivel mínimo
       ========================================= */
    FLOOR(50 + random()*200)::int,
    /* =========================================
       Nivel máximo
       ========================================= */
    FLOOR(250 + random()*200)::int,
    /* =========================================
       Longitud NM
       ========================================= */
    ROUND((50 + random()*500)::numeric,2)
FROM generate_series(1,75);

----ETL silver.vuelos 
INSERT INTO silver.vuelos (
    numero_vuelo,
    aerolinea_id,
    aeronave_id,
    origen_id,
    destino_id,
    aerovia_id,
    salida_programada,
    llegada_programada,
    salida_real,
    llegada_real,
    estado,
    motivo_desviacion
)
SELECT
    /* =========================================
       Número vuelo
       ========================================= */
    fp.callsign,
    /* =========================================
       Aerolínea
       ========================================= */
    al.aerolinea_id,
    /* =========================================
       Aeronave aleatoria
       ========================================= */
    (
        SELECT aeronave_id
        FROM silver.aeronaves
        ORDER BY random()
        LIMIT 1
    ),
    /* =========================================
       Aeropuerto origen
       ========================================= */
    ao.aeropuerto_id,
    /* =========================================
       Aeropuerto destino
       ========================================= */
    ad.aeropuerto_id,
    /* =========================================
       Aerovía aleatoria
       ========================================= */
    (
        SELECT aerovia_id
        FROM silver.aerovias
        ORDER BY random()
        LIMIT 1
    ),
    /* =========================================
       Salida programada
       SIEMPRE antes ETA
       ========================================= */
    fp.eta::timestamptz
        - ((1 + random()*10) * INTERVAL '1 hour'),
    /* =========================================
       Llegada programada
       ========================================= */
    fp.eta::timestamptz,
    /* =========================================
       Salida real
       ========================================= */
    fp.eta::timestamptz
        - ((0.5 + random()*8) * INTERVAL '1 hour'),
    /* =========================================
       Llegada real
       ========================================= */
    CASE
        WHEN random() < 0.7 THEN
            fp.eta::timestamptz
                + ((random()*30) * INTERVAL '1 minute')
        ELSE NULL
    END,
    /* =========================================
       Estado operacional
       ========================================= */
    CASE
        WHEN random() < 0.60 THEN 'SCHED'
        WHEN random() < 0.80 THEN 'ACTIVE'
        WHEN random() < 0.95 THEN 'LANDED'
        WHEN random() < 0.98 THEN 'DIVERTED'
        ELSE 'CANCEL'
    END,
    /* =========================================
       Motivo desviación
       ========================================= */
    CASE
        WHEN random() < 0.05 THEN 'WEATHER'
        WHEN random() < 0.08 THEN 'TECHNICAL'
        ELSE NULL
    END
FROM bronze.raw_flight_plans fp
/* =========================================
   JOIN aerolínea
   ========================================= */
JOIN silver.aerolineas al
    ON LEFT(fp.callsign,3) = al.codigo_icao
/* =========================================
   JOIN aeropuerto origen
   ========================================= */
JOIN silver.aeropuertos ao
    ON fp.origen_icao = ao.ident
/* =========================================
   JOIN aeropuerto destino
   ========================================= */
JOIN silver.aeropuertos ad
    ON fp.destino_icao = ad.ident
/* =========================================
   Validaciones ETL
   ========================================= */
WHERE fp.callsign IS NOT NULL
  AND trim(fp.callsign) <> ''
  AND fp.origen_icao IS NOT NULL
  AND fp.destino_icao IS NOT NULL;


--Silver pasajeros
INSERT INTO silver.pasajeros (
    documento,
    tipo_doc,
    nacionalidad,
    nombre,
    fecha_nacimiento,
    programa_fidelidad,
    categoria
)
SELECT DISTINCT
    /* =========================================
       Documento sintético basado PNR
       ========================================= */
    'DOC-' || reserva_id, 
    /* =========================================
       Tipo documento
       ========================================= */
    COALESCE(
        pasajero_json::json->>'document_type',
        'PASSPORT'
    ),
    /* =========================================
       Nacionalidad
       ========================================= */
    COALESCE(
        pasajero_json::json->>'nationality',
        'CR'
    ),
    /* =========================================
       Nombre completo
       ========================================= */
    TRIM(
        COALESCE(
            pasajero_json::json->>'first_name',
            ''
        )
        || ' ' ||
        COALESCE(
            pasajero_json::json->>'last_name',
            ''
        )
    ),
    /* =========================================
       Fecha nacimiento sintética
       ========================================= */
    CURRENT_DATE
        - FLOOR(7000 + random()*15000)::int,
    /* =========================================
       Programa fidelidad
       ========================================= */
    CASE
        WHEN (pasajero_json::json->>'frequent_flyer')::boolean = true
            THEN 'GOLD'
        ELSE NULL
    END,
    /* =========================================
       Categoría según clase
       ========================================= */
    CASE
        WHEN clase IN ('F','J') THEN 'FIRST'
        WHEN clase IN ('C','W') THEN 'BUSINESS'
        ELSE 'ECONOMY'
    END
FROM bronze.raw_reservations
WHERE pasajero_json IS NOT NULL;


--ETL Silver,pasajero_vuelo
--Insertar los 10 callsigns que faltan en silver.vuelos
INSERT INTO silver.vuelos (
    numero_vuelo,
    aerolinea_id,
    aeronave_id,
    origen_id,
    destino_id,
    aerovia_id,
    salida_programada,
    llegada_programada,
    salida_real,
    llegada_real,
    estado
)
SELECT
    fn.numero_vuelo,
    COALESCE(
        (SELECT al.aerolinea_id FROM silver.aerolineas al
         WHERE al.codigo_icao = fn.airline_icao LIMIT 1),
        (SELECT aerolinea_id FROM silver.aerolineas ORDER BY random() LIMIT 1)
    ),
    (SELECT aeronave_id FROM silver.aeronaves ORDER BY random() LIMIT 1),
    (SELECT aeropuerto_id FROM silver.aeropuertos ORDER BY random() LIMIT 1),
    (SELECT aeropuerto_id FROM silver.aeropuertos ORDER BY random() LIMIT 1),
    (SELECT aerovia_id FROM silver.aerovias ORDER BY random() LIMIT 1),
    salida.salida_programada,
    salida.salida_programada + INTERVAL '3 hours',
    NULL,
    NULL,
    'SCHED'
FROM (
    VALUES
        ('CM392',  'CMP'),
        ('UA889',  'UAL'),
        ('IB6401', 'IBE'),
        ('AA102',  'AAL'),
        ('BA221',  'BAW'),
        ('AV201',  'AVA'),
        ('DL405',  'DAL'),
        ('AF188',  'AFR'),
        ('LH450',  'DLH'),
        ('KL755',  'KLM')
) AS fn(numero_vuelo, airline_icao)
CROSS JOIN LATERAL (
    SELECT NOW() - (random() * 30 || ' days')::interval AS salida_programada
) AS salida
WHERE NOT EXISTS (
    SELECT 1 FROM silver.vuelos v
    WHERE v.numero_vuelo = fn.numero_vuelo
);

--Paso Verificar que se insertaron
SELECT numero_vuelo, vuelo_id
FROM silver.vuelos
WHERE numero_vuelo IN ('CM392','UA889','IB6401','AA102','BA221','AV201','DL405','AF188','LH450','KL755')
ORDER BY numero_vuelo;


-- ETL con una fila por reserva
INSERT INTO silver.pasajeros_vuelo (
    vuelo_id,
    pasajero_id,
    pnr,
    clase,
    asiento,
    tarifa_usd,
    estado,
    equipaje_piezas,
    equipaje_peso_kg
)
SELECT DISTINCT ON (r.reserva_id)
    v.vuelo_id,
    p.pasajero_id,
    LEFT(r.pnr, 10),
    LEFT(r.clase, 5),
    COALESCE(LEFT(b.asiento, 5), 'NA'),
    r.tarifa_usd,
    CASE
        WHEN b.boarding_id IS NOT NULL THEN 'BOARDED'
        WHEN UPPER(r.estado) IN ('CONFIRMED','CHECKED','NOSHOW') THEN UPPER(r.estado)
        ELSE 'CONFIRMED'
    END,
    FLOOR(1 + random() * 3)::int,
    ROUND((5 + random() * 25)::numeric, 2)
FROM bronze.raw_reservations r
JOIN silver.pasajeros p
  ON p.nombre = (r.pasajero_json->>'first_name') || ' ' || (r.pasajero_json->>'last_name')
 AND p.nacionalidad = (r.pasajero_json->>'nationality')
JOIN silver.vuelos v
  ON v.numero_vuelo = r.vuelos_json->>'flight_number'
LEFT JOIN bronze.raw_boarding b
  ON b.pnr = r.pnr
WHERE r.pnr                            IS NOT NULL
  AND r.vuelos_json->>'flight_number'  IS NOT NULL
ORDER BY r.reserva_id, p.pasajero_id, b.timestamp_utc DESC NULLS LAST;

--Cómo verificarlo
SELECT
    COUNT(*)                              AS total_filas,
    COUNT(DISTINCT pnr)                   AS pnrs_unicos,
    COUNT(DISTINCT vuelo_id)              AS vuelos_distintos,
    COUNT(DISTINCT pasajero_id)           AS pasajeros_distintos,
    SUM(CASE WHEN estado = 'BOARDED' THEN 1 ELSE 0 END) AS abordados
FROM silver.pasajeros_vuelo;


-- ETL silver.equipaje
INSERT INTO silver.equipaje (
    tag_id,
    pnr,
    vuelo_id,
    peso_kg,
    tipo,
    estado,
    ubicacion_actual,
    timestamp_ultimo_evento
)
SELECT DISTINCT ON (b.tag_id)
    LEFT(b.tag_id, 20),
    LEFT(b.pnr, 10),
    v.vuelo_id,
    ROUND((5 + random() * 25)::numeric, 2),
    CASE
        WHEN random() < 0.70 THEN 'NORMAL'
        WHEN random() < 0.85 THEN 'FRAGIL'
        WHEN random() < 0.95 THEN 'DEPORTIVO'
        ELSE 'INSTRUMENTO'
    END,
    CASE UPPER(b.evento)
        WHEN 'CHECKIN'   THEN 'CHECKED'
        WHEN 'LOAD'      THEN 'LOADED'
        WHEN 'LOADED'    THEN 'LOADED'
        WHEN 'TRANSFER'  THEN 'TRANSFER'
        WHEN 'UNLOAD'    THEN 'UNLOADED'
        WHEN 'UNLOADED'  THEN 'UNLOADED'
        WHEN 'DELIVERED' THEN 'DELIVERED'
        WHEN 'LOST'      THEN 'LOST'
        ELSE 'CHECKED'
    END,
    LEFT(b.aeropuerto, 50),
    b.timestamp_utc
FROM bronze.raw_baggage b
JOIN silver.vuelos v
  ON v.numero_vuelo = b.vuelo_id
WHERE b.tag_id        IS NOT NULL
  AND b.pnr           IS NOT NULL
  AND b.timestamp_utc IS NOT NULL
ORDER BY b.tag_id, b.timestamp_utc DESC;



-- ETL CARGA_VUELO
INSERT INTO silver.carga_vuelo (
    vuelo_id,
    awb,
    shipper,
    consignee,
    tipo,
    peso_kg,
    volumen_m3,
    origen,
    destino,
    temperatura_req,
    declaracion_aduanera
)
SELECT DISTINCT ON (c.awb)
    v.vuelo_id,
    LEFT(c.awb, 20),
    LEFT(c.declaracion_json->>'shipper', 200),
    LEFT(c.declaracion_json->>'consignee', 200),
    CASE
        WHEN UPPER(c.tipo_carga) IN ('GENERAL','PERECIBLE','PELIGROSA','VALORADA','ANIMALES')
        THEN UPPER(c.tipo_carga)
        ELSE 'GENERAL'
    END,
    c.peso_kg::numeric(8,2),
    c.volumen_m3::numeric(6,2),
    LEFT(c.origen, 4),
    LEFT(c.destino, 4),
    LEFT(c.declaracion_json->>'temperatura_req', 10),
    c.declaracion_json
FROM bronze.raw_cargo c
JOIN silver.vuelos v
  ON v.numero_vuelo = c.vuelo_id
WHERE c.awb       IS NOT NULL
  AND c.peso_kg   IS NOT NULL AND c.peso_kg   > 0
  AND c.volumen_m3 IS NOT NULL AND c.volumen_m3 > 0
ORDER BY c.awb, v.vuelo_id;

--data sintetica tabla carga_vuelo 
UPDATE silver.carga_vuelo
SET
    shipper = (ARRAY[
        'DHL Express Worldwide',
        'FedEx International Priority',
        'UPS Air Freight',
        'Kuehne+Nagel Aerocargo',
        'DB Schenker Logistics',
        'Maersk Air Freight',
        'CEVA Logistics SA',
        'Expeditors International',
        'Bolloré Logistics',
        'Nippon Express Cargo',
        'Panalpina Welttransport',
        'Yusen Logistics Global',
        'Agility Logistics Hub',
        'Hellmann Worldwide',
        'Geodis Air & Sea'
    ])[FLOOR(1 + random() * 15)::int],

    consignee = (ARRAY[
        'Amazon Global Logistics',
        'Walmart Import Center',
        'Apple Distribution International',
        'Samsung Electronics Logistics',
        'Nike Worldwide Distribution',
        'Zara Inditex Imports',
        'Carrefour Global Sourcing',
        'IKEA Supply Chain',
        'Unilever International Trade',
        'Procter & Gamble Imports',
        'Nestlé Global Distribution',
        'Sony Logistics Network',
        'LG Electronics Cargo',
        'H&M Hennes Imports',
        'Adidas Group Logistics'
    ])[FLOOR(1 + random() * 15)::int],

    temperatura_req = CASE
        WHEN tipo = 'PERECIBLE' THEN
            (ARRAY['2-8C','-18C','-25C','0-4C'])[FLOOR(1 + random() * 4)::int]
        WHEN tipo = 'ANIMALES' THEN
            (ARRAY['15-25C','18-22C'])[FLOOR(1 + random() * 2)::int]
        WHEN tipo = 'VALORADA' THEN 'AMBIENT'
        WHEN tipo = 'PELIGROSA' THEN
            (ARRAY['AMBIENT','15-30C','COOL'])[FLOOR(1 + random() * 3)::int]
        ELSE 'AMBIENT'
    END
WHERE shipper IS NULL
   OR consignee IS NULL
   OR temperatura_req IS NULL;
--"El JSON de declaracion_json en bronze no incluye datos de shipper/consignee (campos sensibles por temas de privacidad comercial). Se enriquecieron 
--sintéticamente en silver para mantener el modelo completo, aplicando lógica de negocio (por ejemplo: la temperatura requerida varía según el tipo de carga)."

    
-- ETL TRIPULACION_VUELO
    --Paso 1 — Agregar los 7 callsigns de crew a silver.vuelos
INSERT INTO silver.vuelos (
    numero_vuelo,
    aerolinea_id,
    aeronave_id,
    origen_id,
    destino_id,
    aerovia_id,
    salida_programada,
    llegada_programada,
    salida_real,
    llegada_real,
    estado
)
SELECT
    fn.numero_vuelo,
    COALESCE(
        (SELECT al.aerolinea_id FROM silver.aerolineas al
         WHERE al.codigo_icao = fn.airline_icao LIMIT 1),
        (SELECT aerolinea_id FROM silver.aerolineas ORDER BY random() LIMIT 1)
    ),
    (SELECT aeronave_id FROM silver.aeronaves ORDER BY random() LIMIT 1),
    (SELECT aeropuerto_id FROM silver.aeropuertos ORDER BY random() LIMIT 1),
    (SELECT aeropuerto_id FROM silver.aeropuertos ORDER BY random() LIMIT 1),
    (SELECT aerovia_id FROM silver.aerovias ORDER BY random() LIMIT 1),
    salida.salida_programada,
    salida.salida_programada + INTERVAL '3 hours',
    NULL,
    NULL,
    'SCHED'
FROM (
    VALUES
        ('AFR221',  'AFR'),
        ('AVA245',  'AVA'),
        ('CMP432',  'CMP'),
        ('DAL120',  'DAL'),
        ('IBE6401', 'IBE'),
        ('KLM777',  'KLM'),
        ('UAL998',  'UAL')
) AS fn(numero_vuelo, airline_icao)
CROSS JOIN LATERAL (
    SELECT NOW() - (random() * 30 || ' days')::interval AS salida_programada
) AS salida
WHERE NOT EXISTS (
    SELECT 1 FROM silver.vuelos v
    WHERE v.numero_vuelo = fn.numero_vuelo
);

--Paso 2 — Verificar que se insertaron
SELECT numero_vuelo, vuelo_id
FROM silver.vuelos
WHERE numero_vuelo IN ('AFR221','AVA245','CMP432','DAL120','IBE6401','KLM777','UAL998')
ORDER BY numero_vuelo;

--Paso 3 — ETL de silver.tripulacion_vuelo 
INSERT INTO silver.tripulacion_vuelo (
    vuelo_id,
    rol,
    report_time,
    duty_start,
    duty_end,
    horas_vuelo_duty,
    descanso_horas,
    descanso_minimo_requerido,
    descanso_minimo_cumple
)
SELECT DISTINCT ON (c.roster_id)
    v.vuelo_id,
    /* Mapeo de roles bronze → silver (CHECK constraint) */
    CASE UPPER(c.rol)
        WHEN 'CAPTAIN'        THEN 'CAPTAIN'
        WHEN 'FIRST_OFFICER'  THEN 'FO'
        WHEN 'FO'             THEN 'FO'
        WHEN 'RELIEF_PILOT'   THEN 'RELIEF_CAPTAIN'
        WHEN 'RELIEF_CAPTAIN' THEN 'RELIEF_CAPTAIN'
        WHEN 'PURSER'         THEN 'PURSER'
        WHEN 'CABIN_CREW'     THEN 'FA'
        WHEN 'FA'             THEN 'FA'
        WHEN 'LOADMASTER'     THEN 'LOADMASTER'
        ELSE 'FA'   -- fallback para roles desconocidos o nulos
    END AS rol,
    c.report_time AT TIME ZONE 'UTC',
    c.report_time AT TIME ZONE 'UTC',
    (c.report_time + (c.duty_hours || ' hours')::interval) AT TIME ZONE 'UTC',
    LEAST(c.duty_hours, 12)::numeric(4,2),
    ROUND((10 + random() * 4)::numeric, 2),
    10.00,
    CASE WHEN (10 + random() * 4) >= 10 THEN TRUE ELSE FALSE END
FROM bronze.raw_crew c
JOIN silver.vuelos v
  ON v.numero_vuelo = c.vuelo_id
WHERE c.vuelo_id    IS NOT NULL
  AND c.report_time IS NOT NULL
  AND c.duty_hours  IS NOT NULL
  AND c.duty_hours  > 0
ORDER BY c.roster_id;

--Verificación post-ETL
SELECT
    COUNT(*) AS total_filas,
    COUNT(DISTINCT vuelo_id) AS vuelos_distintos,
    rol, COUNT(*) AS por_rol
FROM silver.tripulacion_vuelo
GROUP BY ROLLUP(rol)
ORDER BY rol;

--ETL silver.aeronaves
--PASO 1 — Agregar las 6 aeronaves del bronze a silver.aeronaves
INSERT INTO silver.aeronaves (
    matricula,
    tipo,
    configuracion_asientos,
    horas_vuelo_totales,
    estado,
    fecha_entrada_servicio
)
SELECT
    mat.matricula,
    mat.tipo,
    mat.config::jsonb,
    ROUND((500 + random() * 60000)::numeric, 2),
    'ACTIVO',
    CURRENT_DATE - FLOOR(random() * 5000)::int
FROM (
    VALUES
        ('TI-BGU',     'B737-800',     '{"business":16,"economy":150}'),
        ('F-GZND',     'Airbus A330',  '{"business":24,"economy":220}'),
        ('HP-1823CMP', 'B737-800',     '{"business":16,"economy":150}'),
        ('N123AA',     'B787-9',       '{"business":30,"economy":260}'),
        ('N456DL',     'Airbus A320',  '{"economy":180}'),
        ('EC-MXA',     'Airbus A320',  '{"economy":180}')
) AS mat(matricula, tipo, config)
WHERE NOT EXISTS (
    SELECT 1 FROM silver.aeronaves a
    WHERE a.matricula = mat.matricula
);

--PASO 2 — Poblar silver.talleres_mro
--Con los 6 talleres del bronze + aeropuertos reales:
INSERT INTO silver.talleres_mro (
    nombre,
    aeropuerto_id,
    tipo,
    capacidad_aeronaves,
    certificaciones,
    activo
)
SELECT
    t.nombre,
    /* Asignamos un aeropuerto basado en el código del taller (BOG, LAX, etc.) */
    COALESCE(
        (SELECT aeropuerto_id FROM silver.aeropuertos WHERE iata = t.iata_code LIMIT 1),
        (SELECT aeropuerto_id FROM silver.aeropuertos ORDER BY random() LIMIT 1)
    ),
    t.tipo,
    t.capacidad,
    t.certificaciones,
    TRUE
FROM (
    VALUES
        ('MRO Bogotá',    'BOG', 'HANGAR',    8,  ARRAY['EASA-145','FAA-145']),
        ('MRO Los Angeles','LAX','HANGAR',   12,  ARRAY['FAA-145','TCCA']),
        ('MRO Madrid',    'MAD', 'ENGINE',    6,  ARRAY['EASA-145','EASA-21']),
        ('MRO Miami',     'MIA', 'LINE',     20,  ARRAY['FAA-145']),
        ('MRO Panamá',    'PTY', 'COMPONENT', 4,  ARRAY['EASA-145','DGAC-PA']),
        ('MRO San José',  'SJO', 'LINE',     10,  ARRAY['DGAC-CR','FAA-145'])
) AS t(nombre, iata_code, tipo, capacidad, certificaciones);

--PASO 3 — Poblar silver.motores
INSERT INTO silver.motores (
    aeronave_id,
    posicion,
    modelo,
    serial_number,
    horas_acumuladas,
    ciclos_acumulados
)
SELECT
    a.aeronave_id,
    pos.posicion,
    /* Modelo de motor según tipo de aeronave */
    CASE
        WHEN a.tipo LIKE '%A320%' OR a.tipo LIKE '%A330%' THEN
            (ARRAY['CFM56-5B','V2500','PW1100'])[FLOOR(1 + random()*3)::int]
        WHEN a.tipo LIKE '%B737%' THEN 'CFM56-7B'
        WHEN a.tipo LIKE '%B787%' THEN
            (ARRAY['TRENT-1000','GENX-1B'])[FLOOR(1 + random()*2)::int]
        ELSE 'CFM56-7B'
    END AS modelo,
    /* Serial trazable */
    'SN-' || a.matricula || '-' || pos.posicion AS serial_number,
    ROUND((1000 + random() * 50000)::numeric, 2),
    FLOOR(500 + random() * 30000)::int
FROM silver.aeronaves a
CROSS JOIN (VALUES (1), (2)) AS pos(posicion)
WHERE NOT EXISTS (
    SELECT 1 FROM silver.motores m
    WHERE m.aeronave_id = a.aeronave_id
      AND m.posicion    = pos.posicion
);

--PASO 4 — Verificar antes del ETL
SELECT 'aeronaves' AS tabla, COUNT(*) AS filas FROM silver.aeronaves
UNION ALL
SELECT 'talleres_mro', COUNT(*) FROM silver.talleres_mro
UNION ALL
SELECT 'motores', COUNT(*) FROM silver.motores;

/* Verificar que las 6 matrículas del bronze ahora existen */
SELECT m.aeronave_id AS bronze_matricula, a.aeronave_id AS silver_id
FROM (VALUES ('TI-BGU'),('F-GZND'),('HP-1823CMP'),('N123AA'),('N456DL'),('EC-MXA')) AS m(aeronave_id)
LEFT JOIN silver.aeronaves a ON a.matricula = m.aeronave_id;

--ETL silver.mantenimiento_eventos
INSERT INTO silver.mantenimiento_eventos (
    aeronave_id,
    motor_id,
    tipo_check,
    componente,
    descripcion,
    taller_id,
    tecnico_id,
    horas_aeronave,
    fecha_inicio,
    fecha_fin,
    costo_usd,
    estado
)
SELECT DISTINCT ON (m.evento_id)
    a.aeronave_id,
    (SELECT motor_id FROM silver.motores mo
     WHERE mo.aeronave_id = a.aeronave_id
     ORDER BY mo.posicion LIMIT 1) AS motor_id,
    CASE UPPER(m.accion)
        WHEN 'INSPECTION'  THEN 'A'
        WHEN 'CLEANING'    THEN 'LINE'
        WHEN 'TEST'        THEN 'LINE'
        WHEN 'REPAIR'      THEN 'B'
        WHEN 'REPLACEMENT' THEN 'C'
        WHEN 'OVERHAUL'    THEN 'D'
        ELSE 'LINE'
    END,
    LEFT(COALESCE(m.componente, 'GENERAL'), 50),
    m.accion,
    CASE UPPER(m.taller_id)
        WHEN 'MRO-BOG' THEN (SELECT taller_id FROM silver.talleres_mro WHERE nombre = 'MRO Bogotá')
        WHEN 'MRO-LAX' THEN (SELECT taller_id FROM silver.talleres_mro WHERE nombre = 'MRO Los Angeles')
        WHEN 'MRO-MAD' THEN (SELECT taller_id FROM silver.talleres_mro WHERE nombre = 'MRO Madrid')
        WHEN 'MRO-MIA' THEN (SELECT taller_id FROM silver.talleres_mro WHERE nombre = 'MRO Miami')
        WHEN 'MRO-PTY' THEN (SELECT taller_id FROM silver.talleres_mro WHERE nombre = 'MRO Panamá')
        WHEN 'MRO-SJO' THEN (SELECT taller_id FROM silver.talleres_mro WHERE nombre = 'MRO San José')
        ELSE (SELECT taller_id FROM silver.talleres_mro ORDER BY random() LIMIT 1)
    END AS taller_id,
    COALESCE(
        NULLIF(REGEXP_REPLACE(m.tecnico_id, '[^0-9]', '', 'g'), '')::int,
        FLOOR(1 + random() * 9999)::int
    ) AS tecnico_id,
    m.horas_aeronave::numeric(10,2),
    m.timestamp_utc AT TIME ZONE 'UTC',
    (m.timestamp_utc +
        CASE UPPER(m.accion)
            WHEN 'CLEANING'    THEN INTERVAL '2 hours'
            WHEN 'TEST'        THEN INTERVAL '4 hours'
            WHEN 'INSPECTION'  THEN INTERVAL '8 hours'
            WHEN 'REPAIR'      THEN INTERVAL '24 hours'
            WHEN 'REPLACEMENT' THEN INTERVAL '48 hours'
            WHEN 'OVERHAUL'    THEN INTERVAL '120 hours'
            ELSE INTERVAL '4 hours'
        END
    ) AT TIME ZONE 'UTC',
    ROUND((
        CASE UPPER(m.accion)
            WHEN 'CLEANING'    THEN 200  + random() * 1000
            WHEN 'TEST'        THEN 500  + random() * 2000
            WHEN 'INSPECTION'  THEN 1000 + random() * 5000
            WHEN 'REPAIR'      THEN 3000 + random() * 15000
            WHEN 'REPLACEMENT' THEN 8000 + random() * 40000
            WHEN 'OVERHAUL'    THEN 30000 + random() * 100000
            ELSE 500
        END
    )::numeric, 2),
    CASE
        WHEN random() < 0.75 THEN 'CLOSED'
        WHEN random() < 0.90 THEN 'INPROGRESS'
        WHEN random() < 0.97 THEN 'OPEN'
        ELSE 'DEFERRED'
    END
FROM bronze.raw_maintenance m
JOIN silver.aeronaves a
  ON a.matricula = m.aeronave_id
WHERE m.aeronave_id    IS NOT NULL
  AND m.timestamp_utc  IS NOT NULL
  AND m.horas_aeronave IS NOT NULL
  AND m.horas_aeronave >= 0
  AND m.accion         IS NOT NULL
ORDER BY m.evento_id;

--
SELECT
    COUNT(*) AS total_eventos,
    COUNT(taller_id) AS con_taller,
    COUNT(*) - COUNT(taller_id) AS sin_taller,
    COUNT(motor_id) AS con_motor
FROM silver.mantenimiento_eventos;


-- ETL COMBUSTIBLE_CARGA
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
SELECT DISTINCT ON (f.fuel_id)
    v.vuelo_id,
    ap.aeropuerto_id,
    f.litros::numeric(10,2),
    f.densidad_kgl::numeric(5,3),
    (f.litros * f.densidad_kgl)::numeric(10,2),
    /* precio por litro derivado del precio_usd total y litros */
    CASE
        WHEN f.litros > 0
        THEN ROUND((f.precio_usd / f.litros)::numeric, 4)
        ELSE 0
    END,
    f.precio_usd::numeric(12,2),
    f.timestamp_utc AT TIME ZONE 'UTC',
    ROUND((0.025 + random() * 0.010)::numeric, 4),
    ROUND((0.025 + random() * 0.015)::numeric, 4)
FROM bronze.raw_fuel f
JOIN silver.vuelos v
  ON v.numero_vuelo = f.vuelo_id
JOIN silver.aeropuertos ap
  ON ap.ident = f.aeropuerto_icao
WHERE f.litros          IS NOT NULL AND f.litros > 0
  AND f.densidad_kgl    IS NOT NULL AND f.densidad_kgl > 0
  AND f.precio_usd      IS NOT NULL AND f.precio_usd >= 0
  AND f.timestamp_utc   IS NOT NULL
ORDER BY f.fuel_id;


-- ETL POSICIONAMIENTO_VUELO
INSERT INTO silver.posicionamiento_vuelo (
    vuelo_id,
    timestamp_utc,
    coordenada,
    velocidad_nudos,
    heading,
    fase_vuelo,
    aerovia_cercana_id,
    desviacion_nm
)
SELECT DISTINCT ON (adsb.adsb_id)
    v.vuelo_id,
    adsb.timestamp_utc AT TIME ZONE 'UTC',
    /* Construye POINTZ con altitud (pies -> metros aprox) */
    ST_SetSRID(
        ST_MakePoint(
            ST_X(adsb.ubicacion::geometry),
            ST_Y(adsb.ubicacion::geometry),
            COALESCE(adsb.altitud_pies * 0.3048, 0)
        ),
        4979
    )::geography,
    adsb.velocidad_nudos::numeric(6,2),
    adsb.heading::numeric(5,2),
    /* Fase de vuelo derivada de altitud y velocidad */
    CASE
        WHEN adsb.altitud_pies < 1000  AND adsb.velocidad_nudos < 50  THEN 'TAXI'
        WHEN adsb.altitud_pies < 1500  AND adsb.velocidad_nudos >= 50 THEN 'TAKEOFF'
        WHEN adsb.altitud_pies BETWEEN 1500 AND 18000
             AND adsb.velocidad_nudos >= 200                          THEN 'CLIMB'
        WHEN adsb.altitud_pies > 28000                                THEN 'CRUISE'
        WHEN adsb.altitud_pies BETWEEN 10000 AND 28000                THEN 'DESCENT'
        WHEN adsb.altitud_pies BETWEEN 3000 AND 10000                 THEN 'APPROACH'
        ELSE 'LANDING'
    END,
    v.aerovia_id,                              -- aerovía del vuelo como "cercana"
    ROUND((random() * 5)::numeric, 2)          -- desviación simulada (0-5 NM)
FROM bronze.raw_adsb_positions adsb
JOIN silver.vuelos v
  ON v.numero_vuelo = adsb.raw_json->>'callsign'
WHERE adsb.ubicacion       IS NOT NULL
  AND adsb.timestamp_utc   IS NOT NULL
  AND adsb.velocidad_nudos IS NOT NULL
  AND adsb.heading         IS NOT NULL
ORDER BY adsb.adsb_id, v.vuelo_id;


-- ETL ENGINE_SENSORS
INSERT INTO silver.engine_sensors (
    engine_id,
    n1_pct,
    n2_pct,
    egt_c,
    fuel_flow_kgh,
    vibration,
    timestamp_utc
)
SELECT DISTINCT ON (s.sensor_id)
    s.engine_id,
    s.n1_pct,
    s.n2_pct,
    s.egt_c,
    s.fuel_flow_kgh,
    s.vibration,
    s.timestamp_utc
FROM bronze.raw_engine_sensors s
WHERE s.engine_id     IS NOT NULL
  AND s.timestamp_utc IS NOT NULL
  AND s.n1_pct        BETWEEN 0 AND 110
  AND s.n2_pct        BETWEEN 0 AND 110
  AND s.egt_c         BETWEEN -50 AND 1200
  AND s.fuel_flow_kgh >= 0
  AND s.vibration     >= 0
ORDER BY s.sensor_id;



--NOTAMS
INSERT INTO silver.notams (
    ident,
    aeropuerto_id,
    tipo,
    referencia,
    coordenada,
    radio_nm,
    altura_min,
    altura_max,
    valido_desde,
    valido_hasta,
    raw_text
)
SELECT
    (ARRAY['A','B','C','D','E'])[FLOOR(1 + random()*5)::int]
        || LPAD(FLOOR(1 + random()*9999)::text, 4, '0')
        || '/26' AS ident,
    ap.aeropuerto_id,
    (ARRAY['N','D','R','C'])[FLOOR(1 + random()*4)::int] AS tipo,
    'REF-' || LPAD(FLOOR(random()*99999)::text, 5, '0') || '/26' AS referencia,
    ST_SetSRID(ST_MakePoint(ap.longitude_deg, ap.latitude_deg), 4326)::geography AS coordenada,
    FLOOR(random() * 50)::int AS radio_nm,
    alturas.altura_min,
    alturas.altura_min + FLOOR(1000 + random() * 30000)::int AS altura_max,
    fechas.valido_desde,
    fechas.valido_desde + (FLOOR(1 + random() * 30) || ' days')::interval AS valido_hasta,
    'NOTAM ' ||
    (ARRAY[
        'RWY 07/25 CLOSED FOR MAINTENANCE',
        'TWY B CLOSED DUE TO PAVEMENT WORK',
        'ILS RWY 09 OUT OF SERVICE',
        'BIRD ACTIVITY VICINITY AERODROME',
        'CRANE OPERATING NEAR APRON',
        'FUEL SERVICE LIMITED AT FBO',
        'MILITARY EXERCISES IN AREA',
        'OBSTACLE LIGHTING UNSERVICEABLE',
        'NAVAID VOR/DME OUT OF SERVICE',
        'TAXIWAY LIGHTING REDUCED INTENSITY',
        'AIRSPACE RESTRICTED DUE TO VIP MOVEMENT',
        'WEATHER RADAR INOPERATIVE',
        'RUNWAY FRICTION LEVEL DEGRADED',
        'GROUND HANDLING SERVICES LIMITED',
        'TEMPORARY ATC FREQUENCY CHANGE'
    ])[FLOOR(1 + random()*15)::int] AS raw_text
FROM generate_series(1, 500) AS gs
CROSS JOIN LATERAL (
    SELECT aeropuerto_id, latitude_deg, longitude_deg
    FROM silver.aeropuertos
    WHERE latitude_deg  IS NOT NULL
      AND longitude_deg IS NOT NULL
    ORDER BY random()
    LIMIT 1
) AS ap
CROSS JOIN LATERAL (
    SELECT FLOOR(random() * 5000)::int AS altura_min
) AS alturas
CROSS JOIN LATERAL (
    SELECT NOW() - (FLOOR(random() * 90) || ' days')::interval AS valido_desde
) AS fechas;

--"En la capa bronze no existe una fuente de NOTAMs porque normalmente provienen de servicios externos como FAA/NOTAMS u OACI a través de APIs en tiempo real, que no formaban 
--parte del scope  de ingestión. Se generó data sintética en silver para mantener el modelo dimensional completo y permitir el análisis cruzado con vuelos, aeropuertos y trayectorias."