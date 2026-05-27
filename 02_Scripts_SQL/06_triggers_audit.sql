                                       --Triggers_audit
--CAPA SILVER   
--1.    
-- =========================================================
-- FUNCIÓN: Validar desactivación de aerolínea
-- Tabla: silver.aerolineas
-- =========================================================

CREATE OR REPLACE FUNCTION silver.fn_validar_desactivacion_aerolinea()
RETURNS TRIGGER AS $$
DECLARE
    v_vuelos_activos INT;
BEGIN
    /*
      Si intentan desactivar la aerolínea,
      verificar que no tenga vuelos
      programados o activos.
    */
    IF NEW.activa = FALSE
       AND OLD.activa = TRUE THEN
        SELECT COUNT(*)
        INTO v_vuelos_activos
        FROM silver.vuelos
        WHERE aerolinea_id = NEW.aerolinea_id
          AND estado IN ('SCHED', 'ACTIVE');
        IF v_vuelos_activos > 0 THEN
            RAISE EXCEPTION
            'No se puede desactivar la aerolínea %. Tiene % vuelos activos o programados.',
            NEW.nombre,
            v_vuelos_activos;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION silver.fn_validar_desactivacion_aerolinea
IS 'Evita desactivar aerolíneas que todavía poseen vuelos activos o programados.';

-- TRIGGER: Validación desactivación aerolínea
-- =========================================================

CREATE TRIGGER trg_validar_desactivacion_aerolinea
BEFORE UPDATE
ON silver.aerolineas
FOR EACH ROW
EXECUTE FUNCTION silver.fn_validar_desactivacion_aerolinea();

COMMENT ON TRIGGER trg_validar_desactivacion_aerolinea
ON silver.aerolineas
IS 'Bloquea la desactivación de aerolíneas con vuelos activos o programados.';

