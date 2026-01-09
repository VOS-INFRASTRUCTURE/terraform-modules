################################################################################
# ECR Module Outputs
#
# Single consolidated output containing all repository details.
# Usage: module.ecr_ecs_node_app.ecr_repository.url
#
# Properties:
#   - name: Repository name (e.g., "ecs-node-app")
#   - arn:  Full ARN for IAM policies and resource references
#   - url:  Full registry URL for docker push/pull commands
#           (format: account.dkr.ecr.region.amazonaws.com/repo-name)
################################################################################

output "ecr_repository" {
  description = "ECR repository details (name, arn, url)"
  value = {
    name = aws_ecr_repository.this.name
    arn  = aws_ecr_repository.this.arn
    url  = aws_ecr_repository.this.repository_url
  }
}

