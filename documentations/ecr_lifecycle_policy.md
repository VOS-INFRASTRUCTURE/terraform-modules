# ECR Lifecycle Policy Guide

## Overview

The ECR module includes an **automatic lifecycle policy** that prevents unbounded repository growth by deleting old images while preserving recent ones.

---

## 📦 Default Configuration

**Retention:** Keep the **latest 10 images**  
**Deletion:** Automatic (daily cleanup by AWS)  
**Scope:** Applies to all tags (tagged and untagged images)

---

## 🔄 How It Works

### Example Timeline

```
Day 1:  Push v1.0.0                              → Repo: [v1.0.0]
Day 2:  Push v1.0.1                              → Repo: [v1.0.0, v1.0.1]
Day 3:  Push v1.0.2                              → Repo: [v1.0.0, v1.0.1, v1.0.2]
...
Day 10: Push v1.0.9                              → Repo: [v1.0.0 ... v1.0.9] (10 images)
Day 11: Push v1.1.0                              → Repo: [v1.0.1 ... v1.1.0] (10 images)
                                                     ❌ v1.0.0 DELETED
Day 12: Push v1.1.1                              → Repo: [v1.0.2 ... v1.1.1] (10 images)
                                                     ❌ v1.0.1 DELETED
```

### Selection Criteria

The policy selects images based on **push timestamp**, not tag name:

```json
{
  "selection": {
    "tagStatus": "any",           // Includes both tagged and untagged
    "countType": "imageCountMoreThan",
    "countNumber": 10             // Keep newest 10
  },
  "action": {
    "type": "expire"              // Delete older images
  }
}
```

---

## ⚙️ Customization

### Change Retention Count

**In `node_app_ecr.tf`:**

```hcl
module "ecr_ecs_node_app" {
  source = "./modules/ecr"

  project_id                = var.project_id
  env                       = var.env
  repo_name                 = "ecs-node-app"
  lifecycle_keep_last_count = 20  # Keep 20 instead of 10
}
```

### Common Retention Values

| Use Case | Recommended Count | Reasoning |
|----------|-------------------|-----------|
| **Dev/Testing** | 5-10 | Rapid iteration, short retention |
| **Staging** | 10-20 | Balance between cost and rollback window |
| **Production** | 20-50 | Longer rollback window, compliance |
| **Long-term archive** | 100+ | Regulatory requirements |

---

## 💰 Cost Impact

### Without Lifecycle Policy

```
10 deployments/day × 365 days = 3,650 images/year
Average image size: 500 MB
Storage: 3,650 × 500 MB = 1,825 GB = 1.78 TB

ECR Storage Cost (us-east-1):
$0.10/GB/month × 1,825 GB = $182.50/month = $2,190/year
```

### With Lifecycle Policy (keep 10)

```
Max images: 10
Storage: 10 × 500 MB = 5 GB

ECR Storage Cost:
$0.10/GB/month × 5 GB = $0.50/month = $6/year

Annual Savings: $2,184 (99.7% reduction)
```

---

## 🛡️ Safety Guarantees

### What's Protected

✅ **Latest N images are NEVER deleted** (where N = `lifecycle_keep_last_count`)  
✅ **Currently running images are safe** (ECS caches locally)  
✅ **Policy runs daily**, not immediately on push  

### What Gets Deleted

❌ Images pushed more than N images ago  
❌ Untagged images (dangling layers from failed builds)  
❌ Images older than the retention window  

---

## 🚨 Important Considerations

### Rollback Window

With `lifecycle_keep_last_count = 10`:

- **You can rollback to the last 10 deployments**
- Older versions are **permanently deleted**
- Plan your retention based on your rollback needs

**Example:**
```bash
# These work (within last 10):
terraform apply -var="ecs_node_app_image_tag=abc123f"  # 2 deploys ago
terraform apply -var="ecs_node_app_image_tag=def456a"  # 9 deploys ago

# This FAILS (more than 10 deploys ago):
terraform apply -var="ecs_node_app_image_tag=old789b"  # 15 deploys ago
# Error: Image not found in ECR
```

### Disaster Recovery

If you need **long-term image retention** for compliance/audit:

**Option 1:** Increase count
```hcl
lifecycle_keep_last_count = 100  # Keep 100 versions
```

**Option 2:** Export critical images to S3
```bash
# Backup production releases to S3
docker pull account.dkr.ecr.region.amazonaws.com/ecs-node-app:v1.0.0
docker save ecs-node-app:v1.0.0 | gzip > v1.0.0.tar.gz
aws s3 cp v1.0.0.tar.gz s3://backup-bucket/ecr-images/
```

**Option 3:** Use separate repo for releases
```hcl
# Dev repo (fast cleanup)
module "ecr_dev" {
  repo_name = "ecs-node-app-dev"
  lifecycle_keep_last_count = 5
}

# Production repo (long retention)
module "ecr_prod" {
  repo_name = "ecs-node-app"
  lifecycle_keep_last_count = 50
}
```

---

## 🔍 Monitoring Cleanup

### View Lifecycle Policy

```bash
aws ecr get-lifecycle-policy \
  --repository-name ecs-node-app \
  --region eu-west-2
```

### Check Remaining Images

```bash
aws ecr list-images \
  --repository-name ecs-node-app \
  --region eu-west-2 \
  --query 'imageIds[*].imageTag' \
  --output table
```

### See What Will Be Deleted (Dry Run)

```bash
aws ecr get-lifecycle-policy-preview \
  --repository-name ecs-node-app \
  --region eu-west-2
```

---

## 📊 Policy Execution

### When Does Cleanup Run?

- **Frequency:** Daily (AWS-managed schedule)
- **Time:** Non-deterministic (AWS chooses optimal time)
- **Delay:** New images are safe for at least 24 hours after push

### Execution Order

1. AWS evaluates all images in the repository
2. Sorts by push timestamp (newest first)
3. Keeps the top N images
4. Deletes images beyond count N
5. Logs deletions to CloudTrail

---

## ✅ Best Practices

### DO

✅ Set retention based on your deployment frequency:
  - 1 deploy/day → keep 10-14 (2 weeks)
  - 5 deploys/day → keep 30-50 (1-2 weeks)
  
✅ Monitor repository size periodically

✅ Tag production releases for easy identification

✅ Test rollback procedures within your retention window

### DON'T

❌ Set count too low (< 5) - limits rollback options

❌ Assume images exist forever without lifecycle policy

❌ Use lifecycle policy as a backup strategy

❌ Set count unnecessarily high (wastes money)

---

## 🎯 Summary

**Current Setup:**
- ✅ Lifecycle policy enabled by default
- ✅ Keeps latest 10 images
- ✅ Automatic daily cleanup
- ✅ Costs ~$0.50/month instead of $182.50/month
- ✅ Configurable via `lifecycle_keep_last_count`

**You're protected!** Your ECR repo won't grow unbounded and rack up storage costs. 🎉

