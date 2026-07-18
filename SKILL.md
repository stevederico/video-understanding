---
name: video-understanding
author: stevederico
skills-sh: later
description: >
  Turn a video file into a full AI understanding: use video-understanding.sh for frames + transcript, then review as agent to produce understanding.md. Local ffmpeg + whisper. Use when user runs /video-understanding, or says "process this video with full understanding", "get frames and transcript then analyze".
allowed-tools: Bash(video-understanding:*), Bash(*video-understanding/video-understanding.sh*), Bash(ffmpeg:*), Bash(whisper-cli:*), Bash(ffprobe:*), Read, Write, Edit, Glob, Grep
metadata:
  version: "1.1.0"
---

# video-understanding

Full pipeline for turning videos into agent-understandable output: timestamped frames + SRT transcript, followed by agent review that correlates visuals with speech and writes a complete `understanding.md`.

Stage 1 is mechanical extraction. Stage 2 is the agent analysis. Generic for any video content.

**Skill root:** `~/.agents/skills/video-understanding/` (also linked as Claude skills via `~/.agents/skills`).

## Prerequisites (local STT + ffmpeg)

Stage 1 needs **ffmpeg** + **whisper.cpp (`whisper-cli`)** + a ggml model.

Install / repair the local stack with **[local-ai-cli](https://github.com/stevederico/local-ai-cli)** (builds whisper.cpp + models, puts tools on PATH):

```bash
git clone https://github.com/stevederico/local-ai-cli.git && cd local-ai-cli && bash setup.sh
# ensures whisper-cli, ffmpeg (via brew), model under ~/.local/opt/whisper.cpp/
```

Do not freestyle alternate whisper installs unless the user asks — use local-ai-cli as the source of truth.

## Optional: BYOK mode (install-free)

The CLI also supports `VU_PROFILE=byok` (xAI STT + optional Mux frames) when keys are set — see repo README. Stage-1 extraction script still implements this; prefer **local** + local-ai-cli unless the user asks for BYOK.


## Configuration
Use `VU_PROFILE=local` (default, fully local whisper) or `grok`.
Default frame interval: 500ms (use --interval 500ms / 0.5 / 2 etc).
Profiles: `~/.agents/skills/video-understanding/config/profiles/<name>.sh` (or use the `video-understanding` command on PATH)
Use --interval <val> or DEFAULT_INTERVAL. Env/flag override.
See `config/profiles/local.sh` for the current local-focused setup.

## Core rules
- Prefer local extraction: ffmpeg + whisper.cpp (`whisper-cli`).
- Never yt-dlp or YouTube links.
- Use `video-understanding` (on PATH → skill `video-understanding.sh`) for stage 1 (supports --interval 500ms etc).
  Explicit path: `~/.agents/skills/video-understanding/video-understanding.sh`
- Follow the generated `AGENT.md` exactly for stage 2.
- Output goes to `<video>_understand/` (or custom dir). The agent then works inside that folder.

## Stage 1: Mechanical extraction
Run the script on a local video file:

```bash
video-understanding /path/to/video.mp4 [interval] [output_dir] [--interval <val>]
# default 500ms. e.g. --interval 500ms or --interval 2
```

- Default interval: 500ms (override via --interval, DEFAULT_INTERVAL in profile/env/positional; accepts 500ms, 0.5 etc)
- Outputs: `frames/tNNmNNs.jpg` (or ...sNNNms.jpg for subsec), `transcript.srt`, `transcript.txt`, `transcript.json`, `manifest.json`, `AGENT.md`
- Env: `VU_MODEL=large-v3-turbo`, `WHISPER_MODEL=...` etc.

## Stage 2: Agent review
After the script runs, point to the output folder:

"read `<output>/AGENT.md` and do it."

The AGENT.md instructs:
- Read transcript.srt fully.
- Read every frame image in order (filenames = timestamps).
- Correlate on-screen content (text, UI, visuals, actions) with spoken words at each time.
- Note scene changes, on-screen text not in audio, key demos, etc.
- Write `understanding.md` with:
  - Summary
  - Timeline table (time | on-screen | spoken)
  - Key visuals
  - Full takeaways
  - Corrected transcript (if frames reveal the audio transcription got a name/term/number wrong; list the fixes).

## Full example flow
1. User: "video understand this: ~/Movies/talk.mov"
2. Agent: `video-understanding ~/Movies/talk.mov --name talk --interval 500ms`
3. Agent: read the generated AGENT.md in `talk_understand/` (or custom suffix) and produce understanding.md
4. Output the summary or full understanding.md to user.

The tool works for any video content. Use it to deeply analyze talks, demos, interviews, etc.

## Tips
- Adjust interval: --interval 500ms (or 0.5) for fast cuts/action, 1-3s for typical, larger (5s+) for slow talking-head.
- After extraction, the agent works entirely from the output folder files.
- Stage 1 is deterministic given the same model + inputs.

## Transcript quality (adopted from x-studio patterns)
- Script now applies post-processing: removes non-speech markers, simple repetitions.
- Outputs `segments.json` with structured {timestamp, speaker, text} for better agent input.
- Whisper tuned with DTW, no-speech-thold 0.68, logprob -0.9, VAD if available.

## Config profiles
- Source with `VU_PROFILE=local` (default) or `grok`.
- Profiles live in `~/.agents/skills/video-understanding/config/profiles/<name>.sh`
- Local profile: fully local whisper via local-ai-cli / whisper.cpp.
- Grok profile: same local extraction; agent may resolve X/media differently.
- Profiles also control DEFAULT_INTERVAL and DEFAULT_OUTDIR_SUFFIX (default 500ms).
- Override via --interval, env (DEFAULT_INTERVAL=500ms), or positional. Env takes precedence.
