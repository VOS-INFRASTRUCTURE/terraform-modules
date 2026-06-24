# SAML Group-Based Access Restriction

Access control works differently depending on how the user logs in.
There are two paths into Redis Insight — local Cognito accounts and
Identity Center federated accounts — and each is governed separately.

No Lambda is required for this model.

---

## The Two Login Paths

```
  Cognito Hosted Login Page
  ┌─────────────────────────────────────────────────────────┐
  │                                                         │
  │   Email _______________   Password ______________       │
  │   [          Log In          ]                          │
  │                                                         │
  │   ─────────────── or ───────────────                    │
  │                                                         │
  │   [ Login with Identity Center ]                        │
  │                                                         │
  └─────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
  Path A: Local user            Path B: Federated user
  (Cognito email+password)      (Identity Center SAML)
```

---

## Path A — Local Cognito User (always allowed)

```
  Browser                      Cognito
     │                            │
     │── POST email + password ──►│
     │                            │ validates credentials
     │                            │ user exists in pool → OK
     │◄── id_token ───────────────│
     │                            │
  ALB sets cookie → Redis Insight loads ✓

  No group check. No Identity Center involved.
  Any user you create directly in the Cognito User Pool
  can always log in.
```

---

## Path B — Identity Center Federated User (group-restricted)

The restriction for federated users is enforced entirely inside **Identity Center**,
before Cognito is ever involved. It works through the application assignment.

```
  Browser            Identity Center                   Cognito
     │                      │                             │
     │── click "Login        │                             │
     │   with IC" ──────────►│                             │
     │                      │ checks: is this user        │
     │                      │ assigned to                 │
     │                      │ "Redis Insight Prod1"?      │
     │                      │                             │
     │            ┌─────────┴─────────┐                   │
     │            │                   │                   │
     │         YES (redis-admins)   NO (any other group)  │
     │            │                   │                   │
     │            │         show error page               │
     │            │         "You don't have permission"   │
     │            │         SAML is never sent ✗          │
     │            │                                       │
     │            │── SAML assertion ────────────────────►│
     │            │   (user authenticated)                │ validates
     │            │                                       │ assertion
     │◄── id_token ──────────────────────────────────────│
     │                                                    │
  ALB sets cookie → Redis Insight loads ✓
```

---

## How the Assignment Works in Identity Center

```
  Identity Center — Redis Insight Prod1 Application
  ┌─────────────────────────────────────────────────────────┐
  │                                                         │
  │  Assigned users and groups:                             │
  │  ┌─────────────────────────────────────────────────┐    │
  │  │  Group: redis-admins                            │    │
  │  │  ├─ alice@company.io   ← can log in via IC ✓   │    │
  │  │  └─ bob@company.io     ← can log in via IC ✓   │    │
  │  └─────────────────────────────────────────────────┘    │
  │                                                         │
  │  NOT assigned:                                          │
  │  ┌─────────────────────────────────────────────────┐    │
  │  │  Group: redis-readonly                          │    │
  │  │  └─ carol@company.io   ← blocked at IC ✗       │    │
  │  └─────────────────────────────────────────────────┘    │
  │                                                         │
  │  Enforcement: Identity Center checks this list          │
  │  before issuing any SAML assertion.                     │
  │  Cognito is not involved in this decision.              │
  └─────────────────────────────────────────────────────────┘
```

To grant a new engineer access to Redis Insight, add them (or their group) to
the Identity Center application assignment. To remove access, remove the assignment.
Changes take effect on the next login — no Terraform, no Cognito changes needed.

---

## Setting the Application Assignment

In the Management Account:

```
Identity Center → Applications → Redis Insight Prod1
→ Assign users and groups

Add:  redis-admins  (group)
```

Remove any other groups or users. Only `redis-admins` members can now use
the Identity Center login path.

---

## Summary of Who Can Access What

```
  ┌───────────────────────┬──────────────────┬────────────────────────────┐
  │  User                 │  Login method    │  Can access Redis Insight? │
  ├───────────────────────┼──────────────────┼────────────────────────────┤
  │  alice (redis-admins) │  Identity Center │  Yes — assigned to app ✓  │
  │  bob   (redis-admins) │  Identity Center │  Yes — assigned to app ✓  │
  │  carol (redis-readonly│  Identity Center │  No  — not assigned ✗     │
  │  contractor           │  Local Cognito   │  Yes — always allowed ✓   │
  └───────────────────────┴──────────────────┴────────────────────────────┘

  The gate for Identity Center users = Identity Center application assignment.
  The gate for local Cognito users   = none (always allowed by design).
```

