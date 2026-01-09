cluster => Cluster is a logical grouping of services
 |||
  v
service => A service is used to run and maintain a specified 
           number of instances of a tasks simultaneously in a cluster
           It is where you will find the deployment status of your tasks if it fails or not.
            It is the place where you will configure
            - Security groups
            - Load balancers
            - Desired count of tasks
            - Auto-scaling policies
            - Launch type (Fargate or EC2)
            - Elastic IPs auto assignment. This also depends if it is on public subnet or private subnet.
                However, if elastic IPs are assigned, it will always be public IPs.
            ALB is under service->configuration and networking tab.
 |||
  v
Tasks  => Created from a task definition.
          You can view the details of running task including the ips and so on.
An example of a running task url will be like this:
https://eu-west-2.console.aws.amazon.com/ecs/v2/clusters/ecs-node-app-cluster/services/staging-ecs-node-app-service/tasks/e3a3da492b914222958c6d0fc1e58c54/
Where:
  - ecs-node-app-cluster is the cluster name
  - staging-ecs-node-app-service is the service name
  - e3a3da492b914222958c6d0fc1e58c54 is the task id (Active running task)

    You will also see the list of containers running as part of the task.

 |||      Task definition contains a template for creating tasks including:
  v       - Docker image to use
          - CPU and memory requirements
          - Networking mode
          - IAM role
          - Environment variables
          - Logging configuration
          - Volume definitions
 |||
  v
container