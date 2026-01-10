# ECS Service Blue/Green Deployment Strategy

This document explains **service-level blue/green deployments** on Amazon ECS, why it is necessary in module-constrained Terraform setups, and how traffic switching, rollback, and scaling work safely.

---

## Why Service-Level Blue/Green?

In our setup:

* ECS **task definitions are immutable**
* Terraform **task definition modules live in a separate public repo**
* CI/CD cannot modify lifecycle rules dynamically

Because of this:

> We **cannot safely change CPU, memory, ports, or container structure** in-place.

Instead of fighting this limitation, we **promote services as the unit of deployment**, not task definitions.

---

## Core Idea

* Keep task definitions immutable
* Create **a new ECS service** for infra-level changes
* Attach the new service to the ALB
* Shift traffic
* Keep old service for rollback

This is equivalent to **AWS CodeDeploy Blue/Green**, implemented manually.

---

## Architecture Diagram

```
                   ┌─────────────────────┐
                   │      ALB Listener    │
                   │  (HTTPS :443 / HTTP)│
                   └─────────┬───────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
        ┌───────▼────────┐       ┌────────▼────────┐
        │ Target Group A  │       │ Target Group B  │
        │ (BLUE)          │       │ (GREEN)         │
        └───────┬────────┘       └────────┬────────┘
                │                         │
        ┌───────▼────────┐       ┌────────▼────────┐
        │ ECS Service     │       │ ECS Service     │
        │ node-app-blue   │       │ node-app-green  │
        └───────┬────────┘       └────────┬────────┘
                │                         │
        ┌───────▼────────┐       ┌────────▼────────┐
        │ Task Def v1    │       │ Task Def v2     │
        │ CPU=256        │       │ CPU=512         │
        │ MEM=1GB        │       │ MEM=2GB         │
        └────────────────┘       └─────────────────┘
```

---

## Deployment Flow (Step-by-Step)

### 1️⃣ Existing State

* `node-app-blue` service is live
* ALB routes 100% traffic to **Target Group A**

---

### 2️⃣ Create New Service (Green)

* Deploy new ECS service:

    * New task definition
    * Updated CPU / memory / config
* Attach to **Target Group B**
* No traffic yet

---

### 3️⃣ Validate Green

* Wait for:

    * ECS service stability
    * Target group health checks
    * Application metrics

---

### 4️⃣ Shift Traffic

Options:

**Option A: Weighted Routing**

* 90% → Blue
* 10% → Green
* Gradually increase

**Option B: Hard Switch**

* Detach Blue target group
* Attach Green target group

---

### 5️⃣ Post-Cutover

* Keep Blue service running (no traffic)
* Monitor for errors
* Rollback instantly if needed

---

### 6️⃣ Cleanup

* Delete Blue service only after confidence
* Or keep for emergency rollback window

---

## Rollback Strategy (Instant)

If Green fails:

```
ALB → reattach Target Group A (Blue)
```

No redeploy
No Terraform apply
No image rollback

---

## Why Not Task Definition Versioning?

| Problem                    | Result                   |
| -------------------------- | ------------------------ |
| Task definitions immutable | Cannot update CPU/memory |
| Module lifecycle locked    | CI/CD cannot override    |
| Terraform drift risk       | High                     |

**Service replacement avoids all of this.**

---

## Cost Considerations

Temporary increase:

* 2 ECS services
* Extra running tasks

Tradeoff:

* Zero downtime
* Safe rollback
* Predictable behavior

This is **cheaper than outages**.

---

## When to Use This Pattern

Use service-level blue/green when:

* Changing CPU or memory
* Changing container structure
* Changing ports or health checks
* Task definition module is immutable
* Rollback safety is critical

---

## Golden Rules

* ❌ Do not mutate running services for infra changes
* ❌ Do not fight Terraform lifecycle constraints
* ✅ Promote services, not tasks
* ✅ Treat services as disposable
* ✅ Keep rollback simple

---

## Summary

> **Services are the deployment unit.**
> **Task definitions are immutable artifacts.**

This approach is:

* AWS-aligned
* Terraform-safe
* CI/CD-friendly
* Production-proven

---

*This document should be kept alongside deployment and infrastructure documentation.*