---

## How Cognito Decides Which Path to Use

Cognito does **not** automatically check local accounts first and then fall back to
Identity Center, or vice versa. The user explicitly chooses their path by which
button they click on the login page.

```
  Cognito Hosted Login Page
  ┌──────────────────────────────────────────────────────────┐
  │                                                          │
  │  Email _______________  Password _______________         │
  │  [              Log In              ]  ◄── local path   │
  │                                                          │
  │  ──────────────────── or ────────────────────────        │
  │                                                          │
  │  [ Login with Identity Center ]  ◄── federated path     │
  │                                                          │
  └──────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
  Cognito local user pool        Identity Center SAML
  (checks password only)         (checks IC assignment only)
  Never touches IC               Never touches local pool
```

The two paths are completely independent. Cognito does not cross-check them.

---

## What Happens When the Same Email Exists on Both

This is the most common confusion. If alice@company.io has both a local Cognito
account AND an Identity Center account, Cognito stores them as **two separate records**:

```
  Cognito User Pool
  ┌────────────────────────────────────────────────────────────────────┐
  │                                                                    │
  │  Record 1 — LOCAL                                                  │
  │  ┌──────────────────────────────────────────────────────────────┐  │
  │  │  username:  alice@company.io                                 │  │
  │  │  email:     alice@company.io                                 │  │
  │  │  type:      local                                            │  │
  │  │  password:  (hashed)                                         │  │
  │  └──────────────────────────────────────────────────────────────┘  │
  │                                                                    │
  │  Record 2 — FEDERATED (created on first IC login)                  │
  │  ┌──────────────────────────────────────────────────────────────┐  │
  │  │  username:  IdentityCenter_a3f7c2b1-...  ← Cognito generates │  │
  │  │  email:     alice@company.io             ← same email        │  │
  │  │  type:      federated / SAML             ← different type    │  │
  │  │  password:  none                                             │  │
  │  └──────────────────────────────────────────────────────────────┘  │
  │                                                                    │
  │  These are TWO separate identities in Cognito's eyes.             │
  │  Same email, different records, different sessions.               │
  └────────────────────────────────────────────────────────────────────┘
```

**What this means in practice:**

- Alice uses the email+password form → gets a local session (Record 1)
- Alice uses the IC button → gets a federated session (Record 2)
- Both sessions are valid at the same time in different browser tabs
- Redis Insight cannot tell them apart — both have the same email attribute

This is usually fine for Redis Insight access since both paths allow access.
The only concern is if you care about a single unified profile per person.

---

## Account Linking (Optional — Single Identity Per Person)

If you want both paths to resolve to the **same Cognito identity**, you use
Cognito's account linking feature. This merges the federated record into the
local record so alice always has one profile regardless of how she logged in.

```
  Without linking:                With linking:
  ┌────────────────────┐          ┌────────────────────────────────────┐
  │  local record      │          │  local record (primary)            │
  │  alice@company.io  │          │  alice@company.io                  │
  │                    │          │  linked providers:                 │
  │  federated record  │          │    ├─ local (email+password)       │
  │  IdentityCenter_.. │  ────►   │    └─ IdentityCenter_a3f7c2..     │
  └────────────────────┘          │                                    │
  2 separate records              │  ONE record, two login methods     │
                                  └────────────────────────────────────┘
```

Account linking is done via a **Pre-SignUp Lambda trigger** that fires the first
time a federated user authenticates. The Lambda calls `adminLinkProviderForUser`
to merge the new federated identity into the existing local record.

For Redis Insight access this is optional — both separate records work fine.
Linking is useful if you have per-user preferences or bookmarks stored in the
Cognito profile that you want shared across both login methods.

---

## When Would You Actually Need a Lambda?

Only if you want Cognito to enforce group restrictions on **local users** as well —
i.e., you want all login paths (local AND federated) to require group membership.

For the model described in this document (local users always allowed, IC users
group-restricted), a Lambda is not needed.
