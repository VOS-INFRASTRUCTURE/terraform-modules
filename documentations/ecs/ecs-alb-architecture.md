# ECS + ALB Architecture

This document explains the production-ready architecture for the Node.js application using ECS Fargate with an Application Load Balancer.

---

## 📊 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                          Internet                                │
│                     (Users/Clients)                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTP/HTTPS
                              │ (Port 80/443)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Application Load Balancer                      │
│              (Public Subnets 3 & 4 - Multi-AZ)                   │
│                                                                  │
│  Security Group: staging-alb-node-app-sg                         │
│  - Ingress: HTTP (80), HTTPS (443) from 0.0.0.0/0              │
│  - Egress: All traffic to ECS tasks                             │
│                                                                  │
│  DNS: staging-node-app-alb-xxxxxxxxx.eu-west-2.elb.amazonaws.com│
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTP
                              │ (Port 3000)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Target Group                                │
│                   staging-node-app-tg                            │
│                                                                  │
│  Target Type: IP (Fargate)                                       │
│  Port: 3000                                                      │
│  Health Check: GET /health (every 30s)                           │
│  Deregistration Delay: 30s                                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │
            ┌─────────────────┴─────────────────┐
            │                                   │
            ▼                                   ▼
┌──────────────────────┐            ┌──────────────────────┐
│   ECS Task (AZ-a)    │            │   ECS Task (AZ-b)    │
│  Private Subnet 1    │            │  Private Subnet 2    │
│  10.0.0.x            │            │  10.0.1.x            │
│                      │            │                      │
│  Container:          │            │  Container:          │
│  - Node.js App       │            │  - Node.js App       │
│  - Port: 3000        │            │  - Port: 3000        │
│  - No Public IP      │            │  - No Public IP      │
│                      │            │                      │
│  Security Group:     │            │  Security Group:     │
│  ecs-node-app-sg     │            │  ecs-node-app-sg     │
│  - Ingress: Port     │            │  - Ingress: Port     │
│    3000 from ALB SG  │            │    3000 from ALB SG  │
└──────────────────────┘            └──────────────────────┘
            │                                   │
            │                                   │
            └─────────────────┬─────────────────┘
                              │
                              │ Outbound Internet
                              │ (ECR, CloudWatch, Updates)
                              ▼
                    ┌─────────────────┐
                    │   NAT Gateway   │
                    │ (Public Subnet) │
                    └─────────┬───────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ Internet Gateway│
                    └─────────────────┘
```

---

## 🔧 Component Breakdown

### 1. **Application Load Balancer (ALB)**

**Location:** Public Subnets 3 & 4 (Multi-AZ)

**Purpose:**
- Accepts HTTP/HTTPS traffic from the internet
- Distributes traffic across ECS tasks in private subnets
- Performs health checks on tasks
- Handles SSL/TLS termination (when HTTPS configured)

**Key Configuration:**
- **Type:** Application Load Balancer (Layer 7)
- **Scheme:** Internet-facing
- **Listeners:**
  - HTTP (Port 80) → Forwards to Target Group
  - HTTPS (Port 443) → Optional (requires SSL certificate)
- **Security Group:** `staging-alb-node-app-sg`
  - Allows HTTP (80) and HTTPS (443) from `0.0.0.0/0`
  - Allows all outbound traffic to reach ECS tasks

**Access URL:**
```
http://staging-node-app-alb-xxxxxxxxx.eu-west-2.elb.amazonaws.com
```

---

### 2. **Target Group**

**Name:** `staging-node-app-tg`

**Purpose:**
- Registers ECS task IPs automatically
- Routes traffic from ALB to healthy tasks
- Monitors task health via health checks

**Configuration:**
- **Target Type:** IP (required for Fargate)
- **Port:** 3000
- **Protocol:** HTTP
- **VPC:** staging VPC

**Health Check:**
- **Path:** `/health`
- **Interval:** 30 seconds
- **Timeout:** 5 seconds
- **Healthy Threshold:** 2 consecutive successes
- **Unhealthy Threshold:** 3 consecutive failures
- **Expected Response:** HTTP 200

**Deregistration Delay:** 30 seconds
- Time to drain connections before removing a task from the target group

---

### 3. **ECS Service**

**Name:** `staging-ecs-node-app-service`

**Location:** Private Subnets 1 & 2 (Multi-AZ)

**Purpose:**
- Maintains desired number of running tasks
- Automatically registers/deregisters tasks with target group
- Performs rolling deployments

**Configuration:**
- **Cluster:** staging-ecs-node-app-cluster
- **Launch Type:** Fargate
- **Desired Count:** 1 task
- **Network Mode:** awsvpc
- **Subnets:** Private Subnet 1, Private Subnet 2
- **Public IP:** Disabled (tasks are in private subnets)
- **Security Group:** `staging-ecs-node-app-sg`

**Load Balancer Integration:**
- **Target Group:** staging-node-app-tg
- **Container Name:** ecs-node-app-container
- **Container Port:** 3000

**Deployment Strategy:**
- **Minimum Healthy:** 50% (can drop to 0 tasks during deployment)
- **Maximum:** 200% (can run up to 2 tasks during deployment)
- **Health Check Grace Period:** 60 seconds

---

### 4. **ECS Tasks**

**Container Name:** `ecs-node-app-container`

**Location:** Private Subnets (No Public IP)

**Configuration:**
- **Image:** From ECR repository
- **CPU:** 256 units (0.25 vCPU)
- **Memory:** 1024 MB (1 GB)
- **Port:** 3000
- **Environment Variables:**
  - `NODE_ENV=production`
  - `PORT=3000`

**Network:**
- Private IP address only
- Outbound internet via NAT Gateway
- Inbound traffic only from ALB

**IAM Roles:**
- **Execution Role:** Pull images from ECR, write logs to CloudWatch
- **Task Role:** ECS Exec permissions for debugging

---

### 5. **Security Groups**

#### **ALB Security Group** (`staging-alb-node-app-sg`)

| Direction | Protocol | Port | Source/Destination | Purpose |
|-----------|----------|------|-------------------|---------|
| Ingress | TCP | 80 | 0.0.0.0/0 | HTTP from internet |
| Ingress | TCP | 443 | 0.0.0.0/0 | HTTPS from internet |
| Egress | All | All | 0.0.0.0/0 | To ECS tasks and internet |

#### **ECS Security Group** (`staging-ecs-node-app-sg`)

| Direction | Protocol | Port | Source/Destination | Purpose |
|-----------|----------|------|-------------------|---------|
| Ingress | TCP | 3000 | ALB Security Group | HTTP from ALB only |
| Egress | All | All | 0.0.0.0/0 | ECR, CloudWatch, external APIs |

---

## 🔒 Security Benefits

### 🎯 Defense in Depth

```
Layer 1: ALB (Public)
  ✅ Accepts traffic from internet
  ✅ SSL/TLS termination (when HTTPS configured)
  ✅ WAF integration (optional - add AWS WAF rules)
  
