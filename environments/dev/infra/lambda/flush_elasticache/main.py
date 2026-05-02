import os
import json
import ssl
import redis


def parse_bool(value: str, default: bool = False) -> bool:
    if value is None:
        return default

    return value.lower() in ("1", "true", "yes", "y", "on")


def lambda_handler(event, context):
    cluster_name = os.environ.get("CLUSTER_NAME", event.get("cluster_name", "unknown"))

    redis_host = os.environ["ELASTICACHE_ENDPOINT"]
    redis_port = int(os.environ.get("ELASTICACHE_PORT", "6379"))

    redis_ssl = parse_bool(os.environ.get("ELASTICACHE_SSL"), default=True)
    flush_mode = os.environ.get("FLUSH_MODE", "ASYNC").upper()

    if flush_mode not in ("SYNC", "ASYNC"):
        raise ValueError("FLUSH_MODE must be either SYNC or ASYNC")

    client = redis.Redis(
        host=redis_host,
        port=redis_port,
        ssl=redis_ssl,
        ssl_cert_reqs=ssl.CERT_NONE if redis_ssl else None,
        socket_connect_timeout=5,
        socket_timeout=20,
        decode_responses=True,
    )

    ping_result = client.ping()

    if flush_mode == "ASYNC":
        flush_result = client.flushall(asynchronous=True)
    else:
        flush_result = client.flushall(asynchronous=False)

    return {
        "ok": True,
        "service": "elasticache",
        "action": "flushed",
        "cluster_name": cluster_name,
        "endpoint": redis_host,
        "port": redis_port,
        "ssl": redis_ssl,
        "flush_mode": flush_mode,
        "ping": ping_result,
        "flush_result": flush_result,
    }
