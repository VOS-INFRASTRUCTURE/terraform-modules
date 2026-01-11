# CERPAC Incident Response Plan (IRP)

**Document Classification:** Internal / Compliance
**Environment:** Production
**Scope:** AWS Cloud Infrastructure (CERPAC)
**Version:** 1.0
**Last Updated:** December 2025

---

## 1. Purpose

This Incident Response Plan (IRP) defines the **processes, roles, and responsibilities** for detecting, analyzing, responding to, and recovering from security incidents affecting the CERPAC production environment.

The objective of this plan is to:

* Minimize impact of security incidents
* Ensure timely and coordinated response
* Preserve forensic evidence
* Meet regulatory, audit, and government security requirements

This plan focuses on **manual, controlled response**, supported by AWS-native detection and logging services.

---

## 2. Scope

This IRP applies to:

* AWS production accounts hosting CERPAC systems
* Application, infrastructure, identity, and data security incidents
* Events detected via AWS WAF, GuardDuty, Security Hub, and CloudTrail

Out of scope:

* Physical security incidents
* End-user device compromise outside AWS

---

## 3. Incident Detection & Sources

Security incidents may be detected through the following mechanisms:

* **AWS GuardDuty** – threat detection (credential misuse, malware, exfiltration)
* **AWS Security Hub** – centralized security findings and compliance alerts
* **AWS WAF** – blocked or anomalous HTTP request patterns
* **AWS CloudTrail** – audit logs for unauthorized or suspicious API activity
* **Operational monitoring** – reports from engineering or operations staff

Detection may be automated or manual.

---

## 4. Incident Classification

All incidents are classified based on severity and impact.

| Severity     | Description                | Examples                                 | Target Response |
| ------------ | -------------------------- | ---------------------------------------- | --------------- |
| **Low**      | Informational / no impact  | Best-practice findings                   | < 24 hours      |
| **Medium**   | Suspicious activity        | Failed compliance check, unusual traffic | < 4 hours       |
| **High**     | Confirmed security threat  | Unauthorized API usage, malware signal   | < 1 hour        |
| **Critical** | Major incident / data risk | Credential compromise, data exfiltration | Immediate       |

---

## 5. Roles & Responsibilities

### 5.1 Incident Response Team

| Role                    | Responsibility                                    |
| ----------------------- | ------------------------------------------------- |
| **Security Lead**       | Overall incident coordination and decision-making |
| **On-Call Engineer**    | Technical investigation and remediation           |
| **Cloud Administrator** | IAM, network, and infrastructure actions          |
| **Compliance Officer**  | Regulatory assessment and reporting               |
| **Management**          | Executive escalation and external communication   |

All actions must be performed by authorized personnel only.

---

## 6. Incident Response Lifecycle

### Phase 1: Identification

* Review GuardDuty and Security Hub findings
* Confirm whether the event represents a true incident
* Assign severity level

### Phase 2: Containment

Depending on incident type, containment actions may include:

* Blocking IPs or patterns in AWS WAF
* Isolating EC2 instances (security groups)
* Disabling compromised IAM credentials
* Restricting network access

Containment actions must minimize service disruption where possible.

### Phase 3: Investigation

* Analyze CloudTrail logs for unauthorized API activity
* Review WAF logs for attack patterns
* Examine GuardDuty findings for context
* Preserve all logs and evidence (no deletion)

### Phase 4: Eradication & Recovery

* Remove malicious artifacts
* Rotate credentials and secrets
* Patch vulnerabilities
* Restore systems from trusted sources
* Validate system integrity

### Phase 5: Closure

* Confirm incident resolution
* Document timeline, actions taken, and impact
* Identify lessons learned
* Update procedures if required

---

## 7. Evidence Preservation

During all incidents:

* CloudTrail logs are retained and protected
* WAF logs remain immutable in S3
* GuardDuty findings are preserved
* No log deletion or modification is permitted

Evidence retention follows defined lifecycle policies and compliance requirements.

---

## 8. Communication & Escalation

### Internal Communication

* Security incidents are communicated to the Incident Response Team
* High and Critical incidents are escalated to management immediately

### External Communication

* External notifications (regulators, partners) are handled by management and compliance teams only
* No unauthorized disclosure is permitted

---

## 9. Post-Incident Review

For High and Critical incidents:

* Conduct a post-incident review
* Document root cause and remediation
* Update this IRP if gaps are identified
* Track action items to completion

---

## 10. Testing & Maintenance

* This IRP is reviewed at least annually
* Tabletop exercises may be conducted periodically
* Updates are approved by the Security Lead

---

## 11. Alignment with Security Architecture

This IRP aligns with the following controls:

* **AWS WAF** – attack prevention
* **Amazon GuardDuty** – threat detection
* **AWS Security Hub** – centralized findings
* **AWS CloudTrail** – audit and forensic logging

Incident response actions are fully traceable via CloudTrail.

---

## 12. Approval & Ownership

| Item             | Details              |
| ---------------- | -------------------- |
| Document Owner   | CERPAC Security Team |
| Approved By      | Management           |
| Next Review Date | January 2026         |

---

**End of Document**
