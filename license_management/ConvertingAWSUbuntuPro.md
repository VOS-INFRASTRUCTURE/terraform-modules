# Converting Ubuntu LTS to Ubuntu Pro on AWS EC2

If you already have an EC2 instance running Ubuntu 24.04 LTS, you don't "install Pro" like a package.

You have **two options**:

1. **Convert the instance license in AWS** (via License Manager) - Recommended ✅
2. **Attach Ubuntu Pro manually** from inside the OS (using a token)

Since you're on **Ubuntu 24.04 LTS**, it's fully supported for Ubuntu Pro conversion.

---

## ✅ Method 1 — Convert to Ubuntu Pro via AWS License Manager (Recommended)

This is the **official AWS-native method** for converting existing Ubuntu LTS instances to Ubuntu Pro.

### 📋 Prerequisites

Before you begin, ensure:

- ✅ **Ubuntu LTS version**: 16.04, 18.04, 20.04, 22.04, or **24.04** (you have this)
- ✅ **AWS Systems Manager (SSM) managed**: Instance must be visible in SSM Fleet Manager
- ✅ **IAM permissions**: You need permissions for:
  - `license-manager:CreateLicenseConversionTaskForResource`
  - `ec2:StopInstances`, `ec2:StartInstances`
  - `ssm:SendCommand`
- ⚠️ **Instance must be STOPPED** during conversion (downtime required)
- ⚠️ **Only works with official Ubuntu AMIs** (not custom images)

### 💰 Cost Implications

**Ubuntu Pro pricing** (as of 2026):

| Instance Type | Hourly Cost (EU-West-2) | Monthly Cost (730h) |
|---------------|-------------------------|---------------------|
| t4g.micro     | ~$0.0023/hour          | ~$1.68/month        |
| t4g.small     | ~$0.0046/hour          | ~$3.36/month        |
| t4g.medium    | ~$0.0092/hour          | ~$6.72/month        |
| t3.medium     | ~$0.0096/hour          | ~$7.01/month        |

💡 **Note**: Ubuntu Pro is **FREE** for personal use (up to 5 machines) via Ubuntu One account.  
For production/commercial use on AWS, you pay the hourly rate above **in addition** to your EC2 costs.

---

### 🔧 Step 1 — Verify AWS Systems Manager (SSM) Access

**Why this matters**: License Manager uses SSM to execute the conversion on your instance.

#### Check if your instance is SSM-managed:

1. Go to: **AWS Console** → **Systems Manager** → **Fleet Manager** → **Managed nodes**
2. Look for your instance ID in the list

**✅ If you see it**: Proceed to Step 2.

**❌ If you DON'T see it**, fix it:

#### How to enable SSM on your instance:

**A. Attach the required IAM role**

Your EC2 instance needs an IAM role with the **AmazonSSMManagedInstanceCore** policy.

```bash
# Via AWS CLI (replace YOUR_INSTANCE_ID and YOUR_ROLE_NAME)
aws iam attach-role-policy \
  --role-name YOUR_ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws ec2 associate-iam-instance-profile \
  --instance-id YOUR_INSTANCE_ID \
  --iam-instance-profile Name=YOUR_INSTANCE_PROFILE
```

**Or via Console**:

1. Go to **EC2** → **Instances** → Select instance
2. **Actions** → **Security** → **Modify IAM role**
3. Select a role with `AmazonSSMManagedInstanceCore` policy (or create one)
4. Click **Update IAM role**

**B. Verify SSM Agent is running**

SSH into your instance and run:

```bash
sudo systemctl status snap.amazon-ssm-agent.amazon-ssm-agent.service
```

If not running:

```bash
sudo snap start amazon-ssm-agent
```

**C. Wait 5-10 minutes**, then check Fleet Manager again.

---

### 🛑 Step 2 — Stop the EC2 Instance

**⚠️ WARNING**: Your instance will be **DOWN** during this step (typically 5-10 minutes).

1. Go to: **EC2** → **Instances**
2. Select your instance
3. **Instance state** → **Stop instance**
4. Wait until **Instance state** = `Stopped`

💡 **Tip**: If running production, schedule this during a maintenance window.

---

### 🔄 Step 3 — Create License Conversion Task

1. Go to: **AWS Console** → **License Manager** → **License type conversions**
2. Click **Create license type conversion**

**Configuration**:

| Field | Value |
|-------|-------|
| **Source license** | `Ubuntu LTS` |
| **Select resources** | Choose your stopped instance(s) |
| **Destination license** | `Ubuntu Pro` |

