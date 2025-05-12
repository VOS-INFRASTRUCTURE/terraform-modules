output "bucket_details" {
  description = "Details of the IAM user"
  value = {
    user_name   = aws_iam_user.user.name
    access_key  = aws_iam_access_key.user_key.id
    secret_key  = aws_iam_access_key.user_key.secret
  }
  sensitive = true
}
