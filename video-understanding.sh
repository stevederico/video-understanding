#!/usr/bin/env bash
# video-understanding — watch a video like a critic: extract frames + a timestamped SRT
# transcript, then hand off to an AI agent to review frames against the
# transcript and write a full understanding of the video.
#
# Supports local video files or X (Twitter) posts.
# For X: defaults to xurl read to resolve video URL, then curl download; --direct for manual CDN URL.
# Extracts frames + transcript like local.
#
# Stage 1 (this script): mechanical extraction. Fast, deterministic, no AI.
# Stage 2 (the agent):    reads frames + SRT, writes understanding.md.
#
# Usage:
#   video-understanding.sh <video-or-x-url> [interval] [output_dir] [--interval <val>] [--direct <mp4-url>] [--name <slug>]
#   --interval accepts 0.5, 500ms, 2s etc. Default: 500ms.
#
# Config: VU_PROFILE=local (default) or grok. Profiles in config/profiles/
# Env vars override profile.
#
# Examples:
#   ./video-understanding.sh ~/Movies/demo.mov
#   ./video-understanding.sh https://x.com/user/status/1234567890 --interval 500ms
#   ./video-understanding.sh https://x.com/user/status/1234567890 --direct https://video.twimg.com/...mp4 --interval 1
#
# STT is local whisper.cpp: whisper-cli must be on PATH and a matching ggml
# model present (see README for the one-time build + model download).
#
# Config: VU_PROFILE=local (default) or grok. See config/profiles/
# Env vars override profile. Local = fully local (whisper + xurl + curl).
#
# Output tree (in <output_dir>):
#   frames/t00m00s.jpg or t00m00s500ms.jpg ...   one JPEG every <interval> (default 500ms), timestamp-named
#   transcript.srt           timestamped captions
#   transcript.txt           plain transcript
#   transcript.json          word/segment data
#   manifest.json            duration, fps, interval, frame->timestamp map
#   AGENT.md                 instructions for the agent (stage 2)

set -euo pipefail

# Load config profile (default: local)
CONFIG_PROFILE="${VU_PROFILE:-local}"
SCRIPT_DIR="$(dirname "$(perl -MCwd -e 'print Cwd::abs_path(shift)' "${BASH_SOURCE[0]}")")"
CONFIG_FILE="$SCRIPT_DIR/config/profiles/${CONFIG_PROFILE}.sh"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

# Optional .env for BYOK keys (gitignored). Checks ./.env then <script-dir>/.env.
# Plain KEY=value lines; already-set environment variables always win (so a
# per-run `XAI_API_KEY=… ./video-understanding.sh` overrides the file).
load_env_file() {
  [ -f "$1" ] || return 0
  local k v
  while IFS='=' read -r k v || [ -n "$k" ]; do
    case "$k" in ''|'#'*|*[!A-Za-z0-9_]*) continue ;; esac  # skip blank/comment/invalid
    [ -n "${!k:-}" ] && continue                             # environment wins
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"       # strip one layer of quotes
    export "$k=$v"
  done < "$1"
}
load_env_file "./.env"
load_env_file "$SCRIPT_DIR/.env"

# Apply profile defaults early (before arg parsing) so DEFAULT_INTERVAL / DEFAULT_OUTDIR_SUFFIX
# from config/profiles/*.sh control behavior (env overrides still win).
: "${DEFAULT_INTERVAL:=0.5}"
: "${DEFAULT_OUTDIR_SUFFIX:=_understand}"
DEFAULT_INTERVAL_RAW="$DEFAULT_INTERVAL"

# Normalize interval value to seconds (float). Accepts numbers, 500ms, 2s, etc.
normalize_interval() {
  local v=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  if [[ "$v" =~ ^([0-9.]+)ms$ ]]; then
    awk -v x="${BASH_REMATCH[1]}" 'BEGIN { printf "%.3f", x / 1000 }'
  elif [[ "$v" =~ ^([0-9.]+)s?$ ]]; then
    awk -v x="${BASH_REMATCH[1]}" 'BEGIN { printf "%.3f", x }'
  else
    echo "$1"
  fi
}

