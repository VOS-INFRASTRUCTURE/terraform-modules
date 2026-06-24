# Redis Insight — Multi-Account with Identity Center + Cognito + ALB

This document set covers an AWS Organizations architecture where Redis Insight is
protected by ALB-native Cognito authentication across multiple production accounts,
with users managed centrally through IAM Identity Center in the management account.

---

## When to Use This Architecture

Use this setup when:
- You have multiple AWS accounts under an AWS Organization
- Engineers already use IAM Identity Center (SSO) to log into the AWS Console
- You want the same identity store to protect Redis Insight (no separate password files)
- Redis is installed directly on EC2 (not as a Docker container)
- You need HTTPS and a proper domain in front of Redis Insight

---

## Document Index

| File | What It Covers |
|------|---------------|
| [01_multi_account_overview.md](01_multi_account_overview.md) | Full org diagram — how all accounts relate |
| [02_identity_center.md](02_identity_center.md) | Management account: Identity Center users and federation |
| [03_cognito_alb.md](03_cognito_alb.md) | Per-account Cognito setup and ALB authentication action |
| [04_ec2_stack.md](04_ec2_stack.md) | EC2: Redis direct install + Docker Compose (Redis Insight + Netdata) |
| [docker-compose.yml](docker-compose.yml) | Redis Insight + Netdata stack (Redis on host, not in Docker) |

---

## Quick Architecture Summary

```
  ┌─────────────────────────────────────────────────────────────────────┐
  │  AWS Management Account                                             │
  │  IAM Identity Center  →  users + groups (single source of truth)   │
  └────────────────────────────┬────────────────────────────────────────┘
                               │  optional: SAML federation
               ┌───────────────┴───────────────┐
               ▼                               ▼
  ┌────────────────────────┐     ┌────────────────────────┐
  │  Production Account 1  │     │  Production Account 2  │
  │                        │     │                        │
  │  Cognito User Pool     │     │  Cognito User Pool     │
  │       ↓                │     │       ↓                │
  │  ALB (HTTPS + auth)    │     │  ALB (HTTPS + auth)    │
  │       ↓                │     │       ↓                │
  │  EC2                   │     │  EC2                   │
  │  ├─ Redis (direct)     │     │  ├─ Redis (direct)     │
  │  ├─ Redis Insight      │     │  ├─ Redis Insight      │
  │  └─ Netdata            │     │  └─ Netdata            │
  └────────────────────────┘     └────────────────────────┘
```

Start with [01_multi_account_overview.md](01_multi_account_overview.md).
