-- Scenario 03: the covering-index caveat. An index-only scan stays heap-free only while
-- the visibility map is current. A mass UPDATE clears VM bits and Heap Fetches reappear
-- until VACUUM restores them. Same covering index as scenario 02.
CREATE INDEX IF NOT EXISTS o03_cov ON orders (tenant_id, status) INCLUDE (amount_cents);
