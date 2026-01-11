import base64
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    output = []

    for record in event.get("records", []):
        record_id = record["recordId"]

        try:
            payload = base64.b64decode(record["data"])
            waf_log = json.loads(payload)

            # WAF decision is always uppercase ALLOW / BLOCK
            action = waf_log.get("action", "ALLOW")

            if action == "BLOCK":
                log_type = "blocked"
            else:
                log_type = "allowed"

            logger.info(f"Processing record {record_id}: action={action}, log_type={log_type}")

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
            # Never let Firehose fail the batch
            logger.error(f"Error processing record {record_id}: {str(e)}")
            output.append({
                "recordId": record_id,
                "result": "ProcessingFailed",
                "data": record["data"]
            })

    logger.info(f"Processed {len(output)} records")
    return {"records": output}
