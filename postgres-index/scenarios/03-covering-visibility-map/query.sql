-- Same covering query as scenario 02; here we watch Heap Fetches change with VM state.
SELECT sum(amount_cents) FROM orders WHERE tenant_id = 3 AND status = 'paid';
