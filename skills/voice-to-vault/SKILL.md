---
type: aiskill
name: voice-to-vault
description: Batch transcribe voice memo recordings into organized markdown notes using multi-agent orchestration.
title: voice-to-vault
tags:
  - transcription
  - audio
  - voice-memos
  - obsidian
---

# overview
Executable skill for turning a queue of voice memo recordings into structured markdown notes using a **multi-agent orchestration team**.

An orchestrator inspects the intake directory, determines clip durations, and delegates transcription to independent worker agents in parallel (one per audio file). Workers transcribe each recording natively, resolve mid-speech corrections, format the output with streamlined YAML metadata, and file the note into a folder based on the spoken trigger word. The orchestrator then safely archives the source audio in an external processed folder and outputs an end-of-run summary.

# preconditions
- **Multi-Agent Runtime**: Runs in any agent framework supporting parallel subagent spawning. Verified on:
  - **Google Antigravity** — the maintained path. Spawns workers via `invoke_subagent`, and its model accepts audio directly, so workers can perform step 4.1 themselves. Skill is discovered at `.agents/skills/voice-to-vault/` (project scope) or `~/.gemini/antigravity/skills/voice-to-vault/` (user scope).
  - **Claude Code** — spawns workers via the Agent tool and can run every step *except* transcription. Claude models accept text and images, not audio, so step 4.1 must be delegated to an external engine (see "Swapping the transcription engine"). Do not attempt to transcribe audio directly here; stop and tell the user what is missing instead. Skill is discovered at `.claude/skills/voice-to-vault/` (project scope) or `~/.claude/skills/voice-to-vault/` (user scope).
  - Both paths are symlinks to the canonical `skills/voice-to-vault/` in this repo. Falls back to sequential processing wherever subagents are unsupported.
- **An audio-capable transcription step**: either a runtime whose model accepts audio directly (the off-device default), or an external engine the workers can shell out to. **Check this before starting a run.** If neither is available, report that and stop — do not guess at, paraphrase, or invent a transcript under any circumstances. A fabricated transcript of someone's own voice is worse than no note at all.
- **Audio Duration Utility**: Shell access to `afinfo` (macOS) or `ffprobe` to measure clip durations.
- **Configuration**: `config.env` configured with vault paths, intake folders, and trigger words.

# procedure

## 1. Synchronize Intake (optional)
Skip this step entirely if the user has placed audio in the intake directory themselves — the pipeline is source-agnostic and treats dropped files identically to synced ones.

If using Apple Voice Memos on macOS, trigger the sync script or Automator wrapper. It copies every configured format (`.m4a` and `.qta` by default) and never deletes from Voice Memos:
```bash
open -a "sync-voice-memos.app" -W
# Or directly via script:
./scripts/sync-voice-memos.sh
```

## 2. Scan and Batch the Queue
1. Read `references/fileHandling.md`.
2. Inspect the root of the intake directory (`AUDIO_INGESTION_DIR`). **Do not recurse into subdirectories.**
3. If any `.qta` recordings exist, convert them to `.m4a` via `afconvert -f m4af -d aac "$file" "${file%.*}.m4a"`. Verify the `.m4a` exists and is non-empty, and only then delete the source `.qta`. If conversion fails, keep the `.qta`, move it to `errors/`, and report it.
4. Parse the recording timestamp from the leading digits of each filename (`YYYYMMDD`).
5. **Apply the future-date guard.** Reject any parsed date later than today and correct it per `references/fileHandling.md` — late-December dates one year ahead are the week-year bug and are corrected by subtracting a year; anything else falls back to the file creation date. Never write a note dated in the future. Record the correction for the run report.
6. Select up to `BATCH_LIMIT` (default 20) most recent files by date/time, using corrected dates.
7. Read each file's duration using `afinfo` and format as `mm-ss` (zero-padded, e.g. `02-15`).
8. Process the batch in chronological order (**oldest to newest**).

## 3. Parallel Worker Execution
For each file in the batch, spawn a worker subagent passing:
- Absolute path to the audio file
- Parsed recording date (`YYYY-MM-DD`)
- Formatted duration (`mm-ss` and `mm.ss`)

Workers run concurrently.

## 4. Worker: Transcribe & Format
Each worker executes the following:
1. **Listen to Audio**: Transcribe the recording verbatim, preserving substantive thoughts while eliminating filler disfluencies (`um`, `ah`). If this runtime cannot accept audio, invoke the configured external engine instead — and if none is configured, fail this file loudly rather than producing a note with no real transcript in it.
2. **Handle Corrections & Noise**: Gracefully resolve in-sentence corrections (capturing the speaker's true intent) and mark unintelligible noisy passages as `[inaudible]`.
3. **Route by Keyword**: Read `references/topicRouting.md`. Extract the first spoken word. If it matches a recognized trigger word (e.g. `idea`, `dream`, `todo`), route to `transcription/{keyword}/`. Otherwise route to `transcription/unsorted/`.
4. **Optional Dream Transfer**: If the keyword is `dream` and `SYNC_DREAM_TO_DAILY=true`, append the transcript into `# dream` of the daily note for the day before the audio date.
5. **Write Markdown Note**: Read `references/noteFormat.md`, and use `templates/transcription_.md` in the repo root as the literal skeleton to fill. Produce the streamlined YAML frontmatter and note body containing:
   - Frontmatter (`type`, `title`, `description`, `tags`, `timestamp`, `date`, `duration`)
   - Date heading `# [[YYYY-MM-DD]]`
   - Native audio player `<audio controls src="file://{processed_audio_path}"></audio>`
   - `# overview` summary
   - `# transcript` cleaned text

## 5. Orchestrator: Safe Archival
Once a worker confirms that the markdown note is written to disk:
1. Move the source audio file to `AUDIO_PROCESSED_DIR` (e.g. `transcription/processed/`).
2. **Never delete** the source audio file during archival.
3. If an audio file fails to process (e.g. 0-second clip or silent error), move it to `errors/` so the queue remains unblocked.

## 6. Run Report
The orchestrator prints a final run report:
- Total files processed and their target folders.
- Files routed to `unsorted/` fallback.
- **Every date correction**: the file, the rejected date, the date used instead, and why. Never apply one silently.
- Any skipped or failed files with reason, including `.qta` conversions that failed and were moved to `errors/`.
- Total recordings remaining in the intake queue.

# swapping the transcription engine
Step 4.1 ("Listen to Audio") is the only step bound to an off-device model. Everything else in this skill — batching, date parsing, keyword routing, note formatting, archival, reporting — is engine-agnostic.

To run fully on-device, replace step 4.1 with a shell call to a local binary and feed its output into step 4.2 onward:

```bash
# Example: whisper.cpp, no audio leaves the machine
whisper-cli -m models/ggml-large-v3.bin -f "$file" -otxt
```

Note the trade-off before switching: local models are materially weaker at proper nouns, technical jargon, mid-sentence self-correction, and noisy-environment reconstruction, and they tend to fail silently — producing a fluent transcript that is quietly wrong. The maintained default here is off-device.
