#!/bin/bash
# ============================================
# GROK / AGENT-FOCUSED PROFILE
# When running under Grok (or similar), the agent handles "cloud" parts like X interaction.
# Mechanical stages remain local.
# Use: VU_PROFILE=grok ./video-understanding.sh ...
# ============================================

: "${VU_PROFILE:=grok}"
export VU_PROFILE

# ----------------------------------------
# STAGE: X Sourcing / Download
# Grok's built-in X tools (the "grok cli" / tools) are used to find posts and provide video URLs.
# The CLI script does NOT call xurl; it expects --direct or the skill/agent to supply the URL.
# Download still uses curl from CDN.
# ----------------------------------------
: "${X_VIDEO_RESOLVER:=grok}"   # "grok" means agent provides URL via tools/skill
export X_VIDEO_RESOLVER
: "${X_DOWNLOAD_METHOD:=curl}"
export X_DOWNLOAD_METHOD
: "${X_CACHE_DIR:=$HOME/.cache/video-understanding/x-videos}"
export X_CACHE_DIR

# ----------------------------------------
# STAGE: Vision / Frame Extraction
# Same as local: ffmpeg for timestamped frames.
# (Could theoretically use Grok vision in future, but currently local.)
# ----------------------------------------
: "${FRAME_QUALITY:=3}"
export FRAME_QUALITY
: "${DEFAULT_INTERVAL:=5}"
export DEFAULT_INTERVAL

# ----------------------------------------
# STAGE: Transcription (STT)
# Local whisper.cpp (same as local profile).
# Agent (Grok) can use its own capabilities for analysis, but STT here is local.
# ----------------------------------------
: "${VU_MODEL:=large-v3-turbo}"
export VU_MODEL
: "${WHISPER_MODEL:=$HOME/.local/opt/whisper.cpp/models/ggml-large-v3-turbo.bin}"
export WHISPER_MODEL
: "${VU_LANG:=auto}"
export VU_LANG

# Whisper tuning (local best practices, same as local)
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
# The SKILL.md + AGENT.md drive this. Under Grok, the agent (Grok) performs the review.
# This stage is "cloud" in the sense that the intelligence comes from the running agent.
# ----------------------------------------
: "${AGENT_PROVIDER:=grok}"
export AGENT_PROVIDER
: "${DEFAULT_OUTDIR_SUFFIX:=_understand}"
export DEFAULT_OUTDIR_SUFFIX

# ----------------------------------------
# STAGE: Caching / Temp / Storage
# Same local paths.
# ----------------------------------------
: "${CACHE_DIR:=$HOME/.cache/video-understanding}"
export CACHE_DIR
: "${TMP_DIR:=/tmp/video-understanding}"
export TMP_DIR

# ----------------------------------------
# Other / Backends
# ----------------------------------------
: "${TRANSCRIPTION_BACKEND:=local}"
export TRANSCRIPTION_BACKEND

# Note: When this profile is active and running inside Grok, the agent uses its native X tools
# (the "grok cli") to find posts and supply video URLs. The bash CLI stays local for extraction.
# See SKILL.md for agent-side usage.
