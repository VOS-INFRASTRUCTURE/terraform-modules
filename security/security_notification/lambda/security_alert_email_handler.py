import json
import os
import boto3
from datetime import datetime
import logging

# Configure logging
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO))
logger = logging.getLogger(__name__)

# AWS SES client
ses_client = boto3.client('ses')

# Configuration from environment variables
FROM_EMAIL = os.environ.get("FROM_EMAIL")
TO_EMAILS = os.environ.get("TO_EMAILS", "").split(",")
PROJECT_NAME = os.environ.get("PROJECT_NAME", "AWS")  # Default to "AWS" if not set
ENVIRONMENT = os.environ.get("ENVIRONMENT", "UNKNOWN")  # Default to "UNKNOWN" if not set

# Allow list for reporting
ALLOWED_SEVERITIES = {"CRITICAL", "HIGH"}

SEVERITY_COLOR = {
    "CRITICAL": "#8B0000",
    "HIGH": "#FF0000",
    "MEDIUM": "#FFA500",
    "LOW": "#FFFF00",
    "INFORMATIONAL": "#439FE0",
    "UNKNOWN": "#CCCCCC",
}


def lambda_handler(event, context):
    # Raw event debug - using print to ensure it always shows
    print(f"=== RECEIVED EVENT ===")
    print(json.dumps(event, indent=2, default=str))
    print(f"=== LOG_LEVEL: {os.environ.get('LOG_LEVEL')} ===")

    try:
        sns = event["Records"][0]["Sns"]
        message = json.loads(sns["Message"])
    except Exception as e:
        print(f"ERROR: Failed to parse SNS event: {e}")
        print(f"Event that failed: {json.dumps(event, indent=2, default=str)}")
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
    remediation = ""

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

            # Remediation
            remediation_info = finding.get("Remediation", {})
            if remediation_info:
                recommendation = remediation_info.get("Recommendation", {})
                remediation = recommendation.get("Text", "")

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

            # Remediation
            remediation_info = finding.get("Remediation", {})
            if remediation_info:
                recommendation = remediation_info.get("Recommendation", {})
                remediation = recommendation.get("Text", "")

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

    # Send HTML email
    try:
        print(f"Sending email alert: title={title} severity={normalized_sev}")
        send_email(
            title=title,
            severity=normalized_sev,
            product=product,
            account=account,
            region=region,
            resource=resource,
            description=description,
            types=types,
            threats=threats,
            remediation=remediation,
            console_url=console_url,
            created_at=created_at,
        )
        print("Email delivery success")
        return {"status": "ok"}
    except Exception as e:
        print(f"ERROR: Email delivery failed: {e}")
        logger.exception("Email delivery failed: %s", e)
        return {"status": "error", "error": str(e)}


