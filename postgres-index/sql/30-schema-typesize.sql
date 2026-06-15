-- Tables for scenario 06 (column type -> index size) and its uuid insert-locality sub-test.
-- Deterministic uuid generators so the stored dataset is reproducible; the live-insert
-- locality test (06) uses PG18's built-in uuidv4()/uuidv7() to measure realistic throughput.

DROP TABLE IF EXISTS typesize CASCADE;
DROP TYPE  IF EXISTS order_status CASCADE;

CREATE TYPE order_status AS ENUM
  ('pending','paid','shipped','closed','cancelled','refunded');

-- deterministic UUIDv4 (random layout) from id
CREATE OR REPLACE FUNCTION det_uuid4(id bigint)
RETURNS uuid LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT (
    substr(h,1,8)||'-'||substr(h,9,4)||'-4'||substr(h,14,3)||'-8'||substr(h,18,3)||'-'||substr(h,21,12)
  )::uuid
  FROM (SELECT md5(id::text || 'v4') AS h) s
$$;

-- deterministic UUIDv7 (first 48 bits = monotonic ms timestamp -> ordered insert locality)
CREATE OR REPLACE FUNCTION det_uuid7(id bigint)
RETURNS uuid LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT (
    substr(tshex,1,8)||'-'||substr(tshex,9,4)||'-7'||substr(h,1,3)||'-8'||substr(h,4,3)||'-'||substr(h,7,12)
  )::uuid
  FROM (
    SELECT lpad(to_hex(1700000000000 + id), 12, '0') AS tshex,
           md5(id::text || 'v7') AS h
  ) s
$$;

CREATE TABLE typesize (
  id              bigint PRIMARY KEY,
  status_enum     order_status NOT NULL,                 -- 4 bytes fixed
  status_vc_short varchar(16)  NOT NULL,                  -- short labels (pending, paid, ...)
  status_vc_long  varchar(40)  NOT NULL,                  -- long labels (payment_captured_pending_review ...)
  status_smallint smallint     NOT NULL,                  -- 2 bytes
  key_bigint      bigint       NOT NULL,                  -- 8 bytes
  key_uuid4       uuid         NOT NULL,                  -- 16 bytes, random
  key_uuid7       uuid         NOT NULL                   -- 16 bytes, time-ordered
);
