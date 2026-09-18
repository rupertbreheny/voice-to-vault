# macOS Permissions & Automator Setup Guide

Apple protects Voice Memos recordings inside macOS sandbox containers:
```
~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings
```
Because this path holds personal audio data, macOS **Transparency, Consent, and Control (TCC)** blocks standard shell processes from reading it without explicit permission, returning `Operation not permitted`.

To allow automated tools and background agents to sync your recordings seamlessly without granting blanket Full Disk Access to your entire shell or terminal, use the **Automator Wrapper Pattern**.

---

### Step 1: Create an Automator Application

1. Open **Automator.app** on your Mac (press `Cmd + Space`, type `Automator`, and press Enter).
2. Choose **New Document** → select **Application** → click **Choose**.
3. In the search bar on the top-left, search for **Run Shell Script**.
4. Drag **Run Shell Script** into the right-hand workflow canvas.
5. In the script box, configure:
   - **Shell**: `/bin/bash`
   - **Pass input**: `to stdin`
   - Replace any default placeholder text with:
     ```bash
     /bin/bash "$HOME/path/to/voice-to-vault/scripts/sync-voice-memos.sh"
     ```
     *(Substitute the real absolute path to your cloned repository)*.
6. Save the application:
   - Press `Cmd + S`.
   - Name: `sync-voice-memos.app`.
   - Location: Put it in a convenient folder, e.g. `~/Applications/` or `~/Documents/code/`.

---

### Step 2: Grant Full Disk Access

1. Open **System Settings** on macOS.
2. Navigate to **Privacy & Security** → **Full Disk Access**.
3. Click the `+` icon at the bottom of the list (authenticate with your Touch ID / password).
4. Select your newly created `sync-voice-memos.app`.
5. Ensure the toggle switch next to `sync-voice-memos.app` is enabled (**ON**).

---

### Step 3: Run the Sync

Now, any automation script, cron job, or AI agent can trigger a sync cleanly by invoking:
```bash
open -a "/path/to/sync-voice-memos.app" -W
```
The `-W` flag tells the terminal to wait until the sync completes before returning.

### Alternative: Grant Full Disk Access Directly to Terminal

> ⚠️ **This is a much larger grant than it sounds — read before choosing it.**
> Full Disk Access on a terminal applies to *everything that terminal ever runs*: every script, every package-manager install hook, and every AI agent you drive from that shell. It is not scoped to Voice Memos. It also covers Mail, Messages, Safari history, Photos, and every other app container on the machine.
> The Automator wrapper in Steps 1–3 exists precisely to avoid this. It grants the same Voice Memos access to one three-line script and nothing else. **Prefer the wrapper.**

If you accept that trade-off and run scripts strictly by hand:
1. Go to **System Settings** → **Privacy & Security** → **Full Disk Access**.
2. Add your terminal application (e.g. **Terminal**, **iTerm**, or your IDE).
3. Run `scripts/sync-voice-memos.sh` directly.

Revoke it the same way (toggle off, or `-` to remove) once you no longer need it.
