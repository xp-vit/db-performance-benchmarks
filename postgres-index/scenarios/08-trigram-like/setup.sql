-- Scenario 08: leading-wildcard LIKE '%term%' cannot use a B-tree; a trigram GIN can.
CREATE INDEX IF NOT EXISTS o08_trgm ON orders USING gin (search_text gin_trgm_ops);
