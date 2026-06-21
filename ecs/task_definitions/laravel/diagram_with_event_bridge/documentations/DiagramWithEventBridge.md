# Architecture Diagram — Laravel Basic 1
## Redis + Horizon + Supervisor + EventBridge

---

## Full Architecture

```
                         ┌──────────────────────────────────────────────────────────────────────┐
                         │                        AWS VPC (eu-west-2)                            │
                         │                                                                       │
   Users / Internet      │                                                                       │
         │               │   ╔═══════════════════════════════════════════════════════════════╗   │
         │               │   ║           ECS Cluster (Fargate — Private Subnets)            ║   │
         ▼               │   ║                                                               ║   │
  ┌─────────────┐        │   ║  ┌─────────────────────────────────────────────────────────┐ ║   │
  │     ALB     │────────┼──▶║  │  Laravel Web Service    [auto-scales: CPU / Req Count]  │ ║   │
  │  (public)   │        │   ║  │                                                         │ ║   │
  │  port 443   │        │   ║  │  ┌──────────────────────┐  ┌──────────────────────┐    │ ║   │
  └─────────────┘        │   ║  │  │       Task 1         │  │       Task 2         │ …  │ ║   │
                         │   ║  │  │  nginx    (port  80) │  │  nginx    (port  80) │    │ ║   │
                         │   ║  │  │  php-fpm  (port 9000)│  │  php-fpm  (port 9000)│    │ ║   │
                         │   ║  │  └──────────────────────┘  └──────────────────────┘    │ ║   │
                         │   ║  └──────────────────────────────┬──────────────────────────┘ ║   │
                         │   ║                                  │ dispatch(new Job())         ║   │
                         │   ║  ┌───────────────────────────────▼──────────────────────────┐ ║   │
                         │   ║  │  Laravel Horizon Service  [desired: 1 — manual scaling]  │ ║   │
                         │   ║  │  ┌────────────────────────────────────────────────────┐  │ ║   │
                         │   ║  │  │  ECS Task                                          │  │ ║   │
                         │   ║  │  │  supervisord (PID 1)                               │  │ ║   │
                         │   ║  │  │    └── php artisan horizon                         │  │ ║   │
                         │   ║  │  │          ├── worker 1 [queue: high]    ← BLPOP DB0 │  │ ║   │
                         │   ║  │  │          ├── worker 2 [queue: default] ← BLPOP DB0 │  │ ║   │
                         │   ║  │  │          └── worker 3 [queue: low]     ← BLPOP DB0 │  │ ║   │
                         │   ║  │  └────────────────────────────────────────────────────┘  │ ║   │
                         │   ║  └──────────────────────────────────────────────────────────┘ ║   │
                         │   ║                                                               ║   │
                         │   ║  ┌─────────────────────────────────────────────────────────┐ ║   │
                         │   ║  │  Laravel Scheduler     [ephemeral — ECS RunTask]        │ ║   │
                         │   ║  │  ┌────────────────────────────────────────────────────┐  │ ║   │
                         │   ║  │  │  ECS Task (RunTask)                                │  │ ║   │
                         │   ║  │  │  php artisan schedule:run                          │  │ ║   │
                         │   ║  │  │  → runs ~5–15 seconds then exits                   │  │ ║   │
                         │   ║  │  └────────────────────────────────────────────────────┘  │ ║   │
                         │   ║  └─────────────────────────────────────────────────────────┘ ║   │
                         │   ║         ▲  fired every 1 minute                              ║   │
                         │   ╚═════════╪══════════════════════════════════════════════════╝ ║   │
                         │             │                                                     ╚   │
                         │   ┌─────────┴──────────┐                                            │
                         │   │  EventBridge        │                                            │
                         │   │  Scheduler          │                                            │
                         │   │  rate(1 minute)     │                                            │
                         │   └────────────────────┘                                            │
                         │                                                                       │
                         │                Redis protocol (TCP 6379)          TCP 3306            │
                         │   ╔══════╤══════════════════════════════╗   ┌──────────────────────┐ │
                         │   ║      ▼  Redis (ElastiCache / EC2)  ║   │  RDS                 │ │
                         │   ║  DB 0 → queue jobs                 ║   │  (MySQL / PostgreSQL) │ │
                         │   ║  DB 1 → cache                      ║   └──────────────────────┘ │
                         │   ║  DB 2 → sessions                   ║                            │
                         │   ║  DB 3 → Horizon metrics            ║                            │
                         │   ║  DB 4 → scheduler locks            ║                            │
                         │   ╚════════════════════════════════════╝                            │
                         └──────────────────────────────────────────────────────────────────────┘

Supporting AWS Services
──────────────────────────────────────────────────────────────────────────────────────
  ECR                   ──(image pull at container start)──────▶  All ECS tasks
  Secrets Manager / SSM ──(secrets injected at container start)─▶  All ECS tasks
  CloudWatch Logs       ◀──(awslogs driver, one group per task)─── All ECS tasks
  IAM Execution Role    ──(ECR pull + Secrets fetch)─────────────▶  ECS tasks
  IAM Task Role         ──(runtime app permissions)──────────────▶  ECS tasks
  IAM EventBridge Role  ──(ecs:RunTask)──────────────────────────▶  EventBridge → Scheduler
```

