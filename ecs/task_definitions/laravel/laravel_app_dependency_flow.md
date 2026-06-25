# Laravel App — ECS Infrastructure Overview

This document describes how all Terraform resources for the Laravel application
fit together. Each section adds a layer of detail, from internet traffic down to
individual container internals.

---

## 1. Traffic Flow (Internet → Containers)

```
                           ┌──────────────────────────────────────────────────────────────────┐
                           │                          AWS VPC                                  │
                           │                                                                   │
   ┌──────────┐            │  ┌─────────────────────────────┐                                 │
   │          │  :80/:443  │  │       Public Subnets         │                                 │
   │ Internet │───────────▶│  │  ┌───────────────────────┐  │                                 │
   │          │            │  │  │  Application Load     │  │                                 │
   └──────────┘            │  │  │  Balancer             │  │                                 │
                           │  │  │  (laravel-app-alb)    │  │                                 │
                           │  │  │                       │  │                                 │
                           │  │  │  Listener :80  ───────┼──┼──────────────────────────────┐  │
                           │  │  │  Target Group :80     │  │                              │  │
                           │  │  └───────────────────────┘  │                              │  │
                           │  └─────────────────────────────┘                              │  │
                           │                                                                │  │
                           │  ┌─────────────────────────────────────────────────────────┐  │  │
                           │  │                  Private Subnets                        │  │  │
                           │  │                                                         │  │  │
                           │  │  ┌─────────────────────────────────────────────────┐   │  │  │
                           │  │  │           ECS Web Task (Fargate)                │◀──┘  │  │
                           │  │  │                                                  │      │  │
                           │  │  │  ┌────────────────────┐  localhost:9000         │      │  │
                           │  │  │  │  nginx  :80  ◀ALB  │─────────────────────┐  │      │  │
                           │  │  │  │  (laravel-nginx img)│                     │  │      │  │
                           │  │  │  └────────────────────┘                     ▼  │      │  │
                           │  │  │                              ┌───────────────────┐  │      │  │
                           │  │  │                              │ php-fpm  :9000    │  │      │  │
                           │  │  │                              │ (laravel-app img) │  │      │  │
                           │  │  │                              │ (runs migrations  │  │      │  │
                           │  │  │                              │  on startup)      │  │      │  │
                           │  │  │                              └───────────────────┘  │      │  │
                           │  │  │      Shared network namespace (awsvpc mode)         │      │  │
                           │  │  └─────────────────────────────────────────────────┘   │      │  │
                           │  │                                                         │      │  │
                           │  │  ┌──────────────────────────────────────────────────────┐  │      │  │
                           │  │  │  ECS Horizon Task (Fargate — long-running service)  │  │      │  │
                           │  │  │  supervisord → php artisan horizon                  │  │      │  │
                           │  │  │  (laravel-app img)  No ALB  desired_count ≥ 1      │  │      │  │
                           │  │  └──────────────────────────────────────────────────────┘  │      │  │
                           │  │                                                             │      │  │
                           │  │  ECS Scheduler Task (Fargate — fire-and-forget)             │      │  │
                           │  │  ┌──────────────────────────────────────────────────────┐  │      │  │
                           │  │  │  php artisan schedule:run  (process exits when done) │  │      │  │
                           │  │  │  (laravel-app img)   No ALB   No ECS service         │  │      │  │
                           │  │  └──────────────────────────────────────────────────────┘  │      │  │
                           │  │       ▲  ecs:RunTask (every 1 minute)                       │      │  │
                           │  └───────┼─────────────────────────────────────────────────────┘      │  │
                           │         │                                                              │  │
                           │  ┌──────┴───────────────────────┐                                     │  │
                           │  │  EventBridge Scheduler        │                                     │  │
                           │  │  rate(1 minute) — UTC         │                                     │  │
                           │  └──────────────────────────────┘                                      │  │
                           └──────────────────────────────────────────────────────────────────────┘  │
                                                                                                      │
                            Note: Overlap possible if a task runs >1 min.                            │
                                  Use withoutOverlapping() in commands (REDIS_SCHEDULER_LOCK_DB=4)   │
```

