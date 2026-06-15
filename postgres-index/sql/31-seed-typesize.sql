-- Deterministic seed for the type-size table.
-- Parameter:  :rows  (default driver passes 10000000 for scenario 06).
-- Long labels map 1:1 to the short ones so the ONLY difference between the
-- status_vc_short and status_vc_long index sizes is label length.

\set ON_ERROR_STOP on
\echo seeding typesize = :rows

TRUNCATE typesize;

INSERT INTO typesize (id, status_enum, status_vc_short, status_vc_long, status_smallint,
                      key_bigint, key_uuid4, key_uuid7)
SELECT
  g,
  status_of(g)::order_status,
  status_of(g),
  CASE status_of(g)
    WHEN 'pending'   THEN 'payment_pending_customer_review'
    WHEN 'paid'      THEN 'payment_captured_successfully_ok'
    WHEN 'shipped'   THEN 'shipment_dispatched_in_transit'
    WHEN 'closed'    THEN 'order_closed_and_archived_final'
    WHEN 'cancelled' THEN 'order_cancelled_by_customer_req'
    ELSE                  'refund_issued_to_original_method'
  END,
  CASE status_of(g)
    WHEN 'pending' THEN 0 WHEN 'paid' THEN 1 WHEN 'shipped' THEN 2
    WHEN 'closed' THEN 3 WHEN 'cancelled' THEN 4 ELSE 5 END,
  g,
  det_uuid4(g),
  det_uuid7(g)
FROM generate_series(1, :rows) g;

ANALYZE typesize;

\echo seeded typesize. count:
SELECT count(*) AS typesize FROM typesize;