---

## Component Interaction Flow

### A — HTTP Request Flow

```
User
 │
 ▼
ALB (port 443, SSL termination)
 │
 ▼
ECS Web Task — nginx (port 80) → php-fpm (port 9000, localhost)
 │  Laravel handles the request
 │  Calls Cache::get()  → Redis DB1
 │  Calls DB query      → RDS
 │  Dispatches job      → Redis DB0 (queue)
 │
 ▼
HTTP Response → User
```

---

### B — Job Dispatch & Processing Flow

```
Web Task
 │
 │  ProcessPaymentJob::dispatch($order)->onQueue('high');
 │
 ▼
Redis DB0  (queue:high list)
 │  [Job-1 serialized payload]
 │
 ▼
Horizon Worker (queue: high) — pulls via BLPOP
 │
 ├── success → LREM (remove from queue) → done ✅
 │
 └── failure
       │
       ├── attempt 1 or 2 → $this->release(600) → back to queue after 10 min
       │
       └── attempt 3 → failed() called
                         → logged to Redis (Horizon failed jobs)
                         → visible in /horizon dashboard
                         → re-dispatch manually from UI
```

---

### C — Scheduling Flow (EventBridge)

```
AWS EventBridge Scheduler
 │  Fires every 1 minute (rate(1 minute))
 │  Uses IAM role with ecs:RunTask permission
 ▼
ECS RunTask API call
 │  Starts one-off laravel-scheduler task
 │
 ▼
ECS Scheduler Task
 │  php artisan schedule:run
 │
 ├── Check: is DailyReportJob due?
 │     YES → dispatch(new DailyReportJob()) → Redis queue
 │     NO  → skip
 │
 ├── Check: is CleanExpiredTokensCommand due?
 │     YES → runs inline
 │     NO  → skip
 │
 └── exits (task stops automatically)

Total task lifetime: ~5–15 seconds
Cost: ~$0.0001 per invocation
```

**Redis lock safety net (onOneServer):**
```
Scheduler Task starts
 │
 ├── Acquires Redis lock: "schedule:DailyReportJob:lock"
 │     ← atomic SETNX — only one task can hold it
 │
 ├── If lock acquired → run → release lock on finish
 │
 └── If lock NOT acquired (another task already running it)
       → skip
```

---

### D — Horizon Supervisor Recovery Flow

```
ECS Task running:
  supervisord
    └── php artisan horizon (PID 42)
          ├── worker 1
          ├── worker 2
          └── worker 3

Scenario: Horizon process crashes (OOM, exception, etc.)

  supervisord detects PID 42 gone (within 1 second)
    │
    └── autorestart=true → starts new:
          php artisan horizon (PID 87) → < 2 seconds
          ├── worker 1 reconnects to Redis
          ├── worker 2 reconnects to Redis
          └── worker 3 reconnects to Redis

  ← ECS never knows this happened
  ← No task replacement needed
  ← Jobs picked up immediately
```

