# Hashtopolis on AWS

Distributed GPU password cracking. The server runs on a cheap `t3.small` with no public ports. GPU spot instances spin up automatically when there are tasks and shut down when there aren't.

---

## What you need before starting

- **AWS CLI** installed and configured (`aws configure`)
- **Terraform** ≥ 1.0 installed
- **AWS SSM Session Manager plugin** — required to access the server without SSH:
  ```
  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
  ```
- **Packer** — to build the GPU agent AMI (only needed once):
  ```
  https://developer.hashicorp.com/packer/install
  ```
- An **AWS key pair** is not needed. Access is via SSM.

---

## Step 1 — Build the agent AMI (one time)

This builds a custom AMI with CUDA, hashcat, and the Hashtopolis agent pre-installed. It takes ~20 minutes. You only do this once (or when you want to update drivers).

Create a file called `agent.pkr.hcl`:

```hcl
packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "agent" {
  region        = "us-east-1"
  instance_type = "g4dn.xlarge"
  ssh_username  = "ubuntu"
  source_ami_filter {
    filters     = { name = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" }
    owners      = ["099720109477"]
    most_recent = true
  }
  ami_name = "hashtopolis-agent-{{timestamp}}"
}

build {
  sources = ["source.amazon-ebs.agent"]
  provisioner "shell" {
    inline = [
      "sudo apt-get update -y",
      "wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb",
      "sudo dpkg -i cuda-keyring_1.1-1_all.deb && sudo apt-get update -y",
      "sudo apt-get install -y cuda-toolkit-12-3 nvidia-driver-545 hashcat python3 python3-pip",
      "sudo pip3 install requests psutil",
      "sudo mkdir -p /opt/hashtopolis",
      "wget -q $(curl -s https://api.github.com/repos/hashtopolis/client/releases/latest | grep browser_download_url | grep .zip | cut -d'\"' -f4) -O /opt/hashtopolis/hashtopolis.zip",
    ]
  }
}
```

Run it:

```bash
packer init agent.pkr.hcl
packer build agent.pkr.hcl
```

At the end you'll see something like:

```
AMI: ami-0abc1234def567890
```

**Save that AMI ID — you need it in Step 2.**

---

## Step 2 — Deploy the server

```bash
terraform init
terraform apply -var="agent_ami_id=ami-0abc1234def567890"
```

> Replace `ami-0abc1234def567890` with the AMI ID from Step 1.

Terraform will ask you to confirm. Type `yes`.

This takes about 2 minutes. When it finishes you'll see output like:

```
server_instance_id = "i-0abc1234def567890"
ssm_shell          = "aws ssm start-session --target i-0abc1234def567890 ..."
ssm_ui             = "aws ssm start-session --target i-0abc1234def567890 ... --document-name AWS-StartPortForwardingSession ..."
```

---

## Step 3 — Access the Hashtopolis UI

Run the `ssm_ui` command from the Terraform output. It will look like:

```bash
aws ssm start-session --target i-0abc1234def567890 --region us-east-1 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

Leave that terminal open. Then open your browser to:

```
http://localhost:8080
```

Log in with:
- **Username:** `admin`
- **Password:** `hashtopolis`

> Change the password immediately: top-right menu → User Settings → Account.

Wait a minute or two after deploy if you get a connection refused — Docker is still pulling images on first boot.

---

## Step 4 — Configure Hashtopolis for auto-scaling

You need to do this once so agents can register automatically.

### 4a — Enable bulk agent registration

This allows multiple spot instances to register using the same voucher.

1. Go to **Config** (top nav) → **Agents** tab
2. Find **"Allow multiple agent registrations per voucher"** and enable it
3. Save

### 4b — Create an agent voucher

1. Go to **Agents** → **New Agent**
2. Click **Create Voucher**
3. Copy the voucher string (looks like `peKxylVY`)

### 4c — Create an API token

The Lambda scaler uses this to check for active tasks.

1. Go to **Config** → **API Tokens**
2. Click **Create Token**
3. Copy the token

---

## Step 5 — Re-apply with the voucher and token

```bash
terraform apply \
  -var="agent_ami_id=ami-0abc1234def567890" \
  -var="hashtopolis_voucher=YOUR_VOUCHER_HERE" \
  -var="hashtopolis_api_key=YOUR_TOKEN_HERE"
