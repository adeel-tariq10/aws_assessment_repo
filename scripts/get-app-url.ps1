# Returns the URL for the running ECS task (public IP on port 3000).
param(
    [string]$AwsRegion = "us-west-2",
    [string]$Cluster = "assessment-hello-world-cluster",
    [string]$Service = "assessment-hello-world-service"
)

$ErrorActionPreference = "Stop"

$taskArn = aws ecs list-tasks `
    --cluster $Cluster `
    --service-name $Service `
    --desired-status RUNNING `
    --query "taskArns[0]" `
    --output text `
    --region $AwsRegion

if (-not $taskArn -or $taskArn -eq "None") {
    Write-Host "No running tasks found. Wait for the ECS service to stabilize." -ForegroundColor Yellow
    exit 1
}

$eniId = aws ecs describe-tasks `
    --cluster $Cluster `
    --tasks $taskArn `
    --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value | [0]" `
    --output text `
    --region $AwsRegion

$publicIp = aws ec2 describe-network-interfaces `
    --network-interface-ids $eniId `
    --query "NetworkInterfaces[0].Association.PublicIp" `
    --output text `
    --region $AwsRegion

$url = "http://${publicIp}:3000"
Write-Host "App URL: $url" -ForegroundColor Green
Write-Host "Health:  ${url}/health"
