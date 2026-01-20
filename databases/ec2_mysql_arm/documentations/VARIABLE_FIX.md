# EC2 MySQL ARM Module - Variable Interpolation Fix ✅

## Issues Fixed

### 1. ✅ Auto-detect ARM AMI by Region

**Problem:** AMI ID was hardcoded for us-east-1, causing issues in other regions.

**Solution:** Added data source to auto-detect latest Ubuntu 24.04 ARM64 AMI for the current region.

**Changes Made:**

#### main.tf
```hcl
# Added data source
data "aws_ami" "ubuntu_arm64" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Use auto-detected AMI with fallback
resource "aws_instance" "mysql_ec2" {
  ami = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu_arm64.id
  # ...
}
```

#### variables.tf
```hcl
variable "ami_id" {
  description = "The AMI ID to use for the instance (leave empty to auto-detect latest Ubuntu 24.04 ARM64 for your region)"
  type        = string
  default     = ""  # Changed from hardcoded AMI ID
}
```

**Benefits:**
- ✅ Works in any AWS region automatically
- ✅ Always uses latest Ubuntu 24.04 ARM64 AMI
- ✅ Can still override with specific AMI if needed
- ✅ No manual AMI ID lookup required

---

### 2. ✅ Fixed MySQL Configuration Variable Interpolation

**Problem:** Variables in mysql.cnf were not being interpolated. They would appear as literal `${var.innodb_buffer_pool_size}` instead of actual values like `6G`.

**Root Cause:** Using `file()` function instead of `templatefile()` function.

**Solution:** Changed to `templatefile()` with proper variable mapping.

**Changes Made:**

#### user_data.tf
```hcl
# BEFORE (wrong - doesn't interpolate variables)
cat > /etc/mysql/mysql.conf.d/custom.cnf <<'MYSQLCONF'
${file("${path.module}/mysql.cnf")}
MYSQLCONF

# AFTER (correct - interpolates variables)
cat > /etc/mysql/mysql.conf.d/custom.cnf <<'MYSQLCONF'
${templatefile("${path.module}/mysql.cnf", {
  innodb_buffer_pool_size = var.innodb_buffer_pool_size
  mysql_max_connections   = var.mysql_max_connections
})}
MYSQLCONF
```

#### mysql.cnf
```ini
# Variables now work correctly (without 'var.' prefix)
innodb_buffer_pool_size=${innodb_buffer_pool_size}
max_connections=${mysql_max_connections}
```

**How it works:**
1. `templatefile()` reads mysql.cnf as a template
2. Replaces `${innodb_buffer_pool_size}` with actual value (e.g., "6G")
3. Replaces `${mysql_max_connections}` with actual value (e.g., "200")
4. Generates final configuration file with real values

**Example Result:**
```ini
# Input template
innodb_buffer_pool_size=${innodb_buffer_pool_size}
max_connections=${mysql_max_connections}

# After interpolation (with defaults)
innodb_buffer_pool_size=6G
max_connections=200
```

---

### 3. ✅ Cleaned Up mysql.cnf

**Fixed:**
- Removed duplicate `default_storage_engine=InnoDB` declaration
- Removed hardcoded values (replaced with template variables)
- Cleaned up malformed comments

---

### 4. ✅ Added AMI Information to Outputs

**Added to outputs.tf:**
```hcl
instance = {
  # ...existing outputs...
  ami_id          = aws_instance.mysql_ec2.ami
  ami_name        = data.aws_ami.ubuntu_arm64.name
  ami_description = data.aws_ami.ubuntu_arm64.description
}
```

**Benefits:**
- Can see which AMI was actually used
- Useful for debugging and documentation
- Know exact Ubuntu version deployed

---

## Testing the Fixes

### Test 1: Different Regions

```hcl
# Deploy in us-east-1
provider "aws" {
  region = "us-east-1"
}

module "mysql_use1" {
  source = "../../databases/ec2_mysql_arm"
  # ... config
}

# Deploy in eu-west-1
provider "aws" {
  region = "eu-west-1"
}

module "mysql_euw1" {
  source = "../../databases/ec2_mysql_arm"
  # ... config
}
```

Both will automatically use the correct ARM64 AMI for their region!

---

### Test 2: Custom Buffer Pool

