# To-do list

0.20.0

  Fix crash when a frame sample lands past the video end
  Delete the Mux asset once frames are pulled
  Recover the asset id when the Mux poll times out
  Guard duration_sec so manifest.json always parses

0.19.0

  Accept any direct video-file URL
  Honor --name for local files
  Reframe X sourcing, drop CDN language
  Help + SKILL cover byok mode

0.18.0

  Optional .env for BYOK keys
  Env vars still take precedence
  Add .env.example, gitignore .env
  Remove todo.md

0.17.0

  BYOK now installs nothing
  Send video straight to xAI STT (no ffmpeg)
  Duration from xAI response, ffprobe local-only
  ffmpeg required only for local backends

0.16.0

  Add BYOK mode: xAI STT + Mux frames
  Pluggable STT_BACKEND / FRAME_BACKEND
  Build SRT from xAI word timestamps
  Two-mode getting-started in README

0.15.0

  List on skills.sh, add install cmd
  Tighten skill description
  Add sample understanding.md output
  State macOS-first platform scope

0.14.0

  Replace jq with node -e
  Drop jq dependency
  Update setup docs to node

0.13.0

  Auto-install jq in skill
  Document xurl X prereq + auth
  Fix oversold X-URL claims
  Note deps in manual setup

0.12.0

  Rewrite README, cut redundancy
  Merge Use/Examples/profiles
  Collapse manual setup to details
  Single options table

0.11.0

  Recommend ask-transcribe-cli first
  Skill auto-installs deps
  Drop manual reqs from top

0.10.0

  Fix BSD/Linux sed portability
  Pick highest-bitrate X video
  Dedupe via TMP_DIR temp
  Recommend ask-transcribe-cli setup

0.9.0

  Update README
  Document --interval flag
  Clarify 500ms default
  Improve examples

0.8.0

  Add --interval parameter
  Default 500ms frames
  Normalize ms s units
  Update docs and help

0.7.0

  Fix macOS sed syntax
  Support script symlinks
  Improve PATH install

0.6.0

  Restore todo notes
  Update project tasks
  Add download method item

0.5.0

  Wire DEFAULT_INTERVAL and DEFAULT_OUTDIR_SUFFIX from profiles
  Add --force for X cache bypass
  Improve xurl video URL extraction
  Add usage examples
  Clarify Grok profile role

0.4.0

  Add config profiles
  Add xurl resolver
  Update --direct flag
  Improve transcript quality
  Add segments.json
  Update docs and CLI

0.3.0

  Remove x-transcribe script
  Merge X support
  Update README SKILL
  Unify into one tool

0.2.0

  Merge x-transcribe into main
  Update script for X
  Mark legacy wrapper
  Improve CLI help

0.1.0

  Add SKILL.md to root
  Remove .grok directory
  Integrate X downloader
  Update README sourcing
  Merge into one skill