---

## 2. ECS Task Internals — Web Task

Both containers run inside the **same ECS task** and share a network namespace
(ECS `awsvpc` mode). They communicate over `localhost` with no extra networking.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    ECS Web Task  (512 CPU / 1024 MB)                         │
│                                                                              │
│   ┌──────────────────────────────┐     ┌──────────────────────────────────┐  │
│   │      nginx container         │     │       php-fpm container          │  │
│   │  (image: laravel-nginx ECR)  │     │   (image: laravel-app ECR)       │  │
│   │                              │     │                                  │  │
│   │  • Serves static assets      │     │  • Runs Laravel application      │  │
│   │  • Reverse-proxies PHP reqs  │     │  • Reads env vars from           │  │
│   │  • Exposes :80 to ALB        │     │    SSM + Secrets Manager         │  │
│   │  • Health: GET /up           │     │  • Runs migrations on startup    │  │
│   │                              │     │    (when APP_SERVICE=web)        │  │
│   │  EXPOSE 80                   │     │  EXPOSE 9000 (internal only)     │  │
│   │                              │     │                                  │  │
│   │  PHP_FPM_HOST=localhost ─────┼────▶│  listen = 9000 (TCP)            │  │
│   │  fastcgi_pass localhost:9000 │     │  (was Unix socket before split)  │  │
│   └──────────────────────────────┘     └──────────────────────────────────┘  │
│                                                                              │
│   Startup order: php-fpm must be HEALTHY before nginx starts (dependsOn)    │
│   Logs: nginx → CloudWatch .../nginx   php-fpm → CloudWatch .../php-fpm     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Secret / Config Injection Flow

Values are fetched by ECS **at container startup**, not at `terraform apply` time.
To pick up a value changed in AWS Console, force a new deployment.

```
  ┌─────────────────────────────────────────────────────────────────────────┐
  │                   AWS Parameter Store (SSM)                             │
  │  APP_NAME  APP_ENV  APP_URL  LOG_*  DB_HOST  DB_PORT  DB_DATABASE      │
  │  CACHE_STORE  SESSION_*  QUEUE_CONNECTION  BROADCAST_CONNECTION         │
  │  FILESYSTEM_DISK  REDIS_CLIENT  REDIS_HOST  REDIS_PORT  REDIS_*_DB     │
  │  MAIL_MAILER  MAIL_SCHEME  MAIL_HOST  MAIL_PORT  MAIL_FROM_*           │
  │  AWS_BUCKET  DEPLOYMENT_STAGE  DEPLOYMENT_REGION  DEMO_MAIL_TO         │
  └───────────────────────────────────┬─────────────────────────────────────┘
                                      │  valueFrom ARN
  ┌───────────────────────────────────┼─────────────────────────────────────┐
  │                   AWS Secrets Manager                                   │
  │  APP_KEY        (laravel-app/app/key)                                   │
  │  DB_USERNAME    (laravel-app/database/credentials → :username::)        │
  │  DB_PASSWORD    (laravel-app/database/credentials → :password::)        │
  │  REDIS_PASSWORD (laravel-app/redis/password)                            │
  │  MAIL_USERNAME  (laravel-app/mail/credentials → :username::)            │
  │  MAIL_PASSWORD  (laravel-app/mail/credentials → :password::)            │
  └───────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      │  ECS fetches at container startup
                                      │  via Task Execution Role
                                      ▼
  ┌──────────────────────────────────────────────────────────────────────────┐
  │            php-fpm container  (+ horizon + scheduler containers)         │
  │            Environment variables injected as $APP_KEY, $DB_HOST, etc.   │
  └──────────────────────────────────────────────────────────────────────────┘

  ⚠️  Running containers do NOT pick up new values automatically.
      Change value in Console → re-run GitHub Actions (force new deployment).
```

---

## 4. Terraform File Map