# Parse args: support --help first, video first, options mixed, positionals for interval/outdir
VIDEO=""
INTERVAL=$(normalize_interval "${DEFAULT_INTERVAL_RAW}")
OUTDIR=""
DIRECT_URL=""
SLUG=""
FORCE_DOWNLOAD=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat <<EOF
video-understanding - Official CLI for video analysis with AI

Usage:
  video-understanding <video-or-x-url> [interval] [outdir] [options]

Options:
  --interval <val>    Frame interval (default 0.5s / 500ms). Accepts 0.5, 500ms, 2s, etc.
  --direct <mp4-url>  Direct CDN URL to use (bypass xurl resolve; for manual CDN)
  --name <slug>       Slug for output (default from file or post ID)
  --force, --no-cache  Re-download even if cached video exists
  -h, --help          Show this help

Modes (VU_PROFILE): local (default, whisper.cpp + ffmpeg, no keys) | byok
  (xAI STT + Mux frames, needs XAI_API_KEY [+ MUX_TOKEN_ID/SECRET], installs
  nothing) | grok (agent supplies the X video URL via --direct). See
  config/profiles/*.sh. Backends are also settable directly:
  STT_BACKEND=local|xai, FRAME_BACKEND=local|mux.
Interval and output dir suffix: --interval, DEFAULT_INTERVAL (500ms default), or positional.

Examples:
  ./video-understanding.sh demo.mov
  ./video-understanding.sh demo.mov --interval 500ms
  XAI_API_KEY=… VU_PROFILE=byok ./video-understanding.sh demo.mov       # no install
  VU_PROFILE=local ./video-understanding.sh https://x.com/.../status/123 --name my-post
  ./video-understanding.sh https://x.com/.../status/123 --direct https://video.twimg.com/...mp4 --name my-post --interval 1
  VU_PROFILE=grok ./video-understanding.sh https://x.com/... --direct <url> --name p
  ./video-understanding.sh x-post.mp4 --force --name retry --interval 0.25

BYOK keys come from the environment (or a gitignored .env). Never hardcoded.
EOF
      exit 0
      ;;
    --interval)
      INTERVAL=$(normalize_interval "$2"); shift 2 ;;
    --interval=*)
      INTERVAL=$(normalize_interval "${1#*=}"); shift ;;
    --direct) DIRECT_URL="$2"; shift 2 ;;
    --video) DIRECT_URL="$2"; shift 2 ;;  # legacy alias for --direct
    --name)  SLUG="$2"; shift 2 ;;
    --force|--no-cache) FORCE_DOWNLOAD=1; shift ;;
    -*)
      echo "Unknown arg: $1" >&2; exit 1 ;;
    *)
      if [[ -z "$VIDEO" ]]; then
        VIDEO="$1"
      elif { [[ "$1" =~ ^[0-9]+$ ]] || [[ "$1" =~ ^[0-9]*\.[0-9]+$ ]] || [[ "$1" =~ ^[0-9.]+(ms|s)?$ ]]; } && [[ "$INTERVAL" == "$(normalize_interval "${DEFAULT_INTERVAL_RAW}")" ]]; then
        INTERVAL=$(normalize_interval "$1")
      elif [[ -z "$OUTDIR" ]]; then
        OUTDIR="$1"
      else
        echo "Unexpected arg: $1" >&2; exit 1
      fi
      shift
      ;;
  esac
done

# Final normalization (covers positional args and profile/env values)
INTERVAL=$(normalize_interval "$INTERVAL")

if [[ -z "$VIDEO" ]]; then
  echo "Error: video or X URL required" >&2
  echo "See --help" >&2
  exit 1
fi

# Apply defaults from config or hardcoded (local profile values)
: "${VU_MODEL:=large-v3-turbo}"
: "${WHISPER_MODEL:=$HOME/.local/opt/whisper.cpp/models/ggml-${VU_MODEL}.bin}"
: "${VU_LANG:=auto}"
: "${FRAME_QUALITY:=3}"
: "${DTW_PRESET:=large.v3.turbo}"
: "${WHISPER_NO_SPEECH_THOLD:=0.68}"
: "${WHISPER_LOGPROB_THOLD:=-0.9}"
: "${VAD_MODEL:=$HOME/.local/opt/whisper.cpp/models/ggml-silero-v6.2.0.bin}"

: "${X_VIDEO_RESOLVER:=xurl}"
: "${X_DOWNLOAD_METHOD:=curl}"
: "${X_CACHE_DIR:=$HOME/.cache/video-understanding/x-videos}"
: "${CACHE_DIR:=$HOME/.cache/video-understanding}"
: "${TMP_DIR:=/tmp/video-understanding}"

# Pluggable backends. local profile = whisper.cpp + ffmpeg (no keys). byok profile
# = xAI STT + Mux frames (bring your own keys). Each is independent.
: "${STT_BACKEND:=local}"          # local (whisper.cpp) | xai
: "${FRAME_BACKEND:=local}"        # local (ffmpeg)      | mux
: "${XAI_STT_URL:=https://api.x.ai/v1/stt}"   # xAI: POST -F file=@video, returns {text,duration,words[]}
: "${STT_WORDS_PER_CUE:=10}"       # group xAI words into ~N-word SRT cues
# Keys come from the environment — NEVER hardcoded: XAI_API_KEY, MUX_TOKEN_ID/SECRET.

mkdir -p "$CACHE_DIR" "$X_CACHE_DIR" "$TMP_DIR"

# Handle X URL or ID as input
if [[ "$VIDEO" =~ ^https?://x\.com/ || "$VIDEO" =~ ^[0-9]+$ ]]; then
  XREF="$VIDEO"
  POST_ID=$(echo "$XREF" | sed -n 's/.*status\/\([0-9]*\).*/\1/p; s/^\([0-9]*\)$/\1/p' | head -1)
  if [[ -z "$POST_ID" ]]; then
    echo "Could not parse post ID from XREF: $XREF" >&2
    exit 1
  fi
  if [[ -z "$SLUG" ]]; then
    SLUG="x-post-${POST_ID}"
  fi
  if [[ -z "$OUTDIR" ]]; then
    OUTDIR="${SLUG}${DEFAULT_OUTDIR_SUFFIX}"
  fi
  VIDEO_FILE="${X_CACHE_DIR}/${SLUG}.mp4"
  if [[ -z "$DIRECT_URL" ]]; then
    if [[ "$X_VIDEO_RESOLVER" == "xurl" ]]; then
      if command -v xurl >/dev/null 2>&1; then
        echo ">> Resolving video URL via xurl read $POST_ID (default)..."
        POST_JSON=$(xurl read "$POST_ID" 2>/dev/null || echo '{}')
        if [ "$POST_JSON" != "{}" ]; then
          if command -v node >/dev/null 2>&1; then
            # Parse xurl JSON with node (no jq dep): recursively collect video
            # variants, pick the highest-bitrate video.twimg.com mp4.
            DIRECT_URL=$(printf '%s' "$POST_JSON" | node -e '
              const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
              const vs = [];
              const walk = o => { if (o && typeof o === "object") { if (Array.isArray(o.variants)) vs.push(...o.variants); Object.values(o).forEach(walk); } };
              walk(d);
              const best = vs.filter(v => v && v.url && v.url.includes("video.twimg.com") && v.url.endsWith(".mp4"))
                             .sort((a, b) => (b.bitrate || 0) - (a.bitrate || 0))[0];
              if (best) process.stdout.write(best.url);
            ' 2>/dev/null || true)
          else
            echo ">> node not found; cannot parse xurl JSON. Provide --direct <url>"
            DIRECT_URL=""
          fi
          if [ -n "$DIRECT_URL" ]; then
            echo ">> Resolved via xurl: $DIRECT_URL"
          else
            echo ">> xurl succeeded but no mp4 video URL found in JSON"
          fi
        else
          echo ">> xurl read failed (auth needed?). Provide --direct <url>"
        fi
      else
        echo ">> xurl not found; provide --direct <direct twimg mp4 url> (or set X_VIDEO_RESOLVER=grok + supply URL from agent)"
      fi
    elif [[ "$X_VIDEO_RESOLVER" == "grok" ]]; then
      echo ">> Using grok resolver: Grok's built-in X tools (grok cli) find post & supply URL; CLI expects --direct or skill provides."
    fi
  fi
  if [[ -n "$DIRECT_URL" && ( ! -f "$VIDEO_FILE" || "$FORCE_DOWNLOAD" ) ]]; then
    echo ">> Downloading X video..."
    curl -L --fail --retry 2 --progress-bar -o "$VIDEO_FILE" "$DIRECT_URL"
  fi
  if [[ -n "$DIRECT_URL" && ! -s "$VIDEO_FILE" ]]; then
    echo "Download failed or empty file: $DIRECT_URL" >&2
    exit 1
  fi
  if [[ ! -f "$VIDEO_FILE" ]]; then
    if [[ "$X_VIDEO_RESOLVER" == "grok" ]]; then
      echo "No video file. Grok profile: use Grok's X tools (grok cli) to find post and supply --direct <url>, or let skill handle." >&2
    else
      echo "No video file. Provide --direct <direct twimg mp4 url> (or ensure xurl can resolve)." >&2
    fi
    exit 1
  fi
  VIDEO="$VIDEO_FILE"
elif [[ "$VIDEO" =~ ^https?:// || -n "$DIRECT_URL" ]]; then
  # Generic direct video-file URL (hosted anywhere) — download to cache, treat
  # as a local file. --direct overrides the positional URL.
  SRC_URL="${DIRECT_URL:-$VIDEO}"
  if [[ -z "$SLUG" ]]; then
    SLUG=$(basename "${SRC_URL%%\?*}"); SLUG="${SLUG%.*}"; [[ -n "$SLUG" ]] || SLUG="video"
  fi
  [[ -z "$OUTDIR" ]] && OUTDIR="${SLUG}${DEFAULT_OUTDIR_SUFFIX}"
  DL_DIR="$CACHE_DIR/downloads"; mkdir -p "$DL_DIR"
  VIDEO_FILE="$DL_DIR/${SLUG}.mp4"
  if [[ ! -f "$VIDEO_FILE" || -n "$FORCE_DOWNLOAD" ]]; then
    echo ">> Downloading video…"
    curl -L --fail --retry 2 --progress-bar -o "$VIDEO_FILE" "$SRC_URL" \
      || { echo "error: download failed: $SRC_URL" >&2; exit 1; }
  fi
  [[ -s "$VIDEO_FILE" ]] || { echo "error: download failed or empty: $SRC_URL" >&2; exit 1; }
  VIDEO="$VIDEO_FILE"
else
  if [[ -z "$OUTDIR" ]]; then
    if [[ -n "$SLUG" ]]; then
      OUTDIR="${SLUG}${DEFAULT_OUTDIR_SUFFIX}"   # --name applies to local files too
    else
      OUTDIR="${VIDEO%.*}${DEFAULT_OUTDIR_SUFFIX}"
    fi
  fi
fi

# --- preflight: bootstrap-friendly dependency checks ------------------------
need_ffmpeg_hint() {
  case "$(uname -s)" in
    Darwin) echo "brew install ffmpeg" ;;
    Linux)  echo "sudo apt install ffmpeg   # or: dnf/pacman install ffmpeg" ;;
    *)      echo "install ffmpeg from https://ffmpeg.org/download.html" ;;
  esac
}
# ffmpeg is only needed for LOCAL stt (audio extract) or LOCAL frames. byok+Mux
# runs fully server-side → no ffmpeg. Work out the effective frame mode first
# (Mux needs creds, else it degrades to local ffmpeg).
FRAME_EFFECTIVE="$FRAME_BACKEND"
if [ "$FRAME_EFFECTIVE" = "mux" ] && { [ -z "${MUX_TOKEN_ID:-}" ] || [ -z "${MUX_TOKEN_SECRET:-}" ]; }; then
  FRAME_EFFECTIVE="local"
