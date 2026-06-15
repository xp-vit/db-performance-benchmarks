-- Substring search for a rare needle (~0.3% of rows). Leading wildcard => no B-tree help.
SELECT count(*) FROM orders WHERE search_text LIKE '%zfornax%';
