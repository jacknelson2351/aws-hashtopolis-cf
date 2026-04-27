import base64
import boto3
import json
import os
import urllib.request

HASHTOPOLIS_URL = os.environ["HASHTOPOLIS_URL"]
ASG_NAME        = os.environ["ASG_NAME"]
MAX_INSTANCES   = int(os.environ["MAX_INSTANCES"])
USERNAME        = os.environ["HASHTOPOLIS_USERNAME"]
PASSWORD        = os.environ["HASHTOPOLIS_PASSWORD"]
REGION          = os.environ["REGION"]


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
    try:
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
        print(f"hashtopolis_tasks total={len(tasks)} runnable={len(runnable)}")
        return len(runnable)
    except Exception as e:
        print(f"Hashtopolis unreachable: {e}")
        return 0

def lambda_handler(event, context):
    asg     = boto3.client("autoscaling", region_name=REGION)
    current = asg.describe_auto_scaling_groups(AutoScalingGroupNames=[ASG_NAME])["AutoScalingGroups"][0]["DesiredCapacity"]

    try:
        token = api_token()
        tasks = active_tasks(token)
    except Exception as e:
        print(f"Hashtopolis unreachable: {e}")
        tasks = 0

    wanted  = min(tasks * 2, MAX_INSTANCES)
    print(f"scaler current={current} active_tasks={tasks} wanted={wanted}")

    if wanted != current:
        print(f"{current} -> {wanted}")
        asg.set_desired_capacity(AutoScalingGroupName=ASG_NAME, DesiredCapacity=wanted, HonorCooldown=False)