fi
NEED_FFMPEG=0
[ "$STT_BACKEND" = "local" ] && NEED_FFMPEG=1
[ "$FRAME_EFFECTIVE" = "local" ] && NEED_FFMPEG=1
if [ "$NEED_FFMPEG" = "1" ]; then
  command -v ffmpeg  >/dev/null || { echo "error: ffmpeg not found → $(need_ffmpeg_hint)  (or go install-free: VU_PROFILE=byok with XAI_API_KEY + MUX_TOKEN_ID/SECRET)" >&2; exit 1; }
  command -v ffprobe >/dev/null || { echo "error: ffprobe not found → $(need_ffmpeg_hint)" >&2; exit 1; }
fi
# STT deps depend on backend.
if [ "$STT_BACKEND" = "local" ]; then
  command -v whisper-cli >/dev/null || { echo "error: whisper-cli not on PATH — install the whole toolchain in one command: git clone https://github.com/stevederico/ask-transcribe-cli.git && cd ask-transcribe-cli && bash install-stt.sh  (or use the byok profile: VU_PROFILE=byok + XAI_API_KEY)" >&2; exit 1; }
  [ -f "$WHISPER_MODEL" ] || { echo "error: model not found: $WHISPER_MODEL → ~/.local/opt/whisper.cpp/models/download-ggml-model.sh ${VU_MODEL}" >&2; exit 1; }
