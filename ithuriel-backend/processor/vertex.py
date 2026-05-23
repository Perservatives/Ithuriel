"""Vertex AI summarization and embeddings."""

from __future__ import annotations

import os
from typing import Any

import structlog
from google.api_core import exceptions as gcp_exceptions
from tenacity import (
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
)
import vertexai
from vertexai.generative_models import GenerativeModel, GenerationConfig
from vertexai.language_models import TextEmbeddingModel

logger = structlog.get_logger(__name__)

SYSTEM_PROMPT = (
    "You are a developer context summarizer. Given raw workspace state, "
    "produce a structured summary. Include: what the developer is building, "
    "current task, key files, recent decisions, open questions. "
    "Be concise, technical, and specific. No filler."
)

FLASH_MODEL = os.environ.get("VERTEX_FLASH_MODEL", "gemini-1.5-flash-002")
PRO_MODEL = os.environ.get("VERTEX_PRO_MODEL", "gemini-1.5-pro-002")
EMBED_MODEL = os.environ.get("VERTEX_EMBED_MODEL", "text-embedding-005")
PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "")
LOCATION = os.environ.get("VERTEX_LOCATION", "us-central1")

_initialized = False


def _ensure_vertex() -> None:
    global _initialized
    if _initialized:
        return
    vertexai.init(project=PROJECT_ID, location=LOCATION)
    _initialized = True


def _retryable_generate(model: GenerativeModel, prompt: str, config: GenerationConfig) -> str:
    @retry(
        retry=retry_if_exception_type(
            (gcp_exceptions.ResourceExhausted, gcp_exceptions.ServiceUnavailable)
        ),
        stop=stop_after_attempt(5),
        wait=wait_exponential(multiplier=1, min=2, max=60),
        reraise=True,
    )
    def _call() -> str:
        response = model.generate_content(
            [SYSTEM_PROMPT, prompt],
            generation_config=config,
        )
        text = response.text
        if not text:
            return ""
        return text.strip()

    return _call()


def summarize_short(raw: str) -> str:
    _ensure_vertex()
    model = GenerativeModel(FLASH_MODEL)
    config = GenerationConfig(max_output_tokens=100, temperature=0.2)
    return _retryable_generate(model, raw[:120_000], config)


def summarize_medium(raw: str) -> str:
    _ensure_vertex()
    model = GenerativeModel(FLASH_MODEL)
    config = GenerationConfig(max_output_tokens=500, temperature=0.2)
    return _retryable_generate(model, raw[:120_000], config)


def summarize_full(raw: str) -> str:
    _ensure_vertex()
    model = GenerativeModel(PRO_MODEL)
    config = GenerationConfig(max_output_tokens=2000, temperature=0.3)
    return _retryable_generate(model, raw[:120_000], config)


def embed(text: str) -> list[float]:
    _ensure_vertex()

    @retry(
        retry=retry_if_exception_type(
            (gcp_exceptions.ResourceExhausted, gcp_exceptions.ServiceUnavailable)
        ),
        stop=stop_after_attempt(5),
        wait=wait_exponential(multiplier=1, min=2, max=60),
        reraise=True,
    )
    def _call() -> list[float]:
        embedding_model = TextEmbeddingModel.from_pretrained(EMBED_MODEL)
        embeddings = embedding_model.get_embeddings([text[:8000]])
        vector: list[float] = list(embeddings[0].values)
        if len(vector) != 1536:
            logger.warning(
                "unexpected_embedding_dim",
                expected=1536,
                actual=len(vector),
            )
        return vector

    return _call()
