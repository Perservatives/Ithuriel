"""Cloud Function entry point — processes context snapshots from Pub/Sub."""

from __future__ import annotations

import base64
import json
import os
from typing import Any

import functions_framework
import structlog
from cloudevents.http import CloudEvent
from google.cloud import pubsub_v1

from store import fetch_raw_from_gcs, write_processed_snapshot, write_snapshot_error
from vertex import embed, summarize_full, summarize_medium, summarize_short

structlog.configure(
    processors=[
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ]
)
logger = structlog.get_logger(__name__)

PROCESSED_TOPIC = os.environ.get("PUBSUB_PROCESSED_TOPIC", "ithuriel-processed")
_publisher: pubsub_v1.PublisherClient | None = None


def _publisher_client() -> pubsub_v1.PublisherClient:
    global _publisher
    if _publisher is None:
        _publisher = pubsub_v1.PublisherClient()
    return _publisher


def _publish_processed(uid: str, snapshot_id: str) -> None:
    project = os.environ["GOOGLE_CLOUD_PROJECT"]
    topic_path = _publisher_client().topic_path(project, PROCESSED_TOPIC)
    payload = json.dumps(
        {"uid": uid, "snapshotId": snapshot_id, "status": "ready"}
    ).encode("utf-8")
    _publisher_client().publish(topic_path, payload)


def _extract_raw_text(payload: dict[str, Any]) -> str:
    raw_content = payload.get("rawContent", "")
    parts = [
        raw_content,
        "\n".join(payload.get("activeFiles", [])),
        "\n".join(payload.get("recentEdits", [])),
        "\n".join(payload.get("terminalHistory", [])),
        f"branch:{payload.get('gitBranch', '')}",
        f"commit:{payload.get('gitCommit', '')}",
    ]
    return "\n\n".join(p for p in parts if p)


def _parse_pubsub_payload(cloud_event: CloudEvent) -> dict[str, str]:
    data = cloud_event.data or {}
    message = data.get("message", data)
    raw_b64 = message.get("data", "")
    if not raw_b64:
        raise ValueError("Empty Pub/Sub message data")
    decoded = base64.b64decode(raw_b64).decode("utf-8")
    parsed: dict[str, str] = json.loads(decoded)
    return parsed


def _delivery_attempt(cloud_event: CloudEvent) -> int:
    attrs = cloud_event.data.get("message", {}).get("attributes", {}) if cloud_event.data else {}
    attempt = attrs.get("googclient_deliveryattempt", "1")
    try:
        return int(attempt)
    except ValueError:
        return 1


@functions_framework.cloud_event
def process_snapshot(cloud_event: CloudEvent) -> None:
    """Pub/Sub triggered Cloud Function (Gen2 CloudEvent)."""
    message: dict[str, str] | None = None
    try:
        message = _parse_pubsub_payload(cloud_event)
        uid = message["uid"]
        snapshot_id = message["snapshotId"]
        raw_ref = message["rawRef"]

        logger.info("processing_snapshot", uid=uid, snapshot_id=snapshot_id)

        payload = fetch_raw_from_gcs(raw_ref)
        text = _extract_raw_text(payload)

        summary_short = summarize_short(text)
        summary_medium = summarize_medium(text)
        summary_full = summarize_full(text)
        vector = embed(summary_full or summary_medium or summary_short)

        write_processed_snapshot(
            uid,
            snapshot_id,
            summary_short=summary_short,
            summary_medium=summary_medium,
            summary_full=summary_full,
            embedding=vector,
        )
        _publish_processed(uid, snapshot_id)
        logger.info("snapshot_complete", uid=uid, snapshot_id=snapshot_id)

    except Exception as exc:
        logger.exception("process_snapshot_failed", error=str(exc))
        if message and _delivery_attempt(cloud_event) >= 3:
            write_snapshot_error(message["uid"], message["snapshotId"], str(exc))
        raise
