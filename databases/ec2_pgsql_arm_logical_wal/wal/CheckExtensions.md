🧠 1. Check available logical decoding plugins (best method)

Run this SQL:

SELECT *
FROM pg_available_extensions
WHERE name = 'wal2json';