```

This updates the agent launch template with the voucher and the Lambda scaler with the API token. Confirm with `yes`.

That's it. The system is fully operational.

---

## How auto-scaling works

The Lambda function runs every minute. It calls the Hashtopolis API, counts non-archived tasks, and sets the Auto Scaling Group's desired capacity accordingly (capped at `max_gpu_instances`, default 5).

- **Add a task in Hashtopolis** → Lambda detects it within 60 seconds → spot GPU instances launch → agents register → cracking starts
- **Archive the task** → Lambda detects no active tasks → ASG scales to 0 → instances terminate → cost drops back to ~$15/mo

---

## Team access

Anyone who needs to access the server — whether via browser or terminal — needs an AWS IAM account in your org's AWS account with the right permissions. No SSH keys, no VPN. Access control is entirely through IAM.

### Setting up IAM for a team member

#### 1. Create the IAM policy

In the AWS Console: **IAM → Policies → Create policy → JSON tab**

Paste this policy and name it `HashstopolisAccess`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSSMSession",
      "Effect": "Allow",
      "Action": [
        "ssm:StartSession",
        "ssm:TerminateSession",
        "ssm:ResumeSession"
      ],
      "Resource": [
        "arn:aws:ec2:*:*:instance/*",
        "arn:aws:ssm:*:*:session/${aws:username}-*"
      ],
      "Condition": {
        "StringLike": {
          "ssm:resourceTag/Name": "hashtopolis-server"
        }
      }
    },
    {
      "Sid": "AllowPortForwarding",
      "Effect": "Allow",
      "Action": "ssm:StartSession",
      "Resource": "arn:aws:ssm:*:*:document/AWS-StartPortForwardingSession"
    },
    {
      "Sid": "AllowConsoleNavigation",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ssm:DescribeSessions",
        "ssm:GetConnectionStatus",
        "ssm:DescribeInstanceInformation",
        "ssm:DescribeInstanceProperties"
      ],
      "Resource": "*"
    }
  ]
}
```

The `Condition` block locks the session permission down to only the instance tagged `Name = hashtopolis-server` — team members can't use this policy to SSM into other instances in the account.

#### 2. Create the IAM user

**IAM → Users → Create user**

1. Set a username (e.g. `alice`)
2. Check **"Provide user access to the AWS Management Console"** if they need browser access
3. On the permissions step, choose **"Attach policies directly"** and select `HashtopolisAccess`
4. Finish creating the user
5. Send them their console login URL, username, and temporary password

#### 3. They install the Session Manager plugin

Team members who want to use the CLI port-forward command (for the web UI) need the plugin:
```
https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
```

Team members who only use the AWS Console don't need it.

---

## Day-to-day access

### Via AWS Console (no CLI needed)

**Shell access:**

1. Go to **EC2 → Instances**
2. Select the `hashtopolis-server` instance
3. Click **Connect → Session Manager tab → Connect**

A terminal opens in the browser. Done.

**Web UI access via console** requires the CLI port-forward command (see below) — the browser-based terminal doesn't support port forwarding.

### Via CLI

**Open a shell on the server:**
```bash
# Copy and run the ssm_shell output from terraform output
aws ssm start-session --target i-xxxx --region us-east-1
```

**Open the web UI:**
```bash
# Run this, leave the terminal open, then go to http://localhost:8080
aws ssm start-session --target i-xxxx --region us-east-1 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

**Get your instance ID and exact commands at any time:**
```bash
terraform output
```

---

## Variables

| Variable | Default | Description |
|---|---|---|
| `region` | `us-east-1` | AWS region |
| `agent_ami_id` | required | AMI ID from Packer build |
| `max_gpu_instances` | `5` | Maximum concurrent GPU spot instances |
| `hashtopolis_voucher` | `""` | Agent registration voucher (set after Step 4) |
| `hashtopolis_api_key` | `""` | JWT API token for the Lambda scaler (set after Step 4) |

---

## Cost

| Resource | $/mo | Notes |
|---|---|---|
| t3.small server | ~$15 | On-demand, runs 24/7 |
| Server EBS volume (8GB gp3) | ~$1 | Root disk |
| Agent AMI snapshot | ~$1.50 | CUDA image stored in S3 after Packer build |
| Elastic IP (attached) | $0 | Only charged when not attached to a running instance |
| Lambda + EventBridge (1/min) | $0 | Well within free tier (43,800 invocations/mo vs 1M free) |
| **Idle total** | **~$18/mo** | |
| g4dn.xlarge spot (when cracking) | $0.16–0.25/hr per instance | Fluctuates — check current prices at EC2 Spot Pricing page |

Spot instances are terminated the moment you archive all tasks.

---

## Troubleshooting

**"Connection refused" on localhost:8080**
Docker is still pulling images on first boot. Wait 2–3 minutes and retry.

**Agents not appearing after tasks are added**
- Check the voucher was saved: `terraform output` should show it was applied
- Check bulk registration is enabled (Step 4a)
- Check the Lambda scaler logs in CloudWatch → Log Groups → `/aws/lambda/hashtopolis-scaler`

**SSM session manager command not found**
Install the session manager plugin linked in the prerequisites section.
