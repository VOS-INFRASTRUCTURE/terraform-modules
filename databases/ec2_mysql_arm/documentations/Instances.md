# AWS EC2 Instance Types Comparison for MySQL (ARM vs x86)

Complete comparison of all EC2 instance types suitable for MySQL databases, comparing ARM (Graviton) against x86 (Intel/AMD) alternatives.

---

## Table of Contents

1. [T-Series: Burstable Performance](#t-series-burstable-performance)
2. [M-Series: General Purpose](#m-series-general-purpose)
3. [R-Series: Memory Optimized](#r-series-memory-optimized)
4. [C-Series: Compute Optimized](#c-series-compute-optimized)
5. [Quick Selection Guide](#quick-selection-guide)
6. [Cost Summary](#cost-summary)

---

## T-Series: Burstable Performance

**Best for:** Development, Testing, Staging, Small Production (variable load)

### ARM (Graviton) - t4g Family

| Instance Type | vCPU | RAM | Baseline CPU | Burst CPU | Network (Gbps) | EBS (Gbps) | Price ($/month)* | Best For |
|--------------|------|-----|--------------|-----------|----------------|------------|------------------|----------|
| **t4g.micro** | 2 | 1 GB | 10% | 100% | Up to 5 | Up to 2.085 | **$6.13** | Dev/Testing |
| **t4g.small** | 2 | 2 GB | 20% | 100% | Up to 5 | Up to 2.085 | **$12.26** | Dev/Small Staging |
| **t4g.medium** | 2 | 4 GB | 20% | 100% | Up to 5 | Up to 2.085 | **$24.53** | **Staging/Light Prod** ⭐ |
| **t4g.large** | 2 | 8 GB | 30% | 100% | Up to 5 | Up to 2.780 | **$49.06** | **Small Production** ⭐ |
| **t4g.xlarge** | 4 | 16 GB | 40% | 100% | Up to 5 | Up to 2.780 | **$98.11** | Medium Production |
| **t4g.2xlarge** | 8 | 32 GB | 40% | 100% | Up to 5 | Up to 2.780 | **$196.22** | Large Databases |

### x86 (Intel) - t3 Family

| Instance Type | vCPU | RAM | Baseline CPU | Burst CPU | Network (Gbps) | EBS (Gbps) | Price ($/month)* | vs ARM |
|--------------|------|-----|--------------|-----------|----------------|------------|------------------|--------|
| **t3.micro** | 2 | 1 GB | 10% | 100% | Up to 5 | Up to 2.085 | **$7.59** | +24% |
| **t3.small** | 2 | 2 GB | 20% | 100% | Up to 5 | Up to 2.085 | **$15.18** | +24% |
| **t3.medium** | 2 | 4 GB | 20% | 100% | Up to 5 | Up to 2.085 | **$30.37** | +24% |
| **t3.large** | 2 | 8 GB | 30% | 100% | Up to 5 | Up to 2.780 | **$60.74** | +24% |
| **t3.xlarge** | 4 | 16 GB | 40% | 100% | Up to 5 | Up to 2.780 | **$121.47** | +24% |
| **t3.2xlarge** | 8 | 32 GB | 40% | 100% | Up to 5 | Up to 2.780 | **$242.93** | +24% |

**CPU Credits:**
- t4g.micro: 12 credits/hour (10% baseline)
- t4g.small: 24 credits/hour (20% baseline)
- t4g.medium: 24 credits/hour (20% baseline)
- t4g.large: 36 credits/hour (30% baseline)

---

## M-Series: General Purpose

**Best for:** Medium to Large Production, General Workloads, Balanced CPU/Memory

### ARM (Graviton) - m7g Family

| Instance Type | vCPU | RAM | Network (Gbps) | EBS (Gbps) | Price ($/month)* | Buffer Pool** | Best For |
|--------------|------|-----|----------------|------------|------------------|---------------|----------|
| **m7g.medium** | 1 | 4 GB | Up to 12.5 | Up to 10 | **$33.58** | 3 GB | Small steady workload |
| **m7g.large** | 2 | 8 GB | Up to 12.5 | Up to 10 | **$67.15** | 6 GB | **Medium Production** ⭐ |
| **m7g.xlarge** | 4 | 16 GB | Up to 12.5 | Up to 10 | **$134.30** | 12 GB | Large Production |
| **m7g.2xlarge** | 8 | 32 GB | Up to 15 | Up to 10 | **$268.60** | 24 GB | Very Large DB |
| **m7g.4xlarge** | 16 | 64 GB | Up to 15 | Up to 10 | **$537.19** | 48 GB | Enterprise DB |

### x86 (Intel) - m7i Family

| Instance Type | vCPU | RAM | Network (Gbps) | EBS (Gbps) | Price ($/month)* | vs ARM |
|--------------|------|-----|----------------|------------|------------------|--------|
| **m7i.large** | 2 | 8 GB | Up to 12.5 | Up to 10 | **$83.95** | +25% |
| **m7i.xlarge** | 4 | 16 GB | Up to 12.5 | Up to 10 | **$167.90** | +25% |
| **m7i.2xlarge** | 8 | 32 GB | Up to 15 | Up to 10 | **$335.79** | +25% |
| **m7i.4xlarge** | 16 | 64 GB | Up to 15 | Up to 10 | **$671.57** | +25% |

---

## R-Series: Memory Optimized

**Best for:** Large Databases, In-Memory Caching, Memory-Intensive Workloads

### ARM (Graviton) - r7g Family

| Instance Type | vCPU | RAM | Network (Gbps) | EBS (Gbps) | Price ($/month)* | Buffer Pool** | Best For |
|--------------|------|-----|----------------|------------|------------------|---------------|----------|
| **r7g.medium** | 1 | 8 GB | Up to 12.5 | Up to 10 | **$41.98** | 6 GB | Small memory-intensive |
| **r7g.large** | 2 | 16 GB | Up to 12.5 | Up to 10 | **$83.95** | 12 GB | **Memory-Heavy DB** ⭐ |
| **r7g.xlarge** | 4 | 32 GB | Up to 12.5 | Up to 10 | **$167.90** | 24 GB | Large In-Memory |
| **r7g.2xlarge** | 8 | 64 GB | Up to 15 | Up to 10 | **$335.79** | 48 GB | Very Large In-Memory |
| **r7g.4xlarge** | 16 | 128 GB | Up to 15 | Up to 10 | **$671.57** | 96 GB | Enterprise In-Memory |
| **r7g.8xlarge** | 32 | 256 GB | 15 | 10 | **$1,343.14** | 192 GB | Massive Databases |

### x86 (Intel) - r7i Family

| Instance Type | vCPU | RAM | Network (Gbps) | EBS (Gbps) | Price ($/month)* | vs ARM |
|--------------|------|-----|----------------|------------|------------------|--------|
| **r7i.large** | 2 | 16 GB | Up to 12.5 | Up to 10 | **$104.94** | +25% |
| **r7i.xlarge** | 4 | 32 GB | Up to 12.5 | Up to 10 | **$209.88** | +25% |
| **r7i.2xlarge** | 8 | 64 GB | Up to 15 | Up to 10 | **$419.75** | +25% |
| **r7i.4xlarge** | 16 | 128 GB | Up to 15 | Up to 10 | **$839.49** | +25% |

---

## C-Series: Compute Optimized

**Best for:** CPU-Intensive Queries, Analytics, High Transaction Throughput, Batch Processing

### ARM (Graviton) - c7g Family

| Instance Type | vCPU | RAM | Network (Gbps) | EBS (Gbps) | Price ($/month)* | Buffer Pool** | Best For |
|--------------|------|-----|----------------|------------|------------------|---------------|----------|
| **c7g.medium** | 1 | 2 GB | Up to 12.5 | Up to 10 | **$29.93** | 1.5 GB | Small compute workload |
| **c7g.large** | 2 | 4 GB | Up to 12.5 | Up to 10 | **$59.86** | 3 GB | Compute-heavy queries |
| **c7g.xlarge** | 4 | 8 GB | Up to 12.5 | Up to 10 | **$119.71** | 6 GB | Analytics DB |
| **c7g.2xlarge** | 8 | 16 GB | Up to 15 | Up to 10 | **$239.42** | 12 GB | **CPU-Heavy Prod** ⭐ |
| **c7g.4xlarge** | 16 | 32 GB | Up to 15 | Up to 10 | **$478.84** | 24 GB | Heavy Analytics |

### x86 (AMD) - c6a Family

| Instance Type | vCPU | RAM | Network (Gbps) | EBS (Gbps) | Price ($/month)* | vs ARM |
|--------------|------|-----|----------------|------------|------------------|--------|
| **c6a.large** | 2 | 4 GB | Up to 12.5 | Up to 10 | **$68.04** | +14% |
| **c6a.xlarge** | 4 | 8 GB | Up to 12.5 | Up to 10 | **$136.08** | +14% |
| **c6a.2xlarge** | 8 | 16 GB | Up to 12.5 | Up to 10 | **$272.16** | +14% |
| **c6a.4xlarge** | 16 | 32 GB | Up to 12.5 | Up to 10 | **$544.32** | +14% |

**When to use C-series:**
- ✅ Complex JOIN operations and aggregations
- ✅ Data processing and reporting
- ✅ High transaction throughput with moderate memory
- ✅ ETL jobs and batch transformations
- ❌ NOT for memory-heavy databases (use R-series)

---

## Quick Selection Guide

| Your Need | Recommended Instance | Monthly Cost | Why |
|-----------|---------------------|--------------|-----|
| **Dev/Test** | t4g.micro | $6.13 | Cheapest, sufficient for testing |
| **Staging** | t4g.medium | $24.53 | Good performance, low cost |
| **Small Prod** | t4g.large | $49.06 | Burstable, handles spikes well |
| **Medium Prod** | m7g.large | $67.15 | Balanced, consistent performance |
| **Large Prod** | m7g.xlarge | $134.30 | High performance, scalable |
| **Memory-Heavy** | r7g.large | $83.95 | 2:1 RAM:vCPU ratio |
| **CPU-Intensive** | c7g.2xlarge | $239.42 | Best CPU, analytics workloads |
| **Massive DB** | r7g.4xlarge | $671.57 | 128GB RAM, enterprise scale |

---

## Cost Summary

### Annual Savings (ARM vs x86)

| Instance Size | ARM (Annual) | x86 (Annual) | **Savings** |
|--------------|--------------|--------------|-------------|
| **Small (t4g.medium)** | $294 | $364 | **$70 (19%)** |
| **Medium (m7g.large)** | $806 | $1,007 | **$201 (20%)** |
| **Large (m7g.xlarge)** | $1,612 | $2,015 | **$403 (20%)** |
| **Memory (r7g.large)** | $1,007 | $1,259 | **$252 (20%)** |
| **Compute (c7g.2xlarge)** | $2,873 | $3,266 | **$393 (14%)** |

### 3-Year TCO Savings

| Fleet Size | ARM Cost (3yr) | x86 Cost (3yr) | **Savings** |
|------------|----------------|----------------|-------------|
| **1 instance (m7g.large)** | $2,418 | $3,021 | **$603** |
| **5 instances** | $12,090 | $15,105 | **$3,015** |
| **10 instances** | $24,180 | $30,210 | **$6,030** |
| **50 instances** | $120,900 | $151,050 | **$30,150** |

---

## Notes

- *All prices based on US East (N. Virginia) on-demand rates, January 2026
- **Buffer Pool Size: Recommended `innodb_buffer_pool_size` (75% of RAM)
- ⭐ = Recommended sweet spot for that use case
- Prices exclude EBS storage, data transfer, and backups
- Reserved Instances and Savings Plans can reduce costs by 40-60%

---

**Recommendation:** Use ARM (Graviton) for 90% of MySQL workloads to get 14-25% cost savings with equal or better performance.

**Last Updated:** January 2026

