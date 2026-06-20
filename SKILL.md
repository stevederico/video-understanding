---
name: video-understanding
description: >
  Turn any video (local file or from X) into a full AI understanding: use video-understanding.sh for frames + transcript, then review as agent to produce understanding.md. Supports sourcing videos from X via search or direct link using safe curl download + local whisper. Use when user runs /video-understanding, or says "video understand this X post", "process this video with full understanding", "get frames and transcript then analyze".
---

# video-understanding

Full pipeline for turning videos into agent-understandable output: timestamped frames + SRT transcript, followed by agent review that correlates visuals with speech and writes a complete `understanding.md`.

This skill combines video sourcing (including from X), mechanical extraction, and the agent analysis stage. It is generic for any video content.

## Core rules
- Use only local tools: ffmpeg + whisper.cpp (whisper-cli). No cloud APIs.
- For X videos: always use direct CDN download with `curl -L` from video.twimg.com. Never yt-dlp or YouTube links.
- Use the project's `video-understanding.sh` for stage 1 (frames + transcript).
- Follow the generated `AGENT.md` exactly for stage 2.
- Output goes to `<video>_understand/` (or custom dir). The agent then works inside that folder.
- Respect existing local whisper setup (no unauthorized `brew install`).

## Sourcing videos (especially from X)
- **Direct X link or post ID**: Use `x_thread_fetch` or `xurl read` to get post data, extract the video media URL (video.twimg.com/...mp4).
- **Search for videos**: Use `x_keyword_search` (add `filter:videos`) or `x_semantic_search` for topics. Then fetch the post and video URL.
- Download safely:
  ```bash
  curl -L --max-time 120 -o /tmp/video.mp4 "https://video.twimg.com/amplify_video/XXXX/vid/avc1/....mp4"
  ```
- For non-X: provide a local path directly to the script.

## Stage 1: Mechanical extraction
Run the project script on the (downloaded or local) video:

```bash
./video-understanding.sh /path/to/video.mp4 [interval_seconds] [output_dir]
```

- Default interval: 5s
- Outputs: `frames/tNNmNNs.jpg` (timestamped filenames), `transcript.srt`, `transcript.txt`, `transcript.json`, `manifest.json`, `AGENT.md`
- Env: `VU_MODEL=large-v3-turbo`, `WHISPER_MODEL=...` etc. as documented in README.

If the video came from X, you may also use `./x-transcribe <x-link> --video <downloaded-mp4>` for a chunked markdown transcript as alternative or supplement.

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
