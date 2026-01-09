# Laravel on ECS (Production Guide)

This document consolidates **all best practices, architectural decisions, and operational patterns** for running a **Laravel application on AWS ECS (Fargate)**. It is intended as a long-term reference for current and future engineers.

---

## 1. Core Principle

> **Containers (ECS) are for stateless workloads.**
> **Stateful systems must use managed services.**

Laravel fits ECS very well **as long as it remains stateless**.

---

## 2. What Runs Where

| Component        | Where it Runs          | Why                                |
| ---------------- | ---------------------- | ---------------------------------- |
| Laravel Web App  | ECS Service            | Stateless HTTP processing          |
| Queue Workers    | ECS Service            | Long-running workers, auto-restart |
| Scheduler        | EventBridge → ECS Task | Exactly-once execution             |
| Migrations       | ECS One-off Task       | Controlled, safe execution         |
| Database         | RDS / Aurora           | Persistent state                   |
| Cache / Sessions | ElastiCache (Redis)    | Distributed locking & speed        |
| File Storage     | S3                     | Durable, scalable                  |
| Secrets / Config | SSM / Secrets Manager  | Secure injection                   |

---

```shell
if [ "$CONTAINER_MODE" = "web" ]; then
  php artisan serve
elif [ "$CONTAINER_MODE" = "queue" ]; then
  php artisan queue:work
elif [ "$CONTAINER_MODE" = "schedule" ]; then
  php artisan schedule:run --no-interaction
fi

```

## 3. Laravel Web Application (HTTP)

* Runs as an **ECS Service** behind an ALB
* Multiple tasks for horizontal scaling
* Stateless: no local file storage, no local sessions

**Requirements**:

* `SESSION_DRIVER=redis`
* `CACHE_DRIVER=redis`
* Uploads go to S3

---

## 4. Queue Workers

### Why queues need special handling

Laravel queues are **long-running processes** and must be supervised externally.

### Correct Pattern

* Dedicated ECS Service
* Same Docker image as web app
* Different runtime mode via env variable

```env
CONTAINER_MODE=queue
```

```bash
php artisan queue:work --sleep=3 --tries=3 --timeout=90
```

### Why ECS Services work

* ECS ensures the worker stays alive
* Crashes are auto-restarted
* Horizontal scaling = increase desired count

❌ Do NOT:

* Run queues inside web containers
* Use Supervisor inside containers

---

## 5. Scheduler (Cron Replacement)

### Key Rule

> **Laravel scheduler must run exactly once per minute.**

### Correct Pattern

**EventBridge → ECS RunTask → `schedule:run`**

Flow:

```
EventBridge (every minute)
   ↓
ECS Task (schedule container)
   ↓
php artisan schedule:run
   ↓
Task exits
```

```yaml
⏱ Every 1 minute
   |
   v
EventBridge Rule fires
   |
   v
ECS RunTask
   |
   v
Container starts
   |
   v
php artisan schedule:run
   |
   v
Laravel checks scheduled jobs
   |
   v
Eligible jobs run
   |
   v
Command exits (0)
   |
   v
Task stops

```

* Same Docker image
* Short-lived task
* Fresh container every run

```env
CONTAINER_MODE=schedule
```

```bash
php artisan schedule:run --no-interaction
```

```yaml
EventBridge
   |
   v
ECS Task (schedule:run)
   |
   v
Dispatch jobs to QUEUE
   |
   v
Redis Queue
   |
   v
ECS Queue Workers (N instances)
```

---

## 6. Why NOT Always-Running Schedulers

| Always Running    | EventBridge + Task    |
| ----------------- | --------------------- |
| Consumes CPU 24/7 | Runs only when needed |
| Can drift         | Precise execution     |
| Hard to monitor   | CloudWatch logs       |
| Risk of crashes   | Fresh task every run  |

Even with 1-minute schedules, **short-lived tasks are cheaper and safer**.

---

## 7. Scheduler Scalability Explained

> **Schedulers decide. Workers execute.**

The scheduler **does NOT do heavy work**.

Correct pattern:

```php
$schedule->job(new GenerateReports);
```

Actual work is done by **queue workers**, which scale horizontally.

---

## 8. `onOneServer()` and Locking

### Important Clarification

`onOneServer()` **does use an external lock**.

Under the hood:

* Uses Laravel cache locks
* Requires Redis or Memcached

```php
Cache::lock('framework/schedule-*')->get();
```

### Cache Driver Compatibility

| Cache Driver | Safe?    |
| ------------ | -------- |
| Redis        | ✅ Yes    |
| Memcached    | ✅ Yes    |
| Database     | ⚠️ Risky |
| File / Array | ❌ No     |

**Redis is mandatory in ECS for correctness.**

---

## 9. Avoiding Race Conditions

### What causes race conditions

* Multiple schedulers running
* Multiple containers calling `schedule:run`

