                                                                --DATA_SYNTHETIC
          --CAPA BRONZE    
--TABLA 1. bronze.raw_adsb_positions
INSERT INTO bronze.raw_adsb_positions (
    icao24,
    ubicacion,
    altitud_pies,
    velocidad_nudos,
    heading,
    timestamp_utc,
    raw_json,
    fecha_ingesta,
    fuente
)
SELECT
    -- =====================================================
    -- ICAO24 hexadecimal
    -- =====================================================
    CASE
        WHEN random() < 0.08 THEN NULL
        ELSE upper(substr(md5(random()::text),1,6))
    END AS icao24,
    -- =====================================================
    -- Posición geográfica cercana a aeropuerto real
    -- =====================================================
    CASE
        WHEN random() < 0.05 THEN NULL
        ELSE ST_SetSRID(
            ST_MakePoint(
                -- Longitud con ruido operacional
                a.longitude_deg +
                ((random() - 0.5) * 0.8),
                -- Latitud con ruido operacional
                a.latitude_deg +
                ((random() - 0.5) * 0.8)
            ),
            4326
        )::geography
    END AS ubicacion,
    -- =====================================================
    -- Altitud
    -- =====================================================
    CASE
        WHEN random() < 0.10 THEN NULL
        ELSE ROUND(
            (
                500 +
                random() * 39000
            )::numeric,
            2
        )
    END AS altitud_pies,
   -- =====================================================
    -- Velocidad
    -- ===================================================== 
    CASE 
        WHEN random() < 0.07 THEN NULL 
        ELSE ROUND(
            (
                120 +
                random() * 420
            )::numeric,
            2
        )
    END AS velocidad_nudos,
    -- =====================================================
    -- Heading
    -- =====================================================
    CASE
        WHEN random() < 0.06 THEN NULL
        ELSE ROUND(
            (
                random() * 360
            )::numeric,
            2
        )
    END AS heading,
    -- =====================================================
    -- Timestamp irregular
    -- =====================================================
    CURRENT_TIMESTAMP
        - (random() * interval '72 hours') 
    AS timestamp_utc, 
    -- =====================================================
    -- JSON crudo tipo ADS-B
    -- ===================================================== 
    jsonb_build_object( 
        'callsign', 
        CASE 
            WHEN random() < 0.15 THEN NULL
            ELSE
                (
                    ARRAY[
                        'AAL',
                        'DAL',
                        'UAL',
                        'AVA',
                        'IBE',
                        'AFR',
                        'KLM',
                        'BAW'
                    ]
                )[floor(random()*8+1)::int]
                ||
                floor(random()*9999)::text
        END,
        'source',
        CASE
            WHEN random() < 0.15 THEN 'OpenSky'
            WHEN random() < 0.30 THEN 'FlightRadar24'
            ELSE 'ADS-B Exchange'
        END,
        'signal_strength_db',
        ROUND(
            (
                -40 - random()*35
            )::numeric,
            2
        ),
        'aircraft_type', 
        (
            ARRAY[
                'A320',
                'A321',
                'B737',
                'B738',
                'B789',
                'E190',
                'A359'
            ]
        )[floor(random()*7+1)::int],
        'emergency',
        CASE
            WHEN random() < 0.01 THEN TRUE
            ELSE FALSE
        END 
    ) AS raw_json,
    -- =====================================================
    -- Fecha ingesta
    -- =====================================================
    CURRENT_TIMESTAMP
        - (random() * interval '24 hours')
 
    AS fecha_ingesta,
    -- =====================================================
    -- Fuente ADS-B
    -- =====================================================
    CASE
        WHEN random() < 0.15 THEN 'OpenSky'
        WHEN random() < 0.30 THEN 'FlightRadar24'
        ELSE 'ADS-B Exchange'
    END AS fuente
FROM (
    -- =====================================================
    -- Multiplica aeropuertos para generar 5000 filas
    -- =====================================================
    SELECT *
    FROM silver.aeropuertos
    WHERE latitude_deg IS NOT NULL
      AND longitude_deg IS NOT NULL
    ORDER BY random()
    LIMIT 5000
) a;

