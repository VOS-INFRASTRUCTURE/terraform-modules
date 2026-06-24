# ALB Domain Auth Relationship

How three domains on one ALB relate to one Cognito user pool and one Identity Center instance.

---

## The Setup (Production Account 1)

```
                        ┌─────────────────────────────────────────────────┐
                        │              Production Account 1                │
                        │                                                  │
  Browser               │   ALB (one listener, port 443)                  │
  ──────                │   ┌─────────────────────────────────────────┐   │
                        │   │                                         │   │
  redis-insight.x.com ──┼──▶│ Rule 1 (priority 83)                   │   │
                        │   │   host: redis-insight.x.com             │   │
                        │   │   action: authenticate-cognito ──────┐  │   │
                        │   │           + forward → EC2:8080       │  │   │
                        │   │                                      │  │   │
  netdata.x.com ────────┼──▶│ Rule 2 (priority 84)                │  │   │
                        │   │   host: netdata.x.com                │  │   │
                        │   │   action: authenticate-cognito ──────┤  │   │
                        │   │           + forward → EC2:8081       │  │   │
                        │   │                                      │  │   │
  example.x.com ────────┼──▶│ Rule 3 (priority 90)                │  │   │
                        │   │   host: example.x.com                │  │   │
                        │   │   action: forward → EC2:80    (none) │  │   │
                        │   │                                      │  │   │
                        │   └──────────────────────────────────────┼──┘   │
                        │                                          │       │
                        │   Cognito User Pool (shared) ◀───────────┘       │
                        │   ┌─────────────────────────┐                   │
                        │   │ App Client              │                   │
                        │   │  callback: /insight/…   │                   │
                        │   │  callback: /netdata/…   │                   │
                        │   │                         │                   │
                        │   │ SAML IdP: IdentityCenter│──────────────────┐│
                        │   └─────────────────────────┘                  ││
                        │                                                 ││
                        │   EC2                                           ││
                        │   ├── Redis (host:6379)                         ││
                        │   └── Docker                                    ││
                        │       ├── Redis Insight (:8080)                 ││
                        │       └── Netdata       (:8081)                 ││
                        │                                                 ││
                        └─────────────────────────────────────────────────┼┘
                                                                          │
                        ┌─────────────────────────────────────────────────┼┐
                        │         Management Account                       ││
                        │                                                  ││
                        │   IAM Identity Center ◀──────────────────────────┘│
                        │   ├── Redis-Admin group                            │
                        │   │     └── user: alice@company.io                 │
                        │   └── SAML Application: Redis Insight Staging      │
                        │         ACS URL → Cognito /saml2/idpresponse       │
                        │         Assigned: Redis-Admin group only            │
                        └────────────────────────────────────────────────────┘
```

**Rule 3 (`example.x.com`) is completely unaffected.** No `authenticate-cognito` action
is on that rule. Requests to it never touch Cognito. The ALB evaluates rules independently
per request — adding auth to rules 1 and 2 does not change rule 3.

---

## How the ALB Session Cookie Works

Understanding this is the key to understanding SSO between the two protected apps.

There are **two separate cookie layers** in play:

```
Layer 1 — Cognito session cookie
  Domain:   .auth.eu-west-2.amazoncognito.com
  Set by:   Cognito hosted UI after successful login
  Scope:    All apps using this Cognito pool (domain-wide)
  TTL:      Cognito user pool session (default 1 day)

Layer 2 — ALB session cookie
  Domain:   redis-insight.x.com   (one per protected domain)
  Set by:   ALB after it exchanges the Cognito token
  Scope:    Only that specific domain
  TTL:      session_timeout in the listener rule (we set 24h)
```

The ALB checks its own cookie first. If missing or expired, it redirects to Cognito.
Cognito checks its own cookie. If that is still valid, Cognito silently issues a new
token — **no login prompt shown to the user**.

---

## Same User Pool — SSO Flow (What Actually Happens)

