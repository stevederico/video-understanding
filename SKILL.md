---
name: video-understanding
description: >
  Turn a video into a complete AI understanding: extract timestamped frames + a transcript, then correlate what's on screen with what's said into an understanding.md. Runs fully local (whisper.cpp + ffmpeg, no keys) or install-free via BYOK (xAI STT + Mux). Use when the user says "video understand this", "analyze this video", or runs /video-understanding.
---

# video-understanding

Full pipeline for turning videos into agent-understandable output: timestamped frames + SRT transcript, followed by agent review that correlates visuals with speech and writes a complete `understanding.md`.

Stage 1 is mechanical extraction. Stage 2 is the agent analysis. Generic for any video content.

## Configuration
Modes: `VU_PROFILE=local` (default — whisper.cpp + ffmpeg, no keys), `byok` (xAI STT via `XAI_API_KEY` + Mux frames, falls back to local ffmpeg if no Mux creds), or `grok` (agent supplies the video URL via `--direct`). local and byok produce identical output files.
Default frame interval: 500ms (use --interval 500ms / 0.5 / 2 etc).
Profiles: config/profiles/<name>.sh
Env vars / --interval override.
See config/profiles/local.sh for the current local-focused setup.

## Core rules
- Two modes: **local** (whisper.cpp + ffmpeg, offline, no keys — the default) or **byok** (`VU_PROFILE=byok`: xAI STT + Mux frames, installs nothing, needs `XAI_API_KEY` [+ Mux creds]). Both yield identical output files.
- Inputs: a local video file, or a direct video-file URL. Post links and post IDs are refused — see Sourcing. Never yt-dlp or YouTube links.
- Use `video-understanding` (the CLI on PATH, or the full path to video-understanding.sh) for stage 1; supports --interval 500ms etc.
- Follow the generated `AGENT.md` exactly for stage 2.
- Output goes to `<video>_understand/` (or custom dir). The agent then works inside that folder.
- If `whisper-cli` or `ffmpeg` is missing, auto-install before stage 1 (see Setup below) — don't ask, just bootstrap. `node` (emits `segments.json`) is assumed present; install it if not.

## Setup (auto-install deps)
Before stage 1, ensure the toolchain exists. Bootstrap what's missing — don't ask:

```bash
# Core: whisper-cli + ffmpeg + model (builds whisper.cpp Metal, symlinks to ~/.local/bin)
if ! command -v whisper-cli >/dev/null || ! command -v ffmpeg >/dev/null; then
  DIR="$HOME/.local/opt/ask-transcribe-cli"
  [ -d "$DIR" ] || git clone https://github.com/stevederico/ask-transcribe-cli.git "$DIR"
  ( cd "$DIR" && bash install-stt.sh )
fi
# node: emits segments.json (no jq dep). Usually already present.
command -v node >/dev/null || brew install node
```

macOS Apple Silicon. `install-stt.sh` needs `cmake`/`ffmpeg` (Homebrew) + `git`/`clang` (Xcode CLT); it prints the `brew install` line if a build dep is missing. Ensure `~/.local/bin` is on `PATH`.

## Sourcing videos
The tool analyses a video the user already has. It does not pull video out of social posts, and passing a post link (`x.com/…/status/…`) or a bare post ID is refused by design.

Downloading a post's video is generally restricted by the platform's terms of service — X's don't permit it. So obtaining the file is the user's call: their own upload, an export the platform offers them, or the rights holder's permission. Then pass the file.

Do not work around this by resolving a post to its CDN URL with your own tools and feeding it to `--direct`. If a user asks for an X post to be analysed, say the tool takes a file and ask them to supply one.

```bash
video-understanding ~/clip.mov                                    # local file
video-understanding https://example.com/talk.mp4 --name talk      # direct file URL
```

Config: `VU_PROFILE=local` (default), `byok` (xAI STT + Mux, install-free), or `grok`. See config/profiles/. Env overrides.

## Stage 1: Mechanical extraction
Run the project script on the video:

```bash
video-understanding /path/to/video.mp4 [interval] [output_dir] [--interval <val>]
# default 500ms. e.g. --interval 500ms or --interval 2
```

- Default interval: 500ms (override via --interval, DEFAULT_INTERVAL in profile/env/positional; accepts 500ms, 0.5 etc)
- Outputs: `frames/tNNmNNs.jpg` (or ...sNNNms.jpg for subsec), `transcript.srt`, `transcript.txt`, `transcript.json`, `segments.json`, `manifest.json`, `AGENT.md`
- Env: `VU_MODEL=large-v3-turbo`, `WHISPER_MODEL=...` etc. as documented in README.

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
- Stage 1 is deterministic (no AI). local mode is fully offline; byok sends the video to xAI/Mux.

## Transcript quality
- Script applies post-processing: removes non-speech markers, simple repetitions.
- Outputs `segments.json` with structured {timestamp, speaker, text} for better agent input.
- Whisper tuned with DTW, no-speech-thold 0.68, logprob -0.9, VAD if available.

## Config profiles
- Source with `VU_PROFILE=local` (default), `byok`, or `grok`.
- Profiles live in `config/profiles/<name>.sh`
- **local**: whisper.cpp + ffmpeg, offline, no keys.
- **byok**: xAI STT + Mux frames (install-free); `XAI_API_KEY` [+ `MUX_TOKEN_ID`/`SECRET`] from env or `.env`. Falls back to local ffmpeg for frames if no Mux creds.
- **grok**: agent passes a direct video URL with --direct; extraction is local.
- Profiles also control DEFAULT_INTERVAL and DEFAULT_OUTDIR_SUFFIX (default 500ms).
- Override via --interval, env (DEFAULT_INTERVAL=500ms), or positional. Env takes precedence.
- Keeps everything portable for any agent.
