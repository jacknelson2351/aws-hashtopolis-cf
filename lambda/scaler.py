import boto3, json, os, urllib.request

HASHTOPOLIS_URL = os.environ["HASHTOPOLIS_URL"]
ASG_NAME        = os.environ["ASG_NAME"]
MAX_INSTANCES   = int(os.environ["MAX_INSTANCES"])
API_KEY         = os.environ["API_KEY"]
REGION          = os.environ["REGION"]

def active_tasks():
    try:
        req = urllib.request.Request(
            f"{HASHTOPOLIS_URL}/api/v2/ui/tasks",
            headers={"Authorization": f"Bearer {API_KEY}"},
        )
        data = json.loads(urllib.request.urlopen(req, timeout=10).read())
        return sum(
            1 for t in data.get("data", [])
            if not t.get("attributes", {}).get("isArchived", False)
        )
    except Exception as e:
        print(f"Hashtopolis unreachable: {e}")
        return 0

def lambda_handler(event, context):
    asg     = boto3.client("autoscaling", region_name=REGION)
    current = asg.describe_auto_scaling_groups(AutoScalingGroupNames=[ASG_NAME])["AutoScalingGroups"][0]["DesiredCapacity"]
    wanted  = min(active_tasks(), MAX_INSTANCES)

    if wanted != current:
        print(f"{current} -> {wanted}")
        asg.set_desired_capacity(AutoScalingGroupName=ASG_NAME, DesiredCapacity=wanted, HonorCooldown=False)
