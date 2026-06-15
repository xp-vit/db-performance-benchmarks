-- Scenario 12: a partial index over the hot slice (status='pending', ~5%) is a fraction of
-- the full index size and at least as fast; the planner only uses it when the query
-- predicate matches the partial WHERE.
CREATE INDEX IF NOT EXISTS o12_partial ON orders (created_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS o12_full    ON orders (status, created_at);
