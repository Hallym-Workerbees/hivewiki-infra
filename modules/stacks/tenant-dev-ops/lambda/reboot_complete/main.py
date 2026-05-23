import json
import os
import urllib.request
import urllib.error
from datetime import datetime, timezone
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


def parse_stepfunctions_time(value: str) -> datetime | None:
    if not value or value == "unknown":
        return None

    try:
        normalized = value.replace("Z", "+00:00")
        return datetime.fromisoformat(normalized)
    except ValueError:
        return None


def format_duration(started_at: str, completed_at: datetime) -> str:
    started = parse_stepfunctions_time(started_at)

    if started is None:
        return "unknown"

    if started.tzinfo is None:
        started = started.replace(tzinfo=timezone.utc)

    delta = completed_at - started
    total_seconds = max(0, int(delta.total_seconds()))

    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60
    seconds = total_seconds % 60

    if hours > 0:
        return f"{hours}h {minutes}m {seconds}s"

    if minutes > 0:
        return f"{minutes}m {seconds}s"

    return f"{seconds}s"


def get_execution_short_name(execution_arn: str, fallback: str) -> str:
    if execution_arn and execution_arn != "unknown":
        return execution_arn.split(":")[-1]

    return fallback


def format_compute_result(result: dict) -> str:
    service = result.get("service", "unknown")
    action = result.get("action", "unknown")
    reason = result.get("reason")

    if service == "rds":
        previous_status = result.get("previous_status", "unknown")
        db_identifier = result.get("db_instance_identifier", "unknown")

        if action == "skipped":
            return f"• RDS: skipped ({previous_status}) - {reason or db_identifier}"

        return f"• RDS: {action} ({previous_status} -> started)"

    if service == "eks":
        previous_desired = result.get("previous_desired", "unknown")

        if action == "skipped":
            return f"• EKS: skipped (desired={previous_desired}) - {reason or 'already active'}"

        target_desired = result.get("target_desired", 1)
        return f"• EKS: {action} (desired={previous_desired} -> {target_desired})"

    return f"• {service}: {action}"


def format_network_result(network_result: dict) -> str:
    if not isinstance(network_result, dict):
        return "• NAT Gateway: unknown"

    build = network_result.get("Build", {})
    build_status = build.get("BuildStatus", "unknown")

    if build_status == "SUCCEEDED":
        return "• NAT Gateway: restored"

    return f"• NAT Gateway: {build_status}"


def lambda_handler(event, context):
    secret_name = os.environ["SECRET_NAME"]
    cluster_name = os.environ.get("CLUSTER_NAME", event.get("cluster_name", "unknown"))

    execution_arn = event.get("execution_arn", "unknown")
    execution_name = event.get("execution_name", "unknown")
    execution_id = get_execution_short_name(execution_arn, execution_name)

    started_at = event.get("started_at", "unknown")
    completed_at_dt = datetime.now(timezone.utc)
    completed_at = completed_at_dt.isoformat(timespec="milliseconds").replace(
        "+00:00", "Z"
    )
    duration = format_duration(started_at, completed_at_dt)

    compute_results = event.get("compute_results", [])
    network_result = event.get("network_result", {})

    if not isinstance(compute_results, list):
        compute_results = []

    compute_lines = [format_compute_result(item) for item in compute_results]
    if not compute_lines:
        compute_lines = ["• No compute result found"]

    network_line = format_network_result(network_result)

    webhook_url = get_secret_value(secret_name)
    post_slack(
        webhook_url,
        {
            "text": f"[{cluster_name}] 리소스 복원 완료",
            "blocks": [
                {
                    "type": "header",
                    "text": {
                        "type": "plain_text",
                        "text": "✅ Hive Reboot Completed",
                    },
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"*{cluster_name}* 클러스터의 리소스 복원 작업이 완료됐어요.",
                    },
                },
                {
                    "type": "section",
                    "fields": [
                        {
                            "type": "mrkdwn",
                            "text": "*Status*\n`Completed`",
                        },
                        {
                            "type": "mrkdwn",
                            "text": "*Operation*\n`reboot`",
                        },
                        {
                            "type": "mrkdwn",
                            "text": f"*Duration*\n`{duration}`",
                        },
                        {
                            "type": "mrkdwn",
                            "text": f"*Execution*\n`{execution_id}`",
                        },
                    ],
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": "*Compute Results*\n" + "\n".join(compute_lines),
                    },
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"*Network Result*\n{network_line}",
                    },
                },
                {
                    "type": "context",
                    "elements": [
                        {
                            "type": "mrkdwn",
                            "text": f"Started `{started_at}`",
                        },
                        {
                            "type": "mrkdwn",
                            "text": f"Completed `{completed_at}`",
                        },
                        {
                            "type": "mrkdwn",
                            "text": f"SFN `{execution_arn}`",
                        },
                    ],
                },
            ],
        },
    )

    return {
        "ok": True,
        "service": "slack",
        "action": "reboot_complete_notified",
        "cluster_name": cluster_name,
        "execution": execution_id,
        "started_at": started_at,
        "completed_at": completed_at,
        "duration": duration,
        "compute_result_count": len(compute_results),
    }
