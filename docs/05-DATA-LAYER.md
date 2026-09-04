# Layer 1 — Data

The layer people skip entirely. Most questions about a Mac are answerable with a SQL
query, and the answer is exact rather than a model's reading of a screenshot.

## Messages

`~/Library/Messages/chat.db` is SQLite. Full Disk Access required.

```bash
sqlite3 ~/Library/Messages/chat.db \
  "SELECT datetime(message.date/1000000000 + 978307200, 'unixepoch', 'localtime') AS d,
          handle.id, message.is_from_me, message.text
   FROM message JOIN handle ON message.handle_id = handle.ROWID
   ORDER BY message.date DESC LIMIT 20"
```

Two gotchas:

- **Apple epoch.** Dates are nanoseconds since 2001-01-01, not 1970. The
  `/1000000000 + 978307200` above converts it.
- **`text` is often NULL** on Ventura and later. Message bodies moved into
  `attributedBody`, a hex-encoded NSAttributedString blob that preserves formatting.
  Parsing it means decoding a typed stream, which is why every iMessage tool has an
  `attributedBody` parser in it.
  [carterlasalle/mac_messages_mcp](https://github.com/carterlasalle/mac_messages_mcp)
  (323 stars) handles this and exposes it over MCP.

Read-only, always. Open with `file:...?mode=ro` and never write while Messages is
running.

## Notes

`~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite`. Bodies are
gzipped protobuf, so raw SQL gets you metadata but not readable text. For actual note
content, AppleScript is easier than reverse-engineering the blob:

```bash
osascript -e 'tell application "Notes" to get body of note 1'
```

## Everything else worth knowing

| What | Where |
|------|-------|
| Safari history | `~/Library/Safari/History.db` |
| Chrome history | `~/Library/Application Support/Google/Chrome/Default/History` |
| Photos | `~/Pictures/Photos Library.photoslibrary/database/Photos.sqlite` |
| Mail index | `~/Library/Mail/V*/MailData/Envelope Index` |
| Reminders / Calendar | `~/Library/Calendars/Calendar.sqlitedb` |
| Music library | `~/Music/Music/Music Library.musiclibrary` |
| App preferences | `~/Library/Preferences/*.plist` (`defaults read`, `plutil -p`) |
| Downloads provenance | `xattr -p com.apple.metadata:kMDItemWhereFroms file` |
| Spotlight | `mdfind "query"`, `mdls file` |

## Rules

1. **Read-only, or you will corrupt something.** Live apps hold write locks and cache
   in memory. Copy the file first if you need to be sure:
   `cp chat.db /tmp/ && sqlite3 /tmp/chat.db ...`
2. **Schemas change between macOS releases.** A query that works on 15 can return an
   empty set on 16. Check `.schema` before trusting a column name.
3. **Full Disk Access is required and it is a big grant.** It gives the process
   everything, including other apps' data and the TCC database itself. Grant it to a
   terminal you control, and understand that means anything that terminal runs.
4. **`defaults` is cached.** `cfprefsd` can return a stale value right after a GUI
   change. `killall cfprefsd` if you need certainty.

## Why this is worth the effort

"Summarize what she said this week" through layer 5 is twenty screenshots of a scrolling
Messages window, a minute of latency, and a summary of whatever happened to be visible.
Through layer 1 it is one query, exact, in milliseconds, over the complete history.

Reach for a database before you reach for a screen.