### How we avoid it

| Problem                | Solution                |
| ---------------------- | ----------------------- |
| Duplicate schedulers   | Single EventBridge rule |
| Job overlap            | `withoutOverlapping()`  |
| Multi-server execution | `onOneServer()`         |

---

## 10. Migrations

### Correct Pattern

* One-off ECS Task
* Run manually or via CI/CD
* Never on container startup

```bash
php artisan migrate --force
```

Why:

* Prevents race conditions
* Avoids accidental re-runs
* Full control & auditability

---

## 11. Configuration & Secrets

* Use **SSM Parameter Store** or **Secrets Manager**
* Inject at container startup
* Restart tasks to pick up changes

⚠️ Laravel loads config at boot time — runtime changes are ignored.

---

## 12. Cost Considerations

EventBridge + short-lived ECS tasks are **cheaper than always-on containers**.

Example:

* Scheduler task: ~2–10 seconds per run
* Total monthly compute: ~24–240 hours
* Cost: **<$4/month**

Always-running scheduler: ~$10+/month

---

## 13. Golden Rules (Remember These)

* **Web & workers** → ECS Services
* **Scheduled jobs** → EventBridge + ECS Tasks
* **Migrations** → One-off ECS Tasks
* **State** → Managed AWS services

---

## 14. Final Verdict

Laravel runs **extremely well on ECS** when:

* It is stateless
* Redis is used for cache/locks/sessions
* Scheduler is event-driven
* Workers are isolated

This architecture is:

* Cloud-native
* Scalable
* Cost-efficient
* Operationally safe

---

### So what scales, and what doesn’t?

| Component      | Scales?                  |
| -------------- | ------------------------ |
| Scheduler task | ❌ (by design — only one) |
| Queue workers  | ✅ horizontally           |
| Jobs           | ✅                        |
| Web services   | ✅                        |



# Laravel Logging for ECS Tasks

---

## Objective

Ensure Laravel logs are captured efficiently in an **AWS ECS container environment**, accessible via **CloudWatch** or container logs.

---

## 1️⃣ Logging Channel Setup

* **Default Laravel Logging:** Configured in `config/logging.php`
* **Recommended for ECS:**

```php
'stack' => [
    'driver' => 'stack',
    'channels' => ['single', 'stderr'],
    'ignore_exceptions' => false,
],
'stderr' => [
    'driver' => 'monolog',
    'handler' => StreamHandler::class,
    'with' => [
        'stream' => 'php://stderr',
    ],
],
```

* **Reason:** `php://stderr` outputs logs to container standard error, automatically captured by ECS.

---

## 2️⃣ Log Levels

* Use standard PSR-3 levels (`debug`, `info`, `warning`, `error`, `critical`).
* Example:

```php
Log::info('Task started: Processing user data.');
Log::error('Failed to process order ID 123.');
```

---

## 3️⃣ ECS Task Considerations

* **No persistent filesystem reliance:** Avoid storing logs in `storage/logs` unless using EFS/S3.
* **CloudWatch Integration:**

```json
"logConfiguration": {
    "logDriver": "awslogs",
    "options": {
        "awslogs-group": "/ecs/laravel-tasks",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "laravel"
    }
}
```

### Logs separation by workload:

| Workload  | Log Group / Stream |
| --------- | ------------------ |
| Web       | /ecs/...-web       |
| Queue     | /ecs/...-queue     |
| Scheduler | /ecs/...-schedule  |
| Migration | /ecs/...-migrate   |

* Each ECS task gets its own stream:

```
ecs/<container-name>/<task-id>
```

* **This keeps logging very clean operationally.**

---

## 4️⃣ Storage/Logs Recommendation

* **Disable file logging in production:**

```env
APP_ENV=production
LOG_CHANNEL=stderr
```

* **Use file logging locally:**

```env
APP_ENV=local
LOG_CHANNEL=stack
```

* Laravel will still use `storage/logs` locally.

---

## 5️⃣ Debugging a Single Container

**Do not:**

* SSH into container
* Exec into container
* Read local files

**Instead:**

* Filter CloudWatch logs by task ID
* Or use CLI:

```bash
aws logs tail /ecs/staging-ecs-laravel-app --follow
```

---

## 6️⃣ Optional: Structured Logging

* For better observability, use **JSON logging**:

```php
'json' => [
    'driver' => 'monolog',
    'handler' => StreamHandler::class,
    'formatter' => Monolog\Formatter\JsonFormatter::class,
    'with' => [
        'stream' => 'php://stderr',
    ],
],
```

---

## 7️⃣ Best Practices

* Centralized logs via ECS and CloudWatch.
* Avoid ephemeral disk storage.
* Use structured logs for metrics and alerts.
* Set CloudWatch retention based on task volume.


**This file is the canonical reference for Laravel on ECS in this project.**