```
Step 1: User visits redis-insight.x.com for the first time
─────────────────────────────────────────────────────────

  Browser                 ALB                Cognito              Identity Center
    │                      │                    │                       │
    │  GET redis-insight/  │                    │                       │
    │─────────────────────▶│                    │                       │
    │                      │  no ALB cookie     │                       │
    │                      │  redirect to login │                       │
    │◀─────────────────────│                    │                       │
    │                      │                    │                       │
    │  GET cognito/login   │                    │                       │
    │──────────────────────┼───────────────────▶│                       │
    │                      │                    │  no Cognito cookie     │
    │                      │                    │  show login page       │
    │◀─────────────────────┼────────────────────│                       │
    │                      │                    │                       │
    │  click: IdentityCenter button             │                       │
    │──────────────────────┼───────────────────▶│                       │
    │                      │                    │  redirect to IC        │
    │◀─────────────────────┼────────────────────│──────────────────────▶│
    │                      │                    │                       │  verify group
    │                      │                    │                       │  assignment
    │                      │                    │  SAML assertion        │
    │                      │                    │◀──────────────────────│
    │                      │                    │                       │
    │                      │                    │  SET Cognito cookie    │
    │                      │                    │  (.amazoncognito.com)  │
    │                      │  tokens            │                       │
    │                      │◀───────────────────│                       │
    │                      │  SET ALB cookie    │                       │
    │                      │  (redis-insight)   │                       │
    │  redis-insight loads │                    │                       │
    │◀─────────────────────│                    │                       │


Step 2: Same user visits netdata.x.com (same browser session)
─────────────────────────────────────────────────────────────

  Browser                 ALB                Cognito              Identity Center
    │                      │                    │                       │
    │  GET netdata/        │                    │                       │
    │─────────────────────▶│                    │                       │
    │                      │  no ALB cookie     │                       │
    │                      │  for netdata.x.com │                       │
    │                      │  redirect to login │                       │
    │◀─────────────────────│                    │                       │
    │                      │                    │                       │
    │  GET cognito/login   │                    │                       │
    │──────────────────────┼───────────────────▶│                       │
    │                      │                    │  Cognito cookie FOUND  │
    │                      │                    │  (from step 1)         │
    │                      │                    │  silent token issue    │
    │                      │                    │  NO login prompt shown │
    │                      │  tokens            │                       │
    │                      │◀───────────────────│                       │
    │                      │  SET ALB cookie    │                       │
    │                      │  (netdata.x.com)   │                       │
    │  netdata loads       │                    │                       │
    │◀─────────────────────│                    │                       │

Result: User sees one login total. Netdata opens transparently.
```

---

## Same User Pool — Cons

| Con | Why it matters |
|-----|---------------|
| **Shared access scope** | Any user who can reach Cognito can reach both Redis Insight and Netdata. IC group assignment protects the federated path, but a local Cognito user you add manually gets both apps — you cannot restrict them to only one. |
| **No per-app group restriction from IC** | IC application assignment is all-or-nothing at the pool level. You cannot say "Redis-Admin gets Redis Insight, Netdata-Admin gets Netdata" using IC alone with a single pool. |
| **Shared failure domain** | If the Cognito pool is misconfigured, hits a service quota, or is deleted, both apps go down simultaneously. |
| **Mixed audit logs** | Cognito login events in CloudWatch are in one pool. You cannot easily separate "who accessed Redis Insight" from "who accessed Netdata" from the Cognito side alone (ALB access logs distinguish, Cognito logs do not). |
| **App client secret shared** | The single app client covers both callback URLs. A stolen client secret (unlikely in ALB-native auth, but worth noting) affects both apps. |

---

## Different User Pools — What Changes

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Production Account 1  (different pools)                                  │
│                                                                          │
│  ALB                                                                     │
│  ├── Rule 1: redis-insight.x.com                                         │
│  │     authenticate-cognito: Pool A  ──▶  Cognito Pool A               │
│  │                                        App Client A                   │
│  │                                        SAML IdP: IC (SAML App A)     │
│  │                                                                        │
│  └── Rule 2: netdata.x.com                                               │
│        authenticate-cognito: Pool B  ──▶  Cognito Pool B               │
│                                           App Client B                   │
│                                           SAML IdP: IC (SAML App B)     │
└─────────────────────────────────────────────────────────────────────────┘

Management Account
├── IC SAML Application A (Redis Insight)  → Pool A ACS URL
│     Assigned: Redis-Admin group
└── IC SAML Application B (Netdata)        → Pool B ACS URL
      Assigned: Netdata-Admin group
```

### Does the user have to log in twice?

**Yes — fully, both times.** There is no shared session between different Cognito pools.

```
User visits redis-insight → Cognito Pool A login page → IC login → lands on Redis Insight
                            Pool A sets:  Cognito cookie in .auth.<region>.amazoncognito.com
                                         ALB cookie     in redis-insight.x.com

User visits netdata      → Cognito Pool B login page
                            Pool B has NO cookie (different Cognito domain for Pool B)
                            → Full login prompt again
                            → IC redirect again
                            → lands on Netdata
```

Each Cognito pool has its own hosted UI domain:
- Pool A: `staging-cerpac-redis-insight.auth.eu-west-2.amazoncognito.com`
- Pool B: `staging-cerpac-netdata.auth.eu-west-2.amazoncognito.com`

These are different origins. Cookies from Pool A are invisible to Pool B.

---

## Shared Pool — How Does ALB Know Which Callback URL to Use?

The ALB constructs the `redirect_uri` dynamically from the **host header of the original request**.
You registered two callback URLs on the App Client, but the ALB only ever sends one of them
per request — whichever domain the user came from.

```
User visits redis-insight.x.com
──────────────────────────────────────────────────────────────────
  1. ALB receives request, sees: Host: redis-insight.x.com
  2. No ALB session cookie → redirect to Cognito, attaching:
       redirect_uri = https://redis-insight.x.com/oauth2/idpresponse
  3. Cognito checks: is this redirect_uri in the App Client's allowed list?
       callback_urls = [
         "https://redis-insight.x.com/oauth2/idpresponse",  ✓ match
         "https://netdata.x.com/oauth2/idpresponse",
       ]
  4. Cognito proceeds, sends auth code back to redis-insight.x.com/oauth2/idpresponse
  5. ALB receives the code at that URL, exchanges it for tokens, sets cookie

