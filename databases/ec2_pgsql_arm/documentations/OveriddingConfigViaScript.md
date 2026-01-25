The correct order (Debian/Ubuntu-safe)
1️⃣ Let the package create the cluster (don’t touch configs yet)
apt-get install -y postgresql postgresql-contrib


At this point:

Cluster exists

Default postgresql.conf is valid

Service may be stopped or started briefly — that’s fine

2️⃣ Start PostgreSQL once (unmodified)
systemctl start postgresql


This guarantees:

data_directory is known

Socket exists

psql can connect

3️⃣ Apply config via ALTER SYSTEM
sudo -u postgres psql <<SQL
ALTER SYSTEM SET listen_addresses = '*';
ALTER SYSTEM SET max_connections = ${var.max_connections};
ALTER SYSTEM SET shared_buffers = '${var.shared_buffers}';
ALTER SYSTEM SET effective_cache_size = '${var.effective_cache_size}';
ALTER SYSTEM SET maintenance_work_mem = '512MB';
ALTER SYSTEM SET work_mem = '16MB';
ALTER SYSTEM SET wal_level = 'minimal';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET effective_io_concurrency = 200;
ALTER SYSTEM SET log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h ';
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
ALTER SYSTEM SET track_activity_query_size = 2048;
ALTER SYSTEM SET track_io_timing = on;
SQL


This writes to:

/etc/postgresql/16/main/postgresql.auto.conf

4️⃣ Restart PostgreSQL (required for many params)
systemctl restart postgresql


No ambiguity. No broken cluster. No duplicated keys.

Why this works perfectly with cloud-init

PostgreSQL is guaranteed to start once

You never overwrite distro-managed files

Settings survive package upgrades

Script is idempotent

Failure mode is obvious (psql fails if server is down)

What still belongs in files

Keep these file-based (you’re already doing this right):

File	Reason
pg_hba.conf	Order-sensitive, not supported by ALTER SYSTEM
SSL certs	File paths
Log directory permissions	OS-level