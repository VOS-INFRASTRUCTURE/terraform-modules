# VPC Network Architecture

This document provides a visual representation of the staging infrastructure VPC network architecture, including all subnets, routing, and internet connectivity components.

---

## 📊 Complete Network Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                      Internet                                            │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                                          ▲  │
                                          │  │
                                          │  └─────────────────────────┐
                                          │                            │
                        ┌─────────────────┴──────────────┐             │
                        │   Internet Gateway (IGW)        │             │
                        │   (Bidirectional traffic)       │             │
                        └─────────────────┬──────────────┘             │
                                          │                            │
                                          │                            │
        ┌─────────────────────────────────┼────────────────────────────┼──────────────────┐
        │                       VPC (10.0.0.0/16)                      │                  │
        │                                 │                            │                  │
        │  ┌──────────────────────────────┼────────────────────────────┼────────────────┐ │
        │  │            Public Route Table                             │                │ │
        │  │  Route: 0.0.0.0/0 → IGW                                   │                │ │
        │  │  Route: 10.0.0.0/16 → local                               │                │ │
        │  └──────────────────────────────┼────────────────────────────┼────────────────┘ │
        │                                 │                            │                  │
        │         ┌───────────────────────┼────────────┐               │                  │
        │         │                       │            │               │                  │
        │  ┌──────▼──────────┐     ┌──────▼──────────┐│               │                  │
        │  │ Public Subnet 3 │     │ Public Subnet 4 ││               │                  │
        │  │ 10.0.2.0/24     │     │ 10.0.3.0/24     ││               │                  │
        │  │ AZ: eu-west-2a  │     │ AZ: eu-west-2b  ││               │                  │
        │  │                 │     │                 ││               │                  │
        │  │  ┌───────────┐  │     │                 ││               │                  │
        │  │  │ NAT GW    │  │     │                 ││               │                  │
        │  │  │ Elastic IP│  │     │                 ││               │                  │
        │  │  │ (Static)  │◄─┼─────┼─────────────────┼┼───────────────┘                  │
        │  │  └─────┬─────┘  │     │                 ││  Outbound traffic from           │
        │  │        │        │     │                 ││  private subnets                 │
        │  │  Resources:     │     │  Resources:     ││                                  │
        │  │  - ECS Tasks    │     │  - ECS Tasks    ││                                  │
        │  │  - ALB          │     │  - ALB          ││                                  │
        │  │  - Bastion      │     │  - Bastion      ││                                  │
        │  └─────────────────┘     └─────────────────┘│                                  │
        │                                             │                                  │
        │  ┌────────────────────────────────────────────────────────────────────┐        │
        │  │            Private Route Table                                     │        │
        │  │  Route: 0.0.0.0/0 → NAT Gateway (outbound only)                    │        │
        │  │  Route: 10.0.0.0/16 → local                                        │        │
        │  └────────────────────────┬───────────────────────┬────────────────────┘        │
        │                           │                       │                            │
        │                    ┌──────▼──────────┐     ┌──────▼──────────┐                 │
        │                    │ Private Subnet 1│     │ Private Subnet 2│                 │
        │                    │ 10.0.0.0/24     │     │ 10.0.1.0/24     │                 │
        │                    │ AZ: eu-west-2a  │     │ AZ: eu-west-2b  │                 │
        │                    │                 │     │                 │                 │
        │                    │  Resources:     │     │  Resources:     │                 │
        │                    │  - RDS          │     │  - RDS          │                 │
        │                    │  - ElastiCache  │     │  - ElastiCache  │                 │
        │                    │  - EC2 (DB/App) │     │  - EC2 (DB/App) │                 │
        │                    │  - Lambda       │     │  - Lambda       │                 │
        │                    │                 │     │                 │                 │
        │                    │  Internet:      │     │  Internet:      │                 │
        │                    │  ✅ Outbound   │     │  ✅ Outbound   │                 │
        │                    │  ❌ Inbound    │     │  ❌ Inbound    │                 │
        │                    └─────────────────┘     └─────────────────┘                 │
        │                                                                                 │
        └─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🏗️ Network Components

### 1. **VPC (Virtual Private Cloud)**
- **CIDR Block:** `10.0.0.0/16`
- **DNS Support:** Enabled
- **DNS Hostnames:** Enabled
- **Purpose:** Isolated virtual network for all staging resources

---

### 2. **Internet Gateway (IGW)**
- **Purpose:** Enables bidirectional communication between VPC and the internet
- **Attached to:** VPC
- **Used by:** Public subnets for direct internet access

---

### 3. **NAT Gateway**
- **Location:** Public Subnet 3 (10.0.2.0/24)
- **Elastic IP:** Static public IP address
- **Purpose:** Allows private subnets to initiate outbound connections to the internet
- **Security:** Blocks all inbound connections from the internet
- **Cost:** ~$32.40/month + data transfer fees

---