3. Click **Convert**

**What happens now**:

- AWS License Manager will:
  - ✅ Verify the instance is stopped
  - ✅ Check SSM connectivity
  - ✅ Modify instance metadata to enable Ubuntu Pro
  - ✅ Update the instance's billing code
  
**⏱️ Expected time**: 2-5 minutes

**Monitor progress**: You'll see the status change from:
- `In progress` → `Successful`

If it fails, check:
- Instance is fully stopped (not stopping)
- SSM agent is active
- IAM role has correct permissions

---

### ▶️ Step 4 — Start the Instance and Verify

1. Go back to **EC2** → **Instances**
2. Select your instance
3. **Instance state** → **Start instance**
4. Wait for **Instance state** = `Running`

**SSH into the instance** and verify:

```bash
# Check Ubuntu Pro status
pro status
```

**✅ Expected output** (Ubuntu Pro active):

```
SERVICE          ENTITLED  STATUS       DESCRIPTION
esm-apps         yes       enabled      Expanded Security Maintenance for Applications
esm-infra        yes       enabled      Expanded Security Maintenance for Infrastructure
livepatch        yes       enabled      Canonical Livepatch service
fips             yes       disabled     NIST-certified FIPS crypto packages
fips-updates     yes       disabled     FIPS compliant crypto packages with stable security updates
usg              yes       disabled     Security compliance and audit tools

Enable services with: pro enable <service>

                Account: AWS
           Subscription: Ubuntu Pro (AWS)
```

**Key indicators**:
- ✅ `Account: AWS` (not "trial" or "free")
- ✅ `esm-apps` and `esm-infra` = `enabled`
- ✅ `livepatch` = `enabled` (automatic kernel security patching without reboots!)

---

### 🔍 Verify Billing

After conversion, verify you're being charged correctly:

1. Go to: **EC2** → **Instances** → Select instance → **Details tab**
2. Look for: **Usage operation** = `RunInstances:00g0` (Ubuntu Pro code)

**Before conversion**: `RunInstances:0010` (standard Ubuntu)  
**After conversion**: `RunInstances:00g0` (Ubuntu Pro)

You can also check **Cost Explorer**:
- Filter by instance ID
- Look for "Ubuntu Pro" line item in hourly charges

---

### 🛡️ What You Get with Ubuntu Pro

After successful conversion:

| Feature | Ubuntu LTS | Ubuntu Pro |
|---------|------------|------------|
| **Security updates** | 5 years | 10+ years |
| **Kernel Livepatch** | ❌ No | ✅ Yes (no reboot needed) |
| **FIPS compliance** | ❌ No | ✅ Optional |
| **CIS hardening** | ❌ Manual | ✅ Automated |
| **Extended support (ESM)** | ❌ No | ✅ Yes |
| **Support SLA** | Community | Optional paid |

**Most valuable for production**:
- 🔒 **Livepatch**: Apply kernel security patches without rebooting
- 📦 **ESM**: Get security updates for 10+ years (beyond standard 5-year LTS)
- 🛡️ **FIPS 140-2**: Cryptographic compliance for government/finance workloads

---

### ⚠️ Important Limitations

1. **Only works with official Ubuntu AMIs**
   - Custom images / Bring Your Own Image (BYOI) → Use Method 2 instead

2. **Requires instance stop**
   - Not suitable for always-on production without planned downtime
   - For zero-downtime: Launch new Ubuntu Pro instances behind a load balancer

3. **Regional pricing varies**
   - Check current pricing: https://aws.amazon.com/ec2/pricing/on-demand/

4. **Cannot revert easily**
   - Once converted, you're billed for Ubuntu Pro
   - To revert: Must launch new standard Ubuntu instance and migrate

---

### 🐛 Troubleshooting

| Problem | Solution |
|---------|----------|
| Instance not in Fleet Manager | Attach IAM role with `AmazonSSMManagedInstanceCore`, restart SSM agent |
| Conversion fails: "Instance not stopped" | Ensure instance is fully stopped (not "stopping") |
| `pro status` shows "Not attached" | Wait 5 minutes after first boot, then run `sudo pro auto-attach` |
| FIPS/Livepatch not enabled | Run `sudo pro enable livepatch` or `sudo pro enable fips` |
| Billing shows standard Ubuntu cost | Check **Usage operation** in instance details, may take 1 hour to update |

---

## ✅ Method 2 — Attach Ubuntu Pro Manually (No AWS License Manager)

If you don't want to use License Manager, or if you're using a custom Ubuntu image, you can attach Pro directly.

