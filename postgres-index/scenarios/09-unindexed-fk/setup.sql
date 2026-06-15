-- Scenario 09: an unindexed foreign key turns cascade delete into an accidental quadratic.
-- Dedicated parent/child so we can rebuild between measurements without touching orders.
-- child.parent_id REFERENCES parent(id) ON DELETE CASCADE. PG does NOT auto-index parent_id.
DROP TABLE IF EXISTS p09_child CASCADE;
DROP TABLE IF EXISTS p09_parent CASCADE;
CREATE TABLE p09_parent (id bigint PRIMARY KEY);
CREATE TABLE p09_child  (
  id        bigint PRIMARY KEY,
  parent_id bigint NOT NULL REFERENCES p09_parent(id) ON DELETE CASCADE,
  filler    text   NOT NULL
);
-- The measured difference: with vs without
--   CREATE INDEX ON p09_child (parent_id);
