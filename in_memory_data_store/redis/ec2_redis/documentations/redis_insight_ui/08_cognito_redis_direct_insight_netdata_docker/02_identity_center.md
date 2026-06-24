# IAM Identity Center — Management Account

IAM Identity Center (formerly AWS SSO) is the central identity store for the whole
AWS Organization. It lives in the management account and issues short-lived credentials
to engineers who need AWS Console or CLI access to any member account.

This document covers:
1. The standalone Identity Center setup (always needed)
2. The optional SAML federation into Cognito (so engineers use one login for everything)

---

## Standalone Role — AWS Console Access Only

```
  ┌────────────────────────────────────────────────────────────────────────┐
  │  Management Account — IAM Identity Center                              │
  │                                                                        │
  │  Identity source:  Built-in (or external: Okta, Azure AD, Google)     │
  │                                                                        │
  │  ┌──────────────────┐   ┌────────────────────────────────────────┐    │
  │  │  Users           │   │  Permission Sets                       │    │
  │  │                  │   │                                        │    │
  │  │  alice           │   │  RedisAdmin                            │    │
  │  │  bob             │   │  ├─ AmazonElastiCacheFullAccess        │    │
  │  │  carol           │   │  ├─ AmazonEC2ReadOnlyAccess            │    │
  │  └────────┬─────────┘   │  └─ CloudWatchReadOnlyAccess           │    │
  │           │             │                                        │    │
  │           │             │  ReadOnly                              │    │
  │           │             │  └─ ViewOnlyAccess                     │    │
  │           │             └────────────────────────────────────────┘    │
  │           │                                                           │
  │           │ assigned to member accounts                               │
  └───────────┼───────────────────────────────────────────────────────────┘
              │
              ├─────────────────────────────────────────┐
              ▼                                         ▼
  ┌──────────────────────────┐             ┌──────────────────────────┐
  │  Production Account 1    │             │  Production Account 2    │
  │  alice → RedisAdmin role │             │  alice → RedisAdmin role │
  │  carol → ReadOnly role   │             │  carol → ReadOnly role   │
  └──────────────────────────┘             └──────────────────────────┘
```

This gives engineers AWS Console + CLI access. It does **not** control Redis Insight
access — that is handled by Cognito in each production account.

---

## Setting Up Identity Center

### Step 1 — Enable Identity Center

In the Management Account:

```
AWS Console → IAM Identity Center → Enable
```

Choose an identity source:
- **Built-in** — create users directly in Identity Center (simplest)
- **External IdP** — Okta, Azure AD, Google Workspace (via SAML/SCIM)

### Step 2 — Create Users

```
Identity Center → Users → Add user

First name:   Alice
Last name:    Smith
Email:        alice@company.io
Username:     alice@company.io
```

Users receive an email to activate their account and set a password.

### Step 3 — Create Groups

```
Identity Center → Groups → Create group

Group name:    redis-admins
Members:       alice, bob

Group name:    redis-readonly
Members:       carol
```

### Step 4 — Create Permission Sets

```
Identity Center → Permission sets → Create permission set

Name:            RedisAdminAccess
Session duration: 4 hours
Policies:
  - AmazonElastiCacheFullAccess
  - AmazonEC2ReadOnlyAccess
  - CloudWatchReadOnlyAccess
```

### Step 5 — Assign to Accounts

```
Identity Center → AWS accounts → select Production Account 1
→ Assign users or groups

Group:           redis-admins
Permission set:  RedisAdminAccess
```

Repeat for Production Account 2. Engineers can now `aws sso login --profile prod-account-1`.

---

## Optional — Federate Identity Center into Cognito

This wires Identity Center as a SAML 2.0 identity provider for Cognito. Engineers use
their existing Identity Center credentials to log into Redis Insight — one login for
everything.

```
  Engineer Browser
       │
       │  https://redis.prod1.company.io
       ▼
  ALB → Cognito (no matching user in local pool)
       │
       │  "Use Identity Center" button on Cognito hosted UI
       ▼
  Identity Center login page
  (same password as AWS Console login)
       │
       │  SAML assertion
       ▼
  Cognito validates SAML → creates federated session
       │
       ▼
  ALB cookie set → Redis Insight served
```

### Federation Flow Diagram

```
  Browser              Cognito (prod acct)       Identity Center (mgmt acct)
     │                       │                           │
     │── GET /redis ─────────►                           │
     │                       │                           │
     │◄─ 302 Cognito login ──│                           │
     │                       │                           │
     │── GET /login (Cognito hosted UI) ──►              │
     │                       │                           │
     │   [clicks "Login with Identity Center"]           │
     │                       │──── SAML AuthnRequest ───►│
     │◄──────────────────────────── 302 IC login ────────│
     │                       │                           │
     │── POST credentials ──────────────────────────────►│
     │                       │                           │
     │◄──────────────────────────── SAML Response ───────│
     │                       │                           │
     │── POST SAML assertion ►                           │
     │                       │ validate assertion        │
     │                       │ issue id_token            │
     │◄─ Set-Cookie + 302 ───│                           │
     │                       │                           │
     │── GET /redis (with cookie) ►                      │
     │◄─ Redis Insight ──────│                           │
```

### Configuring the Federation

**Step 1 — Get the Identity Center SAML metadata**

In the Management Account:
```
Identity Center → Settings → Identity source
→ Download SAML metadata file
```

**Step 2 — Create an Identity Provider in Cognito**

In Production Account (Cognito → User Pool → Sign-in → Identity providers):
```
Provider type:         SAML
Provider name:         IdentityCenter
Metadata document:     (upload the file from Step 1)
Attribute mapping:
  email  ←  http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress
```

**Step 3 — Allow the Identity Provider in the App Client**

Cognito → App client → Edit hosted UI:
```
Identity providers:   ✓ IdentityCenter   ✓ Cognito User Pool
```

**Step 4 — Create a Customer-Managed Application in Identity Center**

In the Management Account:
```
Identity Center → Applications → Add application → Custom SAML 2.0 application

Application name:       Redis Insight Prod1
ACS URL:                https://<cognito-domain>.auth.eu-west-2.amazoncognito.com/saml2/idpresponse
Application SAML audience: urn:amazon:cognito:sp:<user-pool-id>

Attribute mappings:
  Subject  ←  ${user:email}  (format: emailAddress)
  email    ←  ${user:email}
```

**Step 5 — Assign Users to the Application**

```
Identity Center → Applications → Redis Insight Prod1 → Assign users
→ Add redis-admins group
```

This controls the **Identity Center federated path only**. When a user who is NOT
assigned clicks "Login with Identity Center", Identity Center refuses to issue a
SAML assertion and shows "You don't have access to this application."

Local Cognito users (email + password) bypass Identity Center entirely and can
always log in — the IC assignment only controls the "Login with Identity Center"
path. This is by design: local accounts are useful for contractors or service
accounts that don't have Identity Center access.

For a full breakdown of how both login paths work and where each is enforced,
see → **[05_saml_group_restriction.md](05_saml_group_restriction.md)**

---

## Access Control Summary

| Who | Can do what | Via |
|-----|------------|-----|
| alice (redis-admins) | AWS Console, Redis Insight | Identity Center |
| bob (redis-admins) | AWS Console, Redis Insight | Identity Center |
| carol (redis-readonly) | AWS Console only | Identity Center |
| external contractor | Redis Insight only (temp) | Cognito local user |

Local Cognito users can coexist with federated Identity Center users. Useful for
giving temporary access to contractors without adding them to Identity Center.
