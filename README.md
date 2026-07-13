# video-understanding

Your agent's movie critic. Turns any video into something an AI agent can fully
understand: timestamped frames + an SRT transcript, then the agent reviews the
frames against the captions and writes a complete `understanding.md`.

Two stages:
1. **`video-understanding.sh`** (or `video-understanding` if installed on PATH) — mechanical extraction (ffmpeg + local whisper.cpp STT). No AI.
2. **The agent** — reads the frames (filenames are timestamps) and `transcript.srt`,
   correlates picture↔speech, and writes `understanding.md`. Instructions land in
   `AGENT.md` inside the output folder.

## Install

```sh
git clone https://github.com/stevederico/video-understanding.git && cd video-understanding
chmod +x video-understanding.sh
```

### Recommended: let `ask-transcribe-cli` set it all up (macOS Apple Silicon)

One command installs everything this tool needs — no need to wire up ffmpeg,
whisper.cpp, or models yourself. [`ask-transcribe-cli`](https://github.com/stevederico/ask-transcribe-cli)
builds whisper.cpp (Metal), symlinks `whisper-cli` into `~/.local/bin`, downloads
`ggml-large-v3-turbo` to the default path, and pulls in `ffmpeg`:

```sh
git clone https://github.com/stevederico/ask-transcribe-cli.git && cd ask-transcribe-cli && bash install-stt.sh
```

(`bash setup.sh` also adds the `ask` local-LLM CLI; `install-stt.sh` is STT-only.)
Ensure `~/.local/bin` is on your `PATH` and you're done — skip the manual steps
below.

## Manual setup

Prefer to wire it up by hand? You need **ffmpeg**, the **whisper.cpp CLI**
(`whisper-cli`) on your `PATH`, and a GGML model.

### 1. ffmpeg

- macOS: `brew install ffmpeg`
- Linux: `sudo apt install ffmpeg` (or `dnf`/`pacman`)
- Windows: [ffmpeg.org](https://ffmpeg.org/download.html)

### 2. Build whisper.cpp and put the CLI on PATH

Builds from the official upstream repo ([ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp)).
Needs `git` + `cmake` (and `SDL2` only if you want the realtime `whisper-stream`
mic example). On Apple Silicon the build is Metal-accelerated automatically.

```sh
# clone into a tool location (not a projects dir)
git clone https://github.com/ggml-org/whisper.cpp.git ~/.local/opt/whisper.cpp
cd ~/.local/opt/whisper.cpp

# build (drop -DWHISPER_SDL2=ON if you don't need the mic streamer)
cmake -B build -DWHISPER_SDL2=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j --config Release

# expose the CLIs on PATH (symlink into a dir already on $PATH)
mkdir -p ~/.local/bin
for b in whisper-cli whisper-stream whisper-server; do
  ln -sf ~/.local/opt/whisper.cpp/build/bin/$b ~/.local/bin/$b
done
```

Make sure `~/.local/bin` is on your `PATH` (`echo $PATH | tr ':' '\n' | grep .local/bin`).
The symlinks point into `build/bin`, where the dylibs live — **don't move the
build dir afterward**, or rebuild in place if you do (rpaths are absolute).

> When using with the video-understanding skill (via dotfiles or similar), the
> command is usually available as `video-understanding` on your PATH.

### 3. Download a model

```sh
cd ~/.local/opt/whisper.cpp
bash models/download-ggml-model.sh large-v3-turbo   # ~1.5G, the default
```

This lands at `~/.local/opt/whisper.cpp/models/ggml-large-v3-turbo.bin`, which is
exactly where the script looks by default. Override with `$WHISPER_MODEL` if you
keep models elsewhere.

Verify the whole chain:

```sh
whisper-cli -m ~/.local/opt/whisper.cpp/models/ggml-large-v3-turbo.bin \
  -f ~/.local/opt/whisper.cpp/samples/jfk.wav -otxt -of /tmp/jfk && cat /tmp/jfk.txt
```

## Use

From the repo:

```sh
./video-understanding.sh <video-or-x-url> [interval] [output_dir] [--interval <val>] [--direct <mp4-url>] [--name <slug>]
# e.g.
./video-understanding.sh ~/Movies/demo.mov                 # default: every 500ms
./video-understanding.sh ~/Movies/demo.mov --interval 2s   # every 2 seconds
./video-understanding.sh https://x.com/user/status/123 --name my-post
./video-understanding.sh https://x.com/... --direct https://video.twimg.com/...mp4 --interval 500ms --name p
DEFAULT_INTERVAL=2 ./video-understanding.sh clip.mov --force
```

(If installed on your PATH, you can just use `video-understanding` instead of `./video-understanding.sh`.)

**Default interval:** 500ms (use `--interval 500ms`, `--interval 0.5`, `--interval 2s`, or the second positional argument).

Config via `VU_PROFILE=local` (default) or `grok`. See `config/profiles/`.
You can also set `DEFAULT_INTERVAL` (in env, profile, or on the command line before the script).

Then tell your agent: *"read `demo_understand/AGENT.md` and do it."*

## Output (in `<video>_understand/`)

| file | what |
|---|---|
| `frames/tNNmNNs.jpg` (or `tNNmNNsNNNms.jpg`) | one frame per interval; **filename = exact timestamp** (e.g. every 500ms) |
| `transcript.srt` | timestamped captions |
| `transcript.txt` / `.json` | same transcript, other formats |
| `manifest.json` | duration, fps, interval, frame→time map |
| `AGENT.md` | stage-2 instructions for the agent |

## STT engine

Local **whisper.cpp** (`whisper-cli`) — GPU-accelerated (Metal on Apple Silicon),
running the `large-v3-turbo` model set up above. For a different model size,
download the matching `ggml-<size>.bin` (step 3) and pass `VU_MODEL`.

Tuned with DTW for timestamps, no-speech-thold 0.68, logprob -0.9, VAD if available.
Post-processing removes non-speech and simple repetitions (inspired by x-studio).

| var | default | note |
|---|---|---|
| `VU_MODEL` | `large-v3-turbo` | needs matching `ggml-<model>.bin` (`tiny`…`large-v3`) |
| `WHISPER_MODEL` | `~/.local/opt/whisper.cpp/models/ggml-<VU_MODEL>.bin` | explicit model path |
| `VU_LANG` | auto-detect | set e.g. `en` to skip detection |
| `FRAME_QUALITY` | `3` | ffmpeg `-q:v`, 2 best … 31 worst |

```sh
VU_MODEL=base ./video-understanding.sh demo.mov --interval 1s   # smaller/faster, lower accuracy
WHISPER_MODEL=/path/ggml-large-v3.bin ./video-understanding.sh demo.mov
```

## X video support (integrated)

X post videos are supported directly:

```sh
./video-understanding.sh https://x.com/user/status/123
./video-understanding.sh https://x.com/user/status/123 --interval 500ms --direct https://video.twimg.com/...mp4
```

- Default (local profile): uses `xurl` to resolve the video URL from the post, then downloads with `curl`.
- `--direct <mp4-url>`: for manual CDN URLs or when using the Grok profile (Grok supplies the URL via its X tools).
- Grok profile: Grok's built-in X tools find the post and provide the direct URL.

See `./video-understanding.sh --help` or SKILL.md. Works for any agent.

## Configuration profiles

Pick local vs cloud-focused setups via `VU_PROFILE=local` (default) or `grok`.

- Profiles: `config/profiles/<name>.sh`
- Local (current): fully local whisper.cpp + xurl + curl. No cloud.
- Grok: agent uses built-in X tools to supply video URL via --direct; mechanical stages stay local.
- Interval is controlled with `--interval` (or `DEFAULT_INTERVAL` env / profile). Default: `500ms`.
- Keeps the tool portable across agents.

Example:
```sh
VU_PROFILE=local ./video-understanding.sh demo.mov --interval 1
```

## Examples

```sh
# local file, default 500ms
./video-understanding.sh ~/clip.mov

# X post (uses xurl if installed)
./video-understanding.sh https://x.com/user/status/123 --name post123

# custom interval
./video-understanding.sh ~/clip.mov --interval 2s
./video-understanding.sh https://x.com/user/status/123 --interval 500ms --name post123

# force re-download + custom suffix via profile/env
DEFAULT_OUTDIR_SUFFIX=_review ./video-understanding.sh https://x.com/... --direct https://...mp4 --force

# explicit grok profile + agent-provided URL
VU_PROFILE=grok ./video-understanding.sh https://x.com/.../123 --direct https://video.twimg.com/...mp4 --name p
```

## Notes

- Frames are extracted by **seeking to each exact timestamp** (`ffmpeg -ss`), so
  the filename never drifts from the real frame time — unlike the `fps=1/N` filter.
- Fixed-interval sampling: `--interval 500ms` (or `0.5`) for fast-cut content / demos,
  larger values (e.g. `--interval 3s`) for talking-head/screencast.
- All local. No cloud, no API key. Whisper `large-v3-turbo` is the current
  best general model — there's no newer Whisper architecture to switch to.