--TABLA 2.bronze.raw_flight_plans 
INSERT INTO bronze.raw_flight_plans (
    callsign,
    origen_icao,
    destino_icao,
    aerovia,
    niveles,
    eta,
    raw_xml,
    fecha_ingesta
)
SELECT
    -- CALLSIGN
    CASE
        WHEN random() < 0.07 THEN NULL
        WHEN random() < 0.11 THEN ''
        ELSE
            (
                ARRAY[
                    'AVA','DAL','UAL','AAL','IBE',
                    'AFR','KLM','BAW','CMP','JBU',
                    'QTR','ACA','SWA','VOI','JAL'
                ]
            )[floor(random()*15+1)::int]
            ||
            lpad(floor(random()*9999)::text,4,'0')
    END AS callsign,
    -- ORIGEN
    CASE
        WHEN random() < 0.03 THEN NULL
        WHEN random() < 0.05 THEN ''
        ELSE o.ident
    END AS origen_icao,
    -- DESTINO
    CASE
        WHEN random() < 0.03 THEN NULL
        WHEN random() < 0.05 THEN ''
        ELSE d.ident
    END AS destino_icao,
    -- AEROVIA
    CASE
        WHEN random() < 0.12 THEN NULL
        WHEN random() < 0.16 THEN ''
        ELSE
            (
                ARRAY[
                    'UL780','Q77','J25','V3',
                    'UM788','A636','G442',
                    'R576','T783','M674'
                ]
            )[floor(random()*10+1)::int]
            ||
            ' ' ||
            (
                ARRAY[
                    'DCT',
                    'SID',
                    'STAR',
                    'TRANSITION'
                ]
            )[floor(random()*4+1)::int]
    END AS aerovia,
    -- NIVELES
    CASE
        WHEN random() < 0.10 THEN NULL
        WHEN random() < 0.13 THEN ''
        ELSE
            (
                ARRAY[
                    'FL180','FL200','FL220',
                    'FL240','FL260','FL280',
                    'FL300','FL320','FL340',
                    'FL360','FL380','FL400'
                ]
            )[floor(random()*12+1)::int]
    END AS niveles,
    -- ETA
    CURRENT_TIMESTAMP
        + ((random()*18)::int || ' hours')::interval
        + ((random()*59)::int || ' minutes')::interval
    AS eta,
    -- XML
    xmlelement(
        name flight_plan,
 
        xmlforest(
 
            (
                ARRAY['IFR','VFR']
            )[floor(random()*2+1)::int]
            AS flight_rules,
 
            (
                ARRAY[
                    'SCHEDULED',
                    'CARGO',
                    'CHARTER',
                    'POSITIONING',
                    'PRIVATE'
                ]
            )[floor(random()*5+1)::int]
            AS flight_type,
 
            o.ident AS origin,
 
            d.ident AS destination,
 
            (
                ARRAY[
                    'A320',
                    'A321',
                    'A359',
                    'B737',
                    'B738',
                    'B789',
                    'E190',
                    'CRJ9'
                ]
            )[floor(random()*8+1)::int]
            AS aircraft_type
 
        )
 
    ) AS raw_xml,
    -- FECHA INGESTA
    CURRENT_TIMESTAMP
        - ((random()*48)::int || ' hours')::interval
    AS fecha_ingesta
FROM (
    SELECT *
    FROM silver.aeropuertos
    WHERE ident IS NOT NULL
      AND ident <> ''
      AND latitude_deg IS NOT NULL
      AND longitude_deg IS NOT NULL
      AND type IN (
            'large_airport',
            'medium_airport'
      )
    ORDER BY random()
    LIMIT 5000
) o
CROSS JOIN LATERAL (
    SELECT ident
    FROM silver.aeropuertos d
    WHERE d.ident IS NOT NULL
      AND d.ident <> ''
      AND d.ident <> o.ident
      AND d.type IN (
            'large_airport',
            'medium_airport'
      )
    ORDER BY random()
    LIMIT 1
) d;

