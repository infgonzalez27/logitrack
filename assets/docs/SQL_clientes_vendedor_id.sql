-- Asignar vendedor a cliente (LogiTrack)
-- Ejecutar en Supabase → SQL Editor

ALTER TABLE clientes
  ADD COLUMN IF NOT EXISTS vendedor_id UUID
  REFERENCES perfiles_usuario(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS clientes_vendedor_id_idx
  ON clientes (vendedor_id);

COMMENT ON COLUMN clientes.vendedor_id IS
  'Perfil (rol vendedor) responsable de la cartera del cliente';

