CREATE TABLE IF NOT EXISTS rollback_points (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  label TEXT,
  note TEXT,
  created_by_uid TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS rollback_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  point_id UUID REFERENCES rollback_points(id) ON DELETE CASCADE,
  table_name TEXT NOT NULL,
  row_count INT DEFAULT 0,
  rows JSONB NOT NULL
);

ALTER TABLE rollback_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE rollback_snapshots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "rollback_points_read" ON rollback_points;
CREATE POLICY "rollback_points_read" ON rollback_points
  FOR SELECT TO authenticated
  USING (public.has_role(ARRAY['ADMIN','FINANCE']));

DROP POLICY IF EXISTS "rollback_snapshots_read" ON rollback_snapshots;
CREATE POLICY "rollback_snapshots_read" ON rollback_snapshots
  FOR SELECT TO authenticated
  USING (public.has_role(ARRAY['ADMIN','FINANCE']));
