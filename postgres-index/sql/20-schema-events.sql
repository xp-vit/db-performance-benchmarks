-- Append-only time-series tables for the BRIN scenario (05).
-- events           : physical order == ts order  (high correlation, BRIN's best case)
-- events_shuffled  : identical rows, random physical order (correlation ~0, BRIN collapse)

DROP TABLE IF EXISTS events CASCADE;
DROP TABLE IF EXISTS events_shuffled CASCADE;

CREATE TABLE events (
  id        bigint NOT NULL,
  ts        timestamptz NOT NULL,
  device_id integer NOT NULL,
  value     double precision NOT NULL
);

CREATE TABLE events_shuffled (LIKE events);
