# Cognito User Pool + ALB Authentication

Each production account gets its own Cognito User Pool and ALB. The ALB's
`authenticate-cognito` listener action handles the full OIDC flow natively —
no oauth2-proxy or extra containers needed on the EC2.

---

## How ALB Native Cognito Auth Works

```
  Browser                           ALB                      Cognito
     │                               │                          │
     │── GET https://redis.prod1 ───►│                          │
     │                               │ check AWSELBAuthSession  │
     │                               │ cookie — not found       │
     │◄── 302 Cognito /login ────────│                          │
     │    + state + nonce            │                          │
     │                               │                          │
     │── GET /login ────────────────────────────────────────────►
     │                               │                          │
     │   (user enters credentials)   │                          │
     │── POST /login ───────────────────────────────────────────►
     │                               │                          │
     │◄── 302 ALB /oauth2/idpresponse ?code=AUTH_CODE ──────────│
     │                               │                          │
     │── GET /oauth2/idpresponse ───►│                          │
     │   ?code=AUTH_CODE             │── POST /token ───────────►
     │                               │   (exchange code)        │
     │                               │◄── id_token + ───────────│
     │                               │    access_token          │
     │                               │                          │
     │◄── 302 / + Set-Cookie ────────│                          │
     │    AWSELBAuthSession=...      │                          │
     │                               │                          │
     │── GET / (cookie present) ────►│                          │
     │                               │ cookie valid — forward   │
     │                               │── forward to EC2:5540   │
     │◄── Redis Insight HTML ────────│◄── EC2 response ─────────│
```

The ALB handles everything. The EC2 sees only authenticated requests with the user's
identity in forwarded headers (`X-Amzn-Oidc-Identity`, `X-Amzn-Oidc-Data`).

---

## Infrastructure Layout

```
  ┌──────────────────────────────────────────────────────────────────────────┐
  │  Production Account 1  —  VPC                                           │
  │                                                                          │
  │  ┌─────────────────────────────────────────────────────────────────┐    │
  │  │  Public Subnets (AZ-a, AZ-b)                                    │    │
  │  │                                                                 │    │
  │  │  ┌────────────────────────────────────────────────────────────┐ │    │
  │  │  │  Application Load Balancer                                 │ │    │
  │  │  │                                                            │ │    │
  │  │  │  Listener :443 (HTTPS)                                     │ │    │
  │  │  │  ┌────────────────────────────────────────────────────┐    │ │    │
  │  │  │  │  Rule 1 — /  (Redis Insight)                       │    │ │    │
  │  │  │  │  Action 1: authenticate-cognito                    │    │ │    │
  │  │  │  │            User Pool: redis-insight-pool           │    │ │    │
  │  │  │  │            On unauthenticated: authenticate        │    │ │    │
  │  │  │  │  Action 2: forward to target group insight-tg      │    │ │    │
  │  │  │  └────────────────────────────────────────────────────┘    │ │    │
  │  │  │  ┌────────────────────────────────────────────────────┐    │ │    │
  │  │  │  │  Rule 2 — /netdata/*  (Netdata)                    │    │ │    │
  │  │  │  │  Action 1: authenticate-cognito (same pool)        │    │ │    │
  │  │  │  │  Action 2: forward to target group netdata-tg      │    │ │    │
  │  │  │  └────────────────────────────────────────────────────┘    │ │    │
  │  │  └────────────────────────────────────────────────────────────┘ │    │
  │  └─────────────────────────────────────────────────────────────────┘    │
  │                              │                                          │
  │                              │  port 5540 / 19999                       │
  │                              ▼  (ALB SG only)                           │
  │  ┌─────────────────────────────────────────────────────────────────┐    │
  │  │  Private Subnet                                                 │    │
  │  │                                                                 │    │
  │  │  ┌───────────────────────────────────────────────────────────┐  │    │
  │  │  │  EC2  (redis-insight-host)                                │  │    │
  │  │  │  ├─ redis     :6379  (localhost only, systemd)            │  │    │
  │  │  │  ├─ docker: redis-insight  :5540                          │  │    │
  │  │  │  └─ docker: netdata        :19999                         │  │    │
  │  │  └───────────────────────────────────────────────────────────┘  │    │
  │  └─────────────────────────────────────────────────────────────────┘    │
  │                                                                          │
  │  ┌─────────────────────────────────────────────────────────────────┐    │
  │  │  Cognito User Pool  (redis-insight-pool)                        │    │
  │  │  ├─ Users: alice, bob  (or federated from Identity Center)      │    │
  │  │  ├─ App client: redis-insight-alb-client                        │    │
  │  │  │   Callback URL: https://alb-dns/oauth2/idpresponse           │    │
  │  │  └─ Domain: redis-insight-prod1.auth.eu-west-2.amazoncognito.com│    │
  │  └─────────────────────────────────────────────────────────────────┘    │
  └──────────────────────────────────────────────────────────────────────────┘
```

---

## Step 1 — Create the Cognito User Pool

```
AWS Console → Cognito → User Pools → Create user pool

Pool name:              redis-insight-pool
Sign-in options:        Email
Password policy:        Minimum 8 chars, require uppercase + number
MFA:                    Optional TOTP (recommended)
Email delivery:         Cognito (or SES for production)
```

Note the **User Pool ID** (format: `eu-west-2_XXXXXXXXX`).

---

## Step 2 — Create the App Client

