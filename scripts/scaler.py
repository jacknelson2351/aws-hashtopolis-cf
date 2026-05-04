#!/usr/bin/env python3
"""Server-side ASG scaler. Runs every minute via systemd timer."""

import base64
import json
import os
import sys
import urllib.request

import boto3
from botocore.config import Config

HASHTOPOLIS_URL    = os.environ["HASHTOPOLIS_URL"]
ASG_NAME           = os.environ["ASG_NAME"]
MAX_INSTANCES      = int(os.environ["MAX_INSTANCES"])
USERNAME           = os.environ["HASHTOPOLIS_USERNAME"]
PASSWORD_SECRET_ID = os.environ["HASHTOPOLIS_PASSWORD_SECRET_ID"]
REGION             = os.environ["REGION"]

AGENTS_PER_TASK = 2

_boto_cfg = Config(connect_timeout=5, read_timeout=10, retries={"max_attempts": 1})


def get_password():
    sm = boto3.client("secretsmanager", region_name=REGION, config=_boto_cfg)
    return sm.get_secret_value(SecretId=PASSWORD_SECRET_ID)["SecretString"]


def api_token(password):
    credentials = base64.b64encode(f"{USERNAME}:{password}".encode()).decode()
    req = urllib.request.Request(
        f"{HASHTOPOLIS_URL}/api/v2/auth/token",
        data=b"",
        method="POST",
        headers={"Authorization": f"Basic {credentials}"},
    )
    return json.loads(urllib.request.urlopen(req, timeout=10).read())["token"]


def active_tasks(token):
    req = urllib.request.Request(
        f"{HASHTOPOLIS_URL}/api/v2/ui/tasks?maxResults=100",
        headers={"Authorization": f"Bearer {token}"},
    )
    data = json.loads(urllib.request.urlopen(req, timeout=10).read())
    runnable = [
        t for t in data.get("values", [])
        if not t.get("isArchived", False) and int(t.get("priority", 0)) > 0
    ]
    return len(runnable)


def main():
    asg = boto3.client("autoscaling", region_name=REGION, config=_boto_cfg)

    try:
        current = asg.describe_auto_scaling_groups(
            AutoScalingGroupNames=[ASG_NAME]
        )["AutoScalingGroups"][0]["DesiredCapacity"]
    except Exception as e:
        print(f"[error] autoscaling describe failed: {e}", file=sys.stderr)
        return 1

    try:
        password = get_password()
        if not password:
            print("[skip] admin password secret is empty; not scaling")
            return 0
        token = api_token(password)
        tasks = active_tasks(token)
    except Exception as e:
        print(f"[error] hashtopolis unreachable: {e}", file=sys.stderr)
        return 0

    wanted = min(tasks * AGENTS_PER_TASK, MAX_INSTANCES)
    print(f"[scaler] current={current} runnable_tasks={tasks} wanted={wanted}")

    if wanted != current:
        asg.set_desired_capacity(
            AutoScalingGroupName=ASG_NAME,
            DesiredCapacity=wanted,
            HonorCooldown=False,
        )
        print(f"[scale] {current} -> {wanted}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
