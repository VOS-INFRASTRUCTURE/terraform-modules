################################################################################
# Module Outputs: ECS Task Execution Role
#
# Single consolidated output containing all role details.
# Usage: module.ecs_task_execution_role.role.arn
#
# Properties:
#   - arn:  Full ARN for use in ECS task definitions
#   - name: Role name for policy attachments or references
#   - id:   Role ID for internal Terraform dependencies
################################################################################

output "role" {
  description = "ECS Task Execution Role details (arn, name, id)"
  value = {
    arn  = aws_iam_role.ecs_task_execution.arn
    name = aws_iam_role.ecs_task_execution.name
    id   = aws_iam_role.ecs_task_execution.id
  }
}