elif [ "$STT_BACKEND" = "xai" ]; then
  [ -n "${XAI_API_KEY:-}" ] || { echo "error: STT_BACKEND=xai needs XAI_API_KEY in the environment" >&2; exit 1; }
  command -v node >/dev/null || { echo "error: node not found (needed to build SRT from xAI words) → brew install node" >&2; exit 1; }
else
  echo "error: unknown STT_BACKEND '$STT_BACKEND' (use local|xai)" >&2; exit 1
fi
[ -f "$VIDEO" ] || { echo "error: no such file: $VIDEO" >&2; exit 1; }

mkdir -p "$OUTDIR/frames"

echo ">> $VIDEO"

# --- transcription (byok also yields the duration used for frame sampling) --
DUR=""; FPS="unknown"
if [ "$STT_BACKEND" = "xai" ]; then
  echo ">> transcribing with xAI STT (video sent directly — no ffmpeg)…"
  STT_JSON="$TMP_DIR/stt.$$.json"
  curl -sS --fail -X POST "$XAI_STT_URL" \
    -H "Authorization: Bearer $XAI_API_KEY" \
    -F file=@"$VIDEO" > "$STT_JSON" \
    || { echo "error: xAI STT request failed" >&2; rm -f "$STT_JSON"; exit 1; }
  # xAI returns {text, language, duration, words:[{text,start,end}]}. Build the
  # same outputs whisper.cpp would (transcript.srt/.txt/.json) and echo duration.
  DUR=$(node -e '
    const fs = require("fs");
    const d = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const out = process.argv[2], per = Math.max(1, parseInt(process.argv[3], 10) || 10);
    const words = Array.isArray(d.words) ? d.words : [];
    const fmt = t => { const h=Math.floor(t/3600), m=Math.floor(t%3600/60), s=Math.floor(t%60), ms=Math.round((t-Math.floor(t))*1000);
      return `${String(h).padStart(2,"0")}:${String(m).padStart(2,"0")}:${String(s).padStart(2,"0")},${String(ms).padStart(3,"0")}`; };
    const cues = [];
    for (let i=0;i<words.length;i+=per){ const g=words.slice(i,i+per); if(!g.length) continue;
      cues.push({start:g[0].start,end:g[g.length-1].end,text:g.map(w=>w.text).join(" ").trim()}); }
    // If no word timestamps, fall back to one cue of the whole text.
    if(!cues.length && d.text) cues.push({start:0,end:d.duration||0,text:d.text});
    const srt = cues.map((c,i)=>`${i+1}\n${fmt(c.start)} --> ${fmt(c.end)}\n${c.text}\n`).join("\n");
    fs.writeFileSync(`${out}.srt`, srt);
    fs.writeFileSync(`${out}.txt`, (d.text || cues.map(c=>c.text).join(" ")).trim() + "\n");
    fs.writeFileSync(`${out}.json`, JSON.stringify({text:d.text,language:d.language,duration:d.duration,segments:cues},null,2));
    process.stdout.write(String(d.duration||""));
  ' "$STT_JSON" "$OUTDIR/transcript" "$STT_WORDS_PER_CUE")
  rm -f "$STT_JSON"
else
  echo ">> extracting audio…"
  ffmpeg -y -v error -i "$VIDEO" -ac 1 -ar 16000 -vn "$OUTDIR/transcript.wav"
  DUR=$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$VIDEO")
  FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nk=1:nw=1 "$VIDEO" | head -1)
  echo ">> transcribing with whisper.cpp (model=$VU_MODEL)…"
  # DTW word-level alignment for accurate timestamps; preset = model name with
  # '-' → '.' (large-v3-turbo → large.v3.turbo). -ml 60 -sow = readable phrase cues.
  DTW_PRESET="${DTW_PRESET:-${VU_MODEL//-/.}}"
  LANG_ARG=(); [ -n "${VU_LANG:-}" ] && LANG_ARG=(--language "$VU_LANG")
  WHISPER_ARGS=( -m "$WHISPER_MODEL" -f "$OUTDIR/transcript.wav" \
    -of "$OUTDIR/transcript" -osrt -otxt -oj \
    -dtw "$DTW_PRESET" -ml 60 -sow \
    -nth "${WHISPER_NO_SPEECH_THOLD}" -lpt "${WHISPER_LOGPROB_THOLD}" )
  [ -f "$VAD_MODEL" ] && WHISPER_ARGS+=( --vad-model "$VAD_MODEL" )
  whisper-cli "${WHISPER_ARGS[@]}" ${LANG_ARG[@]+"${LANG_ARG[@]}"}
  rm -f "$OUTDIR/transcript.wav"
