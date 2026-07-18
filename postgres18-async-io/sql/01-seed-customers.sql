-- Seed the related customers table once. Idempotent via load_progress marker.
\set ON_ERROR_STOP on

INSERT INTO customers (id, tenant_id, email, created_at)
SELECT g,
       tenant_of(g, :tenants),
       'user.' || g || '@example.com',
       '2021-01-01 00:00:00+00'::timestamptz + (g * interval '15 seconds')
FROM generate_series(1, :customers) g
ON CONFLICT (id) DO NOTHING;

INSERT INTO load_progress (table_name, max_id)
VALUES ('customers', :customers)
ON CONFLICT (table_name) DO UPDATE SET max_id = EXCLUDED.max_id, updated_at = now();

ANALYZE customers;
