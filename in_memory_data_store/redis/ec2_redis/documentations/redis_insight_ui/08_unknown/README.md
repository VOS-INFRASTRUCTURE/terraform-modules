# Redis Insight — AWS Cognito Authentication (Docker)

Replaces the nginx HTTP Basic Auth approach with AWS Cognito as the identity provider.
`oauth2-proxy` sits in front of Redis Insight and enforces a full Cognito login before
any request reaches the UI. No usernames or passwords are stored on the server.

---

## Why Cognito Instead of Basic Auth

| Concern                  | Basic Auth (`.htpasswd`)             | Cognito + oauth2-proxy              |
|--------------------------|--------------------------------------|--------------------------------------|
| Credential storage       | Hashed passwords on the server       | Managed by AWS — nothing on server  |
| Password rotation        | Regenerate `.htpasswd`, reload nginx | Reset in AWS Console or CLI         |
| Multi-factor auth        | Not supported                        | Built-in (SMS, TOTP, email)         |
| User management          | Manual file edits                    | AWS Console / API                   |
| Audit trail              | None                                 | CloudTrail logs every login         |
| Brute-force protection   | None (unless nginx rate-limit added) | Cognito lockout + CAPTCHA           |
| SSO / Google / SAML      | Not possible                         | Supported via identity federation   |
| Token expiry             | Never (until file changes)           | Configurable (minutes to hours)     |

---

## Architecture

### Basic Auth (before)

```
  Browser
    │
    │  http://<HOST>:8080
    ▼
  ┌──────────────────────────────┐
  │  Docker Host                 │
  │                              │
  │  ┌──────────────────────┐    │
  │  │   Nginx              │    │
  │  │   Basic Auth prompt  │    │
  │  │   (.htpasswd)        │    │
  │  └──────────┬───────────┘    │
  │             │                │
  │             ▼                │
  │  ┌──────────────────────┐    │
  │  │   Redis Insight      │    │
  │  │   (internal only)    │    │
  │  └──────────────────────┘    │
  └──────────────────────────────┘

  Weakness: credentials stored on disk.
  One server compromise = all passwords exposed.
```

### Cognito + oauth2-proxy (after)

```
  Browser
    │
    │  http://<HOST>:5540
    ▼
  ┌──────────────────────────────────────────────────────────────────────┐
  │  Docker Host                                                         │
  │                                                                      │
  │  ┌───────────────────────────────────────────────────────────────┐   │
  │  │  oauth2-proxy  (0.0.0.0:5540)                                 │   │
  │  │                                                               │   │
  │  │  1. No valid session cookie?  ──► redirect to Cognito         │   │
  │  │  2. Valid session cookie?     ──► proxy to Redis Insight      │   │
  │  └──────────────────────────┬────────────────────────────────────┘   │
  │                             │                                        │
  │                             │  http://redis-insight:5540             │
  │                             ▼                                        │
  │  ┌──────────────────────────────┐                                    │
  │  │  Redis Insight               │  ← internal only (expose)          │
  │  │  (:5540)                     │                                    │
  │  └──────────────────────────────┘                                    │
  └──────────────────────────────────────────────────────────────────────┘

                          │  redirect (302)
                          ▼
  ┌──────────────────────────────────────────────────────────────────────┐
  │  AWS Cognito (external — managed by AWS)                             │
  │                                                                      │
  │  ┌───────────────────────────┐   ┌────────────────────────────────┐  │
  │  │  Hosted Login UI          │   │  User Pool                     │  │
  │  │  (Cognito domain)         │   │  - Users / Groups              │  │
  │  │                           │   │  - MFA settings                │  │
  │  │  Username + Password      │   │  - Token expiry                │  │
  │  │  (or Google/SAML)         │   │  - CloudTrail audit            │  │
  │  └───────────────────────────┘   └────────────────────────────────┘  │
  └──────────────────────────────────────────────────────────────────────┘
```

### OIDC Token Exchange Flow

```
  Browser                  oauth2-proxy              Cognito
     │                          │                       │
     │── GET /                  │                       │
     │                          │                       │
     │◄─ 302 /oauth2/start ─────│                       │
     │                          │                       │
     │── GET /oauth2/start ─────►                       │
     │                          │── redirect to ────────►
     │                          │   /login?...          │
     │                          │                       │
     │◄──────────────────────────────── 302 /login ─────│
     │                          │                       │
     │── POST /login (user+pw) ────────────────────────►│
     │                          │                       │
     │◄─────────────────────────────── 302 /callback ───│
     │  (with ?code=AUTH_CODE)  │                       │
     │                          │                       │
     │── GET /oauth2/callback ──►                       │
     │   ?code=AUTH_CODE        │── POST /token ────────►
     │                          │   exchange code       │
     │                          │◄── id_token + ────────│
     │                          │    access_token       │
     │                          │                       │
     │◄─ Set-Cookie: session ───│                       │
     │   + 302 /                │                       │
     │                          │                       │
     │── GET / (with cookie) ───►                       │
     │                          │── proxy ─────────────►│Redis Insight
     │◄─ Redis Insight HTML ────│                       │
```

---

## Prerequisites

### 1 — Create a Cognito User Pool

In the AWS Console (Cognito → User Pools → Create):

```
Pool name:          redis-insight-users
Sign-in options:    Email
MFA:                Optional (recommended: TOTP)
```

Note the **User Pool ID** (format: `eu-west-2_XXXXXXXXX`).

### 2 — Create an App Client

Inside the User Pool → App clients → Create:

```
App type:                Confidential client
App client name:         redis-insight-proxy
Client secret:           Generate a client secret   ← required for oauth2-proxy
Authentication flows:    ALLOW_USER_SRP_AUTH
                         ALLOW_REFRESH_TOKEN_AUTH
```

