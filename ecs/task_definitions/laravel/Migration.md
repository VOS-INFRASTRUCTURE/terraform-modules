- Redis App
    - Ensure redis is setup on AWS and running
    - Ensure monitoring and dashboard are setup and running
    - Create Application for this Account on the IC
        - Name: Redis Management Staging Cerpac Cognito
        - Description: Protects Redis Insight & Netdata on the aws account  SAML 2.0 application
        - Copy its metadata and use on your icognitor terraform configuration
    -   Add the domains to the identity centers


- Laravel App
    - Ensure ENVS are set and ENV examples are structured and updated
    - Ensure horizon is installed
    - Ensure all redis database are configured and output set to stderr
    - Test locally to ensure it is still working fine

    - WORKFLOW
        - CONFIGURE Repository Secrets
        - Include AWS ACCOUNT ID and ROLE ARN


- Terraform
    - Create ECR
    - Create Cluster
    - Create Security Group
    - Assign Security Group to All VPC ENDPOINTS
    - ALB - Already exists
    - Create Param Store and Secret Store
    - Create IAM Roles
    - Create Task Definitions
        - app, horzon, scheduler
    - Create App Service
    - Create CI/CD Role ARN
    - Create Horizon Service
    - Create Scheduler EventBridge
    - Create AutoScaling
