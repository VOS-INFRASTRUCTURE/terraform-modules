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

## When Would You Actually Need a Lambda?

Only if you want Cognito to enforce group restrictions on **local users** as well —
i.e., you want all login paths (local AND federated) to require group membership.

For the model described in this document (local users always allowed, IC users
group-restricted), a Lambda is not needed.
