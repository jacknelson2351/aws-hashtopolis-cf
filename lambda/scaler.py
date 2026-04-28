import base64
import boto3
import json
import os
import urllib.request
from botocore.config import Config

HASHTOPOLIS_URL = os.environ["HASHTOPOLIS_URL"]
ASG_NAME        = os.environ["ASG_NAME"]
MAX_INSTANCES   = int(os.environ["MAX_INSTANCES"])
USERNAME        = os.environ["HASHTOPOLIS_USERNAME"]
PASSWORD        = os.environ["HASHTOPOLIS_PASSWORD"]
REGION          = os.environ["REGION"]

AGENTS_PER_TASK = 2

_boto_cfg = Config(connect_timeout=5, read_timeout=10, retries={"max_attempts": 1})


def api_token():
    credentials = base64.b64encode(f"{USERNAME}:{PASSWORD}".encode()).decode()
    req = urllib.request.Request(
        f"{HASHTOPOLIS_URL}/api/v2/auth/token",
        data=b"",
        method="POST",
        headers={"Authorization": f"Basic {credentials}"},
    )
    data = json.loads(urllib.request.urlopen(req, timeout=10).read())
    return data["token"]


def active_tasks(token):
    req = urllib.request.Request(
        f"{HASHTOPOLIS_URL}/api/v2/ui/tasks?maxResults=100",
        headers={"Authorization": f"Bearer {token}"},
    )
    data = json.loads(urllib.request.urlopen(req, timeout=10).read())
    tasks = data.get("values", [])
    runnable = [
        t for t in tasks
        if not t.get("isArchived", False) and int(t.get("priority", 0)) > 0
    ]
    print(f"[tasks] total={len(tasks)} runnable={len(runnable)}")
    return len(runnable)


def lambda_handler(event, context):
    asg = boto3.client("autoscaling", region_name=REGION, config=_boto_cfg)

    try:
        current = asg.describe_auto_scaling_groups(
            AutoScalingGroupNames=[ASG_NAME]
        )["AutoScalingGroups"][0]["DesiredCapacity"]
    except Exception as e:
        print(f"[error] could not reach autoscaling API: {e}")
        return

    try:
        token = api_token()
        tasks = active_tasks(token)
        print(f"[ok] reached hashtopolis at {HASHTOPOLIS_URL}")
    except Exception as e:
        print(f"[error] could not reach hashtopolis: {e}")
        tasks = 0

    wanted = min(tasks * AGENTS_PER_TASK, MAX_INSTANCES)
    print(f"[scaler] current={current} runnable_tasks={tasks} wanted={wanted}")

    if wanted != current:
        print(f"[scale] {current} -> {wanted}")
        asg.set_desired_capacity(
            AutoScalingGroupName=ASG_NAME,
            DesiredCapacity=wanted,
            HonorCooldown=False,
        )
    else:
        print(f"[scaler] no change needed (desired={current})")
