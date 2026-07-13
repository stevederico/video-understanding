# video-understanding

Your agent's movie critic. Turns any video (local file or X post) into something an
AI agent can fully understand: timestamped frames + an SRT transcript, which the
agent then reviews to write a complete `understanding.md`.

Two stages:
1. **`video-understanding.sh`** — mechanical extraction (frames + transcript). No AI, deterministic.
2. **The agent** — reads the frames (filenames are timestamps) + `transcript.srt`, correlates picture↔speech, and writes `understanding.md` following the generated `AGENT.md`.

## Two modes

**Install the tools, or bring your own keys.** Pick per `VU_PROFILE`:

| mode | transcription | frames | you provide | best for |
|---|---|---|---|---|
| **local** (default) | whisper.cpp | ffmpeg | the tools (one-time install; macOS Apple Silicon turnkey) | private, offline, no keys |
| **BYOK** | xAI STT | Mux | `XAI_API_KEY` + Mux creds — **installs nothing** | any OS, no build |

- **local** = install whisper.cpp + ffmpeg once; runs offline, no keys, no per-use cost.
- **BYOK** = no whisper build, no ffmpeg — the video goes straight to xAI (transcript) and Mux (frames), both server-side. Only `curl` + `node` locally (already on any dev box).
- Set only `XAI_API_KEY` (no Mux)? BYOK still transcribes with zero install, but frames then need local `ffmpeg`.
- Both modes produce identical output files.

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

### Get started — local mode (macOS Apple Silicon, no keys)

Install the deps in one command — [`ask-transcribe-cli`](https://github.com/stevederico/ask-transcribe-cli)
builds whisper.cpp (Metal), symlinks `whisper-cli` into `~/.local/bin`, downloads
`ggml-large-v3-turbo`, and installs ffmpeg:

```sh
git clone https://github.com/stevederico/ask-transcribe-cli.git && cd ask-transcribe-cli && bash install-stt.sh
# then:
./video-understanding.sh ~/clip.mov
```

Ensure `~/.local/bin` is on your `PATH`.

### Get started — BYOK mode (any OS, installs nothing)

Bring keys instead of tools. The video is sent to xAI for the transcript and to
Mux for frames — no whisper build, no ffmpeg, no model. Only `curl` + `node`
(already present) are used locally:

```sh
export XAI_API_KEY=xai-...               # transcript  (x.ai)
export MUX_TOKEN_ID=...                   # frames      (dashboard.mux.com)
export MUX_TOKEN_SECRET=...
VU_PROFILE=byok ./video-understanding.sh ~/clip.mov
```

Keys are read from the environment only — never hardcode them. Prefer a file?
Copy `.env.example` to `.env` (gitignored) and fill it in — the script loads
`./.env` then `<script-dir>/.env` automatically; anything you `export` still wins.

Skip the Mux keys and BYOK still transcribes with zero install, but frames fall
back to local `ffmpeg` (so you'd need that one tool).

**Inputs:** a local file, a direct video-file URL (hosted anywhere), or an X post.
X posts are resolved through the X API via [`xurl`](https://github.com/xdevplatform/xurl)
(authed with your X API keys) — or skip that and just pass a direct video URL /
local path. `xurl` is only needed to resolve an `x.com/…` link.

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
| `./video-understanding.sh https://example.com/talk.mp4 --name talk` | a direct video-file URL (hosted anywhere) |
| `./video-understanding.sh https://x.com/u/status/123 --name post` | an X post — resolved via the X API (`xurl`) |
| `… --direct https://example.com/talk.mp4` | pass the video URL explicitly (skips resolving) |
| `… --force` | re-download even if the video is cached |

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
| `VU_PROFILE` | `local` | `local`, `byok` (xAI STT + Mux), or `grok` (agent supplies `--direct`) |
| `STT_BACKEND` | `local` | `local` (whisper.cpp) or `xai` (needs `XAI_API_KEY`) |
| `FRAME_BACKEND` | `local` | `local` (ffmpeg) or `mux` (needs `MUX_TOKEN_ID`/`MUX_TOKEN_SECRET`; falls back to local) |
| `XAI_API_KEY` | — | env/`.env` only, for `STT_BACKEND=xai` |
| `MUX_TOKEN_ID` / `MUX_TOKEN_SECRET` | — | env/`.env` only, for `FRAME_BACKEND=mux` |
| `STT_WORDS_PER_CUE` | `10` | xAI words grouped into ~N-word SRT cues |

## Sources & profiles

- **Local file / direct URL**: pass a path or any direct video-file URL — no X involved, no xurl.
- **X post** — **local** profile: [`xurl`](https://github.com/xdevplatform/xurl) (authed) + `node` resolve the post's video via the X API; the file is cached under `~/.cache/video-understanding`.
- **X post** — **grok** profile: Grok's built-in X tools find the post and supply the URL via `--direct`. Extraction stays local either way.

## Notes

- Local frames seek to each exact timestamp (`ffmpeg -ss`), so filenames never drift from the real frame time (unlike an `fps=1/N` filter).
- **local** mode is fully offline, no keys — whisper tuned with DTW timestamps + VAD; transcript post-processed to drop non-speech markers and repeats. **BYOK** uploads the video to xAI (transcript) and Mux (frames) — zero install, but not offline (your media leaves the machine).