### 4. **Subnets**

#### **Public Subnets** (Internet-Accessible)

| Subnet | CIDR Block | Availability Zone | Route to Internet | Public IPs |
|--------|------------|-------------------|-------------------|------------|
| **Public Subnet 3** | 10.0.2.0/24 | eu-west-2a | Internet Gateway | Auto-assigned |
| **Public Subnet 4** | 10.0.3.0/24 | eu-west-2b | Internet Gateway | Auto-assigned |

**Use Cases:**
- ECS Fargate tasks (when testing/development)
- Application Load Balancers (ALB)
- Bastion hosts
- NAT Gateway
- Resources that need direct internet access

**Traffic Flow:**
- ✅ **Inbound:** Internet → IGW → Public Subnet
- ✅ **Outbound:** Public Subnet → IGW → Internet

---

#### **Private Subnets** (Protected)

| Subnet | CIDR Block | Availability Zone | Route to Internet | Public IPs |
|--------|------------|-------------------|-------------------|------------|
| **Private Subnet 1** | 10.0.0.0/24 | eu-west-2a | NAT Gateway | None |
| **Private Subnet 2** | 10.0.1.0/24 | eu-west-2b | NAT Gateway | None |

**Use Cases:**
- RDS databases
- ElastiCache clusters
- EC2 instances (application servers, databases)
- Lambda functions
- ECS tasks (production - for enhanced security)
- Any resource that should NOT be directly accessible from the internet

**Traffic Flow:**
- ❌ **Inbound:** Blocked (no route from internet)
- ✅ **Outbound:** Private Subnet → NAT Gateway → IGW → Internet

---

### 5. **Route Tables**

#### **Public Route Table**

| Destination | Target | Purpose |
|-------------|--------|---------|
| `10.0.0.0/16` | local | Intra-VPC communication |
| `0.0.0.0/0` | Internet Gateway | All internet traffic |

**Associated Subnets:**
- Public Subnet 3
- Public Subnet 4

---

#### **Private Route Table**

| Destination | Target | Purpose |
|-------------|--------|---------|
| `10.0.0.0/16` | local | Intra-VPC communication |
| `0.0.0.0/0` | NAT Gateway | Outbound internet traffic only |

**Associated Subnets:**
- Private Subnet 1
- Private Subnet 2

---

## 🔒 Security Model

### Traffic Flow Patterns

```
┌─────────────────────────────────────────────────────────────────┐
│ Inbound Internet Traffic                                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ Internet Gateway│
                    └─────────┬───────┘
                              │
                    ┌─────────▼─────────┐
                    │  Public Subnets    │
                    │  (ALB, Bastion)    │
                    └─────────┬─────────┘
                              │
                   Internal VPC routing
                              │
                    ┌─────────▼─────────┐
                    │ Private Subnets    │
                    │ (DB, App servers)  │
                    └───────────────────┘
```

```
┌─────────────────────────────────────────────────────────────────┐
│ Outbound Internet Traffic (from Private Subnets)                │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │
                    ┌─────────┴─────────┐
                    │ Private Subnets    │
                    │ (DB, App servers)  │
                    └─────────┬─────────┘
                              │
                    ┌─────────▼─────────┐
                    │   NAT Gateway      │
                    │ (Public Subnet 3)  │
                    └─────────┬─────────┘
                              │
                    ┌─────────▼─────────┐
                    │ Internet Gateway   │
                    └─────────┬─────────┘
                              │
                              ▼
                         Internet
```

---

## 🎯 High Availability Design

### Multi-AZ Architecture

- **Availability Zone 1 (eu-west-2a):**
  - Public Subnet 3 (10.0.2.0/24)
  - Private Subnet 1 (10.0.0.0/24)
  - NAT Gateway

- **Availability Zone 2 (eu-west-2b):**
  - Public Subnet 4 (10.0.3.0/24)
  - Private Subnet 2 (10.0.1.0/24)

**Benefits:**
- ✅ Fault tolerance across availability zones
- ✅ Automatic failover for multi-AZ resources (RDS, ElastiCache)
- ✅ Load balancing across AZs
- ⚠️ **Note:** Only one NAT Gateway (single point of failure for outbound traffic)

### 💡 Production Recommendation: Add Second NAT Gateway

For production high availability, add a second NAT Gateway:

```
Private Subnet 1 (AZ-a) → NAT Gateway 1 (Public Subnet 3, AZ-a)
Private Subnet 2 (AZ-b) → NAT Gateway 2 (Public Subnet 4, AZ-b)
```

**Additional Cost:** ~$32.40/month per NAT Gateway
**Benefit:** Eliminates single point of failure for outbound internet access

---

## 📍 IP Address Allocation

