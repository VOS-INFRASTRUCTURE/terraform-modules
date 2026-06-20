# Add-App Template

Copy and customize these files to add App 3, App 4, and so on to the shared Redis host.

## Checklist

- [ ] Pick the next available port (`6381` for App 3, `6382` for App 4, …)
- [ ] Replace every occurrence of `N` / `appN` / `APPN` with the real app number
- [ ] Add Terraform resources (Snippet A)
- [ ] `terraform apply`
- [ ] Retrieve the new password and run the deploy script (Snippet B)
- [ ] Update CloudWatch to ship the new log stream
- [ ] Verify isolation with `scripts/03_verify.sh`

---

## Snippet A — Terraform changes

Copy `terraform/_snippet.tf` into `terraform/` as `app3.tf` (or `app4.tf`, etc.)
and fill in the port and app number. Alternatively, paste the block directly into `main.tf`.

After editing, run:
```bash
terraform apply
APP_N_PASS=$(terraform output -raw appN_redis_password)
```

---

## Snippet B — Deploy script

Copy `scripts/deploy_appN.sh`, set `APP_NUMBER` and `REDIS_PORT` at the top,
then run it via SSM:

```bash
# From your local terminal
SSM_CMD=$(terraform output -raw redis_host_ssm)
$SSM_CMD

# Inside the SSM session — paste the edited script or upload it first
sudo bash deploy_appN.sh "$APP_N_PASS"
```

---

## Port Assignment Reference

| App | Port | SG rule variable |
|-----|------|-----------------|
| App 1 | 6379 | `app1_security_group_id` (module default) |
| App 2 | 6380 | `app2_security_group_id` |
| App 3 | 6381 | `app3_security_group_id` |
| App 4 | 6382 | `app4_security_group_id` |
| … | … | … |