Inside the User Pool → App clients → Create app client:

```
App type:               Confidential client
App client name:        redis-insight-alb-client
Client secret:          Generate   ← ALB needs this

Allowed callback URLs:  https://<ALB-DNS>/oauth2/idpresponse
Allowed sign-out URLs:  https://<ALB-DNS>/logout

OAuth 2.0 grant types:  Authorization code grant
OpenID Connect scopes:  openid  email  profile
```

Note the **Client ID** and **Client Secret**.

---

## Step 3 — Set a Cognito Domain

User Pool → App integration → Domain:

```
Cognito domain:   redis-insight-prod1
→ https://redis-insight-prod1.auth.eu-west-2.amazoncognito.com
```

---

## Step 4 — Create the ALB

```
AWS Console → EC2 → Load Balancers → Create → Application Load Balancer

Name:             redis-insight-alb
Scheme:           Internet-facing
IP address type:  IPv4
VPC:              your-vpc
Subnets:          public-subnet-az-a, public-subnet-az-b  (min 2 AZs required)

Security group:   alb-sg
  Inbound: 443 from 0.0.0.0/0

ACM Certificate:  *.company.io  (or redis.prod1.company.io)
```

---

## Step 5 — Create Target Groups

**Redis Insight target group:**
```
Name:             insight-tg
Protocol:         HTTP
Port:             5540
Target type:      Instance
Health check:     HTTP  /  (200 OK)

Register targets: EC2 instance, port 5540
```

**Netdata target group:**
```
Name:             netdata-tg
Protocol:         HTTP
Port:             19999
Target type:      Instance
Health check:     HTTP  /  (200 OK)

Register targets: EC2 instance, port 19999
```

---

## Step 6 — Configure the ALB Listener Rules

**Listener: HTTPS :443**

Rule 1 — Redis Insight (path `/` and `/*`):
```
Condition:   Path is  /  AND  /*  (default rule)

Actions:
  1. authenticate-cognito
     User pool:            <user-pool-arn>
     User pool client:     redis-insight-alb-client
     User pool domain:     redis-insight-prod1
     Session cookie name:  AWSELBAuthSession
     Session timeout:      86400  (24 hours)
     On unauthenticated:   authenticate

  2. Forward to:  insight-tg
```

Rule 2 — Netdata (path `/netdata/*`):
```
Condition:   Path is  /netdata/*

Actions:
  1. authenticate-cognito  (same pool, same client)
  2. Forward to:  netdata-tg
```

---

## Step 7 — EC2 Security Group

```
Security group name:  redis-ec2-sg

Inbound rules:
  Port 5540    Source: alb-sg        (Redis Insight from ALB only)
  Port 19999   Source: alb-sg        (Netdata from ALB only)
  Port 22      Source: your-ip/32    (SSH for maintenance)

Outbound rules:
  All traffic  0.0.0.0/0             (for OS updates, Docker pulls)
```

Redis (port 6379) is **not in this list** — it binds to `127.0.0.1` only and is
unreachable from the network.

---

## Step 8 — Add DNS Record

In Route 53 (or your DNS provider):

```
redis.prod1.company.io  →  CNAME  →  <ALB DNS name>
```

---

## Session and Token Behaviour

```
  ┌─────────────────────────────────────────────────────────────────┐
  │  ALB session cookie: AWSELBAuthSession                          │
  │  Lifetime:           configured on the listener rule            │
  │  Default:            604800 seconds (7 days)                    │
  │  After expiry:       ALB redirects to Cognito login again       │
  └─────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────┐
  │  Cognito tokens                                                 │
  │  Access token:  60 min  (controls when ALB re-validates)        │
  │  Refresh token: 30 days (ALB refreshes access token silently)   │
  │  ID token:      60 min                                          │
  └─────────────────────────────────────────────────────────────────┘
```

The ALB silently refreshes the access token using the refresh token.
Users are only redirected to the login page when the refresh token expires (30 days).

---

## Revoking Access Immediately

Disabling a user in Cognito does not instantly revoke in-flight ALB sessions
because the ALB caches the session cookie for up to `Session timeout` seconds.

For immediate revocation:
```bash
# 1. Disable the user in Cognito
aws cognito-idp admin-disable-user \
  --user-pool-id eu-west-2_XXXXXXXXX \
  --username alice@company.io

# 2. Sign out the user globally (revokes all tokens)
aws cognito-idp admin-user-global-sign-out \
  --user-pool-id eu-west-2_XXXXXXXXX \
  --username alice@company.io
```

The next ALB token validation (within 60 min access token window) will fail,
forcing the user back to the login page where they will be denied.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `400 redirect_mismatch` | Callback URL mismatch | Verify ALB DNS exactly matches `https://<ALB-DNS>/oauth2/idpresponse` in app client |
| Infinite redirect loop | ALB and Cognito domain mismatch | Check Cognito domain name in listener rule matches the User Pool domain |
| `401 Unauthorized` from ALB | Expired session, token not refreshed | Increase session timeout or refresh token lifetime |
| Health check failing | EC2 not returning 200 on `/` | Ensure Redis Insight is running: `docker compose ps` |
| `502 Bad Gateway` | EC2 port 5540 not reachable | Check EC2 security group allows ALB SG on port 5540 |
| ALB can't reach Cognito | VPC endpoint / DNS issue | ALB is in public subnets; it reaches Cognito over the internet — ensure no NAT block |
