import base64
import json
import logging
import re

# Configure logger
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def sanitize_log(value: str) -> str:
    """
    Sanitize a string before logging to prevent log injection.
    Removes newlines, carriage returns, and tabs.
    Converts non-string values to string.
    """
    if not isinstance(value, str):
        value = str(value)
    return re.sub(r'[\r\n\t]', ' ', value)

def lambda_handler(event, context):
    output = []

    records = event.get("records", [])
    logger.info({"event_records_count": len(records)})

    for record in records:
        record_id = sanitize_log(record.get("recordId", "unknown"))

        try:
            # Decode and parse WAF log payload
            payload = base64.b64decode(record["data"])
            waf_log = json.loads(payload)

            # Extract action and log_type
            action = sanitize_log(waf_log.get("action", "ALLOW").upper())
            log_type = "blocked" if action == "BLOCK" else "allowed"

            # Log safely using sanitized values
            logger.info({
                "message": "Processing WAF record",
                "record_id": record_id,
                "action": action,
                "log_type": log_type
            })

            # Append processed record to output
            output.append({
                "recordId": record_id,
                "result": "Ok",
                "data": record["data"],  # Pass-through
                "metadata": {
                    "partitionKeys": {
                        "log_type": log_type
                    }
                }
            })

        except Exception as e:
            # Log errors safely
            logger.error({
                "message": "Error processing WAF record",
                "record_id": record_id,
                "error": sanitize_log(str(e))
            })

            # Mark record as failed
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
