#!/bin/sh
export MODEL_API_KEY="LLM_1066445082842679_ASYU_nVclmvlVezj86qBpiz1GFk"
mkdir -p /tmp/codex-modelapi

CODEX_HOME=/tmp/codex-modelapi codex \
  -m muse-spark-1.3 \
  -c 'model_provider="meta"' \
  -c 'model_providers.meta.name="Meta Model API"' \
  -c 'model_providers.meta.base_url="https://api.meta.ai/v1"' \
  -c 'model_providers.meta.env_key="MODEL_API_KEY"' \
  -c 'model_providers.meta.wire_api="responses"' \
  -c 'model_reasoning_effort="xhigh"'