--TABLA 3.bronze.raw_reservations
INSERT INTO bronze.raw_reservations (
    pnr,
    pasajero_json,
    vuelos_json,
    clase,
    tarifa_usd,
    estado,
    timestamp_utc,
    fecha_ingesta
)
SELECT
    -- =====================================================
    -- PNR 6-8 caracteres alfanuméricos
    -- Compatible con silver.pasajeros_vuelo.pnr
    -- =====================================================
    CASE
        WHEN random() < 0.05 THEN NULL
        ELSE upper(
            substr(md5(random()::text),1,2)
            ||
            floor(random()*90 + 10)::text
            ||
            substr(md5(random()::text),1,2)
        )
    END AS pnr,
    -- =====================================================
    -- JSON pasajero
    -- =====================================================
    jsonb_build_object(
        'first_name',
        (
            ARRAY[
                'Juan',
                'Maria',
                'Carlos',
                'Ana',
                'Luis',
                'Sofia',
                'Daniel',
                'Valeria',
                'Jose',
                'Laura'
            ]
        )[floor(random()*10+1)::int],
        'last_name',
        (
            ARRAY[
                'Garcia',
                'Rodriguez',
                'Lopez',
                'Martinez',
                'Hernandez',
                'Castro',
                'Ramirez',
                'Torres',
                'Vargas',
                'Jimenez'
            ]
        )[floor(random()*10+1)::int],
        'document_type',
        (
            ARRAY[
                'PASSPORT',
                'NATIONAL_ID'
            ]
        )[floor(random()*2+1)::int],
        'nationality',
        (
            ARRAY[
                'CR',
                'US',
                'MX',
                'ES',
                'CO',
                'PA',
                'GT'
            ]
        )[floor(random()*7+1)::int],
        'frequent_flyer',
        CASE
            WHEN random() < 0.35 THEN TRUE
            ELSE FALSE
        END
    ) AS pasajero_json,
    -- =====================================================
    -- JSON vuelos
    -- =====================================================
    jsonb_build_object(
        'flight_number',
        (
            ARRAY[
                'AV201',
                'DL405',
                'AA102',
                'IB6401',
                'CM392',
                'UA889',
                'BA221'
            ]
        )[floor(random()*7+1)::int],
        'origin',
        (
            ARRAY[
                'SJO',
                'LAX',
                'JFK',
                'MIA',
                'MAD',
                'PTY',
                'BOG'
            ]
        )[floor(random()*7+1)::int],
        'destination',
        (
            ARRAY[
                'LAX',
                'SJO',
                'MEX',
                'MAD',
                'PTY',
                'BOG',
                'JFK'
            ]
        )[floor(random()*7+1)::int],
        'airline',
        (
            ARRAY[
                'AVA',
                'DAL',
                'AAL',
                'IBE',
                'CMP',
                'UAL'
            ]
        )[floor(random()*6+1)::int]
    ) AS vuelos_json,
    -- =====================================================
    -- Clase
    -- =====================================================
    CASE
        WHEN random() < 0.03 THEN NULL
        ELSE
            (
                ARRAY[
                    'Y',
                    'J',
                    'F',
                    'W',
                    'B'
                ]
            )[floor(random()*5+1)::int]
    END AS clase,
    -- =====================================================
    -- Tarifa USD
    -- =====================================================
    CASE
        WHEN random() < 0.06 THEN NULL
        ELSE ROUND(
            (
                80 + random()*4200
            )::numeric,
            2
        )
    END AS tarifa_usd,
    -- =====================================================
    -- Estado reserva
    -- =====================================================
    CASE
        WHEN random() < 0.03 THEN NULL
        ELSE
            (
                ARRAY[
                    'CONFIRMED',
                    'CHECKED',
                    'BOARDED',
                    'NOSHOW',
                    'CANCELLED',
                    'PENDING'
                ]
            )[floor(random()*6+1)::int]
    END AS estado,
    -- =====================================================
    -- Timestamp irregular
    -- =====================================================
    CURRENT_TIMESTAMP
        - (random() * interval '45 days')
    AS timestamp_utc,
    -- =====================================================
    -- Fecha ingesta
    -- =====================================================
    CURRENT_TIMESTAMP
        - (random() * interval '5 days')
    AS fecha_ingesta
FROM generate_series(1,5000);