```hcl
module "mysql_large" {
  source = "../../databases/ec2_mysql_arm"
  
  instance_type          = "m7g.xlarge"      # 16GB RAM
  innodb_buffer_pool_size = "12G"           # 75% of 16GB
  mysql_max_connections   = 300
  
  # ... other config
}
```

MySQL configuration will have:
```ini
innodb_buffer_pool_size=12G
max_connections=300
```

---

### Test 3: View AMI Used

```bash
terraform apply

# After deployment
terraform output -json mysql | jq '.instance'
```

Output:
```json
{
  "ami_id": "ami-0abc123def456789",
  "ami_name": "ubuntu/images/hvm-ssd/ubuntu-noble-24.04-arm64-server-20260115",
  "ami_description": "Canonical, Ubuntu, 24.04 LTS, arm64 noble image build on 2026-01-15",
  "instance_type": "m7g.large",
  ...
}
```

---

## Validation Results

All files validated successfully:

```bash
✅ main.tf - No errors
✅ variables.tf - No errors  
✅ user_data.tf - No errors
✅ outputs.tf - No errors
✅ mysql.cnf - Valid template syntax
```

---

## What Changed - Summary

| File | Change | Why |
|------|--------|-----|
| **main.tf** | Added `data.aws_ami.ubuntu_arm64` | Auto-detect ARM AMI by region |
| **main.tf** | Changed `ami = var.ami_id` to conditional | Use auto-detected AMI or custom |
| **variables.tf** | Changed `ami_id` default to `""` | Enable auto-detection |
| **user_data.tf** | Changed `file()` to `templatefile()` | Enable variable interpolation |
| **mysql.cnf** | Changed hardcoded values to variables | Use template variables |
| **mysql.cnf** | Removed duplicates | Clean up configuration |
| **outputs.tf** | Added AMI info | Show which AMI was used |

---

## Benefits of These Changes

### Auto-Detected AMI
✅ **Multi-region support** - Works in any AWS region  
✅ **Always latest** - Gets newest Ubuntu 24.04 ARM64  
✅ **No maintenance** - No manual AMI ID updates  
✅ **Still flexible** - Can override with specific AMI  

### Proper Variable Interpolation
✅ **Dynamic configuration** - MySQL config matches instance size  
✅ **Correct values** - No more literal `${var.name}` in config  
✅ **Validation** - Terraform validates before deploy  
✅ **Flexibility** - Easy to adjust per environment  

---

## Migration Notes

**If you already deployed with hardcoded AMI:**

1. No changes needed - existing instances keep working
2. New deployments will use auto-detected AMI
3. To force AMI update: `terraform taint aws_instance.mysql_ec2`

**If you used custom ami_id:**

```hcl
# Old way (still works)
ami_id = "ami-specific-id"

# New way (recommended - leave empty for auto-detection)
# ami_id = ""  # or just omit it
```

---

## Example Usage

### Basic (Auto-detect everything)
```hcl
module "mysql" {
  source = "../../databases/ec2_mysql_arm"
  
  env        = "production"
  project_id = "myapp"
  
  subnet_id          = "subnet-xxx"
  security_group_ids = ["sg-xxx"]
  
  mysql_database = "myapp_db"
  # AMI auto-detected for current region
  # Buffer pool = 6G (default for m7g.large)
  # Max connections = 200 (default)
}
```

### Custom Instance Size
```hcl
module "mysql_large" {
  source = "../../databases/ec2_mysql_arm"
  
  env        = "production"
  project_id = "myapp"
  
  instance_type          = "r7g.large"  # 16GB RAM
  innodb_buffer_pool_size = "12G"      # 75% of 16GB
  mysql_max_connections   = 300
  
  subnet_id          = "subnet-xxx"
  security_group_ids = ["sg-xxx"]
  
  mysql_database = "myapp_db"
  # AMI still auto-detected
}
```

### Specific AMI (if needed)
```hcl
module "mysql_specific" {
  source = "../../databases/ec2_mysql_arm"
  
  ami_id = "ami-specific-version"  # Override auto-detection
  
  # ... rest of config
}
```

---

## ✅ Status: READY FOR PRODUCTION

Both issues are now fixed and the module is ready for multi-region deployment with proper variable interpolation!

**Last Updated:** January 20, 2026

