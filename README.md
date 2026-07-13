# video-understanding

Your agent's movie critic. Turns any video (local file or X post) into something an
AI agent can fully understand: timestamped frames + an SRT transcript, which the
agent then reviews to write a complete `understanding.md`.

Two stages:
1. **`video-understanding.sh`** — mechanical extraction (ffmpeg + local whisper.cpp). No AI, deterministic.
2. **The agent** — reads the frames (filenames are timestamps) + `transcript.srt`, correlates picture↔speech, and writes `understanding.md` following the generated `AGENT.md`.

> **Platform:** built for **macOS Apple Silicon** — one-command setup, Metal-accelerated
> whisper. Linux/Windows work too, but via the manual dependency steps (no turnkey installer).

## Install

As an agent skill (Claude Code, Cursor, etc.):

```sh
npx skills add stevederico/video-understanding
```

Or grab the standalone CLI:

```sh
git clone https://github.com/stevederico/video-understanding.git
cd video-understanding && chmod +x video-understanding.sh
```

Install the dependencies (**ffmpeg** + whisper.cpp's `whisper-cli` + a model). On
macOS Apple Silicon, [`ask-transcribe-cli`](https://github.com/stevederico/ask-transcribe-cli)
does all of it in one command — builds whisper.cpp (Metal), symlinks `whisper-cli`
into `~/.local/bin`, downloads `ggml-large-v3-turbo`, and installs ffmpeg:

```sh
git clone https://github.com/stevederico/ask-transcribe-cli.git && cd ask-transcribe-cli && bash install-stt.sh
```

Make sure `~/.local/bin` is on your `PATH`. **node** is also used (to parse X responses and emit `segments.json`) — it's already on most dev machines; `brew install node` if not.

**For X posts by URL** you also need [`xurl`](https://github.com/xdevplatform/xurl) (xAI's X API CLI) authed with your X API keys — or just skip it and pass the video with `--direct <mp4-url>`. Local files never need xurl.

<details>
<summary>Manual dependency setup (Linux/Windows, or by hand)</summary>

1. **ffmpeg** — `brew install ffmpeg` · `sudo apt install ffmpeg` · [ffmpeg.org](https://ffmpeg.org/download.html)
2. **node** — [nodejs.org](https://nodejs.org) · `brew install node` · `sudo apt install nodejs` (parses X-URL JSON + emits `segments.json`; usually already installed)
3. **whisper.cpp** — build from [ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp) and put `whisper-cli` on PATH (Metal-accelerated automatically on Apple Silicon):
   ```sh
   git clone https://github.com/ggml-org/whisper.cpp.git ~/.local/opt/whisper.cpp
   cd ~/.local/opt/whisper.cpp
   cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j --config Release
   ln -sf ~/.local/opt/whisper.cpp/build/bin/whisper-cli ~/.local/bin/whisper-cli
   ```
   Don't move `build/` afterward — the symlink's dylib rpaths are absolute; rebuild in place if you do.
4. **Model** — `bash ~/.local/opt/whisper.cpp/models/download-ggml-model.sh large-v3-turbo` (~1.5G). Lands at the default path the script expects.
5. **xurl** (optional, X-by-URL only) — [`github.com/xdevplatform/xurl`](https://github.com/xdevplatform/xurl), then `xurl auth`. Skip it if you always pass `--direct`.
</details>

## Use

```sh
./video-understanding.sh <video-or-x-url> [options]
```

| command | does |
|---|---|
| `./video-understanding.sh clip.mov` | local file, a frame every 500ms (default) |
| `./video-understanding.sh clip.mov --interval 2s` | a frame every 2s |
| `./video-understanding.sh https://x.com/u/status/123 --name post` | X post — `xurl` resolves the video |
| `… --direct https://video.twimg.com/…mp4` | supply the CDN URL manually |
| `… --force` | re-download even if the X video is cached |

Then tell your agent: *"read `clip_understand/AGENT.md` and do it."*
(Installed on your PATH? Use `video-understanding` instead of `./video-understanding.sh`.)

## Output (`<video>_understand/`)

| file | what |
|---|---|
| `frames/tNNmNNs.jpg` | one frame per interval; **filename = exact timestamp** |
| `transcript.srt` / `.txt` / `.json` | timestamped captions · plain · structured |
| `segments.json` | `{timestamp, speaker, text}` per segment |
| `manifest.json` | duration, fps, interval, frame→time map |
| `AGENT.md` | stage-2 instructions for the agent |

## What you get

Stage 2 produces `understanding.md` — the agent's full read of the video. Shape:

```markdown
# Understanding: <video>

**Summary** — 2–4 sentences: what it is and its purpose.

## Timeline
| time  | on-screen                    | spoken / topic              |
|-------|------------------------------|-----------------------------|
| 0:00  | title card "Q3 Launch"       | intro, names the product    |
| 0:12  | dashboard demo, cursor on… | walks through the metrics   |
| 1:45  | code diff on screen          | explains the migration      |

## Key visuals
- 0:12 — dashboard shows 3 KPIs the narration never mentions
- 1:45 — on-screen code corrects a term the audio got wrong

## Full takeaways
- <claims, steps, conclusions, anything actionable>

## Corrected transcript
- 1:45 "MPX" → "MDX" (visible on screen)
```

The point: the agent reads **every frame against the captions**, so it catches
on-screen text, demos, and corrections a transcript alone would miss.

## Options

| flag / var | default | note |
|---|---|---|
| `--interval` | `500ms` | accepts `500ms`, `0.5`, `2s`; or 2nd positional / `DEFAULT_INTERVAL`. Small for fast cuts, larger (`3s`) for talking-head. |
| `--name` | from file / post ID | output slug |
| `--force` | off | ignore cached X video |
| `VU_MODEL` | `large-v3-turbo` | needs matching `ggml-<model>.bin` (`tiny`…`large-v3`) |
| `WHISPER_MODEL` | `~/.local/opt/whisper.cpp/models/ggml-<VU_MODEL>.bin` | explicit model path |
| `VU_LANG` | auto | set e.g. `en` to skip detection |
| `FRAME_QUALITY` | `3` | ffmpeg `-q:v`, 2 best … 31 worst |
| `VU_PROFILE` | `local` | `local` (xurl + curl) or `grok` (agent supplies `--direct`) |

## X videos & profiles

- **local** (default): needs [`xurl`](https://github.com/xdevplatform/xurl) (authed) + `node` to resolve the post's highest-bitrate mp4; `curl` downloads it (cached in `~/.cache/video-understanding/x-videos`). No xurl? Pass the mp4 yourself with `--direct`.
- **grok**: Grok's built-in X tools find the post and supply the URL via `--direct` — no xurl needed. Extraction stays local in both.

## Notes

- Frames seek to each exact timestamp (`ffmpeg -ss`), so filenames never drift from the real frame time (unlike an `fps=1/N` filter).
- Fully local — no cloud, no API key. Whisper tuned with DTW timestamps + VAD; transcript post-processed to drop non-speech markers and repeats.
