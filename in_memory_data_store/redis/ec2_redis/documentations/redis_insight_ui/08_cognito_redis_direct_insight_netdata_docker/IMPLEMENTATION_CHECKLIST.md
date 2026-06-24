# Implementation Checklist

Work through this top to bottom. Each phase depends on the previous one.
If you get stuck on a step, ask for help referencing the step number.

IaC lives in: `terraform-apps/cerpac-infrastructure/staging-infrastructure/`

---

## Current State

```
[x] Management Account — Identity Center enabled
[x] Management Account — Users created
[x] Management Account — Redis-Admin group created with 1 user
[ ] Everything else below
```

---

## Phase 1 — Identity Center SAML Application (Management Account, Manual)

These steps are done in the AWS Console of the **management account**.
You cannot do them from the staging account.

- [ ] **1.1** — Create a custom SAML 2.0 application in Identity Center

  ```
  Identity Center → Applications → Add application
  → I have an application I want to set up (custom SAML 2.0)

  Application name:   Redis Insight Staging
  Description:        Protects Redis Insight on the staging account
  ```

- [ ] **1.2** — Leave the ACS URL and Audience URI blank for now
  
  You will come back to fill these in after Cognito is created (Phase 2).
  Save the application anyway — you need the metadata first.

- [ ] **1.3** — Download the Identity Center SAML metadata

  ```
  Identity Center → Applications → Redis Insight Staging
  → Actions → View metadata

  Copy the metadata URL — it looks like:
  https://portal.sso.<region>.amazonaws.com/saml/metadata/<random-id>
  ```

  Save this URL. It goes into Terraform in Phase 2.

- [ ] **1.4** — Configure attribute mappings on the application

  ```
  Identity Center → Applications → Redis Insight Staging
  → Edit attribute mappings → Add mapping

  App attribute   Maps to              Format
  ────────────    ─────────────────    ──────────────
  Subject         ${user:email}        emailAddress
  email           ${user:email}        basic
  ```

- [ ] **1.5** — Assign the Redis-Admin group to the application

  ```
  Identity Center → Applications → Redis Insight Staging
  → Assign users and groups
  → Add group: Redis-Admin
  ```

  Only users in Redis-Admin can now authenticate via the IC login button.

---

## Phase 2 — Cognito User Pool (Staging Account, Terraform)

Create a new file:
`staging-infrastructure/central_redis_cognito.tf`

Paste this and fill in the metadata URL from step 1.3:

