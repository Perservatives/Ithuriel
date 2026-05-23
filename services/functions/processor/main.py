"""
Pub/Sub-triggered Cloud Function: takes a freshly-arrived ContextSnapshot,
asks Vertex AI for short/medium/full summaries + a 768-dim embedding,
and writes the results back to Firestore + GCS.
"""
from __future__ import annotations

import base64
import json
import logging
import os
from datetime import datetime, timezone

import functions_framework
from google.cloud import firestore, storage, pubsub_v1
from google.cloud.firestore_v1.vector import Vector
from vertexai import init as vertex_init
from vertexai.generative_models import GenerativeModel
from vertexai.language_models import TextEmbeddingModel

PROJECT       = os.environ["GCP_PROJECT"]
REGION        = os.environ.get("VERTEX_REGION", "us-central1")
SNAP_BUCKET   = os.environ["GCS_BUCKET_SNAPSHOTS"]
PROCESSED_TOP = os.environ.get("PROCESSED_TOPIC", "ithuriel-snapshots-processed")

vertex_init(project=PROJECT, location=REGION)
_db        = firestore.Client(project=PROJECT)
_storage   = storage.Client(project=PROJECT)
_publisher = pubsub_v1.PublisherClient()
_processed = _publisher.topic_path(PROJECT, PROCESSED_TOP)

_flash = GenerativeModel("gemini-1.5-flash-002")
_pro   = GenerativeModel("gemini-1.5-pro-002")
_embed = TextEmbeddingModel.from_pretrained("text-embedding-005")


@functions_framework.cloud_event
def handle(event):
    try:
        envelope = json.loads(base64.b64decode(event.data["message"]["data"]).decode("utf-8"))
    except Exception:
        logging.exception("failed to decode pubsub envelope")
        return

    snapshot_id = envelope.get("snapshotId")
    user_id     = envelope.get("userId")
    raw_ref     = envelope.get("rawRef")
    if not (snapshot_id and user_id and raw_ref):
        logging.error("missing required fields in envelope: %s", envelope)
        return

    raw = _load_raw(raw_ref)
    text = _render_for_llm(raw)

    short  = _summarize(_flash, text, max_tokens=120,  style="Two sentences max. Plain prose.")
    medium = _summarize(_flash, text, max_tokens=500,  style="A short paragraph capturing the active task.")
    full   = _summarize(_pro,   text, max_tokens=1800, style="Long-form CLAUDE.md-style brief.")

    # text-embedding-005 returns 768-dim vectors by default. Embed the
    # short+medium summary + a slice of raw text — summaries are more
    # semantically dense than the dump alone, so RAG retrieval over them
    # finds better neighbours.
    embed_input = f"{short}\n\n{medium}\n\n{text[:6000]}"
    vector = _embed.get_embeddings([embed_input])[0].values

    # (a) Portable JSON copy of the vector in GCS.
    embed_path = f"{user_id}/{snapshot_id}.embedding.json"
    _storage.bucket(SNAP_BUCKET).blob(embed_path).upload_from_string(
        json.dumps(vector), content_type="application/json"
    )

    # (b) Native Firestore Vector field — the API's /v1/context/search route
    # runs find_nearest() against this for RAG retrieval. `searchText` is a
    # compact retrieval-friendly bundle so callers don't need a second GCS
    # fetch to render a result.
    _db.collection("snapshots").document(snapshot_id).set({
        "summaryShort":  short,
        "summaryMedium": medium,
        "summaryFull":   full,
        "embedding":     Vector(vector),
        "searchText":    _search_text(raw, medium),
        "embeddingRef":  f"gs://{SNAP_BUCKET}/{embed_path}",
        "processedAt":   datetime.now(timezone.utc),
    }, merge=True)

    _publisher.publish(_processed, json.dumps({
        "snapshotId": snapshot_id, "userId": user_id
    }).encode("utf-8"))

    logging.info("processed snapshot %s for user %s", snapshot_id, user_id)


def _load_raw(ref: str) -> dict:
    assert ref.startswith("gs://"), f"unexpected rawRef: {ref}"
    bucket_name, _, path = ref[5:].partition("/")
    data = _storage.bucket(bucket_name).blob(path).download_as_bytes()
    return json.loads(data)


def _search_text(raw: dict, medium_summary: str) -> str:
    """Compact retrieval-friendly bundle stored on the snapshot doc so RAG
    results carry usable context without a second fetch."""
    bits: list[str] = []
    if raw.get("workspacePath"):
        bits.append(f"workspace={raw['workspacePath']}")
    git = raw.get("gitState") or {}
    if git.get("branch"):     bits.append(f"branch={git['branch']}")
    if git.get("lastCommit"): bits.append(f"commit={git['lastCommit']}")
    if medium_summary:        bits.append(medium_summary)
    return " | ".join(bits)


def _render_for_llm(raw: dict) -> str:
    lines: list[str] = []
    if raw.get("workspacePath"): lines.append(f"Workspace: {raw['workspacePath']}")
    git = raw.get("gitState") or {}
    if git.get("branch"):     lines.append(f"Branch: {git['branch']}")
    if git.get("lastCommit"): lines.append(f"Last commit: {git['lastCommit']}")
    if git.get("changedFiles"):
        lines.append("Changed files:")
        for f in git["changedFiles"][:15]: lines.append(f"  - {f}")
    if git.get("diffSummary"): lines.append("Diff stat:\n" + git["diffSummary"])
    edits = raw.get("recentEdits") or []
    if edits:
        lines.append("Recent edits:")
        for e in edits[:15]:
            lines.append(f"  - {e.get('path','?')}: {e.get('summary','')}")
    hist = raw.get("terminalHistory") or []
    if hist:
        lines.append("Recent terminal commands:")
        for cmd in hist[-15:]: lines.append(f"  $ {cmd}")
    return "\n".join(lines)


def _summarize(model: GenerativeModel, text: str, max_tokens: int, style: str) -> str:
    if not text.strip():
        return ""
    prompt = (
        f"Summarize the developer's current working context.\n"
        f"Style: {style}\n"
        f"Max tokens: {max_tokens}\n\n---\n{text[:12000]}\n"
    )
    resp = model.generate_content(prompt, generation_config={"max_output_tokens": max_tokens, "temperature": 0.2})
    try:
        return resp.text.strip()
    except Exception:
        return ""
