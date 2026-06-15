-- Scenario 02: covering index via INCLUDE -> index-only scan.
-- Same query, two indexes. The INCLUDE variant carries amount_cents in the leaf
-- so the aggregate is answered from the index alone (no heap visit).

-- PLAIN: search key only. Index Scan must visit the heap to read amount_cents.
CREATE INDEX IF NOT EXISTS o02_plain   ON orders (tenant_id, status);

-- COVERING: amount_cents rides along as a non-key payload column.
CREATE INDEX IF NOT EXISTS o02_include ON orders (tenant_id, status) INCLUDE (amount_cents);