```hcl
################################################################################
# Cognito — Redis Insight Auth
#
# Protects Redis Insight and Netdata behind ALB authenticate-cognito action.
# Users log in via Identity Center (SAML federation) or as local Cognito users.
################################################################################

resource "aws_cognito_user_pool" "redis_insight" {
  name = "${var.env}-redis-insight-user-pool"

  # Users can only sign in with email — no self-registration
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true  # no self sign-up
  }

  tags = {
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "redis-insight-auth"
  }
}

# App client — used by the ALB to perform the Cognito token exchange
resource "aws_cognito_user_pool_client" "redis_insight_alb" {
  name         = "${var.env}-redis-insight-alb-client"
  user_pool_id = aws_cognito_user_pool.redis_insight.id

  generate_secret = true  # ALB requires a client secret

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true

  # Populated after ALB is known — Cognito validates callbacks against this list
  callback_urls = [
    "https://${local.redis_insight_full_domain}/oauth2/idpresponse",
    "https://${local.netdata_full_domain}/oauth2/idpresponse",
  ]

  logout_urls = [
    "https://${local.redis_insight_full_domain}",
    "https://${local.netdata_full_domain}",
  ]

  supported_identity_providers = [
    "COGNITO",
    aws_cognito_identity_provider.identity_center.provider_name,
  ]

  depends_on = [aws_cognito_identity_provider.identity_center]
}

# Cognito domain — used by the ALB to redirect users to the Cognito hosted login page
resource "aws_cognito_user_pool_domain" "redis_insight" {
  domain       = "${var.env}-${var.project_id}-redis-insight"
  user_pool_id = aws_cognito_user_pool.redis_insight.id
}

# SAML Identity Provider — wires Identity Center into Cognito
resource "aws_cognito_identity_provider" "identity_center" {
  user_pool_id  = aws_cognito_user_pool.redis_insight.id
  provider_name = "IdentityCenter"
  provider_type = "SAML"

  provider_details = {
    # Paste the metadata URL from Identity Center step 1.3
    MetadataURL = "https://portal.sso.<region>.amazonaws.com/saml/metadata/<replace-me>"
    IDPSignout  = "false"
  }

  attribute_mapping = {
    email = "email"
  }
}

output "redis_insight_cognito" {
  description = "Cognito details — needed to update Identity Center app in Phase 3"
  value = {
    user_pool_id     = aws_cognito_user_pool.redis_insight.id
    user_pool_arn    = aws_cognito_user_pool.redis_insight.arn
    client_id        = aws_cognito_user_pool_client.redis_insight_alb.id
    domain           = aws_cognito_user_pool_domain.redis_insight.domain
    cognito_domain   = "${aws_cognito_user_pool_domain.redis_insight.domain}.auth.${var.network_config.region}.amazoncognito.com"
    acs_url          = "https://${aws_cognito_user_pool_domain.redis_insight.domain}.auth.${var.network_config.region}.amazoncognito.com/saml2/idpresponse"
    audience_uri     = "urn:amazon:cognito:sp:${aws_cognito_user_pool.redis_insight.id}"
  }
}
```

- [ ] **2.1** — Replace `<region>` and `<replace-me>` in the metadata URL with the value from step 1.3

- [ ] **2.2** — Run plan and apply

  ```bash
  cd staging-infrastructure
  terraform plan -target=aws_cognito_user_pool.redis_insight \
                 -target=aws_cognito_user_pool_client.redis_insight_alb \
                 -target=aws_cognito_user_pool_domain.redis_insight \
                 -target=aws_cognito_identity_provider.identity_center
  terraform apply -target=aws_cognito_user_pool.redis_insight \
                  -target=aws_cognito_user_pool_client.redis_insight_alb \
                  -target=aws_cognito_user_pool_domain.redis_insight \
                  -target=aws_cognito_identity_provider.identity_center
  ```

- [ ] **2.3** — Note the outputs

  ```bash
  terraform output redis_insight_cognito
  ```

  You need the `acs_url` and `audience_uri` values for the next phase.

---

## Phase 3 — Update Identity Center App (Management Account, Manual)

Now that Cognito exists, go back and fill in the blank fields from step 1.2.

- [ ] **3.1** — Update the SAML application in Identity Center

  ```
  Identity Center → Applications → Redis Insight Staging
  → Edit application

  ACS URL (Assertion Consumer Service):
    value of acs_url from terraform output
    e.g. https://staging-cerpac-redis-insight.auth.eu-west-2.amazoncognito.com/saml2/idpresponse

  Application SAML audience (SP entity ID):
    value of audience_uri from terraform output
    e.g. urn:amazon:cognito:sp:eu-west-2_XXXXXXXXX
  ```

  Save the application.

- [ ] **3.2** — Verify the attribute mappings are still there (from step 1.4)

---

## Phase 4 — Update ALB Listener Rules (Staging Account, Terraform)

Update the two HTTPS rules in `staging-infrastructure/central_redis_arm_db.tf`
to add `authenticate-cognito` before the `forward` action.

