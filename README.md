# claude-mem-backup

**Daily, verified, crash-safe backups of your [claude-mem](https://github.com/thedotmack/claude-mem) memory database on macOS.**

claude-mem gives Claude Code a long-term memory: every session's observations and summaries live in one SQLite database (`~/.claude-mem/claude-mem.db`). Lose or corrupt that file and months of context are gone. This adds a daily snapshot that's safe to take while claude-mem is running, checks that each copy is good before keeping it, and keeps the last 7 days.

## Why it matters

- **Your memory is one file.** A disk problem, a bad update, an accidental delete or a broken migration can wipe everything Claude has learned about your projects.
- **Copying it the normal way isn't safe.** claude-mem's worker writes to the database all the time in WAL mode. A plain `cp` while it's running can produce a torn, unusable copy that looks fine until you need it.
- **A backup you never verified isn't a backup.** Each snapshot is checked with SQLite's integrity check, and a bad one never replaces a good one.

## What it does

1. **Consistent snapshot:** uses SQLite's `.backup` to take a point-in-time copy while the worker is live.
2. **Verify:** runs `PRAGMA integrity_check` on the copy. If it isn't `ok`, the copy is thrown away and yesterday's good one stays.
3. **Log the contents:** records how many observations and session summaries the snapshot holds, so you can see your memory growing (or spot a sudden drop).
4. **Vector index:** copies the Chroma index (`~/.claude-mem/chroma`), if present, next to the newest snapshot only, to save space.
5. **Retention:** keeps the newest 7 dated snapshots and deletes older ones.
6. **Off-machine copy (optional):** mirrors the newest database into `~/Documents/claude-mem-backups/latest`. If Documents syncs with iCloud, your memory is then off your Mac too.

It runs every day at **13:30** and at login, with low CPU and disk priority, so you won't notice it.

## Install

Requires macOS (it uses the built-in `/usr/bin/sqlite3`) and claude-mem.

```bash
git clone https://github.com/nvark1996/claude-mem-backup.git
cd claude-mem-backup
./install.sh
```

The first snapshot runs immediately. Check it:

```bash
tail ~/Library/Logs/claude-mem-backup.log
# 2026-10-22 13:30:01  OK 2026-10-22 observations=2231 summaries=402 size=48M total=310M
```

**Enable the iCloud mirror (optional):** macOS privacy protection blocks background jobs from writing to Documents. To allow it, add `/bin/bash` in **System Settings → Privacy & Security → Full Disk Access**. Without this, the backup still works and the log just says the mirror was skipped. Granting Full Disk Access to bash is broad, so only do it if you want the off-machine copy.

**Uninstall** (keeps your existing snapshots):

```bash
./install.sh --uninstall
```

## Where things are

| What | Where |
|---|---|
| Snapshots (one folder per day, newest 7 kept) | `~/Library/Application Support/claude-mem-backups/YYYY-MM-DD/` |
| iCloud mirror (newest only, optional) | `~/Documents/claude-mem-backups/latest/` |
| Log | `~/Library/Logs/claude-mem-backup.log` |

## Restore

1. Stop claude-mem's worker (or quit Claude Code).
2. Copy the snapshot back:
   ```bash
   cp ~/Library/Application\ Support/claude-mem-backups/2026-10-22/claude-mem.db ~/.claude-mem/claude-mem.db
   ```
3. Also copy the `chroma` folder back to `~/.claude-mem/chroma` if that snapshot has one.
4. Start Claude Code again.

## Settings

At the top of `claude-mem-backup.sh`: `KEEP=7` (days kept), the source paths and the mirror folder. The time of day is set in `install.sh` (`StartCalendarInterval`). Change it and run `./install.sh` again.

Not affiliated with claude-mem. It just backs up its files.

## License

MIT. See [LICENSE](LICENSE).