-- Tabla 4.raw boarding  
INSERT INTO bronze.raw_boarding (
    pnr,
    vuelo_id,
    asiento,
    gate,
    grupo_embarque,
    timestamp_utc,
    fecha_ingesta
)
SELECT
    -- =====================================================
    -- PNR reutilizado desde raw_reservations
    -- =====================================================
    CASE
        WHEN random() < 0.04 THEN NULL
        ELSE r.pnr
    END AS pnr,
    -- =====================================================
    -- Numero de vuelo operacional
    -- Compatible con silver.vuelos.numero_vuelo
    -- =====================================================
    CASE
        WHEN random() < 0.03 THEN NULL
        ELSE
            (
                ARRAY[
                    'AV201',
                    'DL405',
                    'AA102',
                    'IB6401',
                    'CM392',
                    'UA889',
                    'BA221',
                    'AF188',
                    'KL755',
                    'LH450'
                ]
            )[floor(random()*10+1)::int]
    END AS vuelo_id,
    -- =====================================================
    -- Asiento compatible con VARCHAR(5)
    -- Compatible con silver.pasajeros_vuelo.asiento
    -- =====================================================
    CASE
        WHEN random() < 0.05 THEN NULL
        ELSE
            floor(random()*45 + 1)::INT
            ||
            (
                ARRAY[
                    'A',
                    'B',
                    'C',
                    'D',
                    'E',
                    'F'
                ]
            )[floor(random()*6+1)::int]
    END AS asiento,
    -- =====================================================
    -- Gate
    -- =====================================================
    CASE
        WHEN random() < 0.08 THEN NULL
        ELSE
            (
                ARRAY[
                    'A',
                    'B',
                    'C',
                    'D',
                    'E'
                ]
            )[floor(random()*5+1)::int]
            ||
            floor(random()*35 + 1)::INT
    END AS gate,
    -- =====================================================
    -- Grupo embarque
    -- =====================================================
    CASE
        WHEN random() < 0.05 THEN NULL
        ELSE
            (
                ARRAY[
                    'PRIORITY',
                    'GROUP1',
                    'GROUP2',
                    'GROUP3',
                    'GROUP4',
                    'LASTCALL'
                ]
            )[floor(random()*6+1)::int]
    END AS grupo_embarque,
    -- =====================================================
    -- Timestamp operacional irregular
    -- =====================================================
    CURRENT_TIMESTAMP
        - (random() * interval '30 days')
    AS timestamp_utc,
    -- =====================================================
    -- Fecha ingesta
    -- =====================================================
    CURRENT_TIMESTAMP
        - (random() * interval '5 days')
    AS fecha_ingesta
FROM (
    -- =====================================================
    -- Reutiliza PNRs existentes de reservations
    -- =====================================================
    SELECT pnr
    FROM bronze.raw_reservations
    WHERE pnr IS NOT NULL
    ORDER BY random()
    LIMIT 5000
) r;

 -- Tabla 5.raw_baggage
INSERT INTO bronze.raw_baggage (
    tag_id,
    pnr_id,
    vuelo_id,
    aeropuerto,
    evento,
    timestamp_utc,
    fecha_ingesta
)
SELECT
    -- ====================================================
    -- Tag equipaje estilo aerolínea real
    -- Compatible VARCHAR(20)
    -- =====================================================
    CASE
        WHEN random() < 0.03 THEN NULL
        ELSE
            (
                ARRAY[
                    'AV',
                    'BG',
                    'AA',
                    'DL',
                    'CM',
                    'IB',
                    'UA'
                ]
            )[floor(random()*7+1)::int]
            ||
            floor(random()*900000 + 100000)::INT
    END AS tag_id,
    -- =====================================================
    -- PNR reutilizado desde reservations
    -- Compatible con pasajeros_vuelo.pnr
    -- =====================================================
    CASE
        WHEN random() < 0.05 THEN NULL
        ELSE r.pnr
    END AS pnr,
    -- =====================================================
    -- Número de vuelo operacional
    -- Compatible con silver.vuelos.numero_vuelo
    -- =====================================================
    CASE
        WHEN random() < 0.04 THEN NULL
        ELSE
            (
                ARRAY[
                    'AV201',
                    'DL405',
                    'AA102',
                    'IB6401',
                    'CM392',
                    'UA889',
                    'BA221',
                    'AF188',
                    'KL755',
                    'LH450'
                ]
            )[floor(random()*10+1)::int]
    END AS vuelo_id,
    -- =====================================================
    -- Aeropuerto usando IATA reales
    -- =====================================================
    CASE
        WHEN random() < 0.04 THEN NULL
        ELSE
            (
                ARRAY[
                    'SJO',
                    'LAX',
                    'JFK',
                    'MIA',
                    'MAD',
                    'PTY',
                    'BOG',
                    'CDG',
                    'AMS',
                    'FRA'
                ]
            )[floor(random()*10+1)::int]
    END AS aeropuerto,
    -- =====================================================
    -- Eventos compatibles con silver.equipaje.estado
    -- =====================================================
    CASE
        WHEN random() < 0.03 THEN NULL
        ELSE
            (
                ARRAY[
                    'CHECKED',
                    'LOADED',
                    'TRANSFER',
                    'UNLOADED',
                    'DELIVERED',
                    'LOST'
                ]
            )[floor(random()*6+1)::int]
    END AS evento,
    -- =====================================================
    -- Timestamp desordenado
    -- Permite eventos fuera de orden
    -- =====================================================
    CURRENT_TIMESTAMP
        - (random() * interval '45 days')
    AS timestamp_utc,
    -- =====================================================
    -- Fecha ingesta irregular
    -- =====================================================
    CURRENT_TIMESTAMP
        - (random() * interval '7 days')
    AS fecha_ingesta
