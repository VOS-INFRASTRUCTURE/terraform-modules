################################################################################
# Passwords — one per app, stored in Secrets Manager
#
# special = false avoids shell-quoting issues when the password is written
# into redis.conf by 01_deploy_app2.sh.
################################################################################

resource "random_password" "app1_redis" {
  length  = 32
  special = false
}

resource "random_password" "app2_redis" {
  length  = 32
  special = false
}

################################################################################
# Secrets Manager
################################################################################

resource "aws_secretsmanager_secret" "app1_redis" {
  name                    = "${var.env}-${var.project_id}-app1-redis-password"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "app1_redis" {
  secret_id     = aws_secretsmanager_secret.app1_redis.id
  secret_string = random_password.app1_redis.result
}

resource "aws_secretsmanager_secret" "app2_redis" {
  name                    = "${var.env}-${var.project_id}-app2-redis-password"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "app2_redis" {
  secret_id     = aws_secretsmanager_secret.app2_redis.id
  secret_string = random_password.app2_redis.result
}
