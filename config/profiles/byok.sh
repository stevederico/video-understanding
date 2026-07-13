#!/bin/bash
# ============================================
# BYOK PROFILE (bring your own key)
# STT runs on xAI (needs XAI_API_KEY); frames via Mux (needs MUX_TOKEN_ID/SECRET,
# falls back to local ffmpeg if unset). No local whisper.cpp model/build required.
# Use: VU_PROFILE=byok XAI_API_KEY=... ./video-understanding.sh <video>
# Keys ALWAYS come from the environment — never hardcode them here.
# ============================================

: "${VU_PROFILE:=byok}"; export VU_PROFILE

# ----------------------------------------
# STAGE: Transcription (STT) — xAI
# POST the extracted wav to xAI /v1/stt; word timestamps are turned into
# transcript.srt/.txt/.json locally. Same outputs as the local whisper path.
# ----------------------------------------
: "${STT_BACKEND:=xai}"; export STT_BACKEND
: "${XAI_STT_URL:=https://api.x.ai/v1/stt}"; export XAI_STT_URL
: "${STT_WORDS_PER_CUE:=10}"; export STT_WORDS_PER_CUE
: "${VU_LANG:=auto}"; export VU_LANG

# ----------------------------------------
# STAGE: Frames — Mux
# Uploads the video to Mux and pulls thumbnails at each timestamp. Degrades to
# local ffmpeg automatically if MUX_TOKEN_ID/SECRET are absent (recommended for
# local files — ffmpeg is instant and free; Mux is for zero-local-tool setups).
# ----------------------------------------
: "${FRAME_BACKEND:=mux}"; export FRAME_BACKEND
: "${FRAME_QUALITY:=3}"; export FRAME_QUALITY
: "${DEFAULT_INTERVAL:=0.5}"; export DEFAULT_INTERVAL

# ----------------------------------------
# STAGE: X sourcing (unchanged from local)
# ----------------------------------------
: "${X_VIDEO_RESOLVER:=xurl}"; export X_VIDEO_RESOLVER
: "${X_DOWNLOAD_METHOD:=curl}"; export X_DOWNLOAD_METHOD
: "${X_CACHE_DIR:=$HOME/.cache/video-understanding/x-videos}"; export X_CACHE_DIR

# ----------------------------------------
# STAGE: Cache / temp
# ----------------------------------------
: "${CACHE_DIR:=$HOME/.cache/video-understanding}"; export CACHE_DIR
: "${TMP_DIR:=/tmp/video-understanding}"; export TMP_DIR
: "${DEFAULT_OUTDIR_SUFFIX:=_understand}"; export DEFAULT_OUTDIR_SUFFIX
