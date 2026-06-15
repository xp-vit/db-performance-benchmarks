-- Deterministic seed for customers + orders.
-- Parameters (psql vars, set by the runner):
--   :customers  number of customer rows
--   :orders     number of order rows
-- Re-running is idempotent: tables are truncated first.

\set ON_ERROR_STOP on
\echo seeding customers = :customers, orders = :orders

TRUNCATE orders, customers RESTART IDENTITY CASCADE;

-- customers: mixed-case email so lower(email) expression-index scenario (07) is meaningful.
INSERT INTO customers (id, email, email_ci, created_at)
SELECT g,
       'User.' || g || '@Example.COM',
       ('user.' || g || '@example.com')::citext,
       '2022-01-01 00:00:00+00'::timestamptz + (g * interval '20 seconds')
FROM generate_series(1, :customers) g;

-- orders: all derived columns are pure functions of id => reproducible.
INSERT INTO orders (id, tenant_id, customer_id, status, created_at, amount_cents, payload, search_text)
SELECT
  g,
  tenant_of(g, 500),
  1 + (u01(g, 31) * (:customers - 1))::bigint,                       -- FK into customers
  status_of(g),
  '2023-01-01 00:00:00+00'::timestamptz
     + (g * interval '9.46 seconds')                                 -- correlated with id
     + ((u01(g, 41) - 0.5) * interval '600 seconds'),                -- small jitter, stays near-monotonic
  100 + (u01(g, 51) * 999900)::bigint,                               -- 1.00 .. ~10000.00
  jsonb_build_object(
    'category', (ARRAY['electronics','books','garden','toys','grocery','apparel'])[1 + (u01(g,61)*6)::int % 6],
    'priority', 1 + (u01(g,62)*5)::int % 5,
    'flag',     (u01(g,63) < 0.2),
    'region',   (ARRAY['us-east','us-west','eu','apac'])[1 + (u01(g,64)*4)::int % 4],
    -- sku: mostly common buckets, but ~0.02% carry a rare needle so scenario 04 can
    -- contrast a moderately-selective containment (~1%) with a rare one (~0.02%).
    'sku',      CASE WHEN u01(g,65) < 0.0002 THEN 'RARE-NEEDLE'
                     ELSE 'SKU-' || (1 + (u01(g,66)*40)::int % 40) END
  ),
  search_text_of(g)
FROM generate_series(1, :orders) g;

ANALYZE customers;
ANALYZE orders;

\echo seeded. orders count:
SELECT count(*) AS orders FROM orders;
