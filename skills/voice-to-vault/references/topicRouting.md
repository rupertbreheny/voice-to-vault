# Topic Routing & Keyword Conventions

How spoken keywords dictate note organization, folder hierarchy, and optional integrations.

## 1. The Spoken Keyword Habit
When dictating memos, the user can prefix recordings with a topic keyword:
1. Speak the keyword clearly as the first word (e.g., *"Todo."*, *"Idea."*, *"Dream."*).
2. Pause briefly for 1–2 seconds.
3. Speak the main body of the note.

This simple habit allows the agent to automatically file notes into thematic folders without needing tags or manual sorting.

---

## 2. Trigger Word Registry
Configured via `TRIGGER_WORDS` in `config.env`.

Default recognized trigger words:
- `idea`
- `dream`
- `todo`
- `meeting`
- `journal`
- `note`

### Extraction Logic:
1. Extract the first word of the transcript.
2. Strip surrounding punctuation (`"Idea,"` → `Idea`, `Todo.` → `Todo`).
3. Lowercase the word for directory naming (`idea`).
4. Validate that the word is a recognized trigger word and not conversational opener (e.g. `so`, `well`, `I`, `the`, `recording`).

---

## 3. Destination Routing

### A. Routed (Trigger Word Found)
* **Destination Folder**: `{VAULT_DIR}/transcription/{keyword}/`
* **Filename**:
  ```
  {YYYY-MM-DD} - {mm-ss} - {keyword} - {concise summary}.md
  ```
* Create the destination folder if it does not already exist.

### B. Fallback (No Keyword Dictated)
If the memo starts mid-thought or opens with an unlisted word:
* **Destination Folder**: `{VAULT_DIR}/transcription/unsorted/`
* **Filename**:
  ```
  {YYYY-MM-DD} - {mm-ss} - {concise summary}.md
  ```
* List all fallback notes in the run summary so they are easy to review and file manually.

---

## 4. Optional Integration: Dream Notes to Daily Note

When enabled (`SYNC_DREAM_TO_DAILY=true` in `config.env`):
* Memos routed under `dream` are automatically appended to the user's daily note corresponding to the **day before** the audio recording date.
* **Why the previous day?** Dreams remembered in the morning reflect sleep from the previous night.
* **Format**: Locate `{DAILY_NOTE_PATH_FORMAT}` (e.g. `daily/YYYY/MM/YYYY-MM-DD.md`) and append the cleaned transcript beneath the `# dream` heading.