Note the **Client ID** and **Client Secret**.

### 3 — Configure the Hosted UI

Inside the App client → Edit hosted UI:

```
Allowed callback URLs:    http://<HOST_IP>:5540/oauth2/callback
Allowed sign-out URLs:    http://<HOST_IP>:5540/oauth2/sign_out
Identity providers:       Cognito user pool
OAuth 2.0 grant types:    Authorization code grant
OpenID Connect scopes:    openid  email  profile
```

### 4 — Set a Cognito Domain

User Pool → App integration → Domain:

```
Cognito domain:  redis-insight-<your-suffix>
                 → https://redis-insight-<suffix>.auth.eu-west-2.amazoncognito.com
```

### 5 — Create a Test User

User Pool → Users → Create user:

```
Email:              your-admin@example.com
Temporary password: set one
Mark as confirmed:  yes (or let them change on first login)
```

---

## Files in This Directory

```
01_docker_cognito/
├── README.md               ← you are here
└── docker-compose.yml
```

---

## Step 1 — Create the `.env` File

Create `.env` next to `docker-compose.yml`. **Never commit this file.**

```bash
# Redis passwords
REDIS_APP1_PASSWORD=StrongAppOnePass!
REDIS_APP2_PASSWORD=StrongAppTwoPass!

# Cognito OIDC
COGNITO_REGION=eu-west-2
COGNITO_USER_POOL_ID=eu-west-2_XXXXXXXXX
COGNITO_CLIENT_ID=<app-client-id-from-step-2>
COGNITO_CLIENT_SECRET=<app-client-secret-from-step-2>

# Public address of this host (used for the callback URL)
HOST_IP=<your-ec2-public-ip-or-domain>

# Random 32-byte secret for oauth2-proxy session cookies
# Generate with: openssl rand -base64 32
OAUTH2_COOKIE_SECRET=<32-byte-base64-random>
```

Generate the cookie secret:

```bash
openssl rand -base64 32
```

---

## Step 2 — Start the Stack

```bash
docker compose up -d
docker compose ps
```

Expected:

```
NAME                   STATUS          PORTS
redis-app1             Up              0.0.0.0:6379->6379/tcp
redis-app2             Up              0.0.0.0:6380->6379/tcp
redis-insight          Up              (internal only)
redis-insight-proxy    Up              0.0.0.0:5540->4180/tcp
```

---

## Step 3 — Open the UI

Navigate to `http://<HOST_IP>:5540`.

oauth2-proxy detects no session and redirects you to the Cognito Hosted Login page.
After a successful login, you land back on Redis Insight — no credentials stored anywhere
on the server.

---

## Step 4 — Add Redis Databases

Use **container names** as the host (Docker DNS resolves them within `redis-net`):

**App 1:**
```
Host:     redis-app1
Port:     6379
Password: <REDIS_APP1_PASSWORD from .env>
```

**App 2:**
```
Host:     redis-app2
Port:     6379
Password: <REDIS_APP2_PASSWORD from .env>
```

---

## Managing Users

All user management happens in AWS Cognito — nothing changes on the server.

```bash
# Add a user
aws cognito-idp admin-create-user \
  --user-pool-id eu-west-2_XXXXXXXXX \
  --username new-user@example.com \
  --temporary-password 'TempPass123!' \
  --user-attributes Name=email,Value=new-user@example.com \
                    Name=email_verified,Value=true

# Disable a user (immediate effect — revokes active sessions on next token refresh)
aws cognito-idp admin-disable-user \
  --user-pool-id eu-west-2_XXXXXXXXX \
  --username old-user@example.com

# Force password reset
aws cognito-idp admin-reset-user-password \
  --user-pool-id eu-west-2_XXXXXXXXX \
  --username user@example.com
```

---

## Restricting Access by Email Domain

To allow only users from a specific domain (e.g., `yourcompany.com`), set in `.env`:

```bash
OAUTH2_EMAIL_DOMAIN=yourcompany.com
```

And update the `OAUTH2_PROXY_EMAIL_DOMAINS` env var in `docker-compose.yml` accordingly.
Only Cognito users whose email matches that domain will pass through.

---

## Session Expiry

oauth2-proxy sessions follow the Cognito app client token settings:

| Token          | Default    | Where to change                          |
|----------------|------------|------------------------------------------|
| Access token   | 60 min     | Cognito → App client → Edit             |
| Refresh token  | 30 days    | Cognito → App client → Edit             |
| ID token       | 60 min     | Cognito → App client → Edit             |

When the access token expires, oauth2-proxy uses the refresh token silently —
the user is not redirected to login again until the refresh token itself expires.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Redirect loop on `/` | Callback URL mismatch | Confirm `http://<HOST>:5540/oauth2/callback` matches Cognito app client exactly |
| `403 Permission Denied` after login | Email domain restriction | Set `OAUTH2_PROXY_EMAIL_DOMAINS=*` or add user's domain |
| `invalid_client` from Cognito | Wrong client secret | Re-copy client secret from Cognito; check for trailing spaces in `.env` |
| `oauth2-proxy` crash on startup | Bad cookie secret | Run `openssl rand -base64 32` and update `OAUTH2_COOKIE_SECRET` |
| Token expired — forced re-login | Refresh token expired | Extend refresh token lifetime in Cognito app client settings |
| 502 Bad Gateway | Redis Insight not running | `docker compose ps` — check redis-insight container status |
| DB connect fails in Redis Insight | Wrong host name | Use container name (`redis-app1`), not `localhost` |
| Cognito returns `invalid_grant` | Clock skew on EC2 | `sudo timedatectl set-ntp true` to sync time |
