# ebert

Your agent's movie critic. Turns any video into something an AI agent can fully
understand: timestamped frames + an SRT transcript, then the agent reviews the
frames against the captions and writes a complete `understanding.md`.

Two stages:
1. **`ebert.sh`** — mechanical extraction (ffmpeg + a self-installing STT engine). No AI.
2. **The agent** — reads the frames (filenames are timestamps) and `transcript.srt`,
   correlates picture↔speech, and writes `understanding.md`. Instructions land in
   `AGENT.md` inside the output folder.

## Install

```sh
git clone <this-repo> ebert && cd ebert
```

Prerequisites (the only two):
- **ffmpeg** — `brew install ffmpeg` (macOS) · `sudo apt install ffmpeg` (Linux) · [ffmpeg.org](https://ffmpeg.org/download.html) (Windows)
- **uv** — `curl -LsSf https://astral.sh/uv/install.sh | sh` (macOS/Linux) · `powershell -c "irm https://astral.sh/uv/install.ps1 | iex"` (Windows)

That's it. The transcription engine and model **download themselves on first run**
via `uvx` — no compiler, no Python setup, cross-platform. (Run with
`EBERT_AUTO_INSTALL=1` and ebert will install `uv` for you if it's missing.)

## Use

```sh
./ebert.sh <video> [interval_seconds] [output_dir]
# e.g.
./ebert.sh ~/Movies/demo.mov 5
```

Then tell your agent: *"read `demo_understand/AGENT.md` and do it."*

## Output (in `<video>_understand/`)

| file | what |
|---|---|
| `frames/tNNmNNs.jpg` | one frame per interval; **filename = exact timestamp** |
| `transcript.srt` | timestamped captions |
| `transcript.txt` / `.vtt` / `.json` / `.tsv` | same transcript, other formats |
| `manifest.json` | duration, fps, interval, frame→time map |
| `AGENT.md` | stage-2 instructions for the agent |

## STT engine

Default is **faster-whisper** (`whisper-ctranslate2`) — cross-platform (macOS,
Linux, Windows; CPU or CUDA), runs the `large-v3-turbo` Whisper model, downloads
on first use. On Apple Silicon you can opt into the Metal-accelerated **mlx**
engine for extra speed.

| var | default | note |
|---|---|---|
| `EBERT_ENGINE` | `faster` | `faster` (any OS) or `mlx` (Apple Silicon only) |
| `EBERT_MODEL` | `large-v3-turbo` | any Whisper size: `tiny`…`large-v3`, `distil-*` |
| `EBERT_LANG` | auto-detect | set e.g. `en` to skip detection |
| `EBERT_DEVICE` | `auto` | `faster` only: `auto`/`cpu`/`cuda` |
| `FRAME_QUALITY` | `3` | ffmpeg `-q:v`, 2 best … 31 worst |

```sh
EBERT_ENGINE=mlx ./ebert.sh demo.mov        # Apple Silicon fast path
EBERT_MODEL=base ./ebert.sh demo.mov        # smaller/faster, lower accuracy
```

## Notes

- Frames are extracted by **seeking to each exact timestamp** (`ffmpeg -ss`), so
  the filename never drifts from the real frame time — unlike the `fps=1/N` filter.
- Fixed-interval sampling: smaller interval for fast-cut content, larger for
  talking-head/screencast.
- All local. No cloud, no API key. Whisper `large-v3-turbo` is the current
  best general model — there's no newer Whisper architecture to switch to.
