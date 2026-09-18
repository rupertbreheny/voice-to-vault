# File Handling & Intake Protocol

How audio files are discovered, dated, named, and safely preserved after transcription.

## 1. The Intake Directory
The default intake directory is configured via `AUDIO_INGESTION_DIR` in `config.env` (e.g. `~/Documents/Audio/transcription`).

- **Scan the root of the intake folder only.** Do not recurse into subdirectories — the `processed/` subfolder holds recordings that have already been processed.
- **Accepted formats:** `.m4a`, `.mp3`, `.wav`, `.aac`, and `.qta`.
- **Recordings arrive from two routes, and are treated identically:**
  1. The Voice Memos sync script, which copies `.m4a` and `.qta` out of the Apple container (`SYNC_EXTENSIONS` in `config.env`).
  2. The user dropping files in directly from any other source — another phone, a field recorder, a meeting export, a messaging app voice note. There is no Voice Memos or macOS dependency on this route.
  Never assume a file came from Voice Memos. Filenames from other sources will not follow Apple's convention — see date derivation below.
- **QuickTime Audio (.qta) conversion:** Voice Memos writes `.qta` for some recording formats (commonly stereo / spatial capture). If any are encountered:
  1. Convert to `.m4a`: `afconvert -f m4af -d aac "$file" "${file%.*}.m4a"`
  2. **Verify** the generated `.m4a` exists and is non-empty.
  3. **Only then** delete the `.qta`, so a single recording is never queued twice.
  4. If conversion fails, or produces a missing or zero-byte file, **keep the `.qta`**, move it to `errors/`, and report it. Never delete an unconverted source.

  **Why this deletion is deliberate.** The verified `.m4a` is a complete replacement for the same recording, so keeping both would double-queue it. This is the one and only deletion in the pipeline, it is conditional on a verified conversion, and it applies solely to an intermediate file this pipeline itself created a replacement for. It does not contradict the never-delete rule in section 5, which governs recorded audio.

  **Know the trade-off:** `afconvert` re-encodes. If the source carried more than the resulting channels — a spatial or multichannel capture — that information is not recoverable afterwards. For speech transcription this is irrelevant. If you are archiving recordings for their audio quality rather than their words, set `SYNC_EXTENSIONS="m4a"` so `.qta` files are never pulled in, and handle them yourself.

## 2. Recording Date Derivation: Filename vs. Filesystem
**Critical rule:** Always derive the recording date from the filename, never from filesystem modification time (`mtime`).

Apple Voice Memos and batch-copied files share the naming convention:
```
YYYYMMDD HHMMSS-HASH.m4a
```
For example: `20260918 113006-F8CBAE81.m4a`

* **Why mtime is unreliable**: When files are synced, downloaded, or copied in bulk, macOS stamps them with the copy date, not the recording date. 
* **The parsing rule**: Extract the leading 8 digits (`YYYYMMDD` → `YYYY-MM-DD`). Use this for sorting, the frontmatter `date:` property, and the date prefix in the note title.
* If a custom user file does not match this timestamp format, parse any standard ISO date present in the name (e.g. `2026-09-18`, `2026_09_18`), or fall back to the file creation date. **Always report the fallback in the run summary**, naming the file and the date used, so the user can correct a wrong date rather than discovering it months later.

### Future-date guard (mandatory)

**A recording cannot have been made in the future. Never write a note dated later than today.** This rule is absolute and applies to the frontmatter `date:`, the `## [[date]]` heading, and the date prefix in the filename.

After parsing a candidate date, compare it to today:

```bash
today="$(date '+%Y%m%d')"
[ "$candidate" -gt "$today" ] && echo "invalid — apply correction below"
```

**If the candidate is in the future, correct it in this order:**

1. **Week-year rollover (the common case).** If the candidate falls on **25–31 December** and subtracting exactly one year yields a date on or before today, use the corrected date and set `date_source: corrected-week-year`.

   *Why this specific window:* the bug comes from a date formatter using `YYYY` (ISO **week**-year) where it meant `yyyy` (calendar year). In the final days of December those differ, because the week containing 1 January belongs to the new year. With Sunday-start weeks, 28 December 2025 was the first day of the week containing 1 January 2026, so recordings from 28–31 December 2025 were stamped `2026`. The 27th, a Saturday, was stamped correctly. A whole batch therefore lands exactly one year ahead, always at the end of December.

2. **Otherwise, do not guess a plausible-looking date.** Use the file creation date if it is on or before today; if it is not, use today's date. Set `date_source: file-creation` or `date_source: run-date` accordingly.

3. **Always report every correction in the run summary**, naming the file, the rejected date, the substituted date, and the reason. A silently corrected date is barely better than a silently wrong one.

Transcribe the recording either way. A bad filename is never a reason to lose the audio's contents.

## 3. Batch Selection
1. List all supported audio files in the intake root.
2. Sort by the parsed date/time key to identify the most recent files up to the configured limit (`BATCH_LIMIT`, default 20).
3. Process the chosen batch chronologically (**oldest to newest**). This ensures that related thoughts dictated across multiple clips are transcribed in logical sequence.

## 4. Note Filename Convention
- **When a recognized trigger word is dictated** (e.g. `idea`, `dream`, `todo`, `meeting`, `journal`, `note`):
  ```
  {YYYY-MM-DD} - {mm-ss} - {trigger word} - {concise summary in 5 words or less}.md
  ```
- **When no trigger word was dictated**:
  ```
  {YYYY-MM-DD} - {mm-ss} - {concise summary in 5 words or less}.md
  ```
- `{mm-ss}`: Audio duration zero-padded (e.g., `01-45`, `00-32`), read via `afinfo`.
- **Collision avoidance**: If a note with the exact name already exists in the destination folder, append ` - 2.md`, ` - 3.md`. Never overwrite an existing note.

## 5. Moving Processed Audio (Safe Backup Outside Vault)
Once a note has been successfully written and verified on disk:
- Move the source audio file to `AUDIO_PROCESSED_DIR` (e.g. `transcription/processed/`).
- **Never delete source audio automatically.** The single exception is an intermediate `.qta` whose conversion to `.m4a` has been verified (section 1) — that is a duplicate this pipeline created a replacement for, not a recording being lost.
- **Why audio is stored outside the vault**:
  Audio files are large binaries. Storing hundreds of voice memos inside an Obsidian vault quickly consumes Obsidian Sync storage limits (or cloud drive bandwidth) and bloats mobile sync times. Moving them to an external local directory preserves high-fidelity audio while keeping the vault nimble.
- **Embedded playback via absolute path**: The note embeds an HTML5 `<audio controls src="file:///absolute/path/to/processed/filename.m4a"></audio>` tag so the memo can be played directly inside Obsidian without storing the binary in the vault.
- **Voice Memos deletion is intentionally manual**: The sync script only *copies* recordings from Apple Voice Memos. Deleting recordings from the Voice Memos app is left to the user to guarantee zero accidental data loss.
