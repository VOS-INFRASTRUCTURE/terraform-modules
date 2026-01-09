# SSM Parameter Store – Application Configuration Guide

This document explains **what AWS Systems Manager Parameter Store (SSM Parameter Store) is**, how it differs from **AWS Secrets Manager**, and **when and how to use it** in ECS-based applications.

It complements `SecretManager.md` and focuses on **application configuration**, not credentials.

---

## 🎯 Purpose of SSM Parameter Store

SSM Parameter Store is a **managed key–value store** designed for:

* application configuration
* feature flags
* environment-specific values
* operational toggles
* values that may change frequently

Think of it as:

> **Environment variables, but centrally managed and IAM-controlled**

---

## 🔍 SSM Parameter Store vs Secrets Manager

| Feature            | SSM Parameter Store | Secrets Manager       |
| ------------------ | ------------------- | --------------------- |
| Primary use        | App configuration   | Credentials & secrets |
| Encryption         | Optional (KMS)      | Always encrypted      |
| Rotation           | ❌ No                | ✅ Built-in            |
| Cost               | Mostly free         | Paid                  |
| Max value size     | 4 KB                | 64 KB                 |
| Data model         | Key–value           | JSON / string secret  |
| ECS env injection  | ✅                   | ✅                     |
| Runtime SDK access | ✅                   | ✅                     |

---

## 💰 Cost Implications: SSM Parameter Store vs Secrets Manager

### SSM Parameter Store Pricing

| Tier | Storage | API Calls | Monthly Cost (Example) |
|------|---------|-----------|------------------------|
| **Standard Parameters** | **FREE** (up to 10,000 params) | **FREE** (unlimited standard throughput) | **$0** |
| **Advanced Parameters** | $0.05 per parameter/month | $0.05 per 10,000 API calls | Depends on usage |

#### Standard Parameters (FREE)
- ✅ **No charge** for storage
- ✅ **No charge** for API calls (standard throughput: 1,000 TPS)
- ✅ Max 10,000 parameters per account/region
- ✅ Max value size: **4 KB**
- ✅ No parameter policies (expiration, notifications)

#### Advanced Parameters (PAID)
- 💵 **$0.05/parameter/month** for storage
- 💵 **$0.05 per 10,000 API calls** (higher throughput: 10,000 TPS)
- ✅ Max value size: **8 KB**
- ✅ Support for parameter policies
- ✅ More than 10,000 parameters allowed

**Example: 100 Standard Parameters (Config Values)**
```
Storage:  $0.00/month (FREE)
API calls: $0.00/month (FREE for standard throughput)
───────────────────────
TOTAL:    $0.00/month ✅
```

**Example: 100 Advanced Parameters**
```
Storage:  100 × $0.05 = $5.00/month
API calls: 1,000,000 calls/month ÷ 10,000 × $0.05 = $5.00/month
───────────────────────────────────────────────────────────────
TOTAL:    $10.00/month
```

---

### Secrets Manager Pricing

| Component | Cost | Notes |
|-----------|------|-------|
| **Secret Storage** | **$0.40 per secret/month** | Charged per secret, not per value |
| **API Calls** | **$0.05 per 10,000 API calls** | Same as SSM Advanced tier |
| **Rotation** | Included | No extra charge for using rotation |

**Example: 10 Secrets (DB Credentials, API Keys)**
```
Storage:  10 × $0.40 = $4.00/month
API calls: 100,000 calls/month ÷ 10,000 × $0.05 = $0.50/month
────────────────────────────────────────────────────────────
TOTAL:    $4.50/month 💰
```

**Example: 100 Secrets**
```
Storage:  100 × $0.40 = $40.00/month
API calls: 1,000,000 calls/month ÷ 10,000 × $0.05 = $5.00/month
──────────────────────────────────────────────────────────────
TOTAL:    $45.00/month 💰💰
```

---

### 📊 Direct Cost Comparison

**Scenario: 50 configuration values + 10 secrets**

