# Example 9: Redis Per App

This example has moved to its own subfolder with fully structured files:

**[09_redis_per_app/README.md](./09_redis_per_app/README.md)**

```
09_redis_per_app/
├── README.md                     ← start here
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── passwords.tf
├── redis-config/
│   ├── app1.conf                 ← reference (module-managed)
│   └── app2.conf                 ← deploy this post-apply
├── systemd/
│   └── redis-app2.service
└── scripts/
    ├── 01_deploy_app2.sh
    ├── 02_update_cloudwatch.sh
    └── 03_verify.sh
```
