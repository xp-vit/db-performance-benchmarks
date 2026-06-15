-- Sum an amount over a tenant+status slice. Needs only indexed/included columns,
-- so a covering index can answer it without touching the heap.
SELECT sum(amount_cents) FROM orders WHERE tenant_id = 3 AND status = 'paid';