| Approach | Storage Cost | API Cost (100K calls/mo) | Total/Month |
|----------|--------------|--------------------------|-------------|
| **All in Secrets Manager** | 60 × $0.40 = **$24.00** | $0.50 | **$24.50** |
| **Config in SSM (Standard) + Secrets in SM** | 10 × $0.40 = **$4.00** | $0.50 | **$4.50** |
| **Savings with hybrid approach** | | | **$20.00/month** ✅ |

**Annual Savings: $240/year** by using SSM Parameter Store for non-sensitive config!

---

### 💡 Cost Optimization Recommendations

#### ✅ Use SSM Parameter Store (FREE) for:
- Feature flags (`/prod/app/enable_feature_x`)
- Log levels (`/prod/app/log_level`)
- Timeouts and limits (`/prod/app/request_timeout`)
- API base URLs (`/prod/app/external_api_url`)
- Non-sensitive configuration (`/prod/app/max_upload_size`)
- Environment-specific settings

**Cost Impact:** $0/month for up to 10,000 parameters ✅

#### ✅ Use Secrets Manager (PAID) for:
- Database credentials
- API keys and tokens
- JWT signing secrets
- Encryption keys
- OAuth client secrets
- Third-party service credentials

**Cost Impact:** $0.40/secret/month + API calls

---

### 🎯 Real-World Cost Example

**CERPAC Application Infrastructure:**

```
SSM Parameter Store (Standard Tier):
  - 20 feature flags                     = $0.00
  - 15 service URLs                      = $0.00
  - 10 timeout configurations            = $0.00
  - 5 log level settings                 = $0.00
  ─────────────────────────────────────────────
  Total: 50 parameters                   = $0.00/month ✅

Secrets Manager:
  - 2 database credentials               = $0.80
  - 3 API keys (Stripe, AWS, etc.)       = $1.20
  - 2 JWT secrets                        = $0.80
  - 1 SSL certificate password           = $0.40
  ─────────────────────────────────────────────
  Total: 8 secrets                       = $3.20/month

API Calls (combined):
  - 500,000 calls/month                  = $2.50/month
  ─────────────────────────────────────────────

TOTAL MONTHLY COST:                      = $5.70/month
ANNUAL COST:                             = $68.40/year
```

**If everything was in Secrets Manager:**
```
58 secrets × $0.40                       = $23.20/month
API calls                                = $2.50/month
─────────────────────────────────────────────
TOTAL:                                   = $25.70/month
ANNUAL COST:                             = $308.40/year

SAVINGS BY USING SSM:                    = $240/year ✅
```

---

### ⚠️ Hidden Costs to Consider

#### KMS Encryption (Both Services)
If using **SecureString** (SSM) or **custom KMS keys** (Secrets Manager):
- **KMS key:** $1/month per key
- **API requests:** $0.03 per 10,000 requests

**Note:** Secrets Manager uses AWS-managed keys by default (no extra KMS cost).

#### CloudWatch Logs (If Enabled)
- Log ingestion: $0.50/GB
- Log storage: $0.03/GB/month

#### Data Transfer
- API calls within same region: FREE
- Cross-region calls: Standard data transfer rates apply

---

### 🧮 Cost Calculator

**Quick formula to estimate your costs:**

```
SSM Parameter Store (Standard):
  Monthly Cost = $0 (if < 10,000 params with standard throughput)

SSM Parameter Store (Advanced):
  Monthly Cost = (Number of Advanced Params × $0.05) + (API Calls ÷ 10,000 × $0.05)

Secrets Manager:
  Monthly Cost = (Number of Secrets × $0.40) + (API Calls ÷ 10,000 × $0.05)

Hybrid Approach:
  Monthly Cost = (SSM Cost) + (Secrets Manager Cost)
```

---

### 📈 When Advanced SSM Parameters Make Sense

Use **Advanced Parameters** when you need:
- Parameter size > 4 KB (up to 8 KB)
- More than 10,000 parameters
- Parameter policies (expiration notifications)
- Higher throughput (10,000 TPS vs 1,000 TPS)

