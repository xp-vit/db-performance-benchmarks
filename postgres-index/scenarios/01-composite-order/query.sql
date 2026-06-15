-- The measured query: newest 20 paid orders for one tenant.
-- Equality on tenant_id + status, ordered by created_at DESC, small LIMIT.
SELECT * FROM orders
WHERE tenant_id = 3 AND status = 'paid'
ORDER BY created_at DESC
LIMIT 20;