---

### E — Deployment (Zero Downtime)

```
New Docker image pushed to ECR
 │
 ▼
ECS Rolling Deployment triggered

 Step 1: ECS starts new Horizon task (new image)
           └── new task healthy and connected to Redis

 Step 2: ECS sends SIGTERM to old Horizon task
           └── supervisord receives SIGTERM
               └── sends SIGTERM to php artisan horizon
                   └── Horizon enters TERMINATING state
                         ├── stops accepting new jobs
                         ├── finishes worker 1's current job
                         ├── finishes worker 2's current job
                         └── finishes worker 3's current job
                         → exits cleanly

 Step 3: Old task deregistered
          New task fully active

Total downtime: 0 seconds
Jobs lost:      0
```

---

## Horizon Dashboard Flow

```
Developer opens browser → https://your-app.com/horizon
 │
 ▼
Laravel Web Task (Horizon dashboard routes)
 │
 │  Reads from Redis DB3 (Horizon metrics store):
 ├── Job throughput (jobs/min)
 ├── Failed jobs list (with stack traces)
 ├── Queue sizes (high / default / low)
 ├── Wait times per queue
 ├── Worker count (current active)
 └── Tagged job search
```

**Secure the dashboard:**
```php
// app/Providers/HorizonServiceProvider.php
Horizon::auth(function ($request) {
    return auth()->check() && auth()->user()->isAdmin();
});
```

---

## Security Groups

```
┌──────────────────────────────────────────────────────────────────┐
│  ALB SG                                                          │
│    Inbound:  443 (HTTPS) from 0.0.0.0/0                         │
│    Outbound: 80  → ECS Web SG                                    │
├──────────────────────────────────────────────────────────────────┤
│  ECS Web SG                                                      │
│    Inbound:  80   from ALB SG                                    │
│    Outbound: 6379 → Redis SG         (queue dispatch, cache)     │
│    Outbound: 3306 → RDS SG           (database)                  │
│    Outbound: 443  → 0.0.0.0/0       (ECR, Secrets Manager)      │
├──────────────────────────────────────────────────────────────────┤
│  ECS Horizon SG                                                  │
│    Inbound:  (none)                                              │
│    Outbound: 6379 → Redis SG         (queue consume + metrics)   │
│    Outbound: 3306 → RDS SG           (database in jobs)          │
│    Outbound: 443  → 0.0.0.0/0       (ECR, Secrets Manager)      │
├──────────────────────────────────────────────────────────────────┤
│  ECS Scheduler SG                                                │
│    Inbound:  (none)                                              │
│    Outbound: 6379 → Redis SG         (onOneServer locks)         │
│    Outbound: 3306 → RDS SG           (inline commands)           │
│    Outbound: 443  → 0.0.0.0/0       (ECR, Secrets Manager)      │
├──────────────────────────────────────────────────────────────────┤
│  Redis SG (ElastiCache or EC2)                                   │
│    Inbound:  6379 from ECS Web SG                                │
│    Inbound:  6379 from ECS Horizon SG                            │
│    Inbound:  6379 from ECS Scheduler SG                          │
├──────────────────────────────────────────────────────────────────┤
│  RDS SG                                                          │
│    Inbound:  3306 from ECS Web SG                                │
│    Inbound:  3306 from ECS Horizon SG                            │
│    Inbound:  3306 from ECS Scheduler SG                          │
└──────────────────────────────────────────────────────────────────┘
```

---

## Terraform Module Map

```
ecs/task_definitions/laravel/
├── web_task_definition/         ← nginx + php-fpm (ALB-facing web service)
├── horizon_task_definition/     ← supervisord + php artisan horizon (queue workers)
└── scheduler_task_definition/   ← php artisan schedule:run (ephemeral, EventBridge)
```

Each module creates:
- `aws_ecs_task_definition` — container definitions, resource sizing, secrets
- `aws_cloudwatch_log_group`  — log retention, tags

---

*Last updated: June 2026*