### When to use this method:

- ✅ Custom Ubuntu images (not from AWS Marketplace)
- ✅ On-premises VMs you want to connect to Ubuntu Pro
- ✅ Personal use (free tier - up to 5 machines)
- ✅ Don't want AWS to manage the license

### Prerequisites

Ubuntu 24.04 already has the `pro` tool installed.

Check:

```bash
pro version
```

If missing:

```bash
sudo apt install ubuntu-advantage-tools
```

### Step 1 — Get an Ubuntu Pro token

1. Go to: 👉 **https://ubuntu.com/pro**
2. Sign in with **Ubuntu One** account (create one if needed)
3. **For personal use**: Free tier gives you up to 5 machines
4. **For commercial use**: Subscribe to Ubuntu Pro
5. Copy your **token** (looks like: `CAbCdEf1GhIjKl2MnOpQ3rStUvWxYz`)

### Step 2 — Attach the token to your instance

SSH into your instance and run:

```bash
sudo pro attach <your-token>
```

**Example**:

```bash
sudo pro attach CAbCdEf1GhIjKl2MnOpQ3rStUvWxYz
```

**Expected output**:

```
Enabling default service esm-apps
Updating package lists
Ubuntu Pro: ESM Apps enabled
Enabling default service esm-infra
Updating package lists
Ubuntu Pro: ESM Infra enabled
Enabling default service livepatch
Canonical Livepatch enabled
This machine is now attached to 'Ubuntu Pro'
```

### Step 3 — Verify

Check status:

```bash
pro status
```

**✅ Expected output**:

```
SERVICE          ENTITLED  STATUS       DESCRIPTION
esm-apps         yes       enabled      Expanded Security Maintenance for Applications
esm-infra        yes       enabled      Expanded Security Maintenance for Infrastructure
livepatch        yes       enabled      Canonical Livepatch service
```

**Key difference from Method 1**:
- `Account:` will show your Ubuntu One email (not "AWS")
- Billing happens through your Ubuntu Pro subscription (not AWS)

---

## 🔎 Important: If You're Already Using Ubuntu Pro AMI

If you launched your instance using:

**"Ubuntu Pro 24.04 LTS"** AMI from AWS Marketplace

Then you're **already running Pro** - nothing more needed!

Run:

```bash
pro status
```

If it shows `Account: AWS` and services enabled → ✅ you're good.

---

## 💡 Which Method Should You Use?

| Situation | Best Method |
|-----------|-------------|
| Already running **official Ubuntu LTS AMI** on AWS | **Method 1** (License Manager) ✅ |
| **Custom image** / Bring Your Own Image | **Method 2** (Manual attach) |
| **Personal use** (up to 5 machines) | **Method 2** (Free tier) |
| Launching **new instance** | Just select **Ubuntu Pro AMI** from marketplace |
| **Multi-account AWS setup** | **Method 1** (easier to manage via AWS) |
| **On-premises** or non-AWS | **Method 2** (only option) |

---

## 🚀 Quick Health Check

Run this on your EC2 to check current status:

```bash
# Check Ubuntu version
lsb_release -a

# Check Ubuntu Pro status
pro status

# Check if Pro services are active
systemctl is-active ua-timer.service

# View security updates available via Pro
pro security-status
```

---

## 📚 Additional Resources

- **Ubuntu Pro Documentation**: https://ubuntu.com/pro/tutorial
- **AWS License Manager Guide**: https://docs.aws.amazon.com/license-manager/
- **Ubuntu Pro Pricing**: https://ubuntu.com/pricing/pro
- **Livepatch Documentation**: https://ubuntu.com/security/livepatch

---

## 🆘 Getting Help

If you encounter issues:

1. **Check AWS Systems Manager**:
   ```bash
   sudo systemctl status snap.amazon-ssm-agent.amazon-ssm-agent
   ```

2. **Check Ubuntu Pro logs**:
   ```bash
   sudo journalctl -u ua-timer.service
   ```

3. **Re-attach if status shows errors**:
   ```bash
   sudo pro detach
   sudo pro auto-attach  # For AWS-managed
   # OR
   sudo pro attach <token>  # For manual
   ```

4. **Contact support**:
   - **AWS Support**: For License Manager issues
   - **Canonical Support**: For Ubuntu Pro subscription issues (if you have paid support)
   - **Community**: https://discourse.ubuntu.com/

---

**Last Updated**: February 2026  
**Tested on**: Ubuntu 24.04 LTS, AWS EC2 (Graviton and x86)

