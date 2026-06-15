-- jsonb containment on a selective key combination (~1% of rows).
-- A B-tree cannot serve @>; it is seq scan vs GIN.
SELECT count(*) FROM orders
WHERE payload @> '{"category":"electronics","region":"eu","priority":2}';
