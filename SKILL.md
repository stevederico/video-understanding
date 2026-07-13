---
name: video-understanding
description: >
  Turn any video (local file or from X) into a full AI understanding: use video-understanding.sh for frames + transcript, then review as agent to produce understanding.md. Supports sourcing videos from X via search or direct link using safe curl download + local whisper. Use when user runs /video-understanding, or says "video understand this X post", "process this video with full understanding", "get frames and transcript then analyze".
---

# video-understanding

Full pipeline for turning videos into agent-understandable output: timestamped frames + SRT transcript, followed by agent review that correlates visuals with speech and writes a complete `understanding.md`.

This skill combines video sourcing (including from X), mechanical extraction, and the agent analysis stage. It is generic for any video content.

## Configuration
Use `VU_PROFILE=local` (default, fully local whisper + xurl + curl) or `grok` (agent supplies video URL via its X tools).
Default frame interval: 500ms (use --interval 500ms / 0.5 / 2 etc).
Profiles: config/profiles/<name>.sh
Env vars / --interval override.
See config/profiles/local.sh for the current local-focused setup.

## Core rules
- Use only local tools: ffmpeg + whisper.cpp (whisper-cli). No cloud APIs.
- For X videos: always use direct CDN download with `curl -L` from video.twimg.com. Never yt-dlp or YouTube links.
- Use `video-understanding` (the CLI on PATH, or ~/.agents/.../video-understanding.sh) for stage 1; supports --interval 500ms etc.
- Follow the generated `AGENT.md` exactly for stage 2.
- Output goes to `<video>_understand/` (or custom dir). The agent then works inside that folder.
- If `whisper-cli`, `ffmpeg`, or `jq` is missing, auto-install before stage 1 (see Setup below) — don't ask, just bootstrap. `xurl` is optional (X-by-URL only) and needs auth; prefer `--direct` if it's absent.

## Setup (auto-install deps)
Before stage 1, ensure the toolchain exists. Bootstrap what's missing — don't ask:

```bash
# Core: whisper-cli + ffmpeg + model (builds whisper.cpp Metal, symlinks to ~/.local/bin)
if ! command -v whisper-cli >/dev/null || ! command -v ffmpeg >/dev/null; then
  DIR="$HOME/.local/opt/ask-transcribe-cli"
  [ -d "$DIR" ] || git clone https://github.com/stevederico/ask-transcribe-cli.git "$DIR"
  ( cd "$DIR" && bash install-stt.sh )
fi
# jq: required to parse xurl JSON AND to emit segments.json. Cheap, install it.
command -v jq >/dev/null || brew install jq
```

macOS Apple Silicon. `install-stt.sh` needs `cmake`/`ffmpeg` (Homebrew) + `git`/`clang` (Xcode CLT); it prints the `brew install` line if a build dep is missing. Ensure `~/.local/bin` is on `PATH`.

### X-by-URL needs xurl (optional)
`xurl` (xAI's X API CLI) resolves a post's video URL. It is **not** auto-installed and needs X API credentials in `~/.xurl` — so it can't be fully hands-off. When resolving an X URL:
- **Preferred (no xurl needed):** if you (the agent) have your own X tools, fetch the post and pass the mp4 with `--direct <url>`, or run the `grok` profile.
- **Local profile with xurl:** requires `xurl` on PATH **and** `jq`. If either is missing, fall back to `--direct`. Install: [`github.com/xdevplatform/xurl`](https://github.com/xdevplatform/xurl) (Go binary), then `xurl auth` with X API keys.
- Local video files and `--direct` never touch xurl or jq's X path.

## Sourcing videos (especially from X)
- **Direct X link or post ID**: Pass to CLI.
  - local: defaults to xurl read to resolve video URL then curl.
  - grok: Grok's built-in X tools ("grok cli") find the post & interact with X, providing video URLs (CLI uses --direct or skill supplies).
- Use `--direct <mp4-url>` for manual CDN (bypass resolver).
- Search X: agent X tools find post, pass URL/ID to CLI.
- CLI handles download:
  ```bash
  video-understanding https://x.com/.../status/123
  # manual CDN or force re-download
  video-understanding https://x.com/.../status/123 --direct https://video.twimg.com/...mp4 --force --interval 500ms
  VU_PROFILE=local video-understanding https://... --name post
  ```
- Non-X: local path.

Config: `VU_PROFILE=local` (xurl) or `grok` (Grok's X tools supply --direct). See config/profiles/. Env overrides.

## Stage 1: Mechanical extraction
Run the project script on the (downloaded or local) video:

```bash
video-understanding /path/to/video.mp4 [interval] [output_dir] [--interval <val>]
# default 500ms. e.g. --interval 500ms or --interval 2
```

- Default interval: 500ms (override via --interval, DEFAULT_INTERVAL in profile/env/positional; accepts 500ms, 0.5 etc)
- Outputs: `frames/tNNmNNs.jpg` (or ...sNNNms.jpg for subsec), `transcript.srt`, `transcript.txt`, `transcript.json`, `manifest.json`, `AGENT.md`
- Env: `VU_MODEL=large-v3-turbo`, `WHISPER_MODEL=...` etc. as documented in README.

X videos are handled directly by the main `video-understanding` (or full path to script); use --interval 500ms etc. (xurl default for resolving CDN URL; use --direct to provide manually).

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
1. User: "video understand this X post: https://x.com/.../status/123"
2. Agent: fetch post with X tools → decide profile + extract or supply video URL
3. Agent: `VU_PROFILE=local video-understanding https://x.com/.../123 --name mypost --force --interval 500ms`  (or --direct for grok profile)
4. Agent: read the generated AGENT.md in `mypost_understand/` (or custom suffix) and produce understanding.md
5. Output the summary or full understanding.md to user.

The tool works for any video content. Use it to deeply analyze talks, demos, interviews, etc. from X or local files.

## Tips
- For X videos, prefer the CDN curl method shown above.
- Adjust interval: --interval 500ms (or 0.5) for fast cuts/action, 1-3s for typical, larger (5s+) for slow talking-head.
- After extraction, the agent works entirely from the output folder files.
- All local and deterministic for stage 1.

## Transcript quality (adopted from x-studio patterns)
- Script now applies post-processing: removes non-speech markers, simple repetitions.
- Outputs `segments.json` with structured {timestamp, speaker, text} for better agent input.
- Whisper tuned with DTW, no-speech-thold 0.68, logprob -0.9, VAD if available.
- For X: videos cached in ~/.cache/video-understanding/x-videos (resume/skip re-download).

## Config profiles
- Source with `VU_PROFILE=local` (default) or `grok`.
- Profiles live in `config/profiles/<name>.sh`
- Local profile: fully local whisper + xurl + curl.
- Grok profile: agent uses native X tools + passes URL with --direct; extraction (ffmpeg/whisper) is always local.
- Profiles also control DEFAULT_INTERVAL and DEFAULT_OUTDIR_SUFFIX (default 500ms).
- Override via --interval, env (DEFAULT_INTERVAL=500ms), or positional. Env takes precedence.
- Keeps everything portable for any agent.
