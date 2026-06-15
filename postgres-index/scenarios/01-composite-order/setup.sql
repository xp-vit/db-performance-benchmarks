-- Scenario 01: composite column order.
-- Two candidate indexes over the SAME three columns, opposite leading order.
-- run.sh enables one at a time (drops the other) so each variant is measured in isolation.

-- RIGHT: equality columns (tenant_id, status) lead, sort column (created_at DESC) trails.
-- Serves WHERE tenant_id=? AND status=? ORDER BY created_at DESC LIMIT n with no Sort.
CREATE INDEX IF NOT EXISTS o01_right ON orders (tenant_id, status, created_at DESC);

-- WRONG: sort/range column leads. On older PG the planner cannot jump to the tenant
-- and falls back to a scan. On PG18 it can still scan this index backward in created_at
-- order and filter tenant/status from inside the index - so measure, do not assume.
CREATE INDEX IF NOT EXISTS o01_wrong ON orders (created_at, tenant_id, status);

-- BASELINE: no composite index at all (only the PK). This is the true "wrong" case the
-- war story describes: Seq Scan + in-memory Sort. It anchors the right-vs-nothing gap.
