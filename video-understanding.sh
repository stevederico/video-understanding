#!/usr/bin/env bash
# video-understanding — watch a video like a critic: extract frames + a timestamped SRT
# transcript, then hand off to an AI agent to review frames against the
# transcript and write a full understanding of the video.
#
# Supports local video files or X (Twitter) posts (via direct CDN URL or agent-provided).
# For X: downloads with curl, then extracts frames + transcript like local.
#
# Stage 1 (this script): mechanical extraction. Fast, deterministic, no AI.
# Stage 2 (the agent):    reads frames + SRT, writes understanding.md.
#
# Usage:
#   video-understanding.sh <video-or-x-url> [interval_seconds] [output_dir] [--video <direct-mp4>] [--name <slug>]
#
# Examples:
#   ./video-understanding.sh ~/Movies/demo.mov 5
#   ./video-understanding.sh https://x.com/user/status/1234567890 --video https://video.twimg.com/...mp4
#
# STT is local whisper.cpp: whisper-cli must be on PATH and a matching ggml
# model present (see README for the one-time build + model download).
#
# Env overrides:
#   VU_MODEL        default: large-v3-turbo (needs ggml-<VU_MODEL>.bin)
#   WHISPER_MODEL   explicit model path (default ~/.local/opt/whisper.cpp/models/ggml-<VU_MODEL>.bin)
#   VU_LANG         default: auto-detect (set e.g. en to skip detection)
#   FRAME_QUALITY   ffmpeg -q:v for JPEGs, 2(best)-31(worst), default 3
#
# Output tree (in <output_dir>):
#   frames/t00m05s.jpg ...   one JPEG every <interval> seconds, timestamp-named
#   transcript.srt           timestamped captions
#   transcript.txt           plain transcript
#   transcript.json          word/segment data
#   manifest.json            duration, fps, interval, frame->timestamp map
#   AGENT.md                 instructions for the agent (stage 2)

set -euo pipefail

VIDEO="${1:-}"
INTERVAL="${2:-5}"
OUTDIR="${3:-}"

# Parse all args
XREF=""
VIDEO_URL=""
SLUG=""
shift $(( $# > 0 ? 1 : 0 )) 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat <<EOF
video-understanding - Official CLI for video analysis with AI

Usage:
  video-understanding <video-or-x-url> [interval] [outdir] [options]

Options:
  --video <mp4-url>   Direct video URL (for X posts, get from post metadata)
  --name <slug>       Slug for output (default from file or post ID)
  -h, --help          Show this help

Examples:
  ./video-understanding.sh demo.mov 5
  ./video-understanding.sh https://x.com/user/status/123 --video https://video.twimg.com/...mp4 --name my-post

Does everything: X sourcing (with agent or --video), download, frames + transcript, agent setup.
Better than x-transcribe: full frames + understanding pipeline, unified CLI.
EOF
      exit 0
      ;;
    --video) VIDEO_URL="$2"; shift 2 ;;
    --name)  SLUG="$2"; shift 2 ;;
    *)       echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$VIDEO" ]]; then
  echo "Error: video or X URL required" >&2
  echo "See --help" >&2
  exit 1
fi

MODEL="${VU_MODEL:-large-v3-turbo}"
WMODEL="${WHISPER_MODEL:-$HOME/.local/opt/whisper.cpp/models/ggml-${MODEL}.bin}"
QUALITY="${FRAME_QUALITY:-3}"

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
    OUTDIR="${SLUG}_understand"
  fi
  VIDEO_FILE="/tmp/${SLUG}.mp4"
  if [[ -n "$VIDEO_URL" && ! -f "$VIDEO_FILE" ]]; then
    echo ">> Downloading X video..."
    curl -L --progress-bar -o "$VIDEO_FILE" "$VIDEO_URL"
  fi
  if [[ ! -f "$VIDEO_FILE" ]]; then
    echo "No video file. Provide --video <direct twimg mp4 url> for X post." >&2
    exit 1
  fi
  VIDEO="$VIDEO_FILE"
else
  if [[ -z "$OUTDIR" ]]; then
    OUTDIR="${VIDEO%.*}_understand"
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
command -v ffmpeg  >/dev/null || { echo "error: ffmpeg not found → $(need_ffmpeg_hint)" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "error: ffprobe not found → $(need_ffmpeg_hint)" >&2; exit 1; }
command -v whisper-cli >/dev/null || { echo "error: whisper-cli not on PATH — build whisper.cpp (see README)" >&2; exit 1; }
[ -f "$WMODEL" ] || { echo "error: model not found: $WMODEL → ~/.local/opt/whisper.cpp/models/download-ggml-model.sh ${MODEL}" >&2; exit 1; }
[ -f "$VIDEO" ] || { echo "error: no such file: $VIDEO" >&2; exit 1; }

