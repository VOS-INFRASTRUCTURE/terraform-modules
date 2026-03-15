# EC2 User Data – Optimization Considerations

This document covers known pitfalls and best practices for the `user_data.tf` bootstrap
script used by this module. These improvements should be applied when updating the script.

---

## 1. APT Lock Race Condition (Most Common Failure)

### Problem

Ubuntu cloud images run background APT services on first boot (`apt-daily`, `unattended-upgrades`).
These services hold the `dpkg` lock, causing your `apt-get install` commands to fail with:

```
E: Could not get lock /var/lib/dpkg/lock-frontend
dpkg: error: dpkg status database is locked by another process
```

This is the **#1 cause of cloud-init provisioning failures** on Ubuntu.

---

### Fix A – Wait for the Lock (Minimum Safe Fix)

Add this function immediately after `set -e`:

```shell
# Wait for apt/dpkg locks (Ubuntu boot race condition)
wait_for_apt() {
  while fuser /var/lib/dpkg/lock          >/dev/null 2>&1 || \
        fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
        fuser /var/lib/apt/lists/lock      >/dev/null 2>&1; do
    echo "Waiting for apt lock..."
    sleep 5
  done
}

wait_for_apt
```

This polls all three lock files, not just one. Checking only `lock-frontend` (as many examples
show) is insufficient — the other two can still block installs.

---

### Fix B – Stop Background APT Services First (Recommended)

A more reliable approach is to stop the background services before provisioning begins,
then wait for any in-progress lock to clear:

```shell
# Stop background APT services to prevent lock conflicts during provisioning
systemctl stop apt-daily.service           || true
systemctl stop apt-daily-upgrade.service   || true
systemctl stop unattended-upgrades.service || true

# Wait for any remaining dpkg lock to release
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  echo "Waiting for apt lock..."
  sleep 5
done
```

> ⚠️ The `|| true` is required so `set -e` does not abort the script if a service is
> already stopped or does not exist.

---

### Why Both Locks Matter

| Lock file                          | Held by                        |
|------------------------------------|--------------------------------|
| `/var/lib/dpkg/lock`               | `dpkg` during package installs |
| `/var/lib/dpkg/lock-frontend`      | `apt-get` frontend process     |
| `/var/lib/apt/lists/lock`          | `apt-get update`               |

Fix A handles all three. Fix B stops the root cause and is preferred for production scripts.

---

## 2. Docker Installation Method

### Problem

The commonly used convenience script:

```shell
curl https://get.docker.com | sh
```

Has several issues in automated provisioning:
- Downloads and executes unknown content at runtime (security risk)
- Non-deterministic — installs whatever version is current at the time
- Can fail silently or behave inconsistently in headless environments
- Adds the full Docker CE repository, which is unnecessary for most server workloads

### Recommended Alternative

Use the Ubuntu package directly:

```shell
apt-get install -y docker.io
```

**Benefits:**
- Deterministic — same version pinned to the Ubuntu package repository
- Faster — no additional GPG key or repository setup
- Simpler — no external script execution
- Sufficient for most workloads (Docker CE extras rarely needed on a plain server)

> **Note:** `docker.io` may lag slightly behind the latest Docker CE version. If you
> specifically need the latest Docker CE, use the official Docker APT repository with
> a pinned version instead of the convenience script.

---

## 3. Recommended Bootstrap Order

Running steps out of order is another common source of failures (e.g. installing CloudWatch
before AWS CLI is ready, or installing packages before apt is stable).

The recommended order is:

| Step | Action                               | Why                                                    |
|------|--------------------------------------|--------------------------------------------------------|
| 1    | Stop background APT services         | Prevent lock conflicts                                 |
| 2    | Wait for apt lock to clear           | Ensure no in-progress apt job is running               |
| 3    | `apt-get update && apt-get upgrade`  | Apply latest security patches first                    |
| 4    | Install base packages                | `curl`, `jq`, `unzip`, etc. needed by later steps     |
| 5    | Install AWS CLI v2                   | Required for Secrets Manager and S3 access             |
| 6    | Install Docker *(if enabled)*        | Depends on base packages being present                 |
| 7    | Install Nginx *(if enabled)*         | Independent, but benefits from base packages           |
| 8    | Install CloudWatch agent             | Should come after AWS CLI and packages are ready       |
| 9    | Remove SSH / harden                  | Always last — do not lock yourself out mid-script      |

---

## 4. CloudWatch Log Collection – Conditional Logs

When Docker or Nginx are not installed, their log paths do not exist. The CloudWatch agent
will emit warnings about missing files but will not fail. However, it is cleaner to only
include log paths for services that are actually installed.

**Docker log path** (`/var/log/docker.log`) should only be collected when `install_docker = true`.

**Nginx log paths** (`/var/log/nginx/access.log`, `/var/log/nginx/error.log`) should only
be collected when `install_nginx = true`.

This is handled in `user_data.tf` via Terraform conditionals inside the CloudWatch config JSON.

---

## 5. CloudWatch Metrics Namespace

The current namespace `"EC2/"` is incomplete and results in metrics appearing under a
malformed namespace in CloudWatch. It should include the project/environment context:

```json
"namespace": "EC2/Server"
```

Or more specifically scoped:

```json
"namespace": "${var.env}-${var.project_id}/EC2"
```

This makes it easier to filter metrics per environment in the CloudWatch console.

---

## 6. SSH Removal

SSH is disabled and removed at the end of the script in favour of AWS Session Manager.
This is the correct approach — it **must** remain the last step so that if the script
fails mid-way, you can still SSH in to debug.

> ⚠️ If you move SSH removal earlier in the script and `set -e` causes an abort before
> completion, you will be **permanently locked out** of the instance with no recovery
> path other than replacing it.

Session Manager is pre-installed on Ubuntu 22.04+ AMIs. No manual installation is needed.

---

## Summary – Minimal Patch

If you need to apply a quick fix without a full rewrite, add this block immediately after
`set -e` at the top of the script:

```shell
# ── APT lock fix (Ubuntu boot race condition) ──────────────────────────────
systemctl stop apt-daily.service           || true
systemctl stop apt-daily-upgrade.service   || true
systemctl stop unattended-upgrades.service || true

while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  echo "Waiting for apt lock..."
  sleep 5
done
# ───────────────────────────────────────────────────────────────────────────
```

This single change resolves the most common provisioning failure on Ubuntu EC2 instances.
