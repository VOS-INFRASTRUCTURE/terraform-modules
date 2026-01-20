Short answer: Yes, ARM (Graviton / t4g) is very good for MySQL — and usually the better choice unless you have a specific constraint.

Below is the practical, decision-grade comparison 👇

ARM (t4g / Graviton) vs AMD64 for MySQL
✅ When ARM (t4g) Is the Better Choice (Most Cases)

AWS Graviton (ARM64) instances like t4g, m7g, r7g are excellent for MySQL.

Benefits:

1️⃣ Better Price–Performance

~20–40% better price/performance vs x86

Lower cost per vCPU and per GB RAM

Same MySQL workload → fewer dollars

AWS has benchmarked this extensively.

2️⃣ MySQL Works Natively on ARM

MySQL 8.x fully supports ARM

Ubuntu 22.04 / 24.04 ARM packages are first-class

No emulation, no hacks

You just install:

apt install mysql-server

3️⃣ Lower Power / Better Efficiency

Graviton cores are more efficient

Better sustained performance under load

Especially good for:

OLTP

Read-heavy workloads

Moderate write workloads

4️⃣ t4g Is Fine for Staging & Light Prod

For your staging MySQL:

t4g.medium or t4g.large is usually perfect

Burstable CPU works well for DBs with spiky load

⚠️ When AMD64 (x86) Is Still Better

Choose amd64 if any of the following apply:

❌ You Use Native Binary Plugins

Examples:

Custom MySQL plugins compiled for x86

Closed-source monitoring agents

Legacy backup tools

❌ You Use Docker Images Without ARM Support

Some older images are still linux/amd64 only.

❌ Very High-End / Latency-Critical DBs

For:

Ultra-low latency

Very high write throughput

You’ll want:

r7g (ARM) or

r7i / m7i (x86)

(t4g isn’t ideal at that scale, regardless of CPU type.)

MySQL-Specific Notes (Important)
Threading & ARM

MySQL scales well on ARM

InnoDB performs very well on Graviton

No tuning differences required

Burstable Instances (t4g)

Good for:

Dev

Staging

Small/medium prod

Not ideal for:

Sustained 100% CPU DB load

If CPU credits run out, performance drops.

Recommended Instance Types by Use Case
Use Case	Best Choice
Dev / Staging	t4g.medium
Small Prod DB	t4g.large
Medium Prod DB	m7g.large
Memory-heavy DB	r7g.large
Ultra-critical	r7g or r7i
AMI Compatibility (Ubuntu 24)

Make sure you use:

Ubuntu 24.04 ARM64 AMI (aarch64)

Not amd64

Terraform example:

architecture = "arm64"

Final Verdict

ARM (Graviton / t4g) is an excellent and usually superior choice for MySQL.
Use AMD64 only if you have a specific compatibility requirement.

If you want, I can:

Recommend an exact instance size for your workload

Review your MySQL config for ARM

Help you migrate an existing x86 MySQL EC2 to Graviton safely