User visits netdata.x.com
──────────────────────────────────────────────────────────────────
  1. ALB receives request, sees: Host: netdata.x.com
  2. No ALB session cookie → redirect to Cognito, attaching:
       redirect_uri = https://netdata.x.com/oauth2/idpresponse
  3. Cognito checks: is this redirect_uri in the App Client's allowed list?
       callback_urls = [
         "https://redis-insight.x.com/oauth2/idpresponse",
         "https://netdata.x.com/oauth2/idpresponse",         ✓ match
       ]
  4. Cognito proceeds, sends auth code back to netdata.x.com/oauth2/idpresponse
  5. ALB sets cookie for netdata.x.com
```

The two entries in `callback_urls` are not alternatives for the ALB to pick from —
they are a **whitelist** that Cognito validates against. The ALB always picks the one
that matches the current domain automatically. Cognito just confirms it is allowed.

If you removed `netdata.x.com/oauth2/idpresponse` from the App Client, the Cognito
auth for Netdata would fail with an "invalid redirect_uri" error even though
Redis Insight still works fine.

---

## Different Pools — How Does ALB Know Which Pool to Use?

There is no dynamic lookup. **Each ALB listener rule hard-codes its own pool.**

```hcl
# Rule 1 — redis-insight: uses Pool A explicitly
resource "aws_lb_listener_rule" "redis_insight_rule" {
  action {
    type = "authenticate-cognito"
    authenticate_cognito {
      user_pool_arn       = aws_cognito_user_pool.redis_insight.arn   # Pool A
      user_pool_client_id = aws_cognito_user_pool_client.redis_insight_alb.id
      user_pool_domain    = aws_cognito_user_pool_domain.redis_insight.domain
    }
  }
  action { type = "forward" ... }
}

# Rule 2 — netdata: uses Pool B explicitly
resource "aws_lb_listener_rule" "netdata_rule" {
  action {
    type = "authenticate-cognito"
    authenticate_cognito {
      user_pool_arn       = aws_cognito_user_pool.netdata.arn          # Pool B
      user_pool_client_id = aws_cognito_user_pool_client.netdata_alb.id
      user_pool_domain    = aws_cognito_user_pool_domain.netdata.domain
    }
  }
  action { type = "forward" ... }
}
```

```
Request: Host: redis-insight.x.com
  │
  ▼
ALB evaluates rules top-down
  │
  ├── Rule 1 condition matches (host header = redis-insight.x.com)
  │   authenticate-cognito block says: use Pool A ARN
  │   → redirect to Pool A hosted UI
  │
  └── Rule 2 never evaluated for this request

Request: Host: netdata.x.com
  │
  ▼
ALB evaluates rules top-down
  │
  ├── Rule 1 condition does NOT match
  │
  ├── Rule 2 condition matches (host header = netdata.x.com)
  │   authenticate-cognito block says: use Pool B ARN
  │   → redirect to Pool B hosted UI
  │
  └── Pool A is never contacted
```

The ALB does not inspect the domain at runtime to decide which pool to use.
The mapping is compiled into the rules at `terraform apply` time.
This is why the split-pool design requires two separate Terraform rule blocks —
there is no "auto-detect pool from domain" feature.

---

## Decision Guide

```
                 Do you need different groups for each app?
                 (e.g. Redis-Admin ≠ Netdata-Admin)
                          │
              ┌───────────┴──────────┐
             YES                    NO
              │                      │
              ▼                      ▼
      Different pools           Same pool
      + separate IC apps        + one IC app
              │                      │
              ▼                      ▼
      Users log in TWICE        Users log in ONCE
      (no SSO between apps)     (SSO between apps)
              │                      │
              ▼                      ▼
      More isolation            Shared failure domain
      Per-app audit logs        Mixed audit logs
      Higher infra cost         Lower infra cost
      (2 pools, 2 IC apps)      (1 pool, 1 IC app)
```

**For this project (same admin team manages both tools): same pool is correct.**
The only meaningful con is the shared access scope — which is acceptable because
you want the same Redis-Admin group to reach both tools anyway.

---

## What "Forward Only" Means for example.x.com

```
  Browser                 ALB                    EC2
    │                      │                      │
    │  GET example.x.com/  │                      │
    │─────────────────────▶│                      │
    │                      │  Rule 3 matched       │
    │                      │  action: forward only │
    │                      │─────────────────────▶│
    │                      │                      │  process request
    │                      │◀─────────────────────│
    │◀─────────────────────│                      │
    │  response            │                      │
```

No Cognito redirect. No cookie check. The request goes straight to the EC2 target group.
Adding Cognito auth to rules 1 and 2 had zero effect on this rule.
