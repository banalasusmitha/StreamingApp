# StreamingApp — Orchestration & Scaling (Graded Project)

End-to-end DevOps deployment of a MERN **microservices** streaming platform:
containerization → Amazon ECR → Jenkins CI → Amazon EKS (Helm) → CloudWatch
monitoring/logging → SNS ChatOps.

---

## 1. Application Architecture

The app is **not** a simple two-tier MERN app — it is five containers plus a database:

| Component  | Tech            | Build context            | Dockerfile                       | Port | ECR repo                  |
|------------|-----------------|--------------------------|----------------------------------|------|---------------------------|
| frontend   | React + nginx   | `./frontend`             | `Dockerfile`                     | 80   | `streamingapp-frontend`   |
| auth       | Node/Express    | `./backend/authService`  | `Dockerfile`                     | 3001 | `streamingapp-auth`       |
| streaming  | Node/Express    | `./backend`              | `streamingService/Dockerfile`    | 3002 | `streamingapp-streaming`  |
| admin      | Node/Express    | `./backend`              | `adminService/Dockerfile`        | 3003 | `streamingapp-admin`      |
| chat       | Node + Socket.IO| `./backend`              | `chatService/Dockerfile`         | 3004 | `streamingapp-chat`       |
| mongo      | MongoDB 6       | (official image)         | —                                | 27017| —                         |

> **Why build contexts differ:** the auth Dockerfile copies from its own folder,
> while streaming/admin/chat Dockerfiles `COPY streamingService/...` from the
> parent `backend/` folder. Building them with the wrong context will fail. The
> Jenkinsfile and `build-and-push.sh` already use the correct `-f` flag + context per service.

### Architecture diagram

```
                         ┌────────────────────────┐
        Internet ───────▶│  ELB (LoadBalancer Svc) │
                         └───────────┬────────────┘
                                     │
                            ┌────────▼────────┐
                            │  frontend (x2)   │  React/nginx :80
                            └───┬───┬───┬───┬──┘
            ┌───────────────────┘   │   │   └───────────────────┐
            ▼                       ▼   ▼                       ▼
      auth :3001            streaming :3002   admin :3003   chat :3004
            └───────────────┬───────────────┬─────────────┬───┘
                            ▼               ▼             ▼
                       ┌─────────────────────────────────────┐
                       │        MongoDB (StatefulSet)         │
                       └─────────────────────────────────────┘

   CI:  GitHub push ─▶ Jenkins (EC2) ─▶ build 5 images ─▶ ECR ─▶ helm upgrade ─▶ EKS
   Obs: EKS ─▶ CloudWatch Container Insights (metrics) + Fluent Bit (logs)
   ChatOps: Jenkins post{} ─▶ SNS topic ─▶ Slack/Email
```

---

## 2. Prerequisites

- AWS account + IAM user/role with ECR, EKS, EC2, CloudWatch, SNS permissions
- Local tools: `awscli v2`, `docker`, `kubectl`, `eksctl`, `helm`
- A forked copy of the repo with your changes

```bash
aws --version && docker --version && kubectl version --client && eksctl version && helm version
```

---

## 3. Step 1 — Version Control

```bash
# Fork on GitHub UI, then:
git clone https://github.com/<you>/StreamingApp.git
cd StreamingApp
git remote add upstream https://github.com/UnpredictablePrashant/StreamingApp.git
# keep in sync later:
git fetch upstream && git merge upstream/main
```

Copy the deliverables from this folder into the repo root: `helm/`, `scripts/`,
`Jenkinsfile`, `docs/`.

---

## 4. Step 2/3 — Containerize, AWS CLI, push to ECR

```bash
aws configure          # access key, secret, region=ap-south-1
aws sts get-caller-identity

export AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=ap-south-1
bash scripts/build-and-push.sh    # creates repos + builds + pushes all 5 images
```

Verify in console: **ECR → Repositories** shows five repos each with a `latest` tag.

Local smoke test before cloud (optional but recommended):
```bash
cp .env.example .env      # fill JWT_SECRET etc.
docker compose up --build # open http://localhost:3000
```

---

## 5. Step 4 — Jenkins CI on EC2

### Install Jenkins
```bash
# Ubuntu 22.04 EC2 (t2.medium, SG: 22 + 8080 open)
sudo apt update && sudo apt install -y openjdk-17-jre
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
  | sudo tee /usr/share/keyrings/jenkins-keyring.asc >/dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list >/dev/null
sudo apt update && sudo apt install -y jenkins
sudo systemctl enable --now jenkins

# Docker + AWS CLI on the agent
sudo apt install -y docker.io awscli
sudo usermod -aG docker jenkins && sudo systemctl restart jenkins
```

