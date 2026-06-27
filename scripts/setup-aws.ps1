# AWS one-time infrastructure setup for the Hello AWS assessment.
# Run from PowerShell after: aws configure (or SSO login)
#
# Usage:
#   .\scripts\setup-aws.ps1 -GitHubOrg YOUR_GITHUB_USERNAME -GitHubRepo aws_assessment_repo

param(
    [Parameter(Mandatory = $true)]
    [string]$GitHubOrg,

    [Parameter(Mandatory = $true)]
    [string]$GitHubRepo,

    [string]$AwsRegion = "us-west-2",
    [string]$ProjectName = "assessment-hello-world"
)

$ErrorActionPreference = "Stop"

Write-Host "=== AWS Assessment Infrastructure Setup ===" -ForegroundColor Cyan
Write-Host "Region: $AwsRegion"
Write-Host "GitHub: $GitHubOrg/$GitHubRepo"
Write-Host ""

# Get default VPC and a public subnet
$vpcId = aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text --region $AwsRegion
$subnetId = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpcId" "Name=default-for-az,Values=true" --query "Subnets[0].SubnetId" --output text --region $AwsRegion
$accountId = aws sts get-caller-identity --query Account --output text

Write-Host "Account: $accountId"
Write-Host "VPC: $vpcId"
Write-Host "Subnet: $subnetId"

# CloudWatch log group
aws logs create-log-group --log-group-name "/ecs/$ProjectName" --region $AwsRegion 2>$null
Write-Host "Log group: /ecs/$ProjectName"

# ECR repository
aws ecr create-repository --repository-name $ProjectName --region $AwsRegion 2>$null
$ecrUri = "$accountId.dkr.ecr.$AwsRegion.amazonaws.com/$ProjectName"
Write-Host "ECR: $ecrUri"

# Security group - allow inbound HTTP on port 3000
$sgId = aws ec2 create-security-group `
    --group-name "$ProjectName-sg" `
    --description "Allow HTTP for Hello AWS assessment" `
    --vpc-id $vpcId `
    --region $AwsRegion `
    --query GroupId --output text 2>$null

if (-not $sgId -or $sgId -eq "None") {
    $sgId = aws ec2 describe-security-groups `
        --filters "Name=group-name,Values=$ProjectName-sg" `
        --query "SecurityGroups[0].GroupId" --output text --region $AwsRegion
}

aws ec2 authorize-security-group-ingress `
    --group-id $sgId `
    --protocol tcp `
    --port 3000 `
    --cidr 0.0.0.0/0 `
    --region $AwsRegion 2>$null

Write-Host "Security group: $sgId"

$clusterName = "$ProjectName-cluster"
$serviceName = "$ProjectName-service"

# ECS cluster
aws ecs create-cluster --cluster-name $clusterName --region $AwsRegion 2>$null
Write-Host "ECS cluster: $clusterName"

# IAM roles
$trustPolicy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ecs-tasks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
"@

$execRoleName = "$ProjectName-ecs-execution"
$taskRoleName = "$ProjectName-ecs-task"
$githubRoleName = "$ProjectName-github-actions"

aws iam create-role --role-name $execRoleName --assume-role-policy-document $trustPolicy 2>$null
aws iam attach-role-policy --role-name $execRoleName --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>$null

aws iam create-role --role-name $taskRoleName --assume-role-policy-document $trustPolicy 2>$null

$execRoleArn = aws iam get-role --role-name $execRoleName --query Role.Arn --output text
$taskRoleArn = aws iam get-role --role-name $taskRoleName --query Role.Arn --output text

Write-Host "Execution role: $execRoleArn"
Write-Host "Task role: $taskRoleArn"

# GitHub OIDC provider (idempotent - may already exist)
$oidcProviderArn = "arn:aws:iam::${accountId}:oidc-provider/token.actions.githubusercontent.com"
aws iam create-open-id-connect-provider `
    --url https://token.actions.githubusercontent.com `
    --client-id-list sts.amazonaws.com `
    --thumbprint-list 6938fd4d98bab03faadfb0f0c1d4a5b2d5a5b2d5a `
    2>$null

$githubTrust = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${accountId}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GitHubOrg}/${GitHubRepo}:*"
        }
      }
    }
  ]
}
"@

aws iam create-role --role-name $githubRoleName --assume-role-policy-document $githubTrust 2>$null

$githubPolicy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeServices",
        "ecs:DescribeTaskDefinition",
        "ecs:DescribeTasks",
        "ecs:ListTasks",
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": ["$execRoleArn", "$taskRoleArn"]
    }
  ]
}
"@

aws iam put-role-policy --role-name $githubRoleName --policy-name deploy-policy --policy-document $githubPolicy 2>$null
$githubRoleArn = aws iam get-role --role-name $githubRoleName --query Role.Arn --output text
Write-Host "GitHub Actions role: $githubRoleArn"

# Register initial task definition
$taskDefPath = Join-Path $PSScriptRoot "..\infra\task-definition.json"
$taskDef = Get-Content $taskDefPath -Raw
$taskDef = $taskDef.Replace("REPLACE_WITH_EXECUTION_ROLE_ARN", $execRoleArn)
$taskDef = $taskDef.Replace("REPLACE_WITH_TASK_ROLE_ARN", $taskRoleArn)
$taskDef = $taskDef.Replace("REPLACE_WITH_ECR_IMAGE_URI", "${ecrUri}:latest")

$tempTaskDef = Join-Path $env:TEMP "task-definition-resolved.json"
$taskDef | Set-Content $tempTaskDef -Encoding UTF8

$taskDefArn = aws ecs register-task-definition --cli-input-json "file://$tempTaskDef" --query "taskDefinition.taskDefinitionArn" --output text --region $AwsRegion
Write-Host "Task definition: $taskDefArn"

# Create ECS service
aws ecs create-service `
    --cluster $clusterName `
    --service-name $serviceName `
    --task-definition $taskDefArn `
    --desired-count 1 `
    --launch-type FARGATE `
    --network-configuration "awsvpcConfiguration={subnets=[$subnetId],securityGroups=[$sgId],assignPublicIp=ENABLED}" `
    --region $AwsRegion 2>$null

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Add this GitHub repository secret:" -ForegroundColor Yellow
Write-Host "  Name:  AWS_ROLE_ARN"
Write-Host "  Value: $githubRoleArn"
Write-Host ""
Write-Host "Update infra/task-definition.json with your role ARNs and ECR URI, then commit."
Write-Host ""
Write-Host "Get the public IP of your running task:" -ForegroundColor Yellow
Write-Host "  aws ecs list-tasks --cluster $clusterName --service-name $serviceName --region $AwsRegion"
Write-Host "  aws ecs describe-tasks --cluster $clusterName --tasks <TASK_ARN> --query 'tasks[0].attachments[0].details[?name==\`networkInterfaceId\`].value' --output text --region $AwsRegion"
Write-Host "  Then look up the public IP in EC2 > Network Interfaces, or use the helper script:"
Write-Host "  .\scripts\get-app-url.ps1 -AwsRegion $AwsRegion -Cluster $clusterName -Service $serviceName"
