-- (a) function-wrapped column:
SELECT * FROM customers WHERE lower(email) = 'user.500@example.com';
-- (b) implicit cast on a bigint key (forces per-row cast + seq scan):
SELECT * FROM orders WHERE id = '42'::numeric;
-- (b) correctly typed (uses the PK):
SELECT * FROM orders WHERE id = 42;
