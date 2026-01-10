# ECS Migration Playbook (CERPAC)

This playbook turns the high‑level ECS plan into concrete, repo‑specific steps you can execute safely.

Scope baseline:
- Keep existing ALB, VPC, and certificates
- Shift compute from EC2 to ECS Fargate (API first)
- Use ECR for images; deploy via Terraform + GitHub Actions
- No SSH, rolling updates only

Phases

1) Preparation (no infra change)
- Containerize API (Dockerfile) and verify locally
- Define runtime env (ENV VARS → SSM Parameter Store, secrets → Secrets Manager)
- Tag current resources with Project and Environment if missing

2) Add modular scaffolding (no drift)
- Create Terraform modules shells (no resources yet) under production-infrastructure/modules:
  - ecs/ (cluster, task defs, services, autoscaling, log groups)
  - ecr/ (repo, lifecycle policy)
  - iam/ (task execution + task roles, least privilege)
- Do not refactor existing ALB/VPC yet; reuse

3) Enable ECR and CI pipeline
- Add ECR repo for API
- GitHub Actions job (build → tag with SHA → push to ECR)
- Output image URI as artifact/environment variable

4) Stand up ECS cluster and a canary service
- Create ECS cluster (Fargate)
- Task definition for API (CPU/memory, log group, env/secret refs)
- ECS service with desired_count=1, attach to existing ALB target group (create a new target group to keep blue/green option)
- Health checks through ALB; confirm service stable

5) Cutover and scale
- Increase desired_count
- Shift traffic progressively (weighted target groups or full switch on listener rule)
- Decommission EC2 API nodes when steady

6) Post‑cut hardening
- Autoscaling policies (CPU, memory, ALB requests per target)
- Alarms on 5xx, UnhealthyHostCount, Service CPU/Memory
- Cost guardrails (ECR lifecycle, ECS task min/max)

Repo mapping and minimal module contracts

- modules/ecr
  - inputs: project_id, env, repo_name
  - outputs: repository_url, arn
  - notes: add lifecycle (retain last N images)

- modules/iam
  - inputs: project_id, env, policy attachments (ssm:GetParameters, secretsmanager:GetSecretValue, logs:CreateLogStream/PutLogEvents, ecr:BatchGetImage)
  - outputs: task_execution_role_arn, task_role_arn

- modules/ecs
  - inputs: project_id, env, cluster_name, image, cpu, memory, desired_count, subnets, security_groups, target_group_arn, container_port, env_vars, secret_arns
  - outputs: service_name, task_definition_arn, log_group_name

Environments wiring (environments/*/main.tf)
- call the new modules behind feature flags (enable_ecs, enable_ecr)
- pass env‑specific values via terraform.tfvars

Minimal variable additions to environments/*/variables.tf
- enable_ecr (bool, default false)
- enable_ecs (bool, default false)
- api_image_tag (string, default null) — set by CI

CI/CD outline (GitHub Actions)
- on: push to main, tags
- steps: configure AWS creds → login to ECR → build → tag :$GITHUB_SHA → push → terraform apply with -var api_image_tag=$GITHUB_SHA and toggles enable_ecr/enable_ecs=true

Observability
- CloudWatch Log Group: /aws/ecs/${env}-${project_id}-api (from ecs module)
- Alarms: ALB 5XX > threshold, ECS CPU/Memory > threshold, UnhealthyHostCount > 0
- Dashboards: add ECS service and ALB widgets

Risk controls
- Keep current API behind ALB until ECS healthy
- Use new Target Group for ECS to allow rollback by listener rule switch
- Terraform plan must show no destructive changes to non‑ECS resources

Verification checklist
- ECR repo exists and accepts pushes
- ECS cluster up; service stable with healthy tasks
- ALB listener forwards to ECS target group; health checks green
- Logs present in CloudWatch for task
- No unauthenticated access: SGs least privilege; tasks in private subnets with NAT
- Rollback: scale EC2 back or switch listener to legacy target group if needed

Appendix — Example outputs to expose (ecs module)
- service_name
- service_arn
- task_definition_arn
- log_group_name
- target_group_arn (if created in module)

Keep changes incremental. Land ECR → ECS cluster → canary service → cutover.

