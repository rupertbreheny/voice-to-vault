# Note Format & Transcription Guidelines

Specification for the frontmatter schema and note body layout produced by voice-to-vault.

**Canonical skeleton:** `templates/transcription.md` in the repo root is the authoritative fill-in template — the placeholders (`{{title}}`, `{{description}}`, `{{timestamp}}`, `{{date}}`, `{{duration}}`, `{{audio_uri}}`, `{{transcript}}`) map one-to-one onto the fields specified below. This document explains the fields; the template is what you fill. If the two ever disagree, the template wins.

## 1. Streamlined Frontmatter Schema

Every transcription note starts with clean, universal YAML metadata:

```yaml
---
type: transcription
title: "{note filename without extension}"
description: "{one or two sentence summary of the recording}"
tags: []
timestamp: {current ISO 8601 timestamp, e.g. 2026-09-18T21:00:00Z}
date: {YYYY-MM-DD from the audio filename}
duration: {mm.ss}
---
```

### Field Definitions:
- `type`: Always `transcription`.
- `title`: Matches the filename without the `.md` extension.
- `description`: A concise 1-2 sentence overview of the subject matter. Storing this in frontmatter makes it easily searchable via Obsidian Bases, Dataview, or CLI tools.
- `tags`: Initialized as `[]` for user categorization.
- `timestamp`: Note creation time in UTC ISO 8601 format (`date -u +"%Y-%m-%dT%H:%M:%SZ"`).
- `date`: The recording date extracted from the audio filename (format `YYYY-MM-DD`).
- `duration`: Duration of the clip in minutes and seconds separated by a period (e.g. `02.45`), formatted from `afinfo` duration.
- `date_source`: **Added only when the date did not come cleanly from the filename.** Omit it entirely in the normal case, so ordinary notes stay uncluttered and its presence always means "this date needed intervention". This is the documented exception to the rule that the template is filled verbatim.

  | Value | Meaning |
  | --- | --- |
  | `corrected-week-year` | Filename was a year ahead (late-December week-year bug); one year subtracted |
  | `file-creation` | Filename date was unusable; filesystem creation date used |
  | `run-date` | No usable date anywhere; today's date used |

  Because the field is absent from correctly dated notes, filtering on `date_source` in Obsidian Bases — or a plain `grep -rl date_source` — returns exactly the recordings whose date deserves a second look, and nothing else.

---

## 2. Note Body Layout

```markdown
## [[{YYYY-MM-DD}]]
<audio controls src="file://{absolute path to processed audio file}"></audio>

# overview
{one or two sentences summarizing the recording}

# transcript
{the cleaned, verbatim transcript}
```

### Body Layout Rules:
1. **Date Heading**: The first line is a link to the daily note `## [[{YYYY-MM-DD}]]`. Use the date after the future-date guard in `references/fileHandling.md` has been applied — never link a daily note that has not happened yet.
   * **Exception for Dreams**: When the topic keyword is `dream`, the date link points to the **previous day** (`## [[YYYY-MM-DD - 1 day]]`), as dreams are recalled upon waking and reflect the night before.
2. **Audio Player**: Second line embeds a standard HTML5 audio player pointing to the external file using a `file://` URI. This enables native inline playback within Obsidian and markdown editors without bloating vault storage.
   * **Privacy note**: this URI is an absolute path and therefore contains the user's macOS username (`file:///Users/<username>/...`). It is local-only and harmless inside a private vault, but it travels with the note if that note is ever published, shared, or exported. Flag this to the user rather than silently rewriting the path.
3. **# overview**: One or two clear sentences describing the core topic.
4. **# transcript**: The complete transcribed text.
5. **No Container Tags**: Never wrap sections in XML or HTML wrapper tags (`<overview>`, `<transcript>`). Use standard Markdown headings.

---

## 3. Transcription Intelligence & Principles

The transcribing model should follow these guidelines:

* **Substantive Verbatim Fidelity**: Keep every meaningful word and nuance of thought. Do not over-condense or summarize inside `# transcript`.
* **Disfluency Removal**: Cleanly eliminate filler words (`um`, `uh`, `like`, `you know`) and repetitive stuttering.
* **Audio Correction Resolution**: Voice dictation frequently includes self-corrections (e.g., *"We'll deliver on Friday—actually, sorry, Thursday afternoon"*). The model should accurately preserve the speaker's corrected intent (*"We'll deliver on Thursday afternoon"* or include natural conversational flow without tripping over the stumble).
* **Noisy Environment Handling**: When dictation occurs in noisy conditions (wind, traffic, café chatter), use semantic context to reconstruct ambiguous phrasing. If speech is genuinely unintelligible, mark it honestly as `[inaudible]` rather than hallucinating words.
* **Paragraphing**: Split long dictations into natural paragraphs at pauses or thought transitions.
