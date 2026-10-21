#!/usr/bin/env python3
"""Nova operator brief: gather the state of the user's morning as structured data.

Pulls from the reliable, cheap layers - texts
(chat.db with the attributedBody decoder) and calendar (the Calendar DB
directly). Email is always the Gmail fallback, never Mail.app. It does NOT triage. It hands the agent clean data; the /brief skill
decides what is urgent and how to deliver it. Gathering and judging are separate
so the judging is auditable.

    nova brief            human-readable dump
    nova brief --json     structured, for the agent to triage
"""
import argparse, glob, json, os, subprocess, sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from texts import read as read_texts

CAL_DB = os.path.expanduser(
    "~/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb")
APPLE_EPOCH = 978307200


def _run(cmd, timeout=25):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None


# 2026-10-21: this read Mail.app, which Caleb has banned (10/13: "NEVER USE THE
# MAC MAIL APP WHEN GMAIL MOGS"). Its inbox was 20 TestFlight and Apple receipts
# from Sep 27 to Oct 13 while Gmail primary had nothing unread, so the brief
# showed a full inbox that wasn't his real one. Email is Gmail only.
def emails():
    """Email never comes from Mail.app. Reported unavailable so the Gmail
    fallback route is the one the agent runs."""
    return {"available": False, "items": [],
            "reason": "email is read through Gmail, never Mail.app"}


def calendar_result(items, failing):
    """A store whose sync is erroring hands back months-old data that looks
    current, so it counts as unavailable and the fallback route kicks in."""
    if failing:
        return {"available": False, "items": items,
                "reason": "sync failing: " + ", ".join(failing)}
    return {"available": True, "items": items}


def calendar_today():
    if not os.path.exists(CAL_DB):
        return {"available": False, "reason": "no calendar db", "items": []}
    # OccurrenceCache, not CalendarItem: a recurring event is stored once at its
    # first date, so classes and weekly blocks never matched "today" before.
    q = ("SELECT ci.summary, "
         "datetime(COALESCE(oc.occurrence_start_date, oc.occurrence_date) + 978307200,"
         "'unixepoch','localtime'), "
         "datetime(oc.occurrence_end_date + 978307200,'unixepoch','localtime'), ci.all_day "
         "FROM OccurrenceCache oc JOIN CalendarItem ci ON ci.ROWID = oc.event_id "
         "JOIN Store s ON s.ROWID = oc.store_id "
         "WHERE s.disabled = 0 AND date(COALESCE(oc.occurrence_start_date, "
         "oc.occurrence_date) + 978307200,'unixepoch','localtime') = date('now','localtime') "
         "ORDER BY 2")
    # 2026-10-14: the Google store had error_id 11294 on every sync since April,
    # so the brief showed an empty day while Google held six events.
    sq = "SELECT name, error_id FROM Store WHERE disabled = 0 AND error_id > 0"
    r = _run(["sqlite3", f"file:{CAL_DB}?mode=ro", q], timeout=10)
    sr = _run(["sqlite3", f"file:{CAL_DB}?mode=ro", sq], timeout=10)
    if not r or r.returncode != 0:
        return {"available": False, "reason": (r.stderr.strip() if r else "timed out"), "items": []}
    items = []
    for line in r.stdout.splitlines():
        p = line.split("|")
        if len(p) >= 3 and p[0]:
            items.append({"summary": p[0], "start": p[1], "end": p[2],
                          "all_day": p[3] == "1" if len(p) > 3 else False})
    failing = []
    if sr and sr.returncode == 0:
        failing = [f"{n} (error {e})" for n, e in
                   (l.split("|", 1) for l in sr.stdout.splitlines() if "|" in l)]
    return calendar_result(items, failing)


# 2026-10-06: Full Disk Access was missing and Mail timed out, so all three
# sources came back empty and the brief had nothing. The agent had to work out
# on its own that the same data was one MCP call away. Ship the route as data.
FALLBACKS = {
    "calendar": "mcp__claude_ai_Google_Calendar__list_events for today",
    "email": "mcp__claude_ai_Gmail__search_threads 'in:inbox newer_than:2d "
             "-category:promotions -category:social'",
    "texts": "none without chat.db: grant Full Disk Access to the host app "
             "(Terminal, VS Code) and say the brief is missing texts",
}


def with_fallbacks(b):
    for name, hint in FALLBACKS.items():
        if not b[name]["available"]:
            b[name]["fallback"] = hint
    return b


def gather(days=1):
    reason = None
    try:
        texts = read_texts(days=days, unanswered=True, direct=True)
    except (SystemExit, Exception) as e:  # one dead source must not kill the brief
        texts, reason = None, str(e)
    open_threads = {}
    if isinstance(texts, list):
        for m in texts:
            if not m["from_me"] and m["text"] != "[attachment]":
                open_threads[m["with"]] = m  # newest wins, list is oldest-first
    return with_fallbacks({
        "generated_at": datetime.now().isoformat(timespec="minutes"),
        "email": emails(),
        "texts": {"available": isinstance(texts, list),
                  "reason": reason,
                  "open_threads": [
                      {"with": k, "last": v["text"][:200], "at": v["at"]}
                      for k, v in open_threads.items()]},
        "calendar": calendar_today(),
    })


def render(b):
    print(f"NOVA OPERATOR BRIEF  {b['generated_at']}\n")
    cal = b["calendar"]
    print("TODAY")
    if not cal["available"]:
        print(f"  (calendar unavailable: {cal.get('reason')})")
    elif not cal["items"]:
        print("  nothing on the calendar")
    else:
        for e in cal["items"]:
            when = "all day" if e["all_day"] else e["start"][11:16]
            print(f"  {when}  {e['summary']}")
    print()
    tx = b["texts"]
    if not tx["available"]:
        print(f"TEXTS  (unavailable: {tx.get('reason')})")
    else:
        print(f"TEXTS WAITING ON YOU ({len(tx['open_threads'])})")
        for t in tx["open_threads"][:12]:
            print(f"  {t['with'][:28]:28}  {t['last'][:70]}")
    print()
    em = b["email"]
    if not em["available"]:
        print(f"EMAIL  (unavailable: {em.get('reason')})")
    else:
        unread = [e for e in em["items"] if e["unread"]]
        print(f"RECENT EMAIL ({len(unread)} unread of {len(em['items'])} shown)")
        for e in em["items"][:12]:
            mark = "*" if e["unread"] else " "
            frm = e["from"][:30]
            print(f"  {mark} {frm:30}  {e['subject'][:50]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=1)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    b = gather(days=a.days)
    print(json.dumps(b, indent=2) if a.json else "", end="")
    if not a.json:
        render(b)


if __name__ == "__main__":
    main()