**Cost breakeven:** If you're paying for Secrets Manager anyway, stick with Standard SSM for config (free).

---

## 🧭 When to Use SSM Parameter Store

Use **SSM Parameter Store** for:

* feature flags (enable/disable features)
* log levels
* timeout values
* service URLs
* non-sensitive config
* values ops teams may change often

Example parameter names:

```
/prod/app/log_level
/prod/app/enable_beta
/prod/app/payment_timeout
/prod/app/api_base_url
```

---

## 🔐 Parameter Types

| Type           | Description           |
| -------------- | --------------------- |
| `String`       | Plain text value      |
| `StringList`   | Comma-separated list  |
| `SecureString` | Encrypted value (KMS) |

> ⚠️ Even `SecureString` should not replace Secrets Manager for critical credentials.

---

## 🔁 Access Patterns (Same as Secrets Manager)

SSM Parameter Store supports **both ECS access models**.

---

## ✅ Option 1 — Inject Parameters at Container Startup

### How it Works

1. Terraform creates the parameter
2. ECS task definition references the parameter ARN
3. ECS injects the value as an environment variable at startup

---

### Terraform Example

```hcl
secrets = [
  {
    name      = "LOG_LEVEL"
    valueFrom = aws_ssm_parameter.log_level.arn
  }
]
```

---

### Behavior

* Parameter is read **once at startup**
* Changes in the console do **not** affect running tasks
* Restart or redeploy is required to apply updates

---

### IAM Permissions

**Task Execution Role**:

```json
ssm:GetParameters
```

---

## ✅ Option 2 — Fetch Parameters at Runtime via SDK

### How it Works

* ECS assigns a **Task Role** to the container
* AWS SDK automatically obtains temporary credentials
* App fetches parameters at runtime

---

### Node.js Example

```ts
import { SSMClient, GetParameterCommand } from "@aws-sdk/client-ssm";

const ssm = new SSMClient({});

const param = await ssm.send(
  new GetParameterCommand({
    Name: "/prod/app/log_level",
    WithDecryption: true
  })
);

const logLevel = param.Parameter!.Value;
```

---

### Runtime Behavior

* Parameters can be updated without restarting containers
* App should cache values in memory
* Refresh periodically to reduce API calls

---

### IAM Permissions

**Task Role**:

```json
ssm:GetParameter
```

---

## 🧠 Caching Strategy (Best Practice)

* Fetch parameters once at startup
* Cache in memory
* Refresh on interval (e.g. every 5 minutes)
* Never fetch on every request

---

## 🧱 Terraform & Parameter Values (Source of Truth Rules)

### The Rule

> **Terraform should manage parameter infrastructure, not long-term values.**

If Terraform manages the value and it is later edited in the UI:

* Terraform will overwrite it on the next `apply`

---

### ✅ Recommended Pattern

Terraform creates the parameter:

```hcl
resource "aws_ssm_parameter" "log_level" {
  name = "/prod/app/log_level"
  type = "String"
}
```

Values are then:

* set via AWS Console or CLI
* changed operationally
* never overwritten by Terraform

---

### ❌ Anti-Patterns

* Managing frequently changing values in Terraform
* Using SSM for passwords or API keys
* Fetching parameters per request

---

## 🏆 Recommended Combined Strategy

| Data Type          | Service         | Access Pattern    |
| ------------------ | --------------- | ----------------- |
| DB credentials     | Secrets Manager | Inject at startup |
| JWT signing secret | Secrets Manager | Inject at startup |
| Feature flags      | SSM             | Runtime SDK fetch |
| Log level          | SSM             | Runtime SDK fetch |
| API base URLs      | SSM             | Inject at startup |
| Timeouts           | SSM             | Inject at startup |

---

## 🧭 Final Mental Model

* **Secrets Manager** → things that must never leak
* **SSM Parameter Store** → things operators may change

Both services:

* integrate with ECS
* use IAM for access
* support injection or runtime fetch

---

This document should be used as the **reference guide for application configuration management** across all ECS environments.
