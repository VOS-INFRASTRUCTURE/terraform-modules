# Running Node.js Cron Jobs on ECS

## 📋 Table of Contents
- [Overview](#overview)
- [Approach Comparison](#approach-comparison)
- [Method 1: EventBridge Scheduled Rules](#method-1-eventbridge-scheduled-rules-recommended)
- [Method 2: In-Container Cron (node-cron)](#method-2-in-container-cron-node-cron)
- [Method 3: Lambda + EventBridge](#method-3-lambda--eventbridge)
- [Architecture Diagrams](#architecture-diagrams)
- [Implementation Examples](#implementation-examples)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## 🎯 Overview

There are **3 main approaches** to run scheduled jobs in a Node.js ECS environment:

1. **EventBridge Scheduled Rules** → Triggers ECS tasks on schedule (RECOMMENDED)
2. **In-Container Cron** → Runs cron jobs inside a long-running ECS service
3. **Lambda + EventBridge** → EventBridge triggers Lambda (for simple jobs)

---

## 📊 Approach Comparison

| Aspect | EventBridge → ECS Task | In-Container Cron | Lambda + EventBridge |
|--------|------------------------|-------------------|---------------------|
| **Cost Efficiency** | ✅ Pay only when running | ⚠️ Runs 24/7 | ✅ Pay per execution |
| **Resource Usage** | ✅ Scales to zero | ❌ Always consuming | ✅ Serverless |
| **Fault Tolerance** | ✅ Each run isolated | ⚠️ Crash affects all jobs | ✅ Auto-retry |
| **Code Reuse** | ✅ Same codebase as app | ✅ Same codebase | ⚠️ Lambda-specific code |
| **Complexity** | ⚠️ Moderate (Terraform setup) | ✅ Simple (just install node-cron) | ⚠️ Moderate |
| **Execution Time** | ✅ No limit (can run hours) | ✅ No limit | ❌ 15 min max |
| **Dependencies** | ✅ Full Node.js environment | ✅ Full environment | ⚠️ Lambda layers needed |
| **Observability** | ✅ CloudWatch Logs | ⚠️ Mixed with app logs | ✅ CloudWatch Logs |
| **Best For** | Heavy jobs (reports, ETL) | Frequent light tasks | Simple, quick tasks |

---

## Method 1: EventBridge Scheduled Rules (RECOMMENDED)

### 🎯 When to Use
- **Heavy processing jobs** (data exports, report generation)
- **Database maintenance** (cleanup, archival)
- **Batch operations** (email sends, data sync)
- **Long-running tasks** (> 15 minutes)
- **Cost optimization** (don't need container running 24/7)

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  AWS EventBridge                             │
│  (Cron Expression: 0 2 * * ? = 2 AM daily)                  │
└─────────────────────────────────────────────────────────────┘
                        ↓ (triggers)
┌─────────────────────────────────────────────────────────────┐
│              ECS Task Definition                             │
│  - Image: ecs-node-app:latest                                │
│  - Command: ["node", "jobs/cleanup.js"]                      │
│  - CPU: 256, Memory: 512                                     │
└─────────────────────────────────────────────────────────────┘
                        ↓ (runs in)
┌─────────────────────────────────────────────────────────────┐
│              ECS Cluster (Fargate)                           │
│  - Task starts at scheduled time                             │
│  - Runs job to completion                                    │
│  - Exits with code 0 or 1                                    │
│  - Task stops (no cost until next run)                       │
└─────────────────────────────────────────────────────────────┘
                        ↓ (logs to)
┌─────────────────────────────────────────────────────────────┐
│            CloudWatch Logs                                   │
│  /aws/ecs/staging-cron-jobs                                  │
└─────────────────────────────────────────────────────────────┘
```

---

### Terraform Implementation

#### Step 1: Create Cron Job Task Definition

```hcl
# staging-infrastructure/node_app_cron_jobs.tf

# ========================================
# CRON JOB: Database Cleanup (Daily 2 AM)
# ========================================

resource "aws_ecs_task_definition" "db_cleanup_job" {
  family                   = "${var.env}-db-cleanup-job"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"   # 0.25 vCPU
  memory                   = "512"   # 512 MB
  execution_role_arn       = module.ecs_task_execution_role.role_arn
  task_role_arn            = module.ecs_task_role.role_arn

  container_definitions = jsonencode([
    {
      name      = "db-cleanup"
      image     = "${module.ecr.repository_url}:latest"
      essential = true
      
      # Override command to run specific job
      command = ["node", "jobs/db-cleanup.js"]
      
      environment = [
        {
          name  = "NODE_ENV"
          value = var.env
        },
        {
          name  = "JOB_NAME"
          value = "db-cleanup"
        }
      ]
      
      # Load secrets from Secrets Manager
      secrets = [
        {
          name      = "DB_USERNAME"
          valueFrom = "${module.secret_store.secret_arn}:db_username::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${module.secret_store.secret_arn}:db_password::"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/aws/ecs/${var.env}-cron-jobs"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "db-cleanup"
        }
      }
    }
  ])

  tags = {
    Environment = var.env
    ManagedBy   = "Terraform"
    JobType     = "Cron"
  }
}

# ========================================
# CloudWatch Log Group for Cron Jobs
# ========================================

resource "aws_cloudwatch_log_group" "cron_jobs" {
  name              = "/aws/ecs/${var.env}-cron-jobs"
  retention_in_days = 30

  tags = {
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

# ========================================
# EventBridge Rule: Daily at 2 AM UTC
# ========================================

resource "aws_cloudwatch_event_rule" "db_cleanup_schedule" {
  name                = "${var.env}-db-cleanup-daily"
  description         = "Run database cleanup job daily at 2 AM UTC"
  schedule_expression = "cron(0 2 * * ? *)"  # 2 AM UTC daily

  tags = {
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

# ========================================
# EventBridge Target: Run ECS Task
# ========================================

resource "aws_cloudwatch_event_target" "db_cleanup_target" {
  rule      = aws_cloudwatch_event_rule.db_cleanup_schedule.name
  target_id = "db-cleanup-ecs-task"
  arn       = module.ecs_cluster.cluster_arn
  role_arn  = aws_iam_role.eventbridge_ecs_role.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.db_cleanup_job.arn
    launch_type         = "FARGATE"
    platform_version    = "LATEST"

    network_configuration {
      subnets          = module.vpc.private_subnet_ids
      security_groups  = [aws_security_group.cron_jobs.id]
      assign_public_ip = false
    }
  }
}

# ========================================
# IAM Role: EventBridge to Run ECS Tasks
# ========================================

resource "aws_iam_role" "eventbridge_ecs_role" {
  name = "${var.env}-eventbridge-ecs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy" "eventbridge_ecs_policy" {
  role = aws_iam_role.eventbridge_ecs_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask"
        ]
        Resource = [
          aws_ecs_task_definition.db_cleanup_job.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          module.ecs_task_execution_role.role_arn,
          module.ecs_task_role.role_arn
        ]
      }
    ]
  })
}

# ========================================
# Security Group for Cron Jobs
# ========================================

resource "aws_security_group" "cron_jobs" {
  name        = "${var.env}-cron-jobs-sg"
  description = "Security group for scheduled ECS cron jobs"
  vpc_id      = module.vpc.vpc_id

  # Allow outbound internet access (for DB connections, API calls)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.env}-cron-jobs-sg"
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}
```

---

### Node.js Job Implementation

#### jobs/db-cleanup.js

```javascript
// jobs/db-cleanup.js
const { Client } = require('pg');

async function runCleanup() {
  const client = new Client({
    host: process.env.DB_HOST,
    port: process.env.DB_PORT || 5432,
    database: process.env.DB_NAME,
    user: process.env.DB_USERNAME,     // From Secrets Manager
    password: process.env.DB_PASSWORD, // From Secrets Manager
  });

  try {
    await client.connect();
    console.log('✅ Connected to database');

    // Delete records older than 90 days
    const result = await client.query(`
      DELETE FROM audit_logs 
      WHERE created_at < NOW() - INTERVAL '90 days'
      RETURNING id
    `);

    console.log(`✅ Deleted ${result.rowCount} old audit log records`);

    // Vacuum the table
    await client.query('VACUUM ANALYZE audit_logs');
    console.log('✅ Vacuumed audit_logs table');

    await client.end();
    console.log('✅ Cleanup completed successfully');
    
    process.exit(0); // Success
  } catch (error) {
    console.error('❌ Cleanup failed:', error);
    process.exit(1); // Failure (will show in EventBridge metrics)
  }
}

runCleanup();
```

---

### Cron Expression Examples

```hcl
# Every day at 2 AM UTC
schedule_expression = "cron(0 2 * * ? *)"

# Every Monday at 8 AM UTC
schedule_expression = "cron(0 8 ? * MON *)"

# Every 6 hours
schedule_expression = "cron(0 */6 * * ? *)"

# Every 15 minutes
schedule_expression = "cron(*/15 * * * ? *)"

# First day of every month at midnight
schedule_expression = "cron(0 0 1 * ? *)"

# Every weekday at 9 AM UTC
schedule_expression = "cron(0 9 ? * MON-FRI *)"

# Using rate (simpler for regular intervals)
schedule_expression = "rate(1 hour)"   # Every hour
schedule_expression = "rate(30 minutes)" # Every 30 min
schedule_expression = "rate(1 day)"    # Every day
```

**AWS Cron Format**: `cron(Minutes Hours Day-of-month Month Day-of-week Year)`

**Important**: 
- Use `?` for Day-of-month or Day-of-week (whichever you don't use)
- All times are in **UTC**

---

## Method 2: In-Container Cron (node-cron)

### 🎯 When to Use
- **Frequent light tasks** (every minute, every 5 minutes)
- **Jobs that need shared state** with main application
- **Simple scheduling** without infrastructure overhead
- **Low latency requirements** (no cold start)

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│          ECS Service (Long-Running Container)                │
│  ┌────────────────────────────────────────────────────┐     │
│  │  Node.js Application                               │     │
│  │  ┌──────────────────────────────────────────┐      │     │
│  │  │  Express API (Port 3000)                 │      │     │
│  │  │  - GET /api/users                        │      │     │
│  │  │  - POST /api/orders                      │      │     │
│  │  └──────────────────────────────────────────┘      │     │
│  │                    +                                │     │
│  │  ┌──────────────────────────────────────────┐      │     │
│  │  │  node-cron Scheduler                     │      │     │
│  │  │  - Every 5 min: Cache refresh            │      │     │
│  │  │  - Every hour: Session cleanup           │      │     │
│  │  │  - Daily 3 AM: Generate reports          │      │     │
│  │  └──────────────────────────────────────────┘      │     │
│  └────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

---

### Implementation

#### 1. Install node-cron

```bash
npm install node-cron
```

#### 2. Create Cron Job Manager

```javascript
// jobs/scheduler.js
const cron = require('node-cron');
const { refreshCache } = require('./tasks/cache-refresh');
const { cleanupSessions } = require('./tasks/session-cleanup');
const { generateDailyReport } = require('./tasks/daily-report');

function initializeScheduledJobs() {
  console.log('🕐 Initializing scheduled jobs...');

  // ========================================
  // Job 1: Refresh cache every 5 minutes
  // ========================================
  cron.schedule('*/5 * * * *', async () => {
    console.log('🔄 Running cache refresh...');
    try {
      await refreshCache();
      console.log('✅ Cache refresh completed');
    } catch (error) {
      console.error('❌ Cache refresh failed:', error);
    }
  }, {
    timezone: "UTC"
  });

  // ========================================
  // Job 2: Clean up expired sessions hourly
  // ========================================
  cron.schedule('0 * * * *', async () => {
    console.log('🧹 Running session cleanup...');
    try {
      await cleanupSessions();
      console.log('✅ Session cleanup completed');
    } catch (error) {
      console.error('❌ Session cleanup failed:', error);
    }
  }, {
    timezone: "UTC"
  });

  // ========================================
  // Job 3: Generate daily report at 3 AM UTC
  // ========================================
  cron.schedule('0 3 * * *', async () => {
    console.log('📊 Running daily report generation...');
    try {
      await generateDailyReport();
      console.log('✅ Daily report completed');
    } catch (error) {
      console.error('❌ Daily report failed:', error);
    }
  }, {
    timezone: "UTC"
  });

  console.log('✅ Scheduled jobs initialized');
}

module.exports = { initializeScheduledJobs };
```

#### 3. Integrate with Main App

```javascript
// app.js
const express = require('express');
const { initializeScheduledJobs } = require('./jobs/scheduler');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.json());

// Routes
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.get('/api/users', (req, res) => {
  // ... API logic
});

// ========================================
// Start server and cron jobs
// ========================================
app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
  
  // Initialize cron jobs
  initializeScheduledJobs();
});
```

---

### Cron Syntax (node-cron)

```javascript
// Format: * * * * * (minute hour day month day-of-week)

// Every minute
cron.schedule('* * * * *', task);

// Every 5 minutes
cron.schedule('*/5 * * * *', task);

// Every hour at minute 0
cron.schedule('0 * * * *', task);

// Every day at 2:30 AM
cron.schedule('30 2 * * *', task);

// Every Monday at 9 AM
cron.schedule('0 9 * * 1', task);

// Every weekday at 10 AM
cron.schedule('0 10 * * 1-5', task);

// First day of month at midnight
cron.schedule('0 0 1 * *', task);
```

---

### ⚠️ Caveats of In-Container Cron

| Issue | Impact | Solution |
|-------|--------|----------|
| **Multiple Tasks** | If you run 2+ ECS tasks, cron runs in EACH task | Use distributed lock (Redis, DynamoDB) |
| **Job Failure** | Failure doesn't stop container; hard to detect | Use try/catch + CloudWatch metrics |
| **Mixed Logs** | Cron logs mixed with API logs | Use structured logging with job labels |
| **Resource Contention** | Heavy cron job blocks API requests | Use EventBridge → Separate ECS task instead |

---

### Preventing Duplicate Runs (Multiple Tasks)

```javascript
// jobs/tasks/daily-report.js
const Redis = require('ioredis');
const redis = new Redis(process.env.REDIS_URL);

async function generateDailyReport() {
  const lockKey = 'lock:daily-report';
  const lockDuration = 600; // 10 minutes

  // Try to acquire lock (only one task succeeds)
  const acquired = await redis.set(
    lockKey, 
    process.env.HOSTNAME, // Task ID
    'EX', lockDuration,
    'NX'  // Only set if not exists
  );

  if (!acquired) {
    console.log('⏩ Another task is running this job, skipping');
    return;
  }

  try {
    console.log('🔒 Lock acquired, running job...');
    
    // Generate report logic
    await performReportGeneration();
    
    console.log('✅ Report generated successfully');
  } finally {
    // Release lock
    await redis.del(lockKey);
    console.log('🔓 Lock released');
  }
}

module.exports = { generateDailyReport };
```

---

## Method 3: Lambda + EventBridge

### 🎯 When to Use
- **Simple, lightweight tasks** (< 15 minutes)
- **No shared dependencies** with main app
- **Maximum cost optimization** (pay per 100ms)
- **Serverless-first architecture**

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              AWS EventBridge                                 │
│  schedule_expression = "cron(0 2 * * ? *)"                  │
└─────────────────────────────────────────────────────────────┘
                        ↓ (triggers)
┌─────────────────────────────────────────────────────────────┐
│              AWS Lambda Function                             │
│  - Runtime: Node.js 20.x                                     │
│  - Memory: 512 MB                                            │
│  - Timeout: 5 minutes                                        │
│  - Code: Simple cleanup logic                                │
└─────────────────────────────────────────────────────────────┘
```

### When NOT to Use Lambda

❌ **DO NOT** use Lambda if:
- Job runs > 15 minutes (Lambda max timeout)
- Need Docker environment (use ECS instead)
- Heavy dependencies (Lambda has 250 MB limit unzipped)
- Shared codebase with main app (code duplication)

**Recommendation**: For Node.js apps, use **EventBridge → ECS Task** to reuse codebase.

---

## 🏗️ Architecture Diagrams

### Complete Cron Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         AWS ACCOUNT                                           │
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                      EventBridge Rules                               │    │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │    │
│  │  │ Cache Refresh    │  │ DB Cleanup       │  │ Daily Report     │  │    │
│  │  │ (every 5 min)    │  │ (daily 2 AM)     │  │ (daily 3 AM)     │  │    │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│              ↓                      ↓                      ↓                 │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    ECS Task Definitions                              │    │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │    │
│  │  │ cache-refresh    │  │ db-cleanup       │  │ report-gen       │  │    │
│  │  │ task             │  │ task             │  │ task             │  │    │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│              ↓                      ↓                      ↓                 │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    ECS Cluster (Fargate)                             │    │
│  │  - Tasks run on schedule                                             │    │
│  │  - Each task runs independently                                      │    │
│  │  - Tasks stop after completion                                       │    │
│  │  - Logs to CloudWatch                                                │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│              ↓                                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    CloudWatch Logs                                   │    │
│  │  /aws/ecs/staging-cron-jobs                                          │    │
│  │  - Log streams per task execution                                    │    │
│  │  - 30 day retention                                                  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 💡 Best Practices

### 1. **Use Idempotent Jobs**

```javascript
// BAD: Not idempotent
async function processOrders() {
  const orders = await db.query('SELECT * FROM orders');
  for (const order of orders) {
    await sendEmail(order.email);
  }
}

// GOOD: Idempotent (can run multiple times safely)
async function processOrders() {
  const orders = await db.query(`
    SELECT * FROM orders 
    WHERE email_sent = false 
    AND created_at > NOW() - INTERVAL '1 hour'
  `);
  
  for (const order of orders) {
    await sendEmail(order.email);
    await db.query('UPDATE orders SET email_sent = true WHERE id = ?', [order.id]);
  }
}
```

---

### 2. **Exit with Proper Codes**

```javascript
// jobs/cleanup.js
async function runCleanup() {
  try {
    await performCleanup();
    console.log('✅ Success');
    process.exit(0); // EventBridge sees success
  } catch (error) {
    console.error('❌ Failed:', error);
    process.exit(1); // EventBridge sees failure
  }
}
```

---

### 3. **Add Job Timeout Protection**

```javascript
// jobs/cleanup.js
const JOB_TIMEOUT = 10 * 60 * 1000; // 10 minutes

setTimeout(() => {
  console.error('❌ Job timeout exceeded');
  process.exit(1);
}, JOB_TIMEOUT);

runCleanup();
```

---

### 4. **Use Structured Logging**

```javascript
const logger = {
  info: (msg, meta = {}) => {
    console.log(JSON.stringify({
      level: 'info',
      message: msg,
      job: process.env.JOB_NAME,
      timestamp: new Date().toISOString(),
      ...meta
    }));
  },
  error: (msg, error) => {
    console.error(JSON.stringify({
      level: 'error',
      message: msg,
      job: process.env.JOB_NAME,
      error: error.message,
      stack: error.stack,
      timestamp: new Date().toISOString()
    }));
  }
};

// Usage
logger.info('Starting cleanup', { recordCount: 1000 });
logger.error('Cleanup failed', error);
```

---

### 5. **Monitor Job Success/Failure**

```hcl
# Add CloudWatch Metric Alarm for failed jobs
resource "aws_cloudwatch_metric_alarm" "cron_job_failures" {
  alarm_name          = "${var.env}-cron-job-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FailedInvocations"
  namespace           = "AWS/Events"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Alert when cron job fails"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    RuleName = aws_cloudwatch_event_rule.db_cleanup_schedule.name
  }
}
```

---

## 🛠️ Troubleshooting

### Issue: Cron Job Not Running

**Check EventBridge Rule Status:**
```bash
aws events describe-rule \
  --name staging-db-cleanup-daily \
  --region eu-west-2
```

Look for `"State": "ENABLED"`

---

### Issue: Task Starts But Immediately Stops

**Check Task Logs:**
```bash
aws logs tail /aws/ecs/staging-cron-jobs --follow --since 1h
```

Common causes:
- Missing environment variables
- Database connection failure
- Invalid command in task definition

---

### Issue: In-Container Cron Running Multiple Times

**Cause**: Multiple ECS tasks running same cron

**Solution**: Use distributed lock (see Redis example above)

---

### Issue: Job Times Out

**Solution**: Increase task CPU/memory or optimize code

```hcl
resource "aws_ecs_task_definition" "heavy_job" {
  # ...
  cpu    = "1024"  # 1 vCPU (was 256)
  memory = "2048"  # 2 GB (was 512)
}
```

---

## 📌 Quick Reference

### EventBridge Cron vs. In-Container Cron

```
Use EventBridge → ECS Task when:
  ✅ Heavy processing (reports, ETL)
  ✅ Infrequent jobs (daily, weekly)
  ✅ Want to minimize costs
  ✅ Need isolated execution environment

Use In-Container node-cron when:
  ✅ Frequent jobs (every minute)
  ✅ Light processing (cache refresh)
  ✅ Need shared state with main app
  ✅ Want simpler setup
```

---

## 🔗 Related Documentation
- [How to Force Restart a Task](HowToForceRestartATask.md)
- [ECS Task Usage Guide](ECSTaskUsage.md)
- [ECS Auto Scaling Guide](ECSAutoScaling.md)
- [Parameter Store vs Secrets Manager](ParamStoreVsSecretsManager.md)

---

**Last Updated**: January 2026  
**Maintained By**: Infrastructure Team