```
staging-infrastructure/
│
├── laravel_app_ecr.tf                ← Two ECR repositories
│     module ecr_ecs_laravel_app       (php-fpm image: built from Dockerfile)
│     module ecr_ecs_laravel_nginx     (nginx image:   built from Dockerfile.nginx)
│
├── laravel_app_ecs_cluster.tf        ← Dedicated ECS cluster (enhanced Container Insights)
│     aws_ecs_cluster laravel_app_cluster
│
├── laravel_app_security_group.tf     ← ECS task security group
│     aws_security_group ecs_laravel_app_sg
│       ingress: port 80 from ALB SG only
│       egress:  all (ECR pulls, CloudWatch, RDS, Redis)
│
├── laravel_app_alb.tf                ← Load balancer stack
│     aws_security_group laravel_app_alb_sg   (ingress 80/443 from internet)
│     aws_lb             laravel_app_alb       (internet-facing, public subnets)
│     aws_lb_target_group laravel_app_tg       (port 80, health check /up)
│     aws_lb_listener    laravel_app_http      (port 80 → target group)
│
├── laravel_app_param_store.tf        ← Non-sensitive config (SSM Parameter Store)
│     38 parameters covering APP_*, LOG_*, DB_*, CACHE_*, SESSION_*,
│     QUEUE_*, BROADCAST_*, FILESYSTEM_*, REDIS_*, MAIL_*, AWS_*, DEPLOYMENT_*
│
├── laravel_app_secret_store.tf       ← Sensitive credentials (Secrets Manager)
│     app_key            → APP_KEY
│     db_credentials     → DB_USERNAME + DB_PASSWORD  (JSON)
│     redis_password     → REDIS_PASSWORD
│     mail_credentials   → MAIL_USERNAME + MAIL_PASSWORD  (JSON)
│
├── laravel_app_iam_roles.tf          ← IAM roles for ECS
│     module laravel_app_task_execution_role   (ECS control plane)
│       pulls images from ECR
│       writes logs to CloudWatch
│       fetches secrets/params at startup  ← depends on secret_store + param_store
│
│     module laravel_app_task_role           (application runtime)
│       enable_ecs_exec = true  (for aws ecs execute-command debugging)
│       secrets_arns    → all Secrets Manager ARNs
│       parameter_arns  → all SSM Parameter ARNs
│
├── laravel_app_task_definition.tf    ← Web task (nginx + php-fpm)
│     locals laravel_app_secrets      (shared secret list used by all 3 tasks)
│     module laravel_web_task_definition
│       nginx_image  = ecr_ecs_laravel_nginx.url:TAG  ← depends on ecr.tf
│       ecr_url      = ecr_ecs_laravel_app.url        ← depends on ecr.tf
│       execution_role_arn            ← depends on iam_roles.tf
│       task_role_arn                 ← depends on iam_roles.tf
│       secrets = local.laravel_app_secrets            ← depends on param_store + secret_store
│
├── laravel_app_task_definition_horizon.tf    ← Horizon queue worker task
│     aws_cloudwatch_log_group laravel_horizon_log_group
│     aws_ecs_task_definition  laravel_horizon_task
│       image   = ecr_ecs_laravel_app.url:TAG
│       command = supervisord -c /etc/supervisor/conf.d/horizon.conf
│       secrets = local.laravel_app_secrets  (same list as web)
│
├── laravel_app_task_definition_scheduler.tf  ← Scheduler task
│     aws_cloudwatch_log_group laravel_scheduler_log_group
│     aws_ecs_task_definition  laravel_scheduler_task
│       image   = ecr_ecs_laravel_app.url:TAG
│       command = supervisord -c /etc/supervisor/conf.d/scheduler.conf
│       secrets = local.laravel_app_secrets  (same list as web)
│
├── laravel_app_service.tf            ← ECS services (⚠️ uncomment to activate)
│     aws_ecs_service laravel_web_service
│       cluster         = laravel_app_cluster       ← depends on ecs_cluster.tf
│       task_definition = laravel_web_task          ← depends on task_definition.tf
│       security_groups = ecs_laravel_app_sg        ← depends on security_group.tf
│       load_balancer   = laravel_app_tg (nginx:80) ← depends on alb.tf
│       ignore_changes  = [task_definition, desired_count]
│
│     aws_ecs_service laravel_horizon_service
│       cluster         = laravel_app_cluster
│       task_definition = laravel_horizon_task
│       (no load balancer)
│
│     ← No scheduler service here — EventBridge fires it (see below)
│
├── laravel_app_eventbridge_scheduler.tf  ← Scheduler trigger (⚠️ uncomment to activate)
│     aws_iam_role eventbridge_laravel_scheduler
│       trust: scheduler.amazonaws.com
│       policy: ecs:RunTask + iam:PassRole (scoped to scheduler task + cluster)
│
│     aws_scheduler_schedule laravel_app_scheduler
│       rate(1 minute)  mode=OFF (exact, no flexibility window)
│       target: ecs:RunTask on laravel_app_cluster
│       task_definition: laravel_scheduler_task (LATEST revision — auto-updated by CI/CD)
│       Overlap handling: withoutOverlapping() in Laravel commands (REDIS_SCHEDULER_LOCK_DB=4)
│
├── laravel_app_autoscaling.tf        ← CPU/memory autoscaling (⚠️ uncomment to activate)
│     Scales laravel_web_service between 1–3 tasks
│     CPU target: 70%  scale-out: 60s  scale-in: 300s
│
└── laravel_app_cicd_iam_user.tf      ← GitHub Actions CI/CD user (⚠️ uncomment to activate)
      Scoped to: both ECR repos + all 3 ECS services + task roles + log groups
```