mkdir -p "$OUTDIR/frames"

# --- probe -----------------------------------------------------------------
DUR=$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$VIDEO" | cut -d. -f1)
FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nk=1:nw=1 "$VIDEO" | head -1)
echo ">> $VIDEO"
echo ">> duration ${DUR}s | source fps ${FPS} | sampling every ${INTERVAL}s"

# --- audio + transcription --------------------------------------------------
# Audio is named transcript.wav so engines that name outputs after the input
# basename produce transcript.srt / .txt / .json directly.
echo ">> extracting audio…"
ffmpeg -y -v error -i "$VIDEO" -ac 1 -ar 16000 -vn "$OUTDIR/transcript.wav"

echo ">> transcribing with whisper.cpp (model=$MODEL)…"
# DTW word-level alignment for accurate timestamps; preset = model name with
# '-' → '.' (large-v3-turbo → large.v3.turbo). -ml 60 -sow = readable phrase cues.
DTW_PRESET="${DTW_PRESET:-${MODEL//-/.}}"
LANG_ARG=(); [ -n "${VU_LANG:-}" ] && LANG_ARG=(--language "$VU_LANG")
whisper-cli -m "$WMODEL" -f "$OUTDIR/transcript.wav" \
  -of "$OUTDIR/transcript" -osrt -otxt -oj \
  -dtw "$DTW_PRESET" -ml 60 -sow ${LANG_ARG[@]+"${LANG_ARG[@]}"}
rm -f "$OUTDIR/transcript.wav"

# --- frames at fixed interval, timestamp-named ------------------------------
# Seek to each exact timestamp so the filename always matches the true frame
# time (ffmpeg's fps=1/N filter drifts on short/low-fps clips and would lie).
echo ">> extracting frames every ${INTERVAL}s…"

{
  echo '{'
  echo "  \"video\": \"$VIDEO\","
  echo "  \"duration_sec\": ${DUR:-0},"
  echo "  \"source_fps\": \"$FPS\","
  echo "  \"interval_sec\": $INTERVAL,"
  echo '  "frames": ['
} > "$OUTDIR/manifest.json"

n=0; first=1; t=0
while [ "$t" -lt "${DUR:-0}" ] || [ "$t" -eq 0 ]; do
  printf -v label '%02dm%02ds' $((t/60)) $((t%60))
  # -ss before -i = fast keyframe seek; accurate enough at whole-second steps
  if ffmpeg -y -v error -ss "$t" -i "$VIDEO" -frames:v 1 -q:v "$QUALITY" \
       "$OUTDIR/frames/t${label}.jpg" 2>/dev/null && [ -s "$OUTDIR/frames/t${label}.jpg" ]; then
    [ $first -eq 1 ] && first=0 || echo ',' >> "$OUTDIR/manifest.json"
    printf '    {"file": "frames/t%s.jpg", "t_sec": %d}' "$label" "$t" >> "$OUTDIR/manifest.json"
    n=$((n+1))
  fi
  t=$(( t + INTERVAL ))
  [ "${DUR:-0}" -eq 0 ] && break
done
printf '\n  ]\n}\n' >> "$OUTDIR/manifest.json"
echo ">> $n frames written to $OUTDIR/frames/"

# --- agent handoff ----------------------------------------------------------
cat > "$OUTDIR/AGENT.md" <<'EOF'
# Agent task: understand this video

Stage 1 (extraction) is done. Now YOU do stage 2.

## Inputs in this folder
- `frames/tNNmNNs.jpg` — one frame per sampling interval; the filename IS its
  timestamp (e.g. `t01m30s.jpg` = 1:30 into the video).
- `transcript.srt` — timestamped captions (what was said, when).
- `transcript.txt` — same words, plain.
- `manifest.json` — frame→timestamp map, duration, interval.

## What to do
1. Read `transcript.srt` end to end.
2. Read EVERY frame in `frames/` in timestamp order (the Read tool shows images).
3. For each frame, correlate what's ON SCREEN with what's BEING SAID at that
   timestamp. Note text/UI/slides/people/scene visible in the frame.
4. Watch for: scene/topic changes, on-screen text the audio doesn't mention,
   demos/actions shown, anything the transcript alone would miss.

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
