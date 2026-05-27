CREATE SCHEMA IF NOT EXISTS History;
COMMENT ON SCHEMA history IS
'Schema de almacenamiento inmutable (append-only). Guarda histórico de posiciones ADS-B, hashes de integridad y auditoría de cambios de estado de vuelos. No permite UPDATE ni DELETE.';

CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- ============================================================
-- TABLA: history.vuelos_audit
-- Captura cada cambio de estado de un vuelo con hash de integridad
-- ============================================================
CREATE TABLE IF NOT EXISTS history.vuelos_audit (
    audit_id        BIGSERIAL PRIMARY KEY,
    vuelo_id        INT NOT NULL,
    numero_vuelo    VARCHAR(10),
    estado_anterior VARCHAR(30),
    estado_nuevo    VARCHAR(30),
    operacion       VARCHAR(10) NOT NULL,        -- INSERT / UPDATE
    usuario_bd      VARCHAR(100) DEFAULT CURRENT_USER,
    timestamp_evento TIMESTAMPTZ DEFAULT NOW(),
    snapshot_completo JSONB,                     -- snapshot del registro
    hash_integridad   VARCHAR(64)                -- firma SHA-256
);

COMMENT ON TABLE history.vuelos_audit IS
'Auditoría append-only de cambios de estado en vuelos. Cada fila incluye snapshot JSONB del registro y hash SHA-256 para verificación de integridad.';


-- ============================================================
-- BLOQUEO: Esta tabla es INMUTABLE
-- (no permite UPDATE ni DELETE, solo INSERT)
-- ============================================================
CREATE OR REPLACE RULE no_update_audit AS
    ON UPDATE TO history.vuelos_audit
    DO INSTEAD NOTHING;

CREATE OR REPLACE RULE no_delete_audit AS
    ON DELETE TO history.vuelos_audit
    DO INSTEAD NOTHING;

COMMENT ON RULE no_update_audit ON history.vuelos_audit IS
'Garantiza inmutabilidad: los UPDATE son ignorados silenciosamente.';

COMMENT ON RULE no_delete_audit ON history.vuelos_audit IS
'Garantiza inmutabilidad: los DELETE son ignorados silenciosamente.';

-- ============================================================
-- FUNCIÓN: Auditar cambios en silver.vuelos
-- Genera hash SHA-256 del snapshot para detectar manipulación
-- ============================================================
CREATE OR REPLACE FUNCTION history.fn_auditar_cambio_vuelo()
RETURNS TRIGGER AS $$
DECLARE
    v_snapshot JSONB;
    v_hash     VARCHAR(64);
BEGIN
    /* 
       Capturar el estado NUEVO del registro como JSONB
       (snapshot completo para auditoría histórica)
    */
    v_snapshot := to_jsonb(NEW);
    
    /* 
       Calcular hash SHA-256 del snapshot
       → garantiza integridad: si alguien modifica el JSON,
         el hash deja de coincidir
    */
    v_hash := encode(
        digest(v_snapshot::text, 'sha256'),
        'hex'
    );
    
    /* Insertar registro inmutable de auditoría */
    INSERT INTO history.vuelos_audit (
        vuelo_id,
        numero_vuelo,
        estado_anterior,
        estado_nuevo,
        operacion,
        snapshot_completo,
        hash_integridad
    )
    VALUES (
        NEW.vuelo_id,
        NEW.numero_vuelo,
        CASE WHEN TG_OP = 'UPDATE' THEN OLD.estado ELSE NULL END,
        NEW.estado,
        TG_OP,
        v_snapshot,
        v_hash
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION history.fn_auditar_cambio_vuelo IS
'Captura cada INSERT/UPDATE de silver.vuelos como registro inmutable en history.vuelos_audit con snapshot JSONB y hash SHA-256 para verificación de integridad.';


-- ============================================================
-- TRIGGER: Activar la auditoría
-- ============================================================
DROP TRIGGER IF EXISTS trg_audit_vuelos ON silver.vuelos;

CREATE TRIGGER trg_audit_vuelos
AFTER INSERT OR UPDATE
ON silver.vuelos
FOR EACH ROW
EXECUTE FUNCTION history.fn_auditar_cambio_vuelo();

COMMENT ON TRIGGER trg_audit_vuelos ON silver.vuelos IS
'Registra automáticamente cada cambio de vuelo en el historial inmutable history.vuelos_audit.';

--"Los timestamps detectan cuándo se modificó algo, pero no detectan si alguien modifica el JSON directamente en la tabla de auditoría. 
--El hash SHA-256 es una firma criptográfica: si cambias un solo carácter del snapshot, el hash recalculado deja de coincidir con el almacenado."