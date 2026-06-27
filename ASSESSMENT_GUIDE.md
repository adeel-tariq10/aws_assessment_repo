# AWS Technical Assessment — Step-by-Step Guide

This guide walks you through the full assessment: local app → Docker → AWS → CI/CD → Loom recording.

---

## Architecture Overview

```
Developer pushes code to GitHub (main branch)
        │
        ▼
GitHub Actions workflow triggers
        │
        ├── Checkout source code
        ├── Assume AWS IAM role (OIDC — no long-lived keys)
        ├── docker build → tag with git commit SHA
        ├── docker push → Amazon ECR (container registry)
        ├── Update ECS task definition with new image
        └── ECS Fargate rolls out new container (zero-downtime deploy)
                │
                ▼
        Public IP :3000 → Hello World JSON response
```

**AWS services used:**

| Service | Purpose |
|---------|---------|
| **ECR** | Stores Docker images |
| **ECS Fargate** | Runs containers without managing servers |
| **IAM + OIDC** | Secure CI/CD auth from GitHub (no static AWS keys) |
| **CloudWatch Logs** | Container stdout/stderr |
| **VPC / Security Group** | Network isolation; port 3000 open for demo |

---

## Phase 0 — Prerequisites (install once)

Your machine currently needs these tools. Install before recording.

### 1. Docker Desktop (Windows)
- Download: https://www.docker.com/products/docker-desktop/
- Install, restart, and verify: `docker --version`
- Start Docker Desktop before building images

### 2. AWS CLI v2
- Download: https://aws.amazon.com/cli/
- Verify: `aws --version`
- Configure/sign in with the AWS CLI and use the assessment region `us-west-2`

### 3. AWS account
- Free tier is sufficient for this demo
- Billing alert recommended (AWS Budgets)

### 4. GitHub account
- Create a **public** repo (easier for OIDC demo) or private with same setup

### 5. Loom (or OBS / Windows Game Bar)
- https://www.loom.com — free tier works

---

## Phase 1 — Local project (Steps 1–3)

**Already done in this folder.** You have:

- `app/server.js` — Express Hello World API
- `package.json` — dependencies
- `Dockerfile` — container build instructions
- `.github/workflows/deploy.yml` — CI/CD pipeline

### Step 1: Initialize Git

```powershell
cd "C:\Users\Dev\Desktop\AWS Technical Assessment"
git init
git add .
git commit -m "Initial commit: Hello World app with Docker and CI/CD"
```

### Step 2: Create GitHub repo and push

1. Go to https://github.com/new
2. Name: `aws_assessment_repo` (or your choice - update scripts if different)
3. Do **not** initialize with README (you already have files)
4. Push:

```powershell
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/aws_assessment_repo.git
git push -u origin main
```

### Step 3: Explain the Dockerfile (for your recording)

Open `Dockerfile` and explain each section:

| Line | What to say |
|------|-------------|
| `FROM node:20-alpine` | Base image — official Node on minimal Linux |
| `WORKDIR /app` | All commands run inside `/app` |
| `COPY package.json` + `RUN npm install` | **Layer caching** — deps rebuild only when package.json changes |
| `COPY app/` | Application code copied after deps |
| `EXPOSE 3000` | Documents the port (does not publish it) |
| `USER node` | Non-root user for security |
| `CMD ["npm", "start"]` | Default process when container starts |

---

## Phase 2 — Build and run locally (Step 4)

**Say in recording:** "Before deploying to AWS, I verify the container works locally."

```powershell
# Install deps (optional — Docker will do this too)
npm install

# Build the image
docker build -t hello-aws-assessment:local .

# Run the container (maps host 3000 → container 3000)
docker run -p 3000:3000 hello-aws-assessment:local
```

Open http://localhost:3000 — you should see JSON:

```json
{"message":"Hello from AWS!","version":"1.0.0",...}
```

Stop with `Ctrl+C`, then:

```powershell
docker ps -a
docker images
```

**Explain:** `docker build` reads the Dockerfile and creates an image. `docker run` starts a container from that image.

---

## Phase 3 — Deploy to AWS (Step 5)

### One-time AWS setup

After `aws configure` works:

```powershell
cd "C:\Users\Dev\Desktop\AWS Technical Assessment"
.\scripts\setup-aws.ps1 -GitHubOrg YOUR_GITHUB_USERNAME -GitHubRepo aws_assessment_repo
```

This creates: ECR repo, ECS cluster/service, IAM roles, security group, CloudWatch log group.

**Copy the `AWS_ROLE_ARN` output** and add it in GitHub:

1. Repo → **Settings** → **Secrets and variables** → **Actions**
2. New secret: `AWS_ROLE_ARN` = (value from script)

### Update task definition with real ARNs

Edit `infra/task-definition.json` — replace the three `REPLACE_WITH_*` placeholders with values from the setup script output (or leave placeholders; the setup script registers an initial task definition).

Commit and push:

```powershell
git add infra/task-definition.json
git commit -m "Configure ECS task definition with AWS ARNs"
git push
```

### First deploy via CI/CD

