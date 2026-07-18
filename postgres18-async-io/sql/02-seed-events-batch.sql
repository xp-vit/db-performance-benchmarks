-- Insert one resumable batch of events for id in [:lo, :hi].
-- All columns are pure functions of the id -> deterministic + restartable.
\set ON_ERROR_STOP on

INSERT INTO events (id, tenant_id, customer_id, ts, event_type, status,
                    amount_cents, region, payload, note)
SELECT
  g,
  tenant_of(g, :tenants),
  1 + (u01(g, 11) * (:customers - 1))::bigint,
  '2023-01-01 00:00:00+00'::timestamptz
     + (g * interval '0.9 seconds')                       -- correlated with id (append order)
     + ((u01(g, 12) - 0.5) * interval '300 seconds'),     -- small jitter
  (1 + (u01(g, 13) * 8)::int % 8)::smallint,               -- 8 event types
  (1 + (u01(g, 14) * 5)::int % 5)::smallint,               -- 5 statuses
  100 + (u01(g, 15) * 999900)::bigint,
  (ARRAY['us-east','us-west','eu','apac'])[1 + (u01(g,16)*4)::int % 4],
  jsonb_build_object(
    'k',   (1 + (u01(g,17)*50)::int % 50),
    'src', (ARRAY['web','mobile','api','batch'])[1 + (u01(g,18)*4)::int % 4],
    'ok',  (u01(g,19) < 0.8)
  ),
  -- filler note to reach a realistic row width (~250-300B total)
  'evt ' || g || ' ' || md5(g::text) || ' ' || md5((g*7+1)::text)
FROM generate_series(:lo, :hi) g;

INSERT INTO load_progress (table_name, max_id)
VALUES ('events', :hi)
ON CONFLICT (table_name) DO UPDATE SET max_id = GREATEST(load_progress.max_id, EXCLUDED.max_id), updated_at = now();
