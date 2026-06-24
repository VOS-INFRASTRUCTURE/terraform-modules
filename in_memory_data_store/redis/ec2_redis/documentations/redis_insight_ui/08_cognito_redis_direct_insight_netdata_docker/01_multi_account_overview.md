# Multi-Account Architecture Overview

## AWS Organization Layout

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  AWS Organization (root)                                                        │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  Management Account  (master payer + identity)                           │   │
│  │                                                                          │   │
│  │  ┌────────────────────────────────────────────────────────────────────┐  │   │
│  │  │  IAM Identity Center                                               │  │   │
│  │  │                                                                    │  │   │
│  │  │  Users:                    Groups:                                 │  │   │
│  │  │  ┌───────────────────┐     ┌─────────────────────────────────┐    │  │   │
│  │  │  │  alice@company.io │     │  redis-admins                   │    │  │   │
│  │  │  │  bob@company.io   │ ──► │  ├─ alice@company.io            │    │  │   │
│  │  │  │  carol@company.io │     │  └─ bob@company.io              │    │  │   │
│  │  │  └───────────────────┘     │                                 │    │  │   │
│  │  │                            │  redis-readonly                 │    │  │   │
│  │  │                            │  └─ carol@company.io            │    │  │   │
│  │  │                            └─────────────────────────────────┘    │  │   │
│  │  │                                                                    │  │   │
│  │  │  Permission Sets → assigned to member accounts                     │  │   │
│  │  └────────────────────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│       ┌─────────────────────────────────────────────────────────────────────┐   │
│       │  Production OU                                                      │   │
│       │                                                                     │   │
│       │  ┌───────────────────────────────┐  ┌──────────────────────────┐   │   │
│       │  │  Production Account 1         │  │  Production Account 2    │   │   │
│       │  │  (e.g. prod-eu-west-2)        │  │  (e.g. prod-us-east-1)   │   │   │
│       │  │                               │  │                          │   │   │
│       │  │  Cognito User Pool            │  │  Cognito User Pool       │   │   │
│       │  │  ALB                          │  │  ALB                     │   │   │
│       │  │  EC2 (Redis + Insight)        │  │  EC2 (Redis + Insight)   │   │   │
│       │  └───────────────────────────────┘  └──────────────────────────┘   │   │
│       └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## What Lives Where

| Component | Account | Service | Purpose |
|-----------|---------|---------|---------|
| User directory | Management | IAM Identity Center | Single source of truth for all engineers |
| AWS Console access | Management → Member | Identity Center permission sets | Role-based AWS access per account |
| Redis Insight auth | Production 1 / 2 | Cognito User Pool | Protects the Redis Insight web UI |
| TLS termination + auth check | Production 1 / 2 | ALB (listener rule) | Handles HTTPS + Cognito token validation |
| Redis data store | Production 1 / 2 | EC2 (direct install) | The actual Redis instance |
| Redis GUI | Production 1 / 2 | Docker (Redis Insight) | Web UI for browsing Redis |
| Host monitoring | Production 1 / 2 | Docker (Netdata) | CPU / memory / disk on the EC2 |

---

## Component Relationship Diagram

