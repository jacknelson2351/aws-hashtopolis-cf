# Hashtopolis on AWS

Distributed password cracking on AWS using Hashtopolis. A Hashtopolis server runs on EC2 and a Lambda function automatically scales spot agent instances up and down based on active tasks.

Port 8080 is **not exposed to the internet**. All access is through AWS SSM — no SSH keys, no open ports, no VPN.

---

## What This Builds

| Part | What it does |
|---|---|
| Hashtopolis server | Runs the web UI and API on a `t3.small` EC2 instance using Docker Compose |
| Agent AMI | Pre-installs hashcat and agent dependencies so spot agents boot fast |
| Auto Scaling Group | Holds the agent fleet at `0` when idle, scales up when tasks exist |
| Lambda scaler | Polls Hashtopolis every minute and sets ASG desired capacity accordingly |
| IAM viewer group | Grants named users SSM port-forward access to the UI — no shell, no other permissions |

> **Current state:** CPU-only (`c5.xlarge`) while GPU quota is pending. See [Switching to GPU](#switching-to-gpu) when approved.

---

## Prerequisites

Install these before starting:

- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) — run `aws configure` after installing
- [Terraform ≥ 1.0](https://developer.hashicorp.com/terraform/install)
- [Packer](https://developer.hashicorp.com/packer/install)
- [SSM Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) — required for the port-forward command

No SSH key pair is needed.

---

## Step 1 — Build the Agent AMI

Run once. Packer launches a temporary build instance, installs all dependencies, and snapshots it into an AMI.

```bash
packer init agent.pkr.hcl
packer build agent.pkr.hcl
```

At the end you will see:

```
AMI: ami-0abc1234def567890
```

Save that AMI ID — you need it in the next step.

---

## Step 2 — Deploy

```bash
terraform init
terraform apply -var="agent_ami_id=ami-0abc1234def567890"
```

Replace `ami-0abc1234def567890` with the AMI ID from Step 1. Type `yes` when prompted.

This takes about 2 minutes. When done, run:

```bash
terraform output
```

You'll see your instance ID and the exact SSM commands to use.

### Adding team members

Terraform creates an IAM group called `hashtopolis-viewers`. Add any existing IAM user to it:

**AWS Console:** IAM → User Groups → `hashtopolis-viewers` → Add users

Members can port-forward to the UI but cannot open a shell or access anything else in the account.

---

## Step 3 — Access the Hashtopolis UI

Get the exact command from Terraform and run it:

```bash
terraform output -raw ssm_ui
```

Leave that terminal open, then open:

```
http://localhost:8082
```

Default login:
- **Username:** `admin`
- **Password:** `hashtopolis`

> If you get "connection refused", wait 2–3 minutes — Docker is still pulling images on first boot.

---

## Step 4 — First-time Hashtopolis Setup

Do this once after the server is up.

### 4a — Allow multiple agents to use the same voucher

1. Go to **Config → Server**
2. Enable **"Vouchers can be used multiple times and will not be deleted automatically"**
3. Click **Save Changes**

Without this, the first agent registration consumes the voucher and all subsequent agents fail to register.

### 4b — Create an agent voucher

1. Go to **Agents → Show Agents → + New Agent**
2. Click **Create Voucher** and copy the string (e.g. `peKxylVY`)

---

## Step 5 — Re-apply with the Voucher

```bash
terraform apply \
  -var="agent_ami_id=ami-0abc1234def567890" \
  -var="hashtopolis_voucher=YOUR_VOUCHER_HERE"
```

If you changed the Hashtopolis password, add `-var="hashtopolis_password=YOUR_PASSWORD"` so the Lambda scaler can authenticate.

The stack is now fully operational. Add a task in Hashtopolis and agents will appear within 60 seconds.

---

## How Auto-Scaling Works

The Lambda runs every minute, counts non-archived tasks via the Hashtopolis API, and sets ASG desired capacity accordingly (capped at `max_gpu_instances`).

- **Add a task** → Lambda detects it → spot agents launch → register → cracking starts
- **Archive the task** → Lambda detects zero tasks → ASG scales to 0 → instances terminate

---

## Variables

| Variable | Default | Description |
|---|---|---|
| `region` | `us-east-1` | AWS region |
| `agent_ami_id` | required | AMI ID from the Packer build |
| `viewer_usernames` | `[]` | IAM users to create and grant UI access |
| `max_gpu_instances` | `5` | Max concurrent agent spot instances |
| `local_ui_port` | `8082` | Local port for the SSM tunnel |
| `hashtopolis_voucher` | `""` | Agent registration voucher (set in Step 5) |
| `hashtopolis_username` | `admin` | Hashtopolis user for the Lambda scaler |
| `hashtopolis_password` | `hashtopolis` | Hashtopolis password for the Lambda scaler |

---

## Cost

| Resource | $/mo |
|---|---|
| t3.small server | ~$15 |
| Server EBS volume | ~$1 |
| Agent AMI snapshot | <$1 |
| Elastic IP (attached) | $0 |
| Lambda + EventBridge | $0 (free tier) |
| **Idle total** | **~$16–17/mo** |
| c5.xlarge spot agents | hourly while cracking |

---

## Troubleshooting

**Connection refused on localhost:8082**
Docker is still pulling images. Wait 2–3 minutes and retry. Make sure the SSM port-forward terminal is still open.

**Agents not appearing after adding a task**
- Confirm the voucher was applied: `terraform output`
- Confirm bulk registration is enabled (Step 4a)
- Check Lambda logs: **CloudWatch → Log Groups → `/aws/lambda/hashtopolis-scaler`**
- Check agent logs on a running instance:
```bash
sudo journalctl -u hashtopolis-agent -f
```

**Agent stuck on `downloadBinary`**
The default hashcat cracker URL may need registering. Go to **Config → Crackers → New Cracker**, set version `7.1.2` and URL `https://hashcat.net/files/hashcat-7.1.2.7z`.

**SSM command not found**
Install the Session Manager plugin linked in Prerequisites.

**`VcpuLimitExceeded` during Packer build**
Your account has no vCPU quota for that instance family. The current config uses `c5.xlarge` to avoid this. Request GPU quota before switching to `g4dn.xlarge`.

---

## Destroy

```bash
terraform destroy -var="agent_ami_id=ami-0abc1234def567890"
```

Packer AMIs are not managed by Terraform. Clean them up manually:

```bash
aws ec2 describe-images --owners self \
  --filters "Name=name,Values=hashtopolis-agent-*" \
  --query "Images[].{ImageId:ImageId,SnapshotId:BlockDeviceMappings[0].Ebs.SnapshotId}" \
  --output table
```

```bash
aws ec2 deregister-image --image-id ami-xxxxxxxxxxxxxxxxx
aws ec2 delete-snapshot --snapshot-id snap-xxxxxxxxxxxxxxxxx
```

---

## Switching to GPU

After AWS approves G-instance quotas, make the following exact changes:

### 1. `agent.pkr.hcl` — change build instance type

```diff
-  instance_type = "c5.xlarge"
+  instance_type = "g4dn.xlarge"
```

### 2. `scripts/agent_init.sh` — replace PoCL with NVIDIA drivers + CUDA

```bash
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y software-properties-common
add-apt-repository universe -y
apt-get update -y
apt-get install -y ca-certificates curl p7zip-full python3 python3-pip

# NVIDIA driver + CUDA keyring
curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb -o /tmp/cuda-keyring.deb
dpkg -i /tmp/cuda-keyring.deb
apt-get update -y
apt-get install -y cuda-drivers nvidia-cuda-toolkit

pip3 install requests psutil
```

### 3. `agents.tf` — change instance type and remove `--cpu-only`

```diff
-  instance_type = "c5.xlarge"
+  instance_type = "g4dn.xlarge"
```

```diff
     exec /usr/bin/python3 /opt/hashtopolis/hashtopolis.zip \
       --url "http://${aws_instance.server.private_ip}:8080/api/server.php" \
-      --voucher "${var.hashtopolis_voucher}" \
-      --cpu-only
+      --voucher "${var.hashtopolis_voucher}"
```

### 4. Rebuild the AMI

```bash
packer build agent.pkr.hcl
```

Copy the new AMI ID from the output.

### 5. Re-apply Terraform

```bash
terraform apply \
  -var="agent_ami_id=ami-NEW_AMI_ID_HERE" \
  -var="hashtopolis_voucher=YOUR_VOUCHER_HERE"
```

> After switching, go to **Config → Crackers** in the Hashtopolis UI and register a GPU-compatible hashcat version (7.x) so agents pick it up.
