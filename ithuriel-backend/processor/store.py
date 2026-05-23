"""Firestore and GCS helpers for the context processor."""

from __future__ import annotations

import json
import os
from typing import Any

import structlog
from google.cloud import firestore, storage
from google.cloud.firestore import SERVER_TIMESTAMP

logger = structlog.get_logger(__name__)

db = firestore.Client(project=os.environ.get("GOOGLE_CLOUD_PROJECT"))
storage_client = storage.Client(project=os.environ.get("GOOGLE_CLOUD_PROJECT"))


def fetch_raw_from_gcs(raw_ref: str) -> dict[str, Any]:
    """Load raw snapshot JSON from gs://bucket/path."""
    if not raw_ref.startswith("gs://"):
        raise ValueError(f"Invalid rawRef: {raw_ref}")

    path = raw_ref[5:]
    bucket_name, _, object_path = path.partition("/")
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(object_path)
    data = blob.download_as_text()
    return json.loads(data)


def write_processed_snapshot(
    uid: str,
    snapshot_id: str,
    *,
    summary_short: str,
    summary_medium: str,
    summary_full: str,
    embedding: list[float],
) -> None:
    ref = (
        db.collection("users")
        .document(uid)
        .collection("snapshots")
        .document(snapshot_id)
    )

    @firestore.transactional
    def _update(transaction: firestore.Transaction) -> None:
        snap = ref.get(transaction=transaction)
        if not snap.exists:
            raise ValueError(f"Snapshot {snapshot_id} not found for user {uid}")
        transaction.update(
            ref,
            {
                "status": "ready",
                "summaryShort": summary_short,
                "summaryMedium": summary_medium,
                "summaryFull": summary_full,
                "embedding": embedding,
                "processedAt": SERVER_TIMESTAMP,
                "error": firestore.DELETE_FIELD,
            },
        )

    transaction = db.transaction()
    _update(transaction)
    logger.info("snapshot_processed", uid=uid, snapshot_id=snapshot_id)


def write_snapshot_error(uid: str, snapshot_id: str, error: str) -> None:
    ref = (
        db.collection("users")
        .document(uid)
        .collection("snapshots")
        .document(snapshot_id)
    )
    ref.update(
        {
            "status": "error",
            "error": error[:4096],
            "processedAt": SERVER_TIMESTAMP,
        }
    )
    logger.error("snapshot_failed", uid=uid, snapshot_id=snapshot_id, error=error)
