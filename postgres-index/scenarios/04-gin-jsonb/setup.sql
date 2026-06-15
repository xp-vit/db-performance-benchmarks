-- Scenario 04: GIN on jsonb vs sequential scan for @> containment.
-- jsonb_path_ops is smaller and faster for @> (cannot serve the key-exists ? operator);
-- jsonb_ops is larger but supports ?  -- we record both sizes for the honest nuance.
CREATE INDEX IF NOT EXISTS o04_gin_pathops ON orders USING gin (payload jsonb_path_ops);
CREATE INDEX IF NOT EXISTS o04_gin_ops     ON orders USING gin (payload jsonb_ops);
