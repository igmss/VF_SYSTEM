-- Create retailer_assignment_requests table
CREATE TABLE IF NOT EXISTS retailer_assignment_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  retailer_id UUID REFERENCES retailers(id),
  created_by_uid UUID REFERENCES users(id),
  requested_amount NUMERIC(15,4) NOT NULL,
  vf_phone_number TEXT NOT NULL,
  notes TEXT,
  status TEXT DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'REJECTED')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  assigned_amount NUMERIC(15,4),
  admin_notes TEXT,
  proof_image_url TEXT,
  rejected_reason TEXT,
  processing_by UUID REFERENCES users(id),
  completed_at TIMESTAMPTZ,
  completed_by_uid UUID REFERENCES users(id)
);

-- Enable RLS
ALTER TABLE retailer_assignment_requests ENABLE ROW LEVEL SECURITY;

-- Drop old policies if any
DROP POLICY IF EXISTS "retailers_read_own_requests" ON retailer_assignment_requests;
DROP POLICY IF EXISTS "admins_read_all_requests" ON retailer_assignment_requests;
DROP POLICY IF EXISTS "retailers_create_requests" ON retailer_assignment_requests;
DROP POLICY IF EXISTS "admins_update_requests" ON retailer_assignment_requests;

-- RETAILER policy: Read own requests
CREATE POLICY "retailers_read_own_requests" ON retailer_assignment_requests
  FOR SELECT TO authenticated
  USING (
    created_by_uid = auth.uid() OR
    retailer_id IN (SELECT retailer_id FROM users WHERE id = auth.uid())
  );

-- ADMIN/FINANCE policy: Read all
CREATE POLICY "admins_read_all_requests" ON retailer_assignment_requests
  FOR SELECT TO authenticated
  USING (public.has_role(ARRAY['ADMIN','FINANCE']));

-- RETAILER policy: Create own requests
CREATE POLICY "retailers_create_requests" ON retailer_assignment_requests
  FOR INSERT TO authenticated
  WITH CHECK (
    (public.has_role(ARRAY['RETAILER']) AND created_by_uid = auth.uid()) OR 
    public.is_admin()
  );

-- ADMIN/FINANCE policy: Update all
CREATE POLICY "admins_update_requests" ON retailer_assignment_requests
  FOR UPDATE TO authenticated
  USING (public.has_role(ARRAY['ADMIN','FINANCE']));


-- Update financial_ledger RLS for Retailers
DROP POLICY IF EXISTS "ledger_retailer_read" ON financial_ledger;
CREATE POLICY "ledger_retailer_read" ON financial_ledger
  FOR SELECT TO authenticated
  USING (
    (from_id = (SELECT retailer_id::TEXT FROM users WHERE id = auth.uid())) OR
    (to_id = (SELECT retailer_id::TEXT FROM users WHERE id = auth.uid()))
  );

-- RPC for atomic locking
CREATE OR REPLACE FUNCTION lock_retailer_request(
  p_request_id UUID,
  p_admin_uid UUID
) RETURNS BOOLEAN AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status FROM retailer_assignment_requests WHERE id = p_request_id FOR UPDATE;
  IF v_status = 'PENDING' THEN
    UPDATE retailer_assignment_requests 
    SET status = 'PROCESSING', processing_by = p_admin_uid, updated_at = now()
    WHERE id = p_request_id;
    RETURN TRUE;
  ELSE
    RETURN FALSE;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC for atomic approval and distribution
CREATE OR REPLACE FUNCTION approve_retailer_request(
  p_request_id UUID,
  p_admin_uid UUID,
  p_from_vf_number_id UUID,
  p_amount NUMERIC,
  p_fees NUMERIC,
  p_charge_fees_to_retailer BOOLEAN,
  p_apply_credit BOOLEAN,
  p_admin_notes TEXT,
  p_proof_image_url TEXT
) RETURNS VOID AS $$
DECLARE
  v_req RECORD;
BEGIN
  -- 1. Fetch and lock request
  SELECT * INTO v_req FROM retailer_assignment_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Request not found.'; END IF;
  IF v_req.status = 'COMPLETED' THEN RAISE EXCEPTION 'Request already completed.'; END IF;

  -- 2. Execute distribution
  PERFORM public.distribute_vf_cash(
    v_req.retailer_id,
    p_from_vf_number_id,
    p_amount,
    p_fees,
    p_charge_fees_to_retailer,
    p_apply_credit,
    p_admin_uid::TEXT,
    p_admin_notes
  );

  -- 3. Update request status
  UPDATE retailer_assignment_requests SET
    status = 'COMPLETED',
    assigned_amount = p_amount,
    admin_notes = p_admin_notes,
    proof_image_url = p_proof_image_url,
    completed_at = now(),
    completed_by_uid = p_admin_uid,
    updated_at = now()
  WHERE id = p_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC for rejection
CREATE OR REPLACE FUNCTION reject_retailer_request(
  p_request_id UUID,
  p_admin_uid UUID,
  p_reason TEXT
) RETURNS VOID AS $$
BEGIN
  UPDATE retailer_assignment_requests SET
    status = 'REJECTED',
    rejected_reason = p_reason,
    completed_at = now(),
    completed_by_uid = p_admin_uid,
    updated_at = now()
  WHERE id = p_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
