import json
import os
import urllib.request
from datetime import datetime
import logging

# Configure logging
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO))
logger = logging.getLogger(__name__)

SLACK_WEBHOOK_URL = os.environ.get("SLACK_WEBHOOK_URL")
PROJECT_NAME = os.environ.get("PROJECT_NAME", "AWS")  # Default to "AWS" if not set

SEVERITY_COLOR = {
    "CRITICAL": "#8B0000",
    "HIGH": "#FF0000",
    "MEDIUM": "#FFA500",
    "LOW": "#FFFF00",
    "INFORMATIONAL": "#439FE0",
    "UNKNOWN": "#CCCCCC",
}

# Allow list for reporting
ALLOWED_SEVERITIES = {"CRITICAL", "HIGH"}


def lambda_handler(event, context):
    # Raw event debug - using print to ensure it always shows
    print(f"=== RECEIVED EVENT ===")
    print(json.dumps(event, indent=2))
    print(f"=== LOG_LEVEL: {os.environ.get('LOG_LEVEL')} ===")

    try:
        sns = event["Records"][0]["Sns"]
        message = json.loads(sns["Message"])
    except Exception as e:
        print(f"ERROR: Failed to parse SNS event: {e}")
        print(f"Event that failed: {json.dumps(event, indent=2)}")
        logger.exception("Failed to parse SNS event: %s", e)
        return {"status": "error", "error": str(e)}

    # Defaults
    title = "Security Finding"
    severity = "UNKNOWN"
    product = "Security Hub"
    account = message.get("account", "Unknown")
    region = message.get("region", "Unknown")
    resource = "Unknown"
    description = ""
    console_url = "https://console.aws.amazon.com/securityhub/home"
    created_at = None
    types = []
    threats = []

    # ---------------------------
    # Security Hub Findings
    # ---------------------------
    if "detail" in message and "findings" in message["detail"]:
        finding = message["detail"]["findings"][0]

        # Prefer SourceUrl if available
        console_url = finding.get("SourceUrl", console_url)

        # ---------- OCSF / V2 ----------
        if "finding_info" in finding:
            title = finding.get("title", title)
            severity = finding.get("severity", severity) or "UNKNOWN"
            created_at = finding.get("created_time_dt")

            description = finding.get("finding_info", {}).get("desc", "")

            account = (
                finding.get("cloud", {})
                .get("account", {})
                .get("uid", account)
            )

            region = finding.get("cloud", {}).get("region", region)

            product = (
                finding.get("metadata", {})
                .get("product", {})
                .get("name", product)
            )

            types = finding.get("types", [])
            threats = finding.get("Threats", [])

            # Prefer EC2 instance name
            for r in finding.get("resources", []):
                if r.get("type") == "AWS::EC2::Instance":
                    resource = r.get("uid", resource)
                    tags = r.get("Tags", {})
                    if "Name" in tags:
                        resource = f"{tags['Name']} ({resource})"
                    break

        # ---------- Classic ASFF ----------
        else:
            title = finding.get("Title", title)
            description = finding.get("Description", "")
            severity = finding.get("Severity", {}).get("Label", severity) or "UNKNOWN"
            product = finding.get("ProductName", product)
            account = finding.get("AwsAccountId", account)
            region = finding.get("Region", region)
            created_at = finding.get("CreatedAt")

            types = finding.get("Types", [])
            threats = finding.get("Threats", [])

            resources = finding.get("Resources", [])
            if resources:
                resource = resources[0].get("Id", resource)
                tags = resources[0].get("Tags", {})
                if "Name" in tags:
                    resource = f"{tags['Name']} ({resource})"

    # Suppress non-HIGH/CRITICAL severities
    normalized_sev = str(severity).upper()
    print(f"Parsed severity: {normalized_sev}")

    if normalized_sev not in ALLOWED_SEVERITIES:
        print(f"Suppressed finding with severity={normalized_sev} title={title}")
        return {"status": "suppressed", "severity": severity}

    color = SEVERITY_COLOR.get(normalized_sev, SEVERITY_COLOR["UNKNOWN"])

    # Severity emoji
    severity_emoji = "🔴" if normalized_sev == "CRITICAL" else "🟠"

    attachment_text = f"""
*[{PROJECT_NAME}] {severity_emoji} {severity} Security Finding*

*Title:* {title}
*Severity:* {severity}
*Source:* {product}
*Account:* {account}
*Region:* {region}
*Resource:* {resource}

*Description:*
{description}
"""

    if types:
        attachment_text += f"\n*Types:*\n```{json.dumps(types, indent=2)}```"

    if threats:
        attachment_text += f"\n*Threats:*\n```{json.dumps(threats, indent=2)}```"

    attachment_text += f"\n<{console_url}|Open in AWS Console>"

    slack_payload = {
        "attachments": [
            {
                "color": color,
                "text": attachment_text,
                "footer": f"CreatedAt: {created_at}" if created_at else None,
            }
        ]
    }

    try:
        print(f"Sending alert to Slack: title={title} severity={normalized_sev}")
        send_to_slack(slack_payload)
        print("Slack delivery success")
        return {"status": "ok"}
    except Exception as e:
        print(f"ERROR: Slack delivery failed: {e}")
        logger.exception("Slack delivery failed: %s", e)
        return {"status": "error", "error": str(e)}


def send_to_slack(payload):
    if not SLACK_WEBHOOK_URL:
        raise Exception("SLACK_WEBHOOK_URL not set")

    req = urllib.request.Request(
        SLACK_WEBHOOK_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    with urllib.request.urlopen(req) as response:
        response.read()