Unlock at `http://<ec2-ip>:8080` with
`sudo cat /var/lib/jenkins/secrets/initialAdminPassword`.

### Configure
- **Plugins:** Git, Pipeline, Docker Pipeline, Amazon ECR, CloudBees AWS Credentials.
- **Credentials / IAM:** attach an **IAM instance role** to the EC2 with ECR + EKS
  permissions (cleaner than static keys). Otherwise add AWS keys as Jenkins credentials.
- **Job:** New Item → *Pipeline* → "Pipeline script from SCM" → your repo → `Jenkinsfile`.
- Edit `AWS_ACCOUNT` in the `Jenkinsfile` environment block.

### Auto-trigger on commit
- GitHub repo → Settings → Webhooks → `http://<ec2-ip>:8080/github-webhook/` (push events).
- In the job, enable **GitHub hook trigger for GITScm polling**.
- Fallback: **Poll SCM** `H/5 * * * *`.

Each push now builds all five images, pushes to ECR, and (on `main`) runs `helm upgrade`.

---

## 6. Step 5 — EKS + Helm

```bash
export AWS_REGION=ap-south-1
bash scripts/setup-eks.sh     # cluster + metrics-server + Container Insights

helm upgrade --install streamingapp ./helm/streamingapp \
  --namespace streamingapp --create-namespace \
  --set image.registry=$AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com \
  --set image.tag=latest \
  --set config.jwtSecret=$(openssl rand -hex 16)

kubectl get pods -n streamingapp
kubectl get svc  -n streamingapp   # grab the frontend EXTERNAL-IP (ELB DNS)
```

The chart deploys: 5 Deployments + Services, a Mongo StatefulSet, shared
ConfigMap/Secret, and an HPA on the frontend (2→5 pods @ 70% CPU).

---

## 7. Step 6 — Monitoring & Logging

- **Metrics & alarms:** CloudWatch **Container Insights** (installed by `setup-eks.sh`)
  collects node/pod CPU, memory, network. Create alarms in CloudWatch → Alarms
  (e.g. node CPU > 80%, pod restart count > 0).
- **Logs:** **Fluent Bit** DaemonSet ships container logs to CloudWatch Logs group
  `/aws/containerinsights/streamingapp/application`.
- View: CloudWatch → Container Insights → "streamingapp" cluster map and dashboards.

---

## 8. Step 8 — Validation & Scaling

```bash
# Frontend reachable:
curl -I http://<frontend-elb-dns>

# Trigger autoscaling (load test):
kubectl run -it --rm load --image=busybox -n streamingapp --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://frontend; done"

watch kubectl get hpa,pods -n streamingapp   # replica count should climb to max
```

Screenshot: Jenkins green build, five ECR repos, `kubectl get pods` all Running,
HPA scaling up, CloudWatch dashboard.

---

## 9. Bonus Step 9 — ChatOps

```bash
export AWS_REGION=ap-south-1 ALERT_EMAIL=you@example.com
bash scripts/setup-sns-chatops.sh
# put the printed Topic ARN into the Jenkinsfile post{} blocks
```
For Slack: **AWS Chatbot → configure Slack client → subscribe to `deployment-events`**.
Jenkins publishes success/failure to the topic, which fans out to Slack/email.

---

## 10. Repo layout of deliverables

```
.
├── Jenkinsfile                       # CI/CD pipeline
├── helm/streamingapp/                # Helm chart (5 svcs + mongo + HPA)
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/{config,backend,frontend,mongo}.yaml
├── scripts/
│   ├── build-and-push.sh             # build + push all images to ECR
│   ├── setup-eks.sh                  # EKS + metrics + Container Insights
│   └── setup-sns-chatops.sh          # SNS topic for alerts
└── docs/README.md                    # this document
```

---

## 11. Troubleshooting

| Symptom | Fix |
|---|---|
| `COPY streamingService/...: not found` | Build with context `./backend` and `-f backend/<svc>/Dockerfile` |
| Pods `ImagePullBackOff` | Node IAM role lacks ECR read, or wrong `image.registry`/`tag` |
| HPA shows `<unknown>` CPU | metrics-server not installed/ready |
| Frontend up but API calls fail | Rebuild frontend with `REACT_APP_*` args pointing at the ELB host, not localhost |
| Jenkins `docker: permission denied` | `usermod -aG docker jenkins` + restart Jenkins |
```
