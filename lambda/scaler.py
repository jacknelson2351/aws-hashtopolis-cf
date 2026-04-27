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

# Number of agents to spin up per active task. Multiple agents can work the
# same task in parallel in Hashtopolis, so more than 1 increases throughput.
AGENTS_PER_TASK = 2


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
        # Only count tasks that are queued to run — archived tasks are finished,
        # and priority 0 means the task is paused/deprioritized.
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
        # If Hashtopolis is unreachable, treat as zero tasks so the fleet scales
        # down rather than staying up and burning spend indefinitely.
        print(f"Hashtopolis unreachable: {e}")
        tasks = 0

    # Scale AGENTS_PER_TASK instances per runnable task, capped at MAX_INSTANCES.
    # Example: 2 tasks × 2 agents = 4 instances (if MAX_INSTANCES >= 4).
    wanted = min(tasks * AGENTS_PER_TASK, MAX_INSTANCES)
    print(f"scaler current={current} active_tasks={tasks} wanted={wanted}")

    if wanted != current:
        print(f"{current} -> {wanted}")
        # HonorCooldown=False lets us scale immediately without waiting for the
        # ASG cooldown period — intentional so tasks start cracking right away.
        asg.set_desired_capacity(AutoScalingGroupName=ASG_NAME, DesiredCapacity=wanted, HonorCooldown=False)
