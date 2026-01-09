################################################################################
# Module: ECR
# Purpose: Create an Amazon ECR repository for container images.
################################################################################

resource "aws_ecr_repository" "this" {
  name                 = var.repo_name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  tags = {
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "ECR"
  }
}

################################################################################
# Lifecycle Policy – Automatic Image Cleanup
#
# Purpose: Prevent unbounded repository growth and reduce storage costs
#
# Strategy:
# - Keep the latest N images (based on push time)
# - Delete older images automatically
#
# Example: With lifecycle_keep_last_count = 10
# - Repo has images: v1, v2, v3, ..., v15
# - Policy keeps: v6, v7, v8, v9, v10, v11, v12, v13, v14, v15
# - Policy deletes: v1, v2, v3, v4, v5
################################################################################

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.lifecycle_keep_last_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.lifecycle_keep_last_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
