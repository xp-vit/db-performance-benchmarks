-- Shared core schema: customers + orders. No data here (see seed scripts).
-- These tables carry NO secondary indexes by default; each scenario creates the
-- index it measures so before/after is explicit and isolated.

DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS customers CASCADE;

CREATE TABLE customers (
  id          bigint PRIMARY KEY,
  email       text   NOT NULL,        -- mixed-case, for the lower(email) expression-index scenario (07)
  email_ci    citext NOT NULL,        -- case-insensitive variant
  created_at  timestamptz NOT NULL
);

CREATE TABLE orders (
  id           bigint PRIMARY KEY,
  tenant_id    bigint      NOT NULL,  -- ~500 distinct, power-law skew (a few big tenants)
  customer_id  bigint      NOT NULL,  -- FK target customers(id); NOT indexed by default (scenario 09)
  status       text        NOT NULL,  -- 6 values, ~5% pending
  created_at   timestamptz NOT NULL,  -- correlated with id (append order), spread over 3 years
  amount_cents bigint      NOT NULL,
  payload      jsonb       NOT NULL,  -- realistic doc; 'category' is the containment target (04)
  search_text  text        NOT NULL   -- product-name-like free text for trigram search (08)
);