def send_email(
    title, severity, product, account, region, resource, description, types, threats,
    remediation, console_url, created_at
):
    if not FROM_EMAIL:
        raise Exception("FROM_EMAIL not set")

    if not TO_EMAILS or not TO_EMAILS[0]:
        raise Exception("TO_EMAILS not set")

    color = SEVERITY_COLOR.get(severity, SEVERITY_COLOR["UNKNOWN"])

    # Emoji for severity
    severity_emoji = "🔴" if severity == "CRITICAL" else "🟠"

    # Build HTML email
    html_body = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <style>
            body {{
                font-family: Arial, sans-serif;
                line-height: 1.6;
                color: #333;
                max-width: 800px;
                margin: 0 auto;
                padding: 20px;
            }}
            .header {{
                background: linear-gradient(135deg, {color} 0%, {color}CC 100%);
                color: white;
                padding: 30px;
                border-radius: 8px 8px 0 0;
                text-align: center;
            }}
            .header h1 {{
                margin: 0;
                font-size: 24px;
                font-weight: bold;
            }}
            .severity-badge {{
                display: inline-block;
                background: rgba(255, 255, 255, 0.2);
                padding: 8px 16px;
                border-radius: 20px;
                margin-top: 10px;
                font-size: 14px;
                font-weight: bold;
            }}
            .content {{
                background: #f8f9fa;
                border: 1px solid #dee2e6;
                border-radius: 0 0 8px 8px;
                padding: 30px;
            }}
            .section {{
                background: white;
                padding: 20px;
                margin-bottom: 20px;
                border-radius: 6px;
                border-left: 4px solid {color};
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }}
            .section h2 {{
                margin-top: 0;
                color: {color};
                font-size: 18px;
                border-bottom: 2px solid #e9ecef;
                padding-bottom: 10px;
            }}
            .info-grid {{
                display: grid;
                grid-template-columns: 1fr 1fr;
                gap: 15px;
                margin: 15px 0;
            }}
            .info-item {{
                padding: 10px;
                background: #f8f9fa;
                border-radius: 4px;
            }}
            .info-label {{
                font-weight: bold;
                color: #6c757d;
                font-size: 12px;
                text-transform: uppercase;
                margin-bottom: 5px;
            }}
            .info-value {{
                color: #212529;
                font-size: 14px;
            }}
            .description {{
                background: #fff3cd;
                border: 1px solid #ffc107;
                padding: 15px;
                border-radius: 6px;
                margin: 15px 0;
            }}
            .remediation {{
                background: #d4edda;
                border: 1px solid #28a745;
                padding: 15px;
                border-radius: 6px;
                margin: 15px 0;
            }}
            .remediation h3 {{
                color: #155724;
                margin-top: 0;
            }}
            .code-block {{
                background: #f1f3f5;
                border: 1px solid #dee2e6;
                padding: 12px;
                border-radius: 4px;
                font-family: 'Courier New', monospace;
                font-size: 13px;
                overflow-x: auto;
                margin: 10px 0;
            }}
            .button {{
                display: inline-block;
                background: {color};
                color: white;
                padding: 12px 24px;
                text-decoration: none;
                border-radius: 6px;
                font-weight: bold;
                margin: 20px 0;
                text-align: center;
            }}
            .button:hover {{
                opacity: 0.9;
            }}
            .footer {{
                text-align: center;
                margin-top: 30px;
                padding-top: 20px;
                border-top: 2px solid #dee2e6;
                color: #6c757d;
                font-size: 12px;
            }}
            @media only screen and (max-width: 600px) {{
                .info-grid {{
                    grid-template-columns: 1fr;
                }}
            }}
        </style>
    </head>
    <body>
        <div class="header">
            <h1>{severity_emoji} [{PROJECT_NAME} - {ENVIRONMENT}] {severity} Security Finding</h1>
            <div class="severity-badge">{severity} SEVERITY</div>
        </div>

        <div class="content">
            <div class="section">
                <h2>📋 Finding Details</h2>
                <h3 style="color: #212529; margin-bottom: 15px;">{title}</h3>

                <div class="info-grid">
                    <div class="info-item">
                        <div class="info-label">Source</div>
                        <div class="info-value">{product}</div>
                    </div>
                    <div class="info-item">
                        <div class="info-label">Account</div>
                        <div class="info-value">{account}</div>
                    </div>
                    <div class="info-item">
                        <div class="info-label">Region</div>
                        <div class="info-value">{region}</div>
                    </div>
                    <div class="info-item">
                        <div class="info-label">Resource</div>
                        <div class="info-value">{resource}</div>
                    </div>
                </div>

                {f'<div class="info-item" style="margin-top: 15px;"><div class="info-label">Created At</div><div class="info-value">{created_at}</div></div>' if created_at else ''}
            </div>

            <div class="section">
                <h2>📝 Description</h2>
                <div class="description">
                    {description or "No description provided."}
                </div>
            </div>

            {f'''
            <div class="section">
                <h2>✅ Remediation</h2>
                <div class="remediation">
                    <h3>Recommended Action:</h3>
                    {remediation}
                </div>
            </div>
            ''' if remediation else ''}

            {f'''
            <div class="section">
                <h2>🏷️ Finding Types</h2>
                <div class="code-block">
                    {json.dumps(types, indent=2)}
                </div>
            </div>
            ''' if types else ''}

            {f'''
            <div class="section">
                <h2>⚠️ Threats Detected</h2>
                <div class="code-block">
                    {json.dumps(threats, indent=2)}
                </div>
            </div>
            ''' if threats else ''}

            <div style="text-align: center;">
                <a href="{console_url}" class="button">🔗 Open in AWS Security Hub Console</a>
            </div>
        </div>

        <div class="footer">
            <p>This is an automated security alert from AWS Security Hub</p>
            <p>Only HIGH and CRITICAL severity findings are sent via email</p>
        </div>
    </body>
    </html>
    """

    # Plain text version (fallback)
    text_body = f"""
[{PROJECT_NAME} - {ENVIRONMENT}] {severity_emoji} {severity} Security Finding

Title: {title}
Severity: {severity}
Source: {product}
Account: {account}
Region: {region}
Resource: {resource}

Description:
{description}

{f'Remediation:\n{remediation}\n' if remediation else ''}
{f'Types:\n{json.dumps(types, indent=2)}\n' if types else ''}
{f'Threats:\n{json.dumps(threats, indent=2)}\n' if threats else ''}

Open in AWS Console: {console_url}

---
This is an automated security alert from {PROJECT_NAME} - {ENVIRONMENT}.
Only HIGH and CRITICAL severity findings are sent via email.
"""

    # Send email via SES
    response = ses_client.send_email(
        Source=FROM_EMAIL,
        Destination={
            'ToAddresses': [email.strip() for email in TO_EMAILS if email.strip()]
        },
        Message={
            'Subject': {
                'Data': f'[{PROJECT_NAME} - {ENVIRONMENT}] {severity_emoji} {severity}: {title[:80]}',
                'Charset': 'UTF-8'
            },
            'Body': {
                'Text': {
                    'Data': text_body,
                    'Charset': 'UTF-8'
                },
                'Html': {
                    'Data': html_body,
                    'Charset': 'UTF-8'
                }
            }
        }
    )

    return response

