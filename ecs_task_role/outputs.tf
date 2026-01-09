################################################################################
# Module Outputs: ECS Task Role
#
# Single consolidated output containing all role details.
# Usage: module.ecs_task_role.role.arn
#
# Properties:
#   - arn:  Full ARN for use in ECS task definitions
#   - name: Role name for policy attachments or references
#   - id:   Role ID for internal Terraform dependencies
################################################################################

output "role" {
  description = "ECS Task Role details (arn, name, id)"
  value = {
    arn  = aws_iam_role.ecs_task_role.arn
    name = aws_iam_role.ecs_task_role.name
    id   = aws_iam_role.ecs_task_role.id
  }
}

