import json
import os
import urllib.request
import urllib.error
import boto3


secretsmanager = boto3.client("secretsmanager")


def get_secret_value(secret_name: str) -> str:
    response = secretsmanager.get_secret_value(SecretId=secret_name)

    if "SecretString" not in response:
        raise ValueError(f"Secret {secret_name} does not contain SecretString")

    return response["SecretString"]


def post_slack(webhook_url: str, payload: dict) -> None:
    data = json.dumps(payload).encode("utf-8")

    request = urllib.request.Request(
        webhook_url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            status = response.getcode()
            body = response.read().decode("utf-8")

            if status < 200 or status >= 300:
                raise RuntimeError(
                    f"Slack webhook failed: status={status}, body={body}"
                )

    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        raise RuntimeError(
            f"Slack webhook HTTPError: status={e.code}, body={body}"
        ) from e


def get_execution_short_name(execution_arn: str, fallback: str) -> str:
    if execution_arn and execution_arn != "unknown":
        return execution_arn.split(":")[-1]

    return fallback


def lambda_handler(event, context):
    secret_name = os.environ["SECRET_NAME"]
    cluster_name = os.environ.get("CLUSTER_NAME", event.get("cluster_name", "unknown"))

    execution_arn = event.get("execution_arn", "unknown")
    execution_name = event.get("execution_name", "unknown")
    execution_id = get_execution_short_name(execution_arn, execution_name)

    started_at = event.get("started_at", "unknown")

    text = (
        f":zzz: 리소스 절전 모드 시작\n\n"
        f"{cluster_name} 클러스터의 비용 최적화 작업을 시작했어요.\n\n"
        f"*Status:*\n"
        f"Started\n\n"
        f"*Operation:*\n"
        f"shutdown\n\n"
        f"*Execution:*\n"
        f"{execution_id}\n\n"
        f"*Started At:*\n"
        f"{started_at}\n\n"
        f"*Step Functions execution ARN:*\n"
        f"{execution_arn}"
    )

    webhook_url = get_secret_value(secret_name)
    post_slack(webhook_url, {"text": text})

    return {
        "ok": True,
        "service": "slack",
        "action": "hibernate_start_notified",
        "cluster_name": cluster_name,
        "execution": execution_id,
        "started_at": started_at,
    }
