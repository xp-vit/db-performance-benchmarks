-- Extensions + deterministic pseudo-random helpers shared by every scenario.
-- Determinism strategy: values are a pure hash of the row id (not setseed/random()),
-- so the dataset is byte-identical no matter how many parallel workers run the seed.

CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pg_prewarm;       -- warm-cache control
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- u01(id, salt) -> deterministic double in [0,1). Different salts give independent streams.
CREATE OR REPLACE FUNCTION u01(seed bigint, salt integer)
RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT (hashtextextended(seed::text, salt) & 9223372036854775807)::double precision
         / 9223372036854775807.0
$$;

-- Power-law tenant id in [1, ntenants]: u^k concentrates mass on low ids => a few big tenants.
-- This approximates a Zipfian skew (documented as approximation, not exact Zipf) in METHODOLOGY.
CREATE OR REPLACE FUNCTION tenant_of(id bigint, ntenants integer)
RETURNS bigint
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT 1 + floor( ntenants * power(u01(id, 11), 3.0) )::bigint
$$;

-- status: 6 values, ~5% pending (the hot slice for partial-index scenario 12).
CREATE OR REPLACE FUNCTION status_of(id bigint)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE
    WHEN x <  5 THEN 'pending'
    WHEN x < 45 THEN 'paid'
    WHEN x < 70 THEN 'shipped'
    WHEN x < 85 THEN 'closed'
    WHEN x < 95 THEN 'cancelled'
    ELSE             'refunded'
  END
  FROM (SELECT (u01(id, 22) * 100)::int AS x) s
$$;

-- product-name-like search_text built from word lists; ~0.3% contain the rare term 'zfornax'
-- so the trigram scenario (08) has a selective '%zfornax%' needle on a large table.
CREATE OR REPLACE FUNCTION search_text_of(id bigint)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN u01(id, 71) < 0.003 THEN w || ' zfornax edition' ELSE w END
  FROM (
    SELECT (ARRAY['Premium','Classic','Rugged','Compact','Wireless','Eco','Pro','Lite',
                  'Vintage','Smart'])[1 + (u01(id,72)*10)::int % 10]
        || ' ' ||
           (ARRAY['Widget','Adapter','Bottle','Charger','Backpack','Lamp','Speaker',
                  'Keyboard','Bracket','Cable','Toaster','Mug'])[1 + (u01(id,73)*12)::int % 12] AS w
  ) s
$$;
