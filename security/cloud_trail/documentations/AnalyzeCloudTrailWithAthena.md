```shell
SELECT 
    eventtime,
    useridentity.userName,
    sourceipaddress,
    eventname,
    awsregion,
    errorcode
FROM default.cloudtrail_logs_production_cerpac_cloudtrail_logs
WHERE errorcode IS NOT NULL AND from_iso8601_timestamp(eventtime) BETWEEN 
      timestamp '2026-02-12 21:30:00' AND timestamp '2026-02-12 21:45:00'
ORDER BY from_iso8601_timestamp(eventtime) DESC;

```


Identify the IP address that made the request.

```shell
SELECT 
    eventtime,
    useridentity.userName,
    useridentity.arn,
    sourceipaddress,
    eventname,
    awsregion,
    errorcode
FROM default.cloudtrail_logs_production_cerpac_cloudtrail_logs
WHERE  errorcode IS NOT NULL AND sourceipaddress = '102.91.103.191'
  AND from_iso8601_timestamp(eventtime) BETWEEN 
      timestamp '2026-02-12 21:30:00' AND timestamp '2026-02-12 21:45:00'
ORDER BY from_iso8601_timestamp(eventtime) DESC;


```