FROM (
    -- =====================================================
    -- Reutiliza PNRs reales desde reservations
    -- =====================================================
    SELECT pnr
    FROM bronze.raw_reservations
    WHERE pnr IS NOT NULL
    ORDER BY random()
    LIMIT 5000
) r,
generate_series(1,2);


-- Tabla 6.raw_cargo
INSERT INTO bronze.raw_cargo (
    awb,
    vuelo_id,
    tipo_carga,
    peso_kg,
    volumen_m3,
    origen,
    destino,
    fecha_ingesta,
    declaracion_json
)
SELECT
    -- =====================================================
    -- AWB realista estilo aerolínea/carga
    -- Compatible VARCHAR(20)
    -- =====================================================
    (
        ARRAY[
            '145',
            '016',
            '230',
            '180',
            '529',
            '057'
        ]
    )[floor(random()*6+1)::int]
    ||
    '-'
    ||
    floor(random()*90000000 + 10000000)::BIGINT
    AS awb,
    -- =====================================================
    -- Número de vuelo operacional
    -- Compatible con silver.vuelos.numero_vuelo
    -- =====================================================
    CASE
        WHEN random() < 0.03 THEN NULL
        ELSE
            (
                ARRAY[
                    'AV201',
                    'DL405',
                    'AA102',
                    'IB6401',
                    'CM392',
                    'UA889',
                    'BA221',
                    'AF188',
                    'KL755',
                    'LH450'
                ]
            )[floor(random()*10+1)::int]
    END AS vuelo_id,
    -- =====================================================
    -- Tipo compatible con silver.carga_vuelo.tipo
    -- =====================================================
    CASE
        WHEN random() < 0.04 THEN NULL
        ELSE
            (
                ARRAY[
                    'GENERAL',
                    'PERECIBLE',
                    'PELIGROSA',
                    'VALORADA',
                    'ANIMALES'
                ]
            )[floor(random()*5+1)::int]
    END AS tipo_carga,
    -- =====================================================
    -- Peso coherente carga aérea
    -- =====================================================
    ROUND(
        (random() * 4500 + 20)::NUMERIC,
        2
    )::FLOAT
    AS peso_kg,
    -- =====================================================
    -- Volumen coherente
    -- =====================================================
    ROUND(
        (random() * 35 + 0.5)::NUMERIC,
        2
    )::FLOAT
    AS volumen_m3,
    -- =====================================================
    -- Aeropuerto origen (IATA)
    -- =====================================================
    (
        ARRAY[
            'SJO',
            'LAX',
            'JFK',
            'MIA',
            'MAD',
            'PTY',
            'BOG',
            'CDG',
            'AMS',
            'FRA'
        ]
    )[floor(random()*10+1)::int]
    AS origen,
    -- =====================================================
    -- Aeropuerto destino (IATA)
    -- =====================================================
    (
        ARRAY[
            'LHR',
            'MEX',
            'ORD',
            'ATL',
            'BCN',
            'LIM',
            'EZE',
            'DFW',
            'GRU',
            'YYZ'
        ]
    )[floor(random()*10+1)::int]
    AS destino,
    -- =====================================================
    -- Fecha ingesta irregular Bronze
    -- =====================================================
    CURRENT_TIMESTAMP
        - (random() * interval '60 days')
    AS fecha_ingesta,
    -- =====================================================
    -- Declaración aduanera semi estructurada
    -- =====================================================
    jsonb_build_object(
        'commodity',
        (
            ARRAY[
                'PHARMACEUTICALS',
                'ELECTRONICS',
                'FLOWERS',
                'SEAFOOD',
                'LUXURY_GOODS',
                'LIVE_ANIMALS',
                'AUTOMOTIVE_PARTS'
            ]
        )[floor(random()*7+1)::int],
        'customs_value_usd',
        ROUND(
            (random() * 250000 + 500)::NUMERIC,
            2
        ),
        'dangerous_goods',
        CASE
            WHEN random() < 0.15
            THEN true
            ELSE false
        END,
        'temperature_required',
        CASE
            WHEN random() < 0.25
            THEN '2C'
            WHEN random() < 0.10
            THEN '-18C'
            ELSE NULL
        END,
        'pieces',
        floor(random()*120 + 1)::INT
    )
    AS declaracion_json