| Subnet | CIDR | Usable IPs | First IP | Last IP | Reserved IPs |
|--------|------|------------|----------|---------|--------------|
| **VPC** | 10.0.0.0/16 | 65,536 | - | - | - |
| **Private Subnet 1** | 10.0.0.0/24 | 251 | 10.0.0.4 | 10.0.0.254 | 5 (AWS reserved) |
| **Private Subnet 2** | 10.0.1.0/24 | 251 | 10.0.1.4 | 10.0.1.254 | 5 (AWS reserved) |
| **Public Subnet 3** | 10.0.2.0/24 | 251 | 10.0.2.4 | 10.0.2.254 | 5 (AWS reserved) |
| **Public Subnet 4** | 10.0.3.0/24 | 251 | 10.0.3.4 | 10.0.3.254 | 5 (AWS reserved) |

**AWS Reserved IPs (per subnet):**
- `.0` - Network address
- `.1` - VPC router
- `.2` - DNS server
- `.3` - Future use
- `.255` - Broadcast address

---

## 🔍 Common Use Cases

### Use Case 1: ECS Fargate Tasks

**Testing/Development:**
```
ECS Task → Public Subnet → Public IP assigned → Direct internet access
```

**Production (Recommended):**
```
ECS Task → Private Subnet → NAT Gateway → Internet (outbound only)
ALB → Public Subnet → Routes traffic to ECS tasks in private subnets
```

---

### Use Case 2: RDS Database

```
RDS Instance → Private Subnet 1 & 2 (Multi-AZ)
             → No public IP
             → Accessible only from VPC resources
             → Can download updates via NAT Gateway
```

---

### Use Case 3: Application Load Balancer + Backend

```
Internet → IGW → ALB (Public Subnet) → Target Group → ECS/EC2 (Private Subnet)
                                                      ↓
                                          RDS (Private Subnet)
```

---

## 💰 Cost Breakdown

| Component | Quantity | Cost/Month (Approx) |
|-----------|----------|---------------------|
| **VPC** | 1 | Free |
| **Internet Gateway** | 1 | Free |
| **Subnets** | 4 | Free |
| **Route Tables** | 2 | Free |
| **NAT Gateway** | 1 | $32.40 |
| **Elastic IP (NAT)** | 1 | Free (when attached) |
| **Data Transfer (NAT)** | Variable | $0.045/GB |
| **Total (Fixed)** | - | ~$32.40 |

**Additional Costs:**
- Data transfer through NAT Gateway: $0.045/GB
- Data transfer out to internet: $0.09/GB (first 10TB)

---

## 🛠️ Terraform Resources

| Component | Resource Name | Terraform Resource |
|-----------|---------------|-------------------|
| VPC | `main` | `aws_vpc.main` |
| Internet Gateway | `main` | `aws_internet_gateway.main` |
| NAT Gateway | `main` | `aws_nat_gateway.main` |
| NAT EIP | `nat` | `aws_eip.nat` |
| Public Route Table | `public` | `aws_route_table.public` |
| Private Route Table | `private` | `aws_route_table.private` |
| Public Subnet 3 | `public_subnet3` | `aws_subnet.public_subnet3` |
| Public Subnet 4 | `public_subnet4` | `aws_subnet.public_subnet4` |
| Private Subnet 1 | `private_subnet1` | `aws_subnet.private_subnet1` |
| Private Subnet 2 | `private_subnet2` | `aws_subnet.private_subnet2` |

---

## 🧪 Testing Connectivity

### Test Public Subnet Connectivity
```bash
# SSH to instance in public subnet
ssh ec2-user@<public-ip>

# Test outbound internet
curl -I https://www.google.com
```

### Test Private Subnet Connectivity
```bash
# SSH to bastion in public subnet first
ssh ec2-user@<bastion-public-ip>

# Then SSH to private instance
ssh ec2-user@<private-ip>

# Test outbound internet (via NAT Gateway)
curl -I https://www.google.com

# Test inbound (should fail)
# Try to SSH directly from internet → will fail ✅
```

---

## 📚 Additional Resources

- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/)
- [AWS NAT Gateway Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)
- [AWS Subnet Sizing](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Subnets.html)
- [VPC Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-best-practices.html)

---

## 🔄 Future Enhancements

1. **Add Second NAT Gateway** (High Availability)
   - Place in Public Subnet 4 (AZ-b)
   - Update Private Route Table to use AZ-specific NAT Gateways
   - Cost: Additional $32.40/month

2. **Add VPC Endpoints** (Cost Optimization)
   - S3 Gateway Endpoint (Free)
   - ECR Interface Endpoints (~$7/month)
   - CloudWatch Logs Interface Endpoint (~$7/month)
   - Reduces NAT Gateway data transfer costs

3. **Add VPC Flow Logs** (Security Monitoring)
   - Monitor network traffic patterns
   - Detect anomalies and security threats
   - Store in CloudWatch Logs or S3

4. **Implement Network ACLs** (Additional Security Layer)
   - Subnet-level firewall rules
   - Complement security groups
   - Deny specific IP ranges or protocols

