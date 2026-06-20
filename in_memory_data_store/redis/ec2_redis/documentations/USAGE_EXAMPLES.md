# EC2 Redis — Usage Examples

Detailed examples live in the [`examples/`](./examples/) subfolder.
Each file is self-contained and ready to copy into a Terraform configuration.

| # | Example | Instance | Cost/mo | Key Feature |
|---|---------|----------|---------|-------------|
| [01](./examples/01_basic_development.md) | Basic Development | t4g.micro | $7–8 | Minimal — no password, no backups |
| [02](./examples/02_production_with_backups.md) | Production with Backups | t4g.small | $14–16 | Password in Secrets Manager, daily S3 backups |
| [03](./examples/03_multi_app_shared.md) | Multi-App Shared (DB numbers) | t4g.medium | $28–32 | One Redis, DB-index separation ⚠️ |
| [04](./examples/04_custom_configuration.md) | Custom Configuration | t4g.micro | $7–8 | Non-standard port, volatile-lru eviction |
| [05](./examples/05_minimal_cost.md) | Minimal Cost (POC) | t4g.nano | $3–4 | Absolute minimum, no monitoring |
| [06](./examples/06_cidr_access.md) | CIDR-Based Access | t4g.micro | $7–8 | Allow-list by subnet / VPN CIDR |
| [07](./examples/07_ssh_key_access.md) | SSH Key Access | t4g.micro | $7–8 | EC2 key pair + SSM fallback |
| [08](./examples/08_complete_production.md) | Complete Production | t4g.small | $14–16 | Everything enabled, CloudWatch alarms |
| [**09**](./examples/09_redis_per_app/README.md) | **Redis Per App** ✅ | t4g.small | $14–16 | **Separate process + port + password per app** |

---

## Recommended: Redis Per App

[Example 09](./examples/09_redis_per_app.md) is the pattern to use when multiple applications
share one Redis host. Each app gets:

- Its own Redis process (systemd service)
- Its own port (6379, 6380, 6381 …)
- Its own password (stored in Secrets Manager)
- Its own `maxmemory` budget

A misconfigured app gets `WRONGPASS` or `connection refused` — not silent access to another
app's data.

See also [SeparateRedisPerApp.md](./SeparateRedisPerApp.md) for the full architecture explanation.