---

## 5. Resource Dependency Graph

```
  laravel_app_ecr.tf
  ┌──────────────────────┐
  │ ecr_ecs_laravel_app  │──────────────────────────────────────────────────────────┐
  │ ecr_ecs_laravel_nginx│──────────────────────────────────────────────────────┐   │
  └──────────────────────┘                                                     │   │
                                                                               │   │
  laravel_app_param_store.tf        laravel_app_secret_store.tf               │   │
  ┌─────────────────────┐           ┌──────────────────────────┐              │   │
  │ 38 SSM parameters   │           │ app_key                  │              │   │
  └──────────┬──────────┘           │ db_credentials           │              │   │
             │                      │ redis_password            │              │   │
             │                      │ mail_credentials          │              │   │
             │                      └────────────┬─────────────┘              │   │
             │                                   │                            │   │
             └──────────────────┬────────────────┘                            │   │
                                │                                             │   │
                                ▼                                             │   │
  laravel_app_iam_roles.tf                                                   │   │
  ┌────────────────────────────────────────────┐                             │   │
  │ laravel_app_task_execution_role            │                             │   │
  │ laravel_app_task_role                      │                             │   │
  │   (holds ARNs of all params + secrets)     │                             │   │
  └───────────────────┬────────────────────────┘                             │   │
                      │                                                      │   │
                      │          ┌───────────────────────────────────────────┘   │
                      │          │         (nginx_image)                         │
                      │          │  ┌────────────────────────────────────────────┘
                      │          │  │  (ecr_repository_url)
                      ▼          ▼  ▼
  laravel_app_task_definition.tf
  ┌───────────────────────────────────────────────────────┐
  │ locals.laravel_app_secrets  (shared by all 3 tasks)   │
  │ module laravel_web_task_definition                    │──┐
  └───────────────────────────────────────────────────────┘  │
                                                             │
  laravel_app_task_definition_horizon.tf                     │
  ┌───────────────────────────────────────────────────────┐  │
  │ laravel_horizon_task + log group                      │──┤
  └───────────────────────────────────────────────────────┘  │
                                                             │
  laravel_app_task_definition_scheduler.tf                   │
  ┌───────────────────────────────────────────────────────┐  │
  │ laravel_scheduler_task + log group                    │──┤
  └───────────────────────────────────────────────────────┘  │
                                                             │
  laravel_app_alb.tf          laravel_app_security_group.tf  │
  ┌─────────────────┐         ┌───────────────────────────┐  │
  │ laravel_app_alb │         │ ecs_laravel_app_sg         │  │
  │ laravel_app_tg  │         │  ingress from alb_sg only  │  │
  │ alb_sg          │◀────────│                            │  │
  └────────┬────────┘         └──────────────┬────────────┘  │
           │                                 │               │
           └──────────────┬──────────────────┘               │
                          │                                  │
  laravel_app_ecs_cluster.tf                                 │
  ┌─────────────────────────────┐                           │
  │ laravel_app_cluster         │                           │
  └──────────────┬──────────────┘                           │
                 │                                          │
                 ▼                                          ▼
  laravel_app_service.tf  ◀──────────────────────────────────
  ┌──────────────────────────────────────────────────────────┐
  │ laravel_web_service     → nginx:80 registered to ALB TG  │
  │ laravel_horizon_service → no ALB                         │
  │ (no scheduler service — EventBridge fires it)            │
  └──────────────────────────────────────────────────────────┘
           │
           ▼
  laravel_app_autoscaling.tf   laravel_app_eventbridge_scheduler.tf
  ┌──────────────────────────┐  ┌──────────────────────────────────────┐
  │ Scales web_service       │  │ EventBridge rate(1 minute)           │
  │ CPU 70% / Mem 80%        │  │ → ecs:RunTask laravel_scheduler_task │
  │ min: 1  max: 3           │  │ IAM role scoped to cluster + task    │
  └──────────────────────────┘  └──────────────────────────────────────┘

  laravel_app_cicd_iam_user.tf
  ┌──────────────────────────────────────────────────────────────────────┐
  │ GitHub Actions OIDC role                                             │
  │ ECR push + ECS deploy perms (web + horizon services only)           │
  │ Registers new scheduler task def revision (EventBridge picks it up) │
  └──────────────────────────────────────────────────────────────────────┘
```