--2.
-- =========================================================
-- FUNCIÓN: Control automático de mantenimiento aeronave
-- Tabla: silver.aeronaves
-- =========================================================
CREATE OR REPLACE FUNCTION silver.fn_control_mantenimiento_aeronave()
RETURNS TRIGGER AS $$
BEGIN
    /*
      Regla operacional:
      Si la aeronave supera las 50,000 horas
      de vuelo acumuladas,
      automáticamente pasa a estado:
      MANTENIMIENTO
    */
    IF NEW.horas_vuelo_totales >= 50000
       AND NEW.estado = 'ACTIVO' THEN
        NEW.estado := 'MANTENIMIENTO';
        -- Registrar alerta en auditoría
        INSERT INTO audit.alertas_operacionales (
            tipo_alerta,
            severidad,
            tabla_origen,
            registro_id,
            descripcion,
            fecha_alerta
        )
        VALUES (
            'MANTENIMIENTO_PREVENTIVO',
            'MEDIA',
            'silver.aeronaves',
            NEW.aeronave_id::TEXT,
            'Aeronave enviada automáticamente a mantenimiento por exceso de horas de vuelo.',
            CURRENT_TIMESTAMP
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION silver.fn_control_mantenimiento_aeronave
IS 'Envía automáticamente aeronaves a mantenimiento preventivo cuando superan el límite de horas de vuelo.';

-- TRIGGER: Control mantenimiento aeronave
-- =========================================================
CREATE TRIGGER trg_control_mantenimiento_aeronave
BEFORE INSERT OR UPDATE
ON silver.aeronaves
FOR EACH ROW
EXECUTE FUNCTION silver.fn_control_mantenimiento_aeronave();

COMMENT ON TRIGGER trg_control_mantenimiento_aeronave
ON silver.aeronaves
IS 'Cambia automáticamente el estado de aeronaves a MANTENIMIENTO cuando superan límites operacionales.';

--3.
-- =========================================================
-- FUNCIÓN: Auditoría y control de estado de vuelos
-- Tabla: silver.vuelos
-- =========================================================
CREATE OR REPLACE FUNCTION silver.fn_control_estado_vuelo()
RETURNS TRIGGER AS $$
BEGIN
    /*
      Reglas operacionales:
      
      1. Si existe salida_real:
         estado -> ACTIVE
         
      2. Si existe llegada_real:
         estado -> LANDED
         
      3. Registrar cambios críticos
         en auditoría operacional
    */
    -- Vuelo despegó
    IF NEW.salida_real IS NOT NULL
       AND NEW.estado = 'SCHED' THEN
        NEW.estado := 'ACTIVE';
    END IF;
    -- Vuelo aterrizó
    IF NEW.llegada_real IS NOT NULL THEN
        NEW.estado := 'LANDED';
    END IF;
    -- Auditoría de cambios críticos
    IF OLD.estado IS DISTINCT FROM NEW.estado THEN
        INSERT INTO audit.log_cambios (
            tabla_afectada,
            operacion,
            usuario_bd,
            fecha_cambio,
            valor_anterior,
            valor_nuevo
        )
        VALUES (
            'silver.vuelos',
            'UPDATE',
            CURRENT_USER,
            CURRENT_TIMESTAMP,

            jsonb_build_object(
                'vuelo_id', OLD.vuelo_id,
                'estado', OLD.estado
            ),

            jsonb_build_object(
                'vuelo_id', NEW.vuelo_id,
                'estado', NEW.estado
            )
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION silver.fn_control_estado_vuelo
IS 'Automatiza estados operacionales de vuelos y registra cambios críticos en auditoría.';

-- TRIGGER: Control estado vuelos
-- =========================================================
CREATE TRIGGER trg_control_estado_vuelo
BEFORE UPDATE
ON silver.vuelos
FOR EACH ROW
EXECUTE FUNCTION silver.fn_control_estado_vuelo();

COMMENT ON TRIGGER trg_control_estado_vuelo
ON silver.vuelos
IS 'Actualiza automáticamente estados de vuelo y registra auditoría operacional.';

--4.
-- =========================================================
-- FUNCIÓN: Control estado aeronave por mantenimiento
-- =========================================================

CREATE OR REPLACE FUNCTION silver.fn_control_estado_aeronave_mantenimiento()
RETURNS TRIGGER AS $$
BEGIN
    /*
      Regla operacional:     
      - Si existe mantenimiento crítico
        o mantenimiento activo,
        la aeronave pasa a estado
        MANTENIMIENTO.     
      - Cuando el mantenimiento finaliza,
        la aeronave vuelve a ACTIVO.
    */
    -- Mantenimiento crítico o activo
    IF NEW.tipo_check = 'D'
       OR NEW.estado IN ('OPEN', 'INPROGRESS') THEN
        UPDATE silver.aeronaves
        SET estado = 'MANTENIMIENTO'
        WHERE aeronave_id = NEW.aeronave_id;
    END IF;
    -- Mantenimiento finalizado
    IF NEW.estado = 'CLOSED' THEN
        UPDATE silver.aeronaves
        SET estado = 'ACTIVO'
        WHERE aeronave_id = NEW.aeronave_id
          AND estado = 'MANTENIMIENTO';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION silver.fn_control_estado_aeronave_mantenimiento IS
'Actualiza automáticamente el estado operativo de aeronaves según eventos de mantenimiento activos o críticos.';


-- TRIGGER: Estado automático aeronave mantenimiento
-- =========================================================

CREATE TRIGGER trg_control_estado_aeronave_mantenimiento
AFTER INSERT OR UPDATE
ON silver.mantenimiento_eventos
FOR EACH ROW
EXECUTE FUNCTION silver.fn_control_estado_aeronave_mantenimiento();

COMMENT ON TRIGGER trg_control_estado_aeronave_mantenimiento
ON silver.mantenimiento_eventos IS
'Controla automáticamente el estado de aeronaves durante procesos de mantenimiento.';

--6.
-- =========================================================
-- FUNCIÓN: Validar fatiga de tripulación
-- Tabla: silver.tripulacion_vuelo
-- =========================================================
CREATE OR REPLACE FUNCTION silver.fn_validar_fatiga_tripulacion()
RETURNS TRIGGER AS $$
BEGIN
    /*
      Regla operacional:     
      Detectar posibles casos de fatiga
      cuando:     
      - Las horas de duty exceden límites
      - El descanso es insuficiente
    */
    -- Validar exceso de horas duty
    IF NEW.horas_vuelo_duty > 12 THEN
        RAISE EXCEPTION
        'ALERTA FATIGA: La tripulación excede las horas máximas permitidas de duty (%.2f horas).',
        NEW.horas_vuelo_duty;
    END IF;
    -- Validar descanso insuficiente
    IF NEW.descanso_horas < NEW.descanso_minimo_requerido THEN
        RAISE EXCEPTION
        'ALERTA FATIGA: Descanso insuficiente. Descanso actual: %.2f horas / mínimo requerido: %.2f horas.',
        NEW.descanso_horas,
        NEW.descanso_minimo_requerido;
    END IF;
    -- Actualizar automáticamente indicador de cumplimiento
    NEW.descanso_minimo_cumple :=
        (NEW.descanso_horas >= NEW.descanso_minimo_requerido);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION silver.fn_validar_fatiga_tripulacion IS
'Valida límites operacionales de fatiga de tripulación según horas de duty y descanso mínimo requerido.';

-- TRIGGER: Validación fatiga tripulación
-- =========================================================

CREATE TRIGGER trg_validar_fatiga_tripulacion
BEFORE INSERT OR UPDATE
ON silver.tripulacion_vuelo
FOR EACH ROW
EXECUTE FUNCTION silver.fn_validar_fatiga_tripulacion();

COMMENT ON TRIGGER trg_validar_fatiga_tripulacion
ON silver.tripulacion_vuelo IS
'Bloquea registros de tripulación que incumplen límites de fatiga o descanso operacional.';

--7.
-- =========================================================
-- FUNCIÓN: Validar exceso de combustible
-- Tabla: silver.combustible_carga
-- =========================================================

CREATE OR REPLACE FUNCTION silver.fn_validar_exceso_combustible()
RETURNS TRIGGER AS $$
DECLARE
    v_limite_combustible NUMERIC := 250000; -- límite ejemplo en litros
BEGIN
    /*
      Regla operacional:    
      Detectar cargas excesivas
      de combustible que podrían
      representar:  
      - riesgo operacional
      - sobrepeso aeronave
      - error de carga
      - impacto en performance
    */
    -- Validar litros máximos permitidos
    IF NEW.litros > v_limite_combustible THEN
        RAISE EXCEPTION
        'EXCESO_COMBUSTIBLE: La carga de combustible (%.2f L) excede el límite permitido de %.2f L.',
        NEW.litros,
        v_limite_combustible;
    END IF;
    -- Validar coherencia masa combustible
    IF NEW.masa_kg > (NEW.litros * 1.2) THEN
        RAISE EXCEPTION
        'EXCESO_COMBUSTIBLE: La masa de combustible no coincide con la densidad esperada.';
    END IF;
    -- Calcular automáticamente costo total
    NEW.costo_total_usd :=
        NEW.litros * NEW.precio_usd_litro;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION silver.fn_validar_exceso_combustible IS
'Valida cargas excesivas de combustible, coherencia de masa y calcula automáticamente el costo total.';

-- TRIGGER: Validación exceso combustible
-- =========================================================

CREATE TRIGGER trg_validar_exceso_combustible
BEFORE INSERT OR UPDATE
ON silver.combustible_carga
FOR EACH ROW
EXECUTE FUNCTION silver.fn_validar_exceso_combustible();

COMMENT ON TRIGGER trg_validar_exceso_combustible
ON silver.combustible_carga IS
'Bloquea registros con exceso de combustible o inconsistencias de masa y calcula automáticamente costos.';   

--CAPA GOLD 
--1.
-- =========================================================
-- FUNCIÓN + TRIGGER: Revenue Total automático
-- =========================================================
CREATE OR REPLACE FUNCTION gold.fn_calcular_revenue_total()
RETURNS TRIGGER AS $$
BEGIN
    /*
      Total Revenue = Passenger Revenue + Cargo Revenue
      Base para KPIs comerciales (RASK, margen, rentabilidad)
    */
    NEW.total_revenue_usd :=
        COALESCE(NEW.passenger_revenue_usd, 0)
        + COALESCE(NEW.cargo_revenue_usd, 0);

    IF NEW.total_revenue_usd < 0 THEN
        RAISE EXCEPTION
        'REVENUE INVÁLIDO: no puede ser negativo (%)',
        NEW.total_revenue_usd;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION gold.fn_calcular_revenue_total IS
'Calcula automáticamente el revenue total como suma de pasajeros + carga. Estándar IATA para KPIs comerciales.';

DROP TRIGGER IF EXISTS trg_calcular_revenue_total ON gold.hechos_vuelo;

CREATE TRIGGER trg_calcular_revenue_total
BEFORE INSERT OR UPDATE
ON gold.hechos_vuelo
FOR EACH ROW
EXECUTE FUNCTION gold.fn_calcular_revenue_total();

COMMENT ON TRIGGER trg_calcular_revenue_total
ON gold.hechos_vuelo IS
'Calcula automáticamente total_revenue_usd antes de insertar o actualizar.';

--2.
-- =========================================================
-- FUNCIÓN + TRIGGER: CO2 Emitido automático
-- =========================================================
CREATE OR REPLACE FUNCTION gold.fn_calcular_co2()
RETURNS TRIGGER AS $$
BEGIN
    /*
      CO2 = fuel_consumed_kg × 3.16 / 1000    
      Factor IATA/ICAO oficial: 3.16 kg CO2 por kg jet fuel
      Resultado en toneladas    
      Crítico para reporting CORSIA y metas Net-Zero 2050
    */
    IF NEW.fuel_consumed_kg IS NOT NULL AND NEW.fuel_consumed_kg > 0 THEN
        NEW.co2_emitted_ton :=
            ROUND((NEW.fuel_consumed_kg * 3.16 / 1000)::numeric, 2);
    ELSE
        NEW.co2_emitted_ton := 0;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION gold.fn_calcular_co2 IS
'Calcula automáticamente las emisiones de CO2 en toneladas usando factor estándar ICAO de 3.16 kg CO2 por kg de jet fuel. Crítico para reporting CORSIA.';


CREATE TRIGGER trg_calcular_co2
BEFORE INSERT OR UPDATE
ON gold.hechos_vuelo
FOR EACH ROW
EXECUTE FUNCTION gold.fn_calcular_co2();

COMMENT ON TRIGGER trg_calcular_co2
ON gold.hechos_vuelo IS
'Calcula automáticamente co2_emitted_ton aplicando factor ICAO de 3.16 kg CO2/kg fuel.';

--3.
-- =========================================================
-- FUNCIÓN + TRIGGER: Validar Load Factor en hechos_pasajero
-- =========================================================
CREATE OR REPLACE FUNCTION gold.fn_validar_load_factor_pasajero()
RETURNS TRIGGER AS $$
BEGIN
    /*
      Validaciones de Load Factor (IATA estándar):     
      - LF debe estar entre 0 y 100
      - Alertar si LF < 50% (capacidad ociosa)
      - Alertar si LF > 95% (probable overbooking)
    */
    IF NEW.load_factor_pct IS NOT NULL THEN
        IF NEW.load_factor_pct < 0 OR NEW.load_factor_pct > 100 THEN
            RAISE EXCEPTION
            'LOAD FACTOR INVÁLIDO: % %% (debe estar entre 0 y 100)',
            NEW.load_factor_pct;
        END IF;
        IF NEW.load_factor_pct < 50 THEN
            RAISE NOTICE
            'CAPACIDAD OCIOSA: Load Factor bajo (% %%) - revisar ruta',
            NEW.load_factor_pct;
        END IF;
        IF NEW.load_factor_pct > 95 THEN
            RAISE NOTICE
            'ALERTA OVERBOOKING: Load Factor muy alto (% %%) - posible overbooking',
            NEW.load_factor_pct;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION gold.fn_validar_load_factor_pasajero IS
'Valida que el Load Factor esté entre 0 y 100, alerta por capacidad ociosa (<50%) o posible overbooking (>95%). Estándar IATA 2025: 83.6% promedio.';


CREATE TRIGGER trg_calcular_load_factor_pasajero
BEFORE INSERT OR UPDATE
ON gold.hechos_pasajero
FOR EACH ROW
EXECUTE FUNCTION gold.fn_validar_load_factor_pasajero();

COMMENT ON TRIGGER trg_calcular_load_factor_pasajero
ON gold.hechos_pasajero IS
'Valida automáticamente el Load Factor según rangos IATA y alerta por anomalías.';

--4.
-- =========================================================
-- FUNCIÓN + TRIGGER: Clasificar eficiencia de combustible
-- =========================================================
CREATE OR REPLACE FUNCTION gold.fn_clasificar_eficiencia_combustible()
RETURNS TRIGGER AS $$
BEGIN
    /*
      Validación de eficiencia de combustible  
      Benchmark industria: 0.025 - 0.040 kg/km
      Variación aceptable: ±5% vs planificado
      Variación crítica: >10%
    */
    -- Validar rango realista
    IF NEW.efficiency_kg_km IS NOT NULL THEN
        IF NEW.efficiency_kg_km > 0.10 THEN
            RAISE NOTICE
            'EFICIENCIA ANÓMALA: % kg/km supera el rango realista (revisar)',
            NEW.efficiency_kg_km;
        END IF;
    END IF;
    -- Alertar variaciones críticas
    IF NEW.efficiency_variation_pct IS NOT NULL THEN
        IF ABS(NEW.efficiency_variation_pct) > 10 THEN
            RAISE NOTICE
            'VARIACIÓN CRÍTICA: Eficiencia varió % %% vs plan (revisar operación)',
            NEW.efficiency_variation_pct;
        END IF;
    END IF;
    -- Validar % SAF dentro de rango
    IF NEW.alternative_fuel_pct IS NOT NULL
       AND (NEW.alternative_fuel_pct < 0 OR NEW.alternative_fuel_pct > 100) THEN
        RAISE EXCEPTION
        'SAF INVÁLIDO: % %% debe estar entre 0 y 100',
        NEW.alternative_fuel_pct;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION gold.fn_clasificar_eficiencia_combustible IS
'Valida métricas de eficiencia de combustible: rango realista (<0.10 kg/km), variación vs plan (±10%) y rango válido de SAF (0-100%).';


CREATE TRIGGER trg_clasificar_eficiencia_combustible
BEFORE INSERT OR UPDATE
ON gold.hechos_combustible
FOR EACH ROW
EXECUTE FUNCTION gold.fn_clasificar_eficiencia_combustible();

COMMENT ON TRIGGER trg_clasificar_eficiencia_combustible
ON gold.hechos_combustible IS
'Valida automáticamente eficiencia de combustible y alerta sobre variaciones críticas o SAF fuera de rango.';


SELECT trigger_name, event_object_table, action_timing, event_manipulation
FROM information_schema.triggers
WHERE trigger_schema = 'gold'
ORDER BY event_object_table, trigger_name;


--TABLAS SCHEME AUDIT.
--1.
CREATE TABLE audit.log_accesos (
    log_id BIGSERIAL PRIMARY KEY,
    usuario VARCHAR(100),
    rol VARCHAR(100),
    tabla_accedida VARCHAR(100),
    accion VARCHAR(20),
    fecha_acceso TIMESTAMPTZ DEFAULT NOW(),
    ip_origen VARCHAR (100)
);
--2.

CREATE TABLE audit.cambios_estado_vuelo (
    cambio_id BIGSERIAL PRIMARY KEY,
    vuelo_id UUID,
    estado_anterior VARCHAR(20),
    estado_nuevo VARCHAR(20),
    motivo TEXT,
    usuario VARCHAR(50),
    timestamp_cambio TIMESTAMPTZ DEFAULT NOW(),
    ip_origen VARCHAR (100)
);

--3.
 CREATE TABLE audit.alertas_operacionales (
    alerta_id BIGSERIAL PRIMARY KEY,
    fecha TIMESTAMPTZ DEFAULT now(),
    mensaje TEXT,
    severidad VARCHAR(20)
);





