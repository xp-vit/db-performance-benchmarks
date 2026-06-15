-- Matches the partial WHERE (planner can use the partial index):
SELECT * FROM orders WHERE status = 'pending' ORDER BY created_at DESC LIMIT 50;
-- Does NOT match the partial WHERE (planner must skip the partial index):
SELECT * FROM orders WHERE status = 'paid'    ORDER BY created_at DESC LIMIT 50;
