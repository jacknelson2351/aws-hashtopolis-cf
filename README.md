# Hashtopolis on AWS

Distributed password cracking on AWS using Hashtopolis. A Hashtopolis server runs on EC2; a server-side systemd timer auto-scales GPU spot agents up and down based on active tasks.

Port 8080 is **not exposed to the internet**. All UI access is through AWS SSM port-forward — no SSH keys, no open ports, no VPN.

After Step 2, the system is fully working: admin password and agent voucher are generated, stored in AWS Secrets Manager, and applied to Hashtopolis automatically. No `terraform apply -var=...` two-phase deploys.

---

## What This Builds

| Part | What it does |
|---|---|
| Hashtopolis server | Web UI + API on a `t3.small` EC2 instance via Docker Compose |
| Agent AMI | Pre-installed NVIDIA CUDA drivers so GPU spot agents boot fast |
| Auto Scaling Group | Holds the agent fleet at `0` when idle, scales up when tasks exist |
| Server-side scaler | systemd timer runs `scaler.py` every 3s. Calls `SetDesiredCapacity` only when the value changes (idle = zero AWS API traffic) |
| First-boot bootstrap | Enables multi-use vouchers, generates a voucher, rotates the admin password from default to a TF-generated random value — all via the local API + DB |
| Secrets Manager | Stores the admin password and agent voucher. Server and agents read at runtime via instance role |
| Remote state | S3 bucket + DynamoDB lock table for Terraform state, both encrypted and not publicly accessible |
| IAM viewer group | `hashtopolis-viewers` — SSM port-forward to the UI only, no shell |

---

## Prerequisites

- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) — `aws configure` after installing
- [Terraform ≥ 1.0](https://developer.hashicorp.com/terraform/install)
- [Packer](https://developer.hashicorp.com/packer/install)
- [SSM Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)

No SSH key pair needed.

> **Quota:** `g4dn.xlarge` agents need G-class spot quota. Request both **Running On-Demand G and VT instances** and **All G and VT Spot Instance Requests** under **Service Quotas → EC2** before deploying. Each agent is 4 vCPU, so e.g. 8 vCPU of spot quota = 2 concurrent agents.

---

## Step 0 — Bootstrap remote state (one time per account)

Creates the S3 bucket and DynamoDB lock table for Terraform state. Both are versioned, encrypted, and public access is blocked. They are not managed by Terraform (chicken-and-egg).

```bash
./scripts/bootstrap-state-bucket.sh
```

The script prints the exact `terraform init -migrate-state ...` command to run next — copy and run it. Bucket name is derived from your AWS account ID for global uniqueness.

---

## Step 1 — Build the agent AMI (one time)

Packer launches a `g4dn.xlarge` build instance, installs CUDA + agent dependencies, and snapshots an AMI.

```bash
packer init agent.pkr.hcl
packer build agent.pkr.hcl
```

Save the AMI ID printed at the end (e.g. `ami-05eac013a630b0dd3`).

---

## Step 2 — Deploy

```bash
terraform apply -var="agent_ami_id=ami-05eac013a630b0dd3"
```

Takes ~2 min for Terraform; cloud-init on the server then takes another 2-3 min to finish (Docker pull, multi-use voucher config, voucher creation, admin password rotation). All of it is automatic.

When Terraform finishes:
```bash
terraform output
```
Shows the instance ID, the SSM port-forward command, and helper outputs.

### Adding team members

`terraform apply` creates an IAM group `hashtopolis-viewers`. Add any IAM user to it via the AWS Console (IAM → User Groups → `hashtopolis-viewers` → Add users). Members can port-forward to the UI but cannot open a shell or do anything else.

---

## Step 3 — Log in

1. Get the admin password from Secrets Manager:
   ```bash
   aws secretsmanager get-secret-value --secret-id hashtopolis/admin-password --query SecretString --output text
   ```
2. Open the SSM tunnel (leave running):
   ```bash
   $(terraform output -raw ssm_ui)
   ```
3. Browse to `http://localhost:8082` and log in as `admin` with the password from step 1.

> If you get "connection refused", cloud-init is still bootstrapping. Wait 2-3 min and retry.

---

## Step 4 — Upload wordlists and rules (only remaining manual step)

In the UI:

1. **Files → Wordlists** (or **Rules**) → upload your files
2. Each file uploads in **locked** state — click **Unlock** on each one before using it in a task

> Hashtopolis silently fails tasks that reference locked files.

---

## Step 5 — Create a task, watch it work

Create a task in **Tasks → New Task** with priority > 0. Within ~3 seconds, the scaler detects it and scales the ASG up to `2 × tasks` agents. Each agent boots, pulls the voucher from Secrets Manager, registers, and starts cracking.

Archive the task when done — agents drain to zero within 3 seconds.

---

## How Auto-Scaling Works

A systemd timer on the server runs `scaler.py` every 3 seconds. The scaler:

1. Pulls the admin password from Secrets Manager (via the EC2 instance role)
2. Mints a JWT against the local Hashtopolis API
3. Counts runnable tasks (non-archived, priority > 0)
4. Computes `desired = min(tasks × 2, max_gpu_instances)`
5. Calls `SetDesiredCapacity` **only when the value changes**

Idle steady-state is local-API traffic only — zero AWS API calls until something changes.

---

## Variables

| Variable | Default | Description |
|---|---|---|
| `region` | `us-east-1` | AWS region |
| `availability_zone` | `us-east-1b` | AZ for the subnet and instances |
| `agent_ami_id` | required | AMI ID from the Packer build |
| `max_gpu_instances` | `5` | Max concurrent agent spot instances |
| `local_ui_port` | `8082` | Local port for the SSM tunnel |
| `hashtopolis_username` | `admin` | Hashtopolis user the scaler authenticates as |

The admin password and agent voucher are stored in AWS Secrets Manager — never in Terraform variables or `terraform.tfvars`. The admin password lives in TF state (since Terraform generates it via `random_password`), but state is encrypted in S3.

---

## Cost

| Resource | $/mo |
|---|---|
| t3.small server | ~$15 |
| Server EBS volume | ~$1 |
| Agent AMI snapshot | <$1 |
| Elastic IP (attached) | $0 |
| Secrets Manager (2 secrets) | ~$0.80 |
| S3 state bucket + DynamoDB lock | <$0.10 |
| **Idle total** | **~$17** |
| g4dn.xlarge spot agents | ~$0.16-0.30/hr per instance while cracking |

---

## Troubleshooting

**Connection refused on localhost:8082**
Bootstrap still running. Wait 2-3 min after `terraform apply` finishes. Confirm cloud-init is done with `aws ssm send-command ... cloud-init status`.

**Agents not appearing after adding a task**
- Both secrets are set: `aws secretsmanager get-secret-value --secret-id hashtopolis/voucher` and `... hashtopolis/admin-password`
- Scaler logs (SSM into the server): `sudo journalctl -u hashtopolis-scaler -f`
- Agent logs (SSM into a running agent): `sudo journalctl -u hashtopolis-agent -f`
- Agent cloud-init log if the agent never registered: `sudo tail /var/log/cloud-init-output.log`

**Agents fail to launch with "Max spot instance count exceeded"**
- Your G-class spot quota is full. Check current usage:
  ```bash
  aws ec2 describe-spot-instance-requests --filters "Name=state,Values=open,active" --query 'SpotInstanceRequests[*].[SpotInstanceRequestId,State,InstanceId,LaunchSpecification.InstanceType]' --output table
  ```
- Cancelled spot requests can linger and count against quota for a few minutes. If the requests are zombies (instance is `terminated` but request is `active`):
  ```bash
  aws ec2 cancel-spot-instance-requests --spot-instance-request-ids sir-XXXX
  ```
- Increase the quota under **Service Quotas → EC2 → All G and VT Spot Instance Requests** if you need more concurrency.

**Agents fail to launch with "InsufficientInstanceCapacity"**
That's regional spot capacity, not quota. Try a different AZ:
```bash
terraform apply -var="agent_ami_id=ami-XXXX" -var="availability_zone=us-east-1c"
```

**Agent stuck on `downloadBinary`**
Hashcat cracker isn't registered. In the UI: **Config → Crackers → New Cracker**, version `7.1.2`, URL `https://hashcat.net/files/hashcat-7.1.2.7z`.

**SSM `start-session: command not found`**
Install the Session Manager plugin linked in Prerequisites.

**Bootstrap finished but admin password in SM is `hashtopolis`**
The bootstrap's password rotation self-check failed and fell back to the default. Look at `/var/log/cloud-init-output.log` for `[bootstrap] admin password rotation FAILED` — usually means the Hashtopolis source layout changed and the in-container PHP hash invocation broke.

---

## Destroy

```bash
terraform destroy -var="agent_ami_id=ami-XXXX"
```

The agent AMI and the state bucket/lock table are not Terraform-managed. To remove them:

```bash
# AMI
aws ec2 describe-images --owners self \
  --filters "Name=name,Values=hashtopolis-agent-*" \
  --query "Images[].{ImageId:ImageId,SnapshotId:BlockDeviceMappings[0].Ebs.SnapshotId}" \
  --output table

aws ec2 deregister-image --image-id ami-XXXXXXXXXXXXXXXXX
aws ec2 delete-snapshot --snapshot-id snap-XXXXXXXXXXXXXXXXX

# State backend (only if you're tearing down everything)
aws s3 rb s3://hashtopolis-tfstate-<account-id> --force
aws dynamodb delete-table --table-name hashtopolis-tfstate-lock
```