Layer 2: Security Groups
  ✅ ECS tasks only accept traffic from ALB
  ✅ No direct internet access to tasks
  
Layer 3: Private Subnets
  ✅ ECS tasks have no public IPs
  ✅ Cannot be reached from internet
  ✅ Outbound only via NAT Gateway
```

### 🔐 Attack Surface Reduction

| Component | Public Access | Inbound Internet | Outbound Internet |
|-----------|---------------|------------------|-------------------|
| **ALB** | ✅ Yes | ✅ Yes | ✅ Yes |
| **ECS Tasks** | ❌ No | ❌ No | ✅ Yes (via NAT) |
| **Databases** | ❌ No | ❌ No | ✅ Yes (via NAT) |

---

## 🚀 Traffic Flow

### Inbound (User Request)

```
1. User Browser
   ↓ HTTP/HTTPS request
2. DNS Resolution (ALB DNS name)
   ↓ Resolves to ALB IPs
3. Application Load Balancer (Public Subnets)
   ↓ Selects healthy target
4. Target Group
   ↓ Routes to task IP
5. ECS Task (Private Subnet)
   ↓ Container processes request
6. Response flows back through ALB
   ↓
7. User receives response
```

### Outbound (Task to Internet)

```
1. ECS Task (Private Subnet)
   ↓ Makes outbound request
2. Private Route Table
   ↓ Routes to NAT Gateway
3. NAT Gateway (Public Subnet)
   ↓ Translates to public IP
4. Internet Gateway
   ↓ Sends to internet
5. External Service (ECR, API, etc.)
```

---

## 📊 High Availability

### Multi-AZ Deployment

- **ALB:** Deployed in 2 availability zones (eu-west-2a, eu-west-2b)
- **ECS Tasks:** Can run in either AZ (currently 1 task)
- **Target Group:** Automatically registers tasks in both AZs

### Automatic Failover

```
┌─────────────────────────────────────────┐
│ Task in AZ-a becomes unhealthy          │
│   ↓                                     │
│ ALB health check detects failure        │
│   ↓                                     │
│ ALB stops routing traffic to task       │
│   ↓                                     │
│ ECS Service detects unhealthy task      │
│   ↓                                     │
│ New task starts in AZ-a or AZ-b         │
│   ↓                                     │
│ ALB routes traffic to new healthy task  │
└─────────────────────────────────────────┘
```

### Scaling (Future)

**Horizontal Scaling:**
```terraform
# Increase desired_count in node_app_service.tf.bak
desired_count = 3

