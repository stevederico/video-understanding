---
name: video-understanding
description: >
  Turn any video (local file or from X) into a full AI understanding: use video-understanding.sh for frames + transcript, then review as agent to produce understanding.md. Supports sourcing videos from X via search or direct link using safe curl download + local whisper. Use when user runs /video-understanding, or says "video understand this X post", "process this video with full understanding", "get frames and transcript then analyze".
---

# video-understanding

Full pipeline for turning videos into agent-understandable output: timestamped frames + SRT transcript, followed by agent review that correlates visuals with speech and writes a complete `understanding.md`.

This skill combines video sourcing (including from X), mechanical extraction, and the agent analysis stage. It is generic for any video content.

## Configuration
Use `VU_PROFILE=local` (default, fully local whisper + xurl + curl) or `grok` (future cloud steps).
Profiles: config/profiles/<name>.sh
Env vars override the chosen profile.
See config/profiles/local.sh for the current local-focused setup.

## Core rules
- Use only local tools: ffmpeg + whisper.cpp (whisper-cli). No cloud APIs.
- For X videos: always use direct CDN download with `curl -L` from video.twimg.com. Never yt-dlp or YouTube links.
- Use the project's `video-understanding.sh` for stage 1 (frames + transcript).
- Follow the generated `AGENT.md` exactly for stage 2.
- Output goes to `<video>_understand/` (or custom dir). The agent then works inside that folder.
- Respect existing local whisper setup (no unauthorized `brew install`).

## Sourcing videos (especially from X)
- **Direct X link or post ID**: Pass to CLI.
  - local: defaults to xurl read to resolve video URL then curl.
  - grok: Grok's built-in X tools ("grok cli") find the post & interact with X, providing video URLs (CLI uses --direct or skill supplies).
- Use `--direct <mp4-url>` for manual CDN (bypass resolver).
- Search X: agent X tools find post, pass URL/ID to CLI.
- CLI handles download:
  ```bash
  ./video-understanding.sh https://x.com/.../status/123
  # manual CDN
  ./video-understanding.sh https://x.com/.../status/123 --direct https://video.twimg.com/...mp4
  ```
- Non-X: local path.

Config: `VU_PROFILE=local` (xurl) or `grok` (Grok's X tools). See config/profiles/. Env overrides.

## Stage 1: Mechanical extraction
Run the project script on the (downloaded or local) video:

```bash
./video-understanding.sh /path/to/video.mp4 [interval_seconds] [output_dir]
```

- Default interval: 5s
- Outputs: `frames/tNNmNNs.jpg` (timestamped filenames), `transcript.srt`, `transcript.txt`, `transcript.json`, `manifest.json`, `AGENT.md`
- Env: `VU_MODEL=large-v3-turbo`, `WHISPER_MODEL=...` etc. as documented in README.

X videos are handled directly by the main `./video-understanding.sh` script (xurl default for resolving CDN URL; use --direct to provide manually).

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
2. Agent: fetch post with X tools → extract video URL → curl download to /tmp/video.mp4
3. Agent: `./video-understanding.sh /tmp/video.mp4 5 /tmp/myvideo_understand`
4. Agent: read the generated AGENT.md in /tmp/myvideo_understand/ and produce understanding.md
5. Output the summary or full understanding.md to user.

The tool works for any video content. Use it to deeply analyze talks, demos, interviews, etc. from X or local files.

## Tips
- For X videos, prefer the CDN curl method shown above.
- Adjust interval: smaller (2-3s) for fast cuts, larger (10s+) for slow talking-head.
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
- Grok profile: placeholder for future cloud steps (e.g. Grok vision or enrichment) while keeping local fallbacks.
- Override any var via env (takes precedence over profile).
- Keeps everything portable for any agent.