fi
: "${DUR:=0}"
echo ">> duration ${DUR}s | fps ${FPS} | sampling every ${INTERVAL}s"

# Post-process transcript (inspired by x-studio): drop non-speech and simple dupes
if [ -f "$OUTDIR/transcript.txt" ]; then
  echo ">> cleaning transcript..."
  # drop [music]/sound-effect lines, then dedupe consecutive identical lines.
  # No `sed -i` (BSD vs GNU differ) — pipe to a PID-scoped temp under TMP_DIR.
  CLEAN_TMP="$TMP_DIR/clean.$$.txt"
  sed -E -e '/^\[.*\]$/d' -e '/^\*(music|laughter|applause)\*$/Id' "$OUTDIR/transcript.txt" \
    | awk 'NF && $0 != last { print; last=$0 }' > "$CLEAN_TMP" \
    && mv "$CLEAN_TMP" "$OUTDIR/transcript.txt"
fi

# Structured segments (inspired by x-studio: timestamp, speaker, text)
if [ -f "$OUTDIR/transcript.json" ] && command -v node >/dev/null; then
  node -e '
    const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const out = (d.segments || []).map(s => ({timestamp: String(s.start), speaker: null, text: s.text}));
    process.stdout.write(JSON.stringify(out, null, 2));
  ' "$OUTDIR/transcript.json" > "$OUTDIR/segments.json" 2>/dev/null || true
