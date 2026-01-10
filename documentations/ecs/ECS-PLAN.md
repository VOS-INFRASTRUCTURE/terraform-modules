# Terraform-based Scalable Deployment Plan

This document outlines a **clean, production-ready approach** to deploying and running the Node.js API with **horizontal scaling, zero-downtime deployments, and no SSH-based operations**, fully managed using **Terraform + AWS managed services**.

---

## 🎯 Goals

* Horizontal scaling
* Zero / near-zero downtime deployments
* Immutable infrastructure (no manual SSH)
* Fully reproducible environments
* Clear separation of infrastructure and application delivery

---

## 🏗️ Target Architecture (High-Level)

```
GitHub Actions
   |
   |  (Build Docker Image)
   v
Amazon ECR
   |
   |  (New Image Tag)
   v
ECS Service (Fargate)
   |
   |  (Auto Scaling, Rolling / Blue-Green Deployments)
   v
Application Load Balancer (HTTPS)
```

All AWS resources are **provisioned and managed by Terraform**.

---

## 🧱 Infrastructure Components (Terraform Managed)

### Networking

* VPC
* Public & Private Subnets (Multi-AZ)
* Internet Gateway
* NAT Gateway
* Route Tables
* Security Groups

### Load Balancing & SSL

* Application Load Balancer (ALB)
* HTTPS Listener (ACM Certificate)
* HTTP → HTTPS Redirect
* Target Groups
* Health Checks

### Container Platform (ECS Fargate)

* ECS Cluster
* ECS Task Definitions
* ECS Services

* Auto Scaling Policies
* IAM Roles (Task + Execution)
* CloudWatch Log Groups

### Container Registry

* Amazon ECR Repository
* Image Lifecycle Policies

### Configuration & Secrets

* AWS SSM Parameter Store
* AWS Secrets Manager
* IAM policies for secure access

### Observability

* CloudWatch Logs
* CloudWatch Metrics & Alarms

### Optional Supporting Services

* Amazon RDS / Aurora (Database)
* ElastiCache Redis (Sessions / Cache)
* S3 (Uploads, Assets)

---

## 📁 Recommended Terraform Structure

```
infra/
├── modules/
│   ├── vpc/
│   ├── alb/
│   ├── ecs/
│   ├── ecr/
│   ├── iam/
│   ├── rds/
│   └── redis/
│
├── envs/
│   ├── staging/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   │
│   └── production/
│       ├── main.tf
│       ├── variables.tf
│       └── terraform.tfvars
│
└── versions.tf
```

This structure allows:

* environment isolation (staging vs production)
* safe rollouts
* reusable infrastructure modules

---

## 🔁 Deployment Flow (CI/CD)

### Infrastructure Lifecycle

* Terraform provisions infrastructure **once or on change**
* Stored in remote state (S3 + DynamoDB lock)

### Application Deployment (Every Release)

1. GitHub Actions builds Docker image
2. Image is tagged with commit SHA
3. Image is pushed to Amazon ECR
4. ECS Service is updated with new image
5. ALB routes traffic only to healthy tasks

No SSH. No SCP. No in-place mutation.

---

## 🚀 Deployment Strategies

### Rolling Deployment (Default)

* Gradual replacement of running tasks
* Configurable healthy percentage
* ALB health checks control traffic

Recommended ECS settings:

* minimum healthy percent: `50–100`
* maximum percent: `200`

### Blue-Green Deployment (Advanced)

* Two target groups (blue & green)
* Traffic switch controlled by CodeDeploy
* Instant rollback capability

---

## 📈 Auto Scaling Strategy

ECS service scales based on:

* CPU utilization
* Memory utilization
* ALB request count per target

Scaling is automatic and multi-AZ by default.

---

## 🔐 State Management (Critical)

Terraform uses a **remote backend**:

* S3 bucket for state
* DynamoDB for state locking
* Encrypted at rest

This ensures safe collaboration and prevents state corruption.

---

## 🚫 What Terraform Does NOT Handle

Terraform should not:

* SSH into servers
* Run `npm install`
* Build Docker images
* Run application-level scripts

These belong in **CI/CD pipelines**, not infrastructure code.

---

## ✅ Benefits of This Approach

* Zero-downtime deployments
* Horizontal scaling out of the box
* No server management
* Reproducible environments
* Safer rollbacks
* Lower operational overhead

---

## 🧭 Next Implementation Steps

1. Create Terraform VPC & networking modules
2. Provision ALB + HTTPS
3. Create ECS Cluster (Fargate)
4. Add ECR repository
5. Migrate app to stateless model
6. Update GitHub Actions to deploy via ECR + ECS
7. Enable autoscaling and monitoring

---

## 🔧 Repo-specific execution checklist (this repo)

Use these concrete steps aligned to the current repository layout:

- Module scaffolding
  - [x] Add ECS/ECR/IAM module skeletons under `production-infrastructure/modules`:
    - `modules/ecs/README.md` (cluster/service/task/logs contract)
    - `modules/ecr/README.md` (repo + lifecycle)
    - `modules/iam/README.md` (task roles)

- Wire up environment toggles
  - Add variables in `environments/*/variables.tf` (or equivalent):
    - `enable_ecr` (bool, default false)
    - `enable_ecs` (bool, default false)
    - `api_image_tag` (string, default null)
  - Update `environments/*/main.tf` to conditionally call the new modules when toggles are true.

- ECR first
  - Create ECR repo via module; expose `repository_url` output.
  - Configure GitHub Actions to build and push images tagged with `${GITHUB_SHA}`.

- ECS canary service
  - Stand up ECS cluster (Fargate) and a canary service for the API.
  - Create a new ALB target group for ECS; keep legacy group for rollback.
  - Confirm health checks green before switching traffic.

- Cutover + autoscaling
  - Switch listener rules to ECS target group; increase desired_count.
  - Add autoscaling (CPU/Memory/ALB Req per Target) and alarms.

References in this repo
- Additional playbook: `production-infrastructure/documentations/ecs_migration_playbook.md`
- Existing ALB/VPC assets: `production-infrastructure/networking.tf`, `production-infrastructure/cerpac_alb.tf`
- Place new modules here: `production-infrastructure/modules/{ecs,ecr,iam}`

---

This document serves as the **baseline reference** for evolving the current EC2-based deployment into a **modern, scalable, Terraform-managed platform**.