# Tasks will be distributed across AZs
# ALB automatically balances traffic
```

**Auto-scaling:**
```terraform
# Add auto-scaling target
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 10
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.node_app_cluster.name}/${aws_ecs_service.node_app_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale based on CPU
resource "aws_appautoscaling_policy" "ecs_cpu_policy" {
  # Scale out when CPU > 70%
  # Scale in when CPU < 30%
}
```

---

## 🧪 Testing the Setup

### 1. Get ALB DNS Name

After `terraform apply`, get the ALB DNS name:

```bash
terraform output alb_dns_name
```

**Example Output:**
```
staging-node-app-alb-1234567890.eu-west-2.elb.amazonaws.com
```

### 2. Test HTTP Access

```bash
# Health check
curl http://<ALB-DNS-NAME>/health

# Main endpoint
curl http://<ALB-DNS-NAME>/

# Check headers
curl -I http://<ALB-DNS-NAME>/
```

### 3. Verify Load Balancing

```bash
# Scale to multiple tasks
# terraform: desired_count = 2
# terraform apply

# Make multiple requests
for i in {1..10}; do
  curl http://<ALB-DNS-NAME>/
  echo ""
done

# Should see different task IPs/hostnames if your app returns them
```

### 4. Test Health Checks

```bash
# Watch target group health in AWS Console
# ECS → Clusters → staging-ecs-node-app-cluster → Services → staging-ecs-node-app-service → Target Groups

# View registered targets
aws elbv2 describe-target-health \
  --target-group-arn <TARGET-GROUP-ARN> \
  --region eu-west-2
```

---

## 🔍 Monitoring & Troubleshooting

### CloudWatch Logs

**Log Groups:**
- `/ecs/staging-ecs-node-app` - Application logs
- `/aws/ecs/containerinsights/staging-ecs-node-app-cluster/performance` - Container Insights

### ALB Metrics

**CloudWatch Metrics:**
- `TargetResponseTime` - How long tasks take to respond
- `HealthyHostCount` - Number of healthy targets
- `UnHealthyHostCount` - Number of unhealthy targets
- `RequestCount` - Total requests
- `HTTPCode_Target_2XX_Count` - Successful responses

### Common Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| **503 Service Unavailable** | No healthy targets | Check task logs, verify `/health` endpoint works |
| **Connection Timeout** | ALB can't reach tasks | Check security groups, verify tasks are running |
| **Task Failing Health Checks** | Task keeps restarting | Check application logs, increase health check timeout |
| **Can't Pull Image** | Task stuck in PENDING | Verify NAT Gateway exists, check ECR permissions |

---

## 💰 Cost Breakdown

| Component | Quantity | Cost/Month (Approx) |
|-----------|----------|---------------------|
| **Application Load Balancer** | 1 | $16.20 |
| **ALB LCU Hours** | Variable | ~$5-20 |
| **ECS Fargate (0.25 vCPU, 1GB)** | 1 task | ~$10 |
| **NAT Gateway** | 1 | $32.40 |
| **Data Transfer (NAT)** | Variable | $0.045/GB |
| **CloudWatch Logs** | 5GB/month | ~$2.50 |
| **Total (Estimated)** | - | **~$70-90/month** |

**Notes:**
- LCU (Load Balancer Capacity Units) based on traffic volume
- Fargate cost scales linearly with task count
- Data transfer costs vary by usage

---

## 🎯 Production Recommendations

### 1. **Enable HTTPS** ✅
```terraform
# Get SSL certificate from ACM (AWS Certificate Manager)
# Uncomment HTTPS listener in node_app_alb.tf.bak
# Redirect HTTP to HTTPS
```

### 2. **Add WAF** 🔒
```terraform
# Add AWS WAF Web ACL to ALB
# Protect against common attacks (SQL injection, XSS, etc.)
```

### 3. **Enable Access Logs** 📊
```terraform
# Log all ALB requests to S3
# Useful for debugging and compliance
```

### 4. **Add Auto-scaling** 📈
```terraform
# Scale based on CPU, memory, or request count
# min_capacity = 2, max_capacity = 10
```

### 5. **Add Second NAT Gateway** 🔧
```terraform
# One NAT Gateway per AZ for high availability
# Eliminates single point of failure
```

### 6. **Container Insights** 👁️
```terraform
# Enable ECS Container Insights for detailed metrics
# CPU, memory, network per task
```

---

## 📚 Related Files

- `node_app_alb.tf` - ALB, target group, listeners
- `node_app_service.tf` - ECS service configuration
- `node_app_security_group.tf` - ECS security group
- `node_app_task_definition.tf` - Container specifications
- `networking.tf` - VPC, subnets, NAT Gateway

---

## ✅ Summary

Your Node.js application now has a **production-ready architecture**:

✅ **Security:**
- ECS tasks in private subnets (no public IPs)
- Only ALB can reach tasks
- ALB handles internet traffic

✅ **High Availability:**
- Multi-AZ deployment
- Automatic health checks and failover
- Zero-downtime deployments

✅ **Scalability:**
- Easy to add more tasks
- ALB distributes traffic automatically
- Can add auto-scaling

✅ **Outbound Internet:**
- Tasks can reach ECR, CloudWatch, external APIs
- Via NAT Gateway (secure outbound only)

**Access your application:**
```
http://<ALB-DNS-NAME>/
```

🎉 Your application is now secure, scalable, and production-ready!

