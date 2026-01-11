# AWS Security Hub Standards – NIS Compliance Guidance

This note documents the security standards reviewed within **AWS Security Hub**, explains their differences, and records the **recommended enablement scope** for Nigeria Immigration Service (NIS)–related systems.

---

## 1. Context

AWS Security Hub evaluates AWS environments against predefined **security and compliance standards**. These standards do **not** provide security controls themselves; instead, they continuously assess AWS resources and generate **findings (pass/fail)**.

Enabling additional standards increases:

* Compliance expectations
* Volume of findings
* Audit and documentation obligations

Therefore, only standards aligned with contractual or regulatory requirements should be enabled.

---

## 2. Standards Reviewed

### 2.1 AWS Foundational Security Best Practices

**Description:**
AWS’s baseline security recommendations covering IAM, logging, networking, encryption, and monitoring.

**Assessment:**

* Vendor-neutral
* Low risk
* Widely accepted baseline

**Status for NIS:**
**Recommended – Enable**

---

### 2.2 CIS AWS Foundations Benchmark

**Description:**
Security benchmarks published by the Center for Internet Security (CIS), widely used by governments and regulated industries.

**Versions Observed:**

* v1.2.0 – Obsolete
* v1.4.0 – Obsolete
* v3.0.0 – Superseded
* v5.0.0 – Current and most comprehensive

**Important Note:**
Only **one CIS version** should be enabled at a time to avoid duplicate and conflicting findings.

**Status for NIS:**
**Enable CIS AWS Foundations Benchmark v5.0.0 only**

---

### 2.3 AWS Resource Tagging Standard

**Description:**
Validates the presence of required tags (e.g., Environment, Project, Owner) on AWS resources.

**Assessment:**

* Improves asset traceability
* Supports audits and governance
* Minimal operational risk

**Status for NIS:**
**Recommended – Enable**

---

### 2.4 NIST Special Publication 800-53 (Revision 5)

**Description:**
Comprehensive security framework for U.S. federal government and defense systems.

**Assessment:**

* Extremely strict
* Requires extensive policies, procedures, and evidence

**Status for NIS:**
**Do NOT enable unless explicitly mandated by NIS in writing**

---

### 2.5 NIST Special Publication 800-171 (Revision 2)

**Description:**
Subset of NIST 800-53 focused on protecting controlled unclassified information (CUI) handled by contractors.

**Assessment:**

* Less extensive than 800-53
* Still introduces significant compliance obligations

**Status for NIS:**
**Optional – Enable only if contractually required**

---

### 2.6 PCI DSS (v3.2.1 and v4.0.1)

**Description:**
Payment Card Industry Data Security Standard, applicable only to environments processing or storing cardholder data.

**Assessment:**

* Not applicable to NIS systems
* Introduces unnecessary audit scope

**Status for NIS:**
**Do NOT enable**

---

## 3. Summary Table – Security Hub Standards Decision

| Standard                                 | Purpose                                        | Recommended Action | Reason                                                           |
| ---------------------------------------- | ---------------------------------------------- | ------------------ | ---------------------------------------------------------------- |
| AWS Foundational Security Best Practices | AWS baseline security controls                 | **Enable**         | Safe default baseline aligned with AWS guidance                  |
| CIS AWS Foundations Benchmark v5.0.0     | Government-grade AWS security benchmark        | **Enable**         | Current CIS version; widely accepted for public-sector workloads |
| AWS Resource Tagging Standard            | Resource ownership and governance              | **Enable**         | Improves audit traceability with minimal risk                    |
| CIS AWS Foundations Benchmark v1.2.0     | Legacy CIS benchmark                           | Disable            | Obsolete and superseded                                          |
| CIS AWS Foundations Benchmark v1.4.0     | Legacy CIS benchmark                           | Disable            | Obsolete and superseded                                          |
| CIS AWS Foundations Benchmark v3.0.0     | Older CIS benchmark                            | Disable            | Redundant when v5.0.0 is enabled                                 |
| NIST SP 800-53 Rev 5                     | US federal security framework                  | Do not enable      | Excessive scope unless explicitly mandated by NIS                |
| NIST SP 800-171 Rev 2                    | Controlled unclassified information protection | Do not enable      | Only applicable if contractually required                        |
| PCI DSS v3.2.1                           | Payment card security                          | Do not enable      | Not applicable to NIS workloads                                  |
| PCI DSS v4.0.1                           | Payment card security (current)                | Do not enable      | Not applicable to NIS workloads                                  |

---

## 4. Final Recommended Enablement Set

### Enable:

* AWS Foundational Security Best Practices
* CIS AWS Foundations Benchmark **v5.0.0**
* AWS Resource Tagging Standard

### Disable / Do Not Enable:

* CIS AWS Foundations Benchmark v1.2.0
* CIS AWS Foundations Benchmark v1.4.0
* CIS AWS Foundations Benchmark v3.0.0
* NIST SP 800-53 Rev 5
* NIST SP 800-171 Rev 2 (unless mandated)
* PCI DSS v3.2.1
* PCI DSS v4.0.1

---

## 4. Compliance Positioning for NIS Documentation

For NIS compliance documentation, the recommended statement is:

> “Security monitoring and continuous compliance validation are implemented using AWS-native security services aligned with AWS Foundational Security Best Practices and the CIS AWS Foundations Benchmark.”

This wording:

* Avoids unnecessary regulatory commitments
* Aligns with government audit expectations
* Accurately reflects the enabled standards

---

**Document Status:** Final and approved for internal compliance reference
