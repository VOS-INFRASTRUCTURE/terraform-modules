import base64
import json
import logging
import re

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def sanitize_log(value: str) -> str:
    if not isinstance(value, str):
        value = str(value)
    return re.sub(r'[\r\n\t]', ' ', value)

def lambda_handler(event, context):

    output = []

    records = event.get("records", [])
    logger.info({"event_records_count": len(records)})

    account_id = context.invoked_function_arn.split(":")[4]
    region = context.invoked_function_arn.split(":")[3]

    for record in records:
        record_id = sanitize_log(record.get("recordId", "unknown"))

        try:
            payload = base64.b64decode(record["data"])
            waf_log = json.loads(payload)

            action = sanitize_log(waf_log.get("action", "ALLOW").upper())
            log_type = "blocked" if action == "BLOCK" else "allowed"

            logger.info({
                "message": "Processing WAF record",
                "record_id": record_id,
                "action": action,
                "log_type": log_type
            })

            output.append({
                "recordId": record_id,
                "result": "Ok",
                "data": record["data"],
                "metadata": {
                    "partitionKeys": {
                        "log_type": log_type,
                        "account_id": account_id,
                        "region": region
                    }
                }
            })

        except Exception as e:

            logger.error({
                "message": "Error processing WAF record",
                "record_id": record_id,
                "error": sanitize_log(str(e))
            })

            output.append({
                "recordId": record_id,
                "result": "ProcessingFailed",
                "data": record["data"]
            })

    logger.info({
        "message": "Finished processing WAF records",
        "total_records": len(output)
    })

    return {"records": output}