- [ ] **4.1** — Replace the redis-insight HTTPS rule

  Find `aws_lb_listener_rule.redis_insight_tg_https_tg_rule` and replace its `action` block:

  ```hcl
  resource "aws_lb_listener_rule" "redis_insight_tg_https_tg_rule" {
    listener_arn = aws_lb_listener.cerpac_alb_https_listener.arn
    priority     = 83

    condition {
      host_header {
        values = [local.redis_insight_full_domain]
      }
    }

    action {
      type  = "authenticate-cognito"
      order = 1
      authenticate_cognito {
        user_pool_arn       = aws_cognito_user_pool.redis_insight.arn
        user_pool_client_id = aws_cognito_user_pool_client.redis_insight_alb.id
        user_pool_domain    = aws_cognito_user_pool_domain.redis_insight.domain
        on_unauthenticated_request = "authenticate"
        session_cookie_name        = "AWSELBAuthSession"
        session_timeout            = 86400  # 24 hours
      }
    }

    action {
      type             = "forward"
      order            = 2
      target_group_arn = aws_lb_target_group.redis_insight_tg.arn
    }
  }
  ```

- [ ] **4.2** — Replace the netdata HTTPS rule the same way

  Find `aws_lb_listener_rule.netdata_tg_https_tg_rule` and replace its `action` block:

  ```hcl
  resource "aws_lb_listener_rule" "netdata_tg_https_tg_rule" {
    listener_arn = aws_lb_listener.cerpac_alb_https_listener.arn
    priority     = 84

    condition {
      host_header {
        values = [local.netdata_full_domain]
      }
    }

    action {
      type  = "authenticate-cognito"
      order = 1
      authenticate_cognito {
        user_pool_arn       = aws_cognito_user_pool.redis_insight.arn
        user_pool_client_id = aws_cognito_user_pool_client.redis_insight_alb.id
        user_pool_domain    = aws_cognito_user_pool_domain.redis_insight.domain
        on_unauthenticated_request = "authenticate"
        session_cookie_name        = "AWSELBAuthSession"
        session_timeout            = 86400
      }
    }

    action {
      type             = "forward"
      order            = 2
      target_group_arn = aws_lb_target_group.netdata_tg.arn
    }
  }
  ```

- [ ] **4.3** — Apply

  ```bash
  terraform plan
  terraform apply
  ```

---

## Phase 5 — Test

- [ ] **5.1** — Open `https://redis-insight.<your-domain>` in a browser

  You should be redirected to the Cognito hosted login page which shows:
  - An email + password form (local Cognito users)
  - A button "Sign in with IdentityCenter"

- [ ] **5.2** — Click "Sign in with IdentityCenter"

  You should be redirected to the Identity Center login page.
  Log in with the user who is in the Redis-Admin group.
  After login you should land on Redis Insight.

- [ ] **5.3** — Test with a user NOT in Redis-Admin

  Log in with an Identity Center user who is not assigned to the
  "Redis Insight Staging" application.
  You should see Identity Center's "You don't have permission" error.
  Redis Insight should never load.

- [ ] **5.4** — Test Netdata at `https://netdata.<your-domain>`

  Should require the same Cognito login (shared user pool, same session cookie).
  After logging into Redis Insight first, Netdata should open without a second login.

---

## Phase 6 — Optional: Add Local Cognito Users

Local Cognito users bypass Identity Center and can always log in.
Useful for contractors or service accounts.

```bash
aws cognito-idp admin-create-user \
  --user-pool-id <user-pool-id-from-output> \
  --username contractor@example.com \
  --temporary-password 'TempPass123!' \
  --user-attributes Name=email,Value=contractor@example.com \
                    Name=email_verified,Value=true \
  --region eu-west-2
```

---

## Dependency Map

```
  Phase 1 (IC app created, metadata URL obtained)
      │
      ▼
  Phase 2 (Cognito created — acs_url + audience_uri from output)
      │
      ▼
  Phase 3 (IC app updated with acs_url + audience_uri)
      │
      ▼
  Phase 4 (ALB rules updated with authenticate-cognito)
      │
      ▼
  Phase 5 (Test)
```
