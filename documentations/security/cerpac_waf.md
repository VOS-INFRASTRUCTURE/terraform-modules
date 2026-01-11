# CERPAC – AWS WAF Logging & Security Architecture

## Overview

This document describes the **layer‑7 security and logging architecture** implemented for the CERPAC production environment. The design follows **AWS best practices**, emphasizes **defense‑in‑depth**, and is structured to meet **security, audit, and compliance requirements** for government‑grade systems.

The solution protects the application at the edge, records security decisions immutably, and enforces controlled data retention.

---

## High‑Level Request Flow

```
Client Request
     ↓
AWS WAF (ALLOW / BLOCK decision)
     ↓
Application Load Balancer (ALB)
     ↓
Backend Services (EC2)
```

* All inbound HTTP/HTTPS traffic passes through **AWS WAF** before reaching the application.
* Malicious or abusive requests are **blocked at the edge**, before consuming backend resources.

---

## WAF Logging & Audit Flow

```
AWS WAF
     ↓
Kinesis Data Firehose
     ↓
Lambda Log Router
     ├─ BLOCK  → s3://<bucket>/blocked/
     └─ ALLOW  → s3://<bucket>/allowed/
     ↓
Amazon S3 (Lifecycle‑managed storage)
```

### Purpose of Each Component

#### AWS WAF

* Performs **Layer‑7 inspection** of requests.
* Applies managed rule groups (OWASP, SQLi, rate‑limiting, etc.).
* Makes an explicit **ALLOW or BLOCK decision** for every request.

#### Kinesis Data Firehose

* Acts as a **managed log delivery pipeline**.
* Buffers, batches, and reliably delivers WAF logs to S3.
* Eliminates the need for custom ingestion infrastructure.

#### Lambda Log Router

* Executes **asynchronously** during log delivery (not inline with traffic).
* Inspects each WAF log record.
* Routes logs based on decision:

    * `BLOCK` → `blocked/`
    * `ALLOW` → `allowed/`

#### Amazon S3

* Serves as the **immutable audit log store**.
* Enforces **prefix‑based lifecycle policies**.
* Buckets are private, encrypted, and access‑controlled.

---

## Data Retention Strategy

Retention is intentionally differentiated to balance **audit requirements**, **cost control**, and **data minimization** principles.

| Log Category     | S3 Prefix  | Retention Policy | Rationale                                                  |
| ---------------- | ---------- | ---------------- | ---------------------------------------------------------- |
| Blocked Requests | `blocked/` | 90 days          | Security investigations, audit evidence, incident response |
| Allowed Requests | `allowed/` | 7 days           | Short‑term troubleshooting and tuning                      |
| Error / Fallback | `errors/`  | 7 days           | Operational visibility only                                |

Lifecycle expiration is enforced automatically by S3.

---

## Security Design Principles

### 1. Defense in Depth

* Network security (VPC, Security Groups)
* Application edge protection (AWS WAF)
* Rate limiting and abuse prevention
* Backend isolation behind ALB

### 2. Least Privilege

* WAF uses AWS‑managed service roles.
* Firehose IAM role is scoped strictly to required S3 access.
* Lambda execution role is limited to logging only.

### 3. Fail‑Safe Logging

* Firehose error output prefix ensures **no silent data loss**.
* Dynamic partitioning prevents log intermixing.

### 4. Separation of Concerns

* Security enforcement (WAF)
* Log transport (Firehose)
* Classification logic (Lambda)
* Storage and retention (S3)

---

## Compliance & Audit Alignment

This architecture aligns with common regulatory and security frameworks:

### Logging & Monitoring

* All security decisions are logged.
* Logs are immutable once written.
* CloudWatch metrics provide real‑time visibility.

### Data Minimization

* Allowed traffic logs are retained briefly.
* Long‑term storage is limited to security‑relevant events.

### Accountability & Traceability

* Each blocked request is traceable by timestamp, rule ID, and source.
* Logs support forensic investigation and audit review.

### Availability & Resilience

* Fully managed AWS services (WAF, Firehose, S3, Lambda).
* No single point of failure introduced by custom infrastructure.

---

## Why This Design Is Correct

* Uses **AWS‑native, supported integrations** only.
* Avoids custom log ingestion or agent‑based solutions.
* Scales automatically with traffic volume.
* Minimizes operational overhead.
* Provides clear, explainable controls for auditors.

This approach is consistent with architectures used in **regulated, high‑trust environments**, including government and financial systems.

---

## Summary

The CERPAC WAF and logging architecture provides:

* Proactive edge protection
* Deterministic security decisions
* Reliable and auditable logging
* Controlled retention and cost management
* Clear separation of security responsibilities

The implementation demonstrates **due diligence**, **security best practices**, and **compliance readiness**.

---

*Document maintained as part of the CERPAC production infrastructure security baseline.*
