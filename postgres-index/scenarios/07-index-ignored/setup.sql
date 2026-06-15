-- Scenario 07: "I added an index and nothing changed." Two reasons the planner ignores it.
-- (a) function on the column: a plain index on email cannot serve WHERE lower(email)=$1.
-- (b) implicit cast: a bigint PK cannot serve WHERE id = '42'::numeric (compare done in numeric).
CREATE INDEX IF NOT EXISTS c07_email_plain ON customers (email);            -- (a) unused for lower()
CREATE INDEX IF NOT EXISTS c07_email_lower ON customers (lower(email));      -- (a) the fix
-- (b) uses the existing orders PK; no extra index needed.