---

## 6. Docker Images

```
  deployment-laravel repo
  │
  ├── Dockerfile              → laravel-app image  (ECR: ecs-laravel-app)
  │    Stage 1: node (npm run build → public/build/)
  │    Stage 2: php-base (PHP 8.4 FPM + extensions + supervisor)
  │    Stage 3: composer deps
  │    Stage 4: production image
  │      CMD: php-fpm                          ← web task
  │      CMD override: supervisord horizon     ← horizon task
  │      CMD override: supervisord scheduler   ← scheduler task
  │      COPY manifest.json only (PHP needs it for Vite asset URLs)
  │
  └── Dockerfile.nginx        → nginx image   (ECR: ecs-laravel-nginx)
       Stage 1: node (npm run build → compiled CSS/JS)
       Stage 2: nginx:stable-alpine
         COPY nginx.conf.template  (uses envsubst for PHP_FPM_HOST)
         COPY public/              (static assets for direct serving)
         COPY public/build/        (compiled frontend assets)
         ENV PHP_FPM_HOST=localhost  ← set in ECS task definition
```

---

## 7. Deploy Sequence (GitHub Actions)

```
  Code push to main
        │
        ▼
  Build & push two Docker images
  ┌─────────────────────────────────────────────┐
  │  docker build -f Dockerfile       → ECR push │  (laravel-app:SHA)
  │  docker build -f Dockerfile.nginx → ECR push │  (laravel-nginx:SHA)
  └──────────────────────────────────┬──────────┘
                                     │
                                     ▼
  Update ECS task definitions with new image SHAs
  (aws ecs register-task-definition for web, horizon, scheduler)
                                     │
                                     ▼
  Force new deployments
  ┌─────────────────────────────────────────────┐
  │  aws ecs update-service laravel-web-service  │
  │  aws ecs update-service laravel-horizon      │
  │  aws ecs update-service laravel-scheduler    │
  └──────────────────────────────────┬──────────┘
                                     │
                                     ▼
  ECS stops old tasks, starts new ones
  → New containers fetch CURRENT values from SSM + Secrets Manager
  → php-fpm container runs `php artisan migrate` on startup
  → Containers pass health checks → ALB routes traffic
```