The push to `main` triggers GitHub Actions. Watch: **Actions** tab in GitHub.

When green, get your app URL:

```powershell
.\scripts\get-app-url.ps1
```

Open the URL in a browser — same Hello JSON, now on AWS.

**Manual alternative (if you want to demo ECR push before CI/CD):**

```powershell
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com
docker tag hello-aws-assessment:local ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/assessment-hello-world:latest
docker push ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/assessment-hello-world:latest
```

---

## Phase 4 — CI/CD demo (Steps 6–7)

### Show the workflow file

Open `.github/workflows/deploy.yml` and explain:

1. **Trigger:** `push` to `main` (and manual `workflow_dispatch`)
2. **OIDC auth:** `configure-aws-credentials` assumes IAM role — no secrets except `AWS_ROLE_ARN`
3. **Build & push:** Docker image tagged with `github.sha` for traceability
4. **Deploy:** ECS task definition updated → service rolling update

### Demo a code change end-to-end

```powershell
# Edit app/server.js — change message to "Hello from AWS — deployed via CI/CD!"
git add app/server.js
git commit -m "Update welcome message to demonstrate CI/CD"
git push
```

**Say in recording:** "This push triggers the pipeline. GitHub Actions builds a new image, pushes to ECR, and ECS replaces the running task with zero downtime."

Watch Actions → then refresh the app URL (may take 2–5 minutes).

---

## Phase 5 — Recording script (Step 8)

Suggested **10–15 minute** Loom outline:

| Time | Section | What to show |
|------|---------|--------------|
| 0:00 | Intro | "Simple Hello World on AWS with Docker and GitHub Actions CI/CD" |
| 0:30 | Repo | File tree: app, Dockerfile, workflow |
| 2:00 | Dockerfile | Walk line-by-line (table above) |
| 4:00 | Local Docker | `docker build`, `docker run`, localhost:3000 |
| 6:00 | Architecture | Diagram (below) or whiteboard |
| 8:00 | AWS Console | ECR image, ECS cluster/service, running task, CloudWatch logs |
| 10:00 | CI/CD | GitHub Actions run; explain push → build → ECR → ECS |
| 12:00 | Live change | Edit message, push, show new response |
| 14:00 | Wrap | Best practices: OIDC, layer caching, health checks, Fargate vs EC2 |

### Architecture diagram (draw or show)

```
┌─────────────┐     push      ┌──────────────────┐
│   GitHub    │──────────────▶│  GitHub Actions  │
│   (main)    │               │  build + deploy  │
└─────────────┘               └────────┬─────────┘
                                       │ OIDC
                                       ▼
                              ┌──────────────────┐
                              │   Amazon ECR     │
                              │  (Docker images) │
                              └────────┬─────────┘
                                       │ pull
                                       ▼
                              ┌──────────────────┐
                              │  ECS Fargate     │
                              │  (assessment app)│
                              └────────┬─────────┘
                                       │ :3000
                                       ▼
                                   Browser
```

### Talking points (best practices)

- **Why Fargate?** No EC2 to patch; good for small services and demos
- **Why ECR?** Native integration with ECS; private registry in your account
- **Why OIDC vs access keys?** Short-lived credentials; keys never stored in GitHub
- **Alternatives:** App Runner (simpler), Elastic Beanstalk, EKS (Kubernetes), Lambda (if app fit serverless)

---

## Phase 6 — Cleanup (after assessment)

Avoid ongoing charges:

```powershell
aws ecs update-service --cluster assessment-hello-world-cluster --service assessment-hello-world-service --desired-count 0 --region us-west-2
aws ecs delete-service --cluster assessment-hello-world-cluster --service assessment-hello-world-service --force --region us-west-2
aws ecs delete-cluster --cluster assessment-hello-world-cluster --region us-west-2
aws ecr delete-repository --repository-name assessment-hello-world --force --region us-west-2
aws logs delete-log-group --log-group-name /ecs/assessment-hello-world --region us-west-2
# Delete IAM roles and security group via console or CLI as needed
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Docker not found | Install Docker Desktop; restart terminal |
| AWS CLI not found | Install AWS CLI v2; add to PATH |
| GitHub Action fails on OIDC | Check `AWS_ROLE_ARN` secret; repo name in IAM trust policy |
| ECS task won't start | CloudWatch -> `/ecs/assessment-hello-world`; check execution role |
| Can't reach app URL | Security group must allow TCP 3000; task needs `assignPublicIp=ENABLED` |
| `wget` health check fails | Alpine image has wget; if you change base image, adjust health check |

---

## Deliverable checklist

- [ ] Git repo with app, Dockerfile, workflow
- [ ] Local `docker build` / `docker run` demonstrated
- [ ] Container running on AWS (ECS + ECR)
- [ ] CI/CD triggered from GitHub push
- [ ] Code change deployed automatically
- [ ] Loom recording with architecture explanation
- [ ] Shareable Loom link submitted

---

## Next step for you

**Start with Phase 0** — install Docker Desktop and AWS CLI, then tell me when ready and we can walk through Phase 1 together live (git init, first build, AWS setup).
