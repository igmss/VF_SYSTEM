-- Phase 3 Schema Changes

-- 1. Create uid_mapping table
CREATE TABLE IF NOT EXISTS uid_mapping (
  firebase_uid TEXT PRIMARY KEY,
  supabase_uid UUID NOT NULL
);

-- Enable RLS
ALTER TABLE uid_mapping ENABLE ROW LEVEL SECURITY;
CREATE POLICY "uid_mapping_read" ON uid_mapping FOR SELECT TO authenticated USING (true);

-- 2. Add supabase_uid to collectors
ALTER TABLE collectors ADD COLUMN IF NOT EXISTS supabase_uid UUID;