FROM generate_series(1,5000);


--TABLA 7.bronze.raw_engine_sensors
INSERT INTO bronze.raw_engine_sensors (
    engine_id,
    n1_pct,
    n2_pct,
    egt_c,
    fuel_flow_kgh,
    vibration,
    timestamp_utc,
    fecha_ingesta
) 
SELECT
    -- ENGINE ID
    CASE
        WHEN random() < 0.05 THEN NULL
        ELSE
            'ENG-' ||
            (
                ARRAY[
                    'CFM56',
                    'LEAP1A',
                    'PW1100',
                    'TRENTXWB',
                    'GE90',
                    'V2500'
                ]
            )[floor(random()*6+1)::int]
            ||
            '-' ||
            lpad((floor(random()*9999))::text,4,'0')
    END,
    -- N1
    CASE
        WHEN random() < 0.06 THEN NULL
        ELSE round((20 + random()*85)::numeric,2)
    END,
    -- N2
    CASE
        WHEN random() < 0.06 THEN NULL
        ELSE round((45 + random()*55)::numeric,2)
    END,
    -- EGT
    CASE
        WHEN random() < 0.05 THEN NULL
        ELSE round((350 + random()*450)::numeric,2)
    END,
    -- FUEL FLOW
    CASE
        WHEN random() < 0.07 THEN NULL
        ELSE round((500 + random()*6500)::numeric,2)
    END,
    -- VIBRATION
    CASE
        WHEN random() < 0.08 THEN NULL
        ELSE round((0.1 + random()*4)::numeric,2)
    END,
    CURRENT_TIMESTAMP
        - (random() * interval '72 hours'),
    CURRENT_TIMESTAMP
        - (random() * interval '24 hours')
FROM generate_series(1,5000);

--TABLA 8.bronze.raw_maintenance
INSERT INTO bronze.raw_maintenance (
    aeronave_id,
    componente,
    accion,
    taller_id,
    tecnico_id,
    horas_aeronave,
    timestamp_utc,
    fecha_ingesta
)
SELECT
    -- AERONAVE
    CASE
        WHEN random() < 0.05 THEN NULL
        ELSE
            (
                ARRAY[
                    'N123AA',
                    'N456DL',
                    'EC-MXA',
                    'HP-1823CMP',
                    'TI-BGU',
                    'F-GZND'
                ]
            )[floor(random()*6+1)::int]
    END,
    -- COMPONENTE
    CASE
        WHEN random() < 0.04 THEN NULL
        ELSE
            (
                ARRAY[
                    'ENGINE',
                    'APU',
                    'LANDING_GEAR',
                    'BRAKES',
                    'HYDRAULIC_SYSTEM',
                    'FUEL_PUMP',
                    'AVIONICS',
                    'FLAPS'
                ]
            )[floor(random()*8+1)::int]
    END,
    -- ACCION
    CASE
        WHEN random() < 0.03 THEN NULL
        ELSE
            (
                ARRAY[
                    'INSPECTION',
                    'REPLACEMENT',
                    'REPAIR',
                    'CLEANING',
                    'TEST',
                    'OVERHAUL'
                ]
            )[floor(random()*6+1)::int]
    END,
    -- TALLER
    CASE
        WHEN random() < 0.05 THEN NULL
        ELSE
            'MRO-' ||
            (
                ARRAY[
                    'SJO',
                    'PTY',
                    'MIA',
                    'MAD',
                    'BOG',
                    'LAX'
                ]
            )[floor(random()*6+1)::int]
    END,
    -- TECNICO
    CASE
        WHEN random() < 0.07 THEN NULL
        ELSE
            'TECH-' || lpad((floor(random()*9999))::text,4,'0')
    END,
    -- HORAS
    CASE
        WHEN random() < 0.05 THEN NULL
        ELSE round((500 + random()*65000)::numeric,2)
    END,
    CURRENT_TIMESTAMP
        - (random() * interval '90 days'),
    CURRENT_TIMESTAMP
        - (random() * interval '24 hours') 
