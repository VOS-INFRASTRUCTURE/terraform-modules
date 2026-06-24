# Session and Cookie TTL

There are three independent timers running when a user is logged in.
They are set in different places and expire independently.

---

## The Three Timers

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Timer 1 — Identity Center Session                                            │
│                                                                              │
│  Set by:   Identity Center after the user logs in via the IC portal         │
│  Stored:   IC portal cookie in the browser                                  │
│  Default:  1 hour (configured in IC app: Session duration)                  │
│  Controls: How long the user stays logged into the IC portal itself          │
│  Location: Identity Center → Applications → Redis Insight → Session duration │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ Timer 2 — Cognito User Pool Session                                          │
│                                                                              │
│  Set by:   Cognito hosted UI after a successful SAML assertion from IC      │
│  Stored:   Cookie on .auth.eu-west-2.amazoncognito.com domain               │
│  Default:  1 day (User Pool → App integration → Refresh token expiry)       │
│  Controls: How long Cognito can silently re-issue tokens without prompting  │
│  Location: Cognito User Pool → App clients → Token expiration               │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ Timer 3 — ALB Session Cookie                                                 │
│                                                                              │
│  Set by:   ALB after it exchanges the Cognito auth code for tokens          │
│  Stored:   Cookie on redis-insight.x.com / netdata.x.com (per domain)      │
│  Value:    86400 seconds = 24 hours (set in session_timeout in Terraform)   │
│  Controls: How long the ALB accepts requests without re-checking Cognito    │
│  Location: aws_lb_listener_rule → authenticate_cognito → session_timeout    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## What Happens When Each One Expires

### Timer 3 expires first (ALB cookie — 24h)

This is the most common expiry in normal use.

```
Day 0, 09:00 — user logs in
  ALB cookie set, expires: Day 1, 09:00

Day 1, 09:01 — user visits redis-insight.x.com
  │
  ▼
ALB checks cookie → EXPIRED
  │
  ▼
ALB redirects browser to Cognito login page
  │
  ▼
Cognito checks its own session cookie (.amazoncognito.com)
  │
  ├── Cognito session still valid (Timer 2 = 1 day, not yet expired)
  │     │
  │     ▼
  │   Cognito silently issues new tokens — NO login prompt shown
  │   Browser is redirected back to redis-insight.x.com
  │   ALB sets a new cookie, expires: Day 2, 09:01
  │   User sees Redis Insight load normally
  │
  └── Cognito session also expired (Timer 2)
        │
        ▼
      Cognito shows the login page
      User must log in again
```

**Visible to user:** nothing — the redirect cycle happens in under a second.
**If Timer 2 is still alive:** the re-login is completely silent.

---

### Timer 2 expires (Cognito session — 1 day)

```
Day 0, 09:00 — user logs in via Identity Center
  Cognito session set, expires: Day 1, 09:00
  ALB cookie set,     expires: Day 1, 09:00  (same duration in this config)

Day 1, 09:01 — ALB cookie expires, ALB redirects to Cognito
  │
  ▼
Cognito session also expired
  │
  ▼
Cognito shows hosted login page with options:
  [ email + password field ]
  [ Sign in with IdentityCenter ]
  │
  ▼
User clicks IdentityCenter
  │
  ▼
Browser goes to Identity Center login page
  │
  ├── IC session (Timer 1) still valid → silent redirect back, no prompt
  │
  └── IC session also expired → user must enter their IC credentials
```

---

### Timer 1 expires (Identity Center session — 1 hour)

IC session is the shortest by default. It only matters when the full chain
needs to re-authenticate (Timer 2 and Timer 3 both expired, or user
explicitly logs out).

```
During a fresh login flow:
  Browser → Cognito → Identity Center
                          │
                          ├── IC session valid (< 1h since last IC login)
                          │     → silent redirect, no credentials prompt
                          │
                          └── IC session expired
                                → user sees IC login screen
                                → must enter email + password (or MFA)
                                → IC session resets to 1 hour
```

IC session expiry does NOT affect an already-authenticated ALB session.
If the ALB cookie (Timer 3) is valid, the request never reaches Cognito or IC.

---

## Timeline Example (Default Values)

```
Time    Event
──────  ──────────────────────────────────────────────────────────────────
00:00   User logs in via IC → all three timers start
        Timer 1 (IC)      → expires 01:00
        Timer 2 (Cognito) → expires 24:00 (next day)
        Timer 3 (ALB)     → expires 24:00 (next day)

01:00   IC session expires
        No effect — ALB cookie is still valid, request never touches IC

24:01   ALB cookie expires on redis-insight.x.com
        ALB redirects to Cognito
        Cognito session just expired too (same 24h)
        Cognito shows login page → user clicks IdentityCenter
        IC session long expired → user must enter IC credentials
        Full login cycle: ~5 seconds visible to user

(next day)
24:01   New ALB cookie set, expires: 48:00
        New Cognito session set, expires: 48:00
        New IC session set, expires: 25:01
```

---

## Where to Change Each Timer

| Timer | Where to change | Field |
|-------|----------------|-------|
| IC session (1h) | IC console → Applications → Redis Insight Staging → Edit | Session duration |
| Cognito refresh token (1d) | Cognito → User Pool → App clients → redis_management_alb → Edit | Refresh token expiration |
| ALB session cookie (24h) | `central_redis_arm_db.tf` → `authenticate_cognito` block | `session_timeout` |

---

## Recommended Values for an Internal Admin Tool

```
IC session:       8 hours  (covers a full work day, less churn than 1h)
Cognito session:  7 days   (refresh token — Cognito re-issues access tokens silently)
ALB cookie:       8 hours  (matches IC session — clean daily logout)
```

With these values: user logs in once in the morning, works all day, session
expires overnight. The next morning they do one login — Identity Center prompts
for credentials, the rest is silent redirects.

To apply the ALB change:

```hcl
# central_redis_arm_db.tf
session_timeout = 28800  # 8 hours
```

IC and Cognito token expiry are changed in their respective consoles (not Terraform).