fi

# --- frame backend selection ------------------------------------------------
# local (default): ffmpeg seeks each timestamp locally — instant, free.
# mux: upload the video to Mux, pull thumbnails at each timestamp from
# image.mux.com. Only worth it when you have no local ffmpeg; for a local file
# it's slower (async upload + processing). Degrades to local if creds/setup fail.
# The asset is deleted on exit (mux_cleanup) — Mux public playback means anyone
# with the id can fetch the video, so it must not outlive the run.
mux_prepare() {  # $1=video → echoes "<playback-id> <asset-id>", or nothing on failure
  local auth="$MUX_TOKEN_ID:$MUX_TOKEN_SECRET" up asset pid resp aid
  up=$(curl -sS --fail -u "$auth" https://api.mux.com/video/v1/uploads \
        -H "Content-Type: application/json" \
        -d '{"cors_origin":"*","new_asset_settings":{"playback_policy":["public"]}}' 2>/dev/null) || return 1
  local url id
  url=$(printf '%s' "$up" | node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8"));process.stdout.write(d.data?.url||"")') || return 1
  id=$(printf '%s' "$up" | node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8"));process.stdout.write(d.data?.id||"")') || return 1
  [ -n "$url" ] || return 1
  curl -sS --fail -X PUT -H "Content-Type: video/mp4" --data-binary @"$1" "$url" >/dev/null 2>&1 || return 1
  # poll upload → asset_id, then asset → ready + playback id (cap ~5 min)
  for _ in $(seq 1 60); do
    resp=$(curl -sS -u "$auth" "https://api.mux.com/video/v1/uploads/$id" 2>/dev/null)
    aid=$(printf '%s' "$resp" | node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8"));process.stdout.write(d.data?.asset_id||"")' 2>/dev/null)
    [ -n "$aid" ] && break
    sleep 5
  done
  [ -n "$aid" ] || return 1
  for _ in $(seq 1 60); do
    resp=$(curl -sS -u "$auth" "https://api.mux.com/video/v1/assets/$aid" 2>/dev/null)
    pid=$(printf '%s' "$resp" | node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8"));const a=d.data||{};process.stdout.write(a.status==="ready"?(a.playback_ids?.[0]?.id||""):"")' 2>/dev/null)
    [ -n "$pid" ] && break
    sleep 5
  done
  # Always report the asset id, even if the readiness poll timed out — an asset
  # that exists must be deletable, or a public copy is stranded on Mux forever.
  printf '%s:%s' "$pid" "$aid"
  [ -n "$pid" ]   # exit status = did we get a usable playback id
}

# Mux assets are created with public playback (image.mux.com needs it — signed
# playback would require a signing key + a JWT per thumbnail). So the asset is
# deleted as soon as frames are pulled, and on any exit path in between.
MUX_ASSET_ID=""
mux_cleanup() {
  [ -n "$MUX_ASSET_ID" ] || return 0
  local aid="$MUX_ASSET_ID"; MUX_ASSET_ID=""   # clear first: never delete twice
  echo ">> deleting Mux asset $aid…"
  curl -sS --fail -X DELETE -u "$MUX_TOKEN_ID:$MUX_TOKEN_SECRET" \
    "https://api.mux.com/video/v1/assets/$aid" >/dev/null 2>&1 \
    || echo "warning: could not delete Mux asset $aid — it is PUBLIC; remove it at dashboard.mux.com" >&2
}
trap mux_cleanup EXIT

# FRAME_EFFECTIVE was resolved in preflight (mux→local if creds absent). If it's
# still mux, prepare the asset; on failure, fall back to local ffmpeg (which
# preflight only guaranteed present when NEED_FFMPEG=1).
FRAME_MODE="$FRAME_EFFECTIVE"
MUX_PID=""
if [ "$FRAME_MODE" = "mux" ]; then
  echo ">> Mux frames: uploading + processing asset (this can take a while)…"
  # mux_prepare runs in a subshell, so it reports "<playback-id>:<asset-id>" on
  # stdout rather than setting MUX_ASSET_ID directly. Record the asset id even
  # when the playback id is empty, so cleanup can still delete a stranded asset.
  MUX_OUT=$(mux_prepare "$VIDEO" || true)
  MUX_PID="${MUX_OUT%%:*}"
  MUX_ASSET_ID="${MUX_OUT#*:}"
  [ "$MUX_OUT" = "$MUX_ASSET_ID" ] && MUX_ASSET_ID=""   # no ':' → nothing to clean
  if [ -z "$MUX_PID" ]; then
    if command -v ffmpeg >/dev/null; then
      echo ">> Mux setup failed — falling back to local ffmpeg frames"; FRAME_MODE="local"
    else
      echo "error: Mux frame setup failed and no local ffmpeg to fall back to → check MUX creds, or install ffmpeg" >&2; exit 1
    fi
  fi
fi

# --- frames at fixed interval, timestamp-named ------------------------------
# Seek to each exact timestamp so the filename always matches the true frame
# time (ffmpeg's fps=1/N filter drifts on short/low-fps clips and would lie).
# Supports fractional seconds (e.g. 0.5 for 500ms). Filename encodes timestamp.
echo ">> extracting frames every ${INTERVAL}s (${FRAME_MODE})…"

# duration_sec is a JSON number, so DUR must be numeric. The xAI path takes it
# from the API response, which may be absent or non-numeric — fall back to 0
# rather than emitting a manifest that won't parse.
case "$DUR" in
  ''|*[!0-9.]*|*.*.*) DUR_JSON=0 ;;
  *) DUR_JSON="$DUR" ;;
esac

{
  echo '{'
  echo "  \"video\": \"$VIDEO\","
  echo "  \"duration_sec\": ${DUR_JSON},"
  echo "  \"source_fps\": \"$FPS\","
  echo "  \"interval_sec\": $INTERVAL,"
  echo '  "frames": ['
} > "$OUTDIR/manifest.json"

n=0; first=1; t=0
dur=${DUR:-0}
while true; do
  # Build label: tMMmSSs.jpg for whole seconds, tMMmSSsMMMms.jpg for sub-second
  label=$(awk -v t="$t" '
    BEGIN {
      tot = t + 0;
      min = int(tot / 60);
      sec = int(tot % 60);
      ms = int( (tot - int(tot)) * 1000 + 0.5 );
      if (ms == 0) {
        printf "%02dm%02ds", min, sec;
      } else {
        printf "%02dm%02ds%03dms", min, sec, ms;
      }
    }')
  fpath="$OUTDIR/frames/t${label}.jpg"
  # A missing frame is normal (the last sample can land exactly at the end of the
  # video), so every step here must stay zero-status under `set -e` — an
  # unguarded failure would kill the run before manifest.json is closed.
  grabbed=0
  if [ "$FRAME_MODE" = "mux" ]; then
    # Pull a JPEG at time=$t from the Mux thumbnail service.
    code=$(curl -sS -o "$fpath" -w '%{http_code}' "https://image.mux.com/${MUX_PID}/thumbnail.jpg?time=${t}&width=1280" 2>/dev/null || echo 000)
    if [ "$code" = "200" ] && [ -s "$fpath" ]; then grabbed=1; fi
  else
    ffmpeg -y -v error -ss "$t" -i "$VIDEO" -frames:v 1 -q:v "$FRAME_QUALITY" "$fpath" 2>/dev/null || true
    if [ -s "$fpath" ]; then grabbed=1; fi
  fi
  [ "$grabbed" = "1" ] || rm -f "$fpath"   # don't leave a 0-byte frame behind
  if [ "$grabbed" = "1" ]; then
    [ $first -eq 1 ] && first=0 || echo ',' >> "$OUTDIR/manifest.json"
    printf '    {"file": "frames/t%s.jpg", "t_sec": %s}' "$label" "$t" >> "$OUTDIR/manifest.json"
    n=$((n+1))
  fi
  # next timestamp (float)
  t=$(awk -v t="$t" -v i="$INTERVAL" 'BEGIN { printf "%.3f", t + i }')
  if [ "$dur" = "0" ] || awk -v t="$t" -v d="$dur" 'BEGIN { exit (t > d + 0.001) ? 0 : 1 }'; then
    break
  fi
done
printf '\n  ]\n}\n' >> "$OUTDIR/manifest.json"
echo ">> $n frames written to $OUTDIR/frames/"

# Frames are local now — drop the public Mux copy immediately (the EXIT trap is
# only a backstop for the paths that never get here).
mux_cleanup

# --- agent handoff ----------------------------------------------------------
cat > "$OUTDIR/AGENT.md" <<'EOF'
# Agent task: understand this video

Stage 1 (extraction) is done. Now YOU do stage 2.

## Inputs in this folder
- `frames/tNNmNNs.jpg` (or `tNNmNNsNNNms.jpg` for sub-second) — one frame per sampling interval; the filename IS its
  timestamp (e.g. `t01m30s.jpg` = 1:30, `t01m30s500ms.jpg` = 1:30.500 into the video).
- `transcript.srt` — timestamped captions (what was said, when).
- `transcript.txt` — same words, plain.
- `segments.json` — structured segments (timestamp, speaker, text) if available.
- `manifest.json` — frame→timestamp map, duration, interval.

## What to do
1. Read `transcript.srt` end to end.
2. Read EVERY frame in `frames/` in timestamp order (the Read tool shows images).
3. For each frame, correlate what's ON SCREEN with what's BEING SAID at that
   timestamp. Note text/UI/slides/people/scene visible in the frame.
4. Watch for: scene/topic changes, on-screen text the audio doesn't mention,
   demos/actions shown, anything the transcript alone would miss.
5. Use `segments.json` for clean speaker/timestamp data if present.

## Output: write `understanding.md` in this folder with
- **Summary** — 2–4 sentences: what the video is and its purpose.
- **Timeline** — table: `time | on-screen | spoken/topic`, one row per notable
  beat (group frames where nothing changes).
- **Key visuals** — important text, diagrams, UI, faces, or moments and when.
- **Full takeaways** — the complete understanding: claims, steps, conclusions,
  anything actionable.
- **Corrected transcript** — only if frames reveal the audio transcription got
  a name/term/number wrong; list the fixes.
EOF

echo ""
echo "== done =="
echo "Extraction complete → $OUTDIR/"
echo "Next: point your agent at $OUTDIR/AGENT.md to produce understanding.md"
