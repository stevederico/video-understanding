#!/bin/bash
# ============================================
# LOCAL FOCUSED PROFILE
# All stages use local tools only (ffmpeg + local whisper).
# No cloud APIs, no external services.
# ============================================

: "${VU_PROFILE:=local}"
export VU_PROFILE

# ----------------------------------------
# STAGE: Vision / Frame Extraction
# ffmpeg settings for extracting timestamped frames.
# ----------------------------------------
: "${FRAME_QUALITY:=3}"         # ffmpeg -q:v (lower=better)
export FRAME_QUALITY
: "${DEFAULT_INTERVAL:=0.5}"      # default 500ms; override with --interval, env, or positional
export DEFAULT_INTERVAL

# ----------------------------------------
# STAGE: Transcription (STT) + Frames — both local, no keys
# ----------------------------------------
: "${STT_BACKEND:=local}"; export STT_BACKEND      # whisper.cpp
: "${FRAME_BACKEND:=local}"; export FRAME_BACKEND   # ffmpeg
: "${VU_MODEL:=large-v3-turbo}"
export VU_MODEL
: "${WHISPER_MODEL:=$HOME/.local/opt/whisper.cpp/models/ggml-large-v3-turbo.bin}"
export WHISPER_MODEL
: "${VU_LANG:=auto}"
export VU_LANG

# Whisper tuning (local best practices)
: "${DTW_PRESET:=large.v3.turbo}"
export DTW_PRESET
: "${WHISPER_NO_SPEECH_THOLD:=0.68}"
export WHISPER_NO_SPEECH_THOLD
: "${WHISPER_LOGPROB_THOLD:=-0.9}"
export WHISPER_LOGPROB_THOLD
: "${VAD_MODEL:=$HOME/.local/opt/whisper.cpp/models/ggml-silero-v6.2.0.bin}"
export VAD_MODEL

# ----------------------------------------
# STAGE: Agent / Understanding
# How the agent (Grok or other) performs review.
# All instructions are portable (SKILL.md + generated AGENT.md).
# ----------------------------------------
: "${AGENT_PROVIDER:=portable}"
export AGENT_PROVIDER
: "${DEFAULT_OUTDIR_SUFFIX:=_understand}"
export DEFAULT_OUTDIR_SUFFIX

# ----------------------------------------
# STAGE: Caching / Temp
# Where to store downloaded videos and temp files.
# ----------------------------------------
: "${CACHE_DIR:=$HOME/.cache/video-understanding}"
export CACHE_DIR
: "${TMP_DIR:=/tmp/video-understanding}"
export TMP_DIR

# ----------------------------------------
# Other
# ----------------------------------------
: "${TRANSCRIPTION_BACKEND:=local}"
export TRANSCRIPTION_BACKEND