FROM generate_series(1,5000);
 
--TABLA 9.bronze.raw_fuel
INSERT INTO bronze.raw_fuel (
    vuelo_id,
    aeropuerto_icao,
    litros,
    densidad_kgl,
    precio_usd,
    timestamp_utc,
    fecha_ingesta
 
)
SELECT
    -- VUELO
    CASE
        WHEN random() < 0.06 THEN NULL
        ELSE
            (
                ARRAY[
                    'AVA245',
                    'DAL120',
                    'UAL998',
                    'IBE6401',
                    'CMP432',
                    'AFR221',
                    'KLM777'
                ]
            )[floor(random()*7+1)::int]
    END,
    -- ICAO
    CASE
        WHEN random() < 0.05 THEN NULL
        ELSE
            (
                ARRAY[
                    'MROC',
                    'KJFK',
                    'LEMD',
                    'SKBO',
                    'MMMX',
                    'EGLL',
                    'LFPG',
                    'OMDB'
                ]
            )[floor(random()*8+1)::int]
    END,
    -- LITROS
    CASE
        WHEN random() < 0.04 THEN NULL
        ELSE round((2000 + random()*120000)::numeric,2)
    END,
    -- DENSIDAD
    CASE
        WHEN random() < 0.05 THEN NULL
        ELSE round((0.78 + random()*0.06)::numeric,3)
    END,
    -- PRECIO
    CASE
        WHEN random() < 0.05 THEN NULL
        ELSE round((5000 + random()*150000)::numeric,2)
    END,
    CURRENT_TIMESTAMP
        - (random() * interval '30 days'),
    CURRENT_TIMESTAMP
        - (random() * interval '24 hours')
FROM generate_series(1,5000);
 
--TABLA 10.bronze.raw_crew
INSERT INTO bronze.raw_crew (
    vuelo_id,
    crew_id,
    rol,
    report_time,
    duty_hours,
    fecha_ingesta
)
SELECT
    -- VUELO
    CASE
        WHEN random() < 0.05 THEN NULL
        ELSE
            (
                ARRAY[
                    'AVA245',
                    'DAL120',
                    'UAL998',
                    'IBE6401',
                    'CMP432',
                    'AFR221',
                    'KLM777'
                ]
            )[floor(random()*7+1)::int]
    END,
    -- CREW ID
    CASE
        WHEN random() < 0.04 THEN NULL
        ELSE
            'CREW-' || lpad((floor(random()*99999))::text,5,'0')
    END,
    -- ROL
    CASE
        WHEN random() < 0.03 THEN NULL
        ELSE
            (
                ARRAY[
                    'CAPTAIN',
                    'FIRST_OFFICER',
                    'CABIN_CREW',
                    'PURSER',
                    'RELIEF_PILOT'
                ]
            )[floor(random()*5+1)::int]
    END,
    -- REPORT TIME
    CURRENT_TIMESTAMP
        - (random() * interval '7 days'),
    -- DUTY HOURS
    CASE
        WHEN random() < 0.06 THEN NULL
        ELSE round((1 + random()*14)::numeric,2)
    END,
    CURRENT_TIMESTAMP
        - (random() * interval '24 hours')
FROM generate_series(1,5000);





