```
  Developer's Browser
        │
        │  https://redis.prod1.company.io
        │  (DNS → ALB)
        ▼
  ┌─────────────────────────────────────────────────────────────────────────┐
  │  Production Account 1                                                   │
  │                                                                         │
  │  ┌──────────────────────────────────────────────────────────────────┐   │
  │  │  Application Load Balancer (public subnet, HTTPS :443)           │   │
  │  │                                                                  │   │
  │  │  Listener Rule:                                                  │   │
  │  │  1. authenticate-cognito  ──► redirect to Cognito login          │   │
  │  │  2. (authenticated)       ──► forward to target group            │   │
  │  └──────────────────────────────────┬───────────────────────────────┘   │
  │                                     │                                   │
  │          ┌──────────────────────────┘                                   │
  │          │  (only reaches EC2 after Cognito validates token)            │
  │          ▼                                                              │
  │  ┌───────────────────────────────────────────────────────────────────┐  │
  │  │  EC2 Instance  (private subnet)                                   │  │
  │  │                                                                   │  │
  │  │  ┌─────────────────────────────────────────────────────────────┐  │  │
  │  │  │  OS — Redis (direct install, systemd)                       │  │  │
  │  │  │  Listens on 127.0.0.1:6379  (not exposed to network)        │  │  │
  │  │  └─────────────────────────────────────────────────────────────┘  │  │
  │  │                                                                   │  │
  │  │  ┌──────────────────────────┐  ┌──────────────────────────────┐  │  │
  │  │  │  Docker: redis-insight   │  │  Docker: netdata             │  │  │
  │  │  │  :5540 (target for ALB)  │  │  :19999 (separate ALB rule)  │  │  │
  │  │  │  connects to localhost   │  │  monitors host metrics       │  │  │
  │  │  └──────────────────────────┘  └──────────────────────────────┘  │  │
  │  └───────────────────────────────────────────────────────────────────┘  │
  │                                                                         │
  │  ┌───────────────────────────────────────────────────────────────────┐  │
  │  │  Cognito User Pool                                                │  │
  │  │  ├─ Users: alice, bob  (or federated from Identity Center)        │  │
  │  │  ├─ Hosted UI: login page served by AWS                           │  │
  │  │  └─ App Client: registered callback URL = ALB DNS name            │  │
  │  └───────────────────────────────────────────────────────────────────┘  │
  └─────────────────────────────────────────────────────────────────────────┘

  ┌───────────────────────────────────────────────────────────────────────────┐
  │  Management Account                                                       │
  │  IAM Identity Center  (optional: federated as IdP into Cognito above)    │
  └───────────────────────────────────────────────────────────────────────────┘
```

---

## Two Identity Systems — How They Relate

This architecture has two identity systems that serve different purposes:

```
  ┌───────────────────────────────────────────────────────────────────┐
  │  IAM Identity Center (Management Account)                         │
  │                                                                   │
  │  "Who can log into the AWS Console and run Terraform?"            │
  │                                                                   │
  │  Controls:                                                        │
  │  ─ AWS Console login to each account                              │
  │  ─ CLI access via aws sso login                                   │
  │  ─ Permission sets (ReadOnly, Admin, etc.)                        │
  └────────────────────────────┬──────────────────────────────────────┘
                               │
                               │  Option A: completely separate
                               │  Option B: federated (Identity Center
                               │            as SAML IdP → Cognito)
                               │
  ┌────────────────────────────▼──────────────────────────────────────┐
  │  Cognito User Pool (per Production Account)                       │
  │                                                                   │
  │  "Who can log into the Redis Insight web UI?"                     │
  │                                                                   │
  │  Controls:                                                        │
  │  ─ Redis Insight access via browser                               │
  │  ─ Netdata dashboard access (separate ALB rule)                   │
  └───────────────────────────────────────────────────────────────────┘
```

**Option A — Keep them separate (simpler):**
Cognito has its own users. Engineers have two sets of credentials: one for AWS Console (Identity Center) and one for Redis Insight (Cognito). Simpler to set up.

**Option B — Federate Identity Center into Cognito (advanced):**
Cognito delegates authentication to Identity Center via SAML 2.0. Engineers use the same Identity Center login for both the AWS Console and Redis Insight. One identity to manage. See [02_identity_center.md](02_identity_center.md) for the federation setup.

---

## Security Layers Summary

```
  Internet
      │
      │  HTTPS only (ALB terminates TLS)
      ▼
  ┌───────────────────────────────────────────────────────────────────┐
  │  Layer 1: Network                                                 │
  │  ALB Security Group: inbound 443 from 0.0.0.0/0                  │
  │  EC2 Security Group: inbound 5540 + 19999 from ALB SG only       │
  │                      inbound 6379 from EC2 itself (localhost)     │
  └───────────────────────────────────────────────────────────────────┘
      │
  ┌───────────────────────────────────────────────────────────────────┐
  │  Layer 2: Authentication                                          │
  │  ALB authenticate-cognito action: valid Cognito JWT required      │
  │  Unauthenticated requests → 302 redirect to Cognito login         │
  └───────────────────────────────────────────────────────────────────┘
      │
  ┌───────────────────────────────────────────────────────────────────┐
  │  Layer 3: Application                                             │
  │  Redis Insight itself has no built-in auth in this setup —        │
  │  it trusts that all requests have already been authenticated      │
  │  by the ALB above.                                                │
  └───────────────────────────────────────────────────────────────────┘
```
