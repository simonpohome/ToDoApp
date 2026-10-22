"""Deadlines data and Canvas logic (no user interface).

Saved in (same place and format as the earlier Tk version, so its data carries over):
%APPDATA%\\Deadlines\\deadlines.json = {"tasks": [...], "subjects": [...], "canvas": {...},
"subject_colors": {lowercase subject: "#rrggbb"}}
"""

import json
import os
import re
import urllib.error
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

DATA_DIR = Path(os.environ.get("APPDATA", Path.home())) / "Deadlines"
DATA_FILE = DATA_DIR / "deadlines.json"


# ---------- Saving and loading ----------

def default_canvas():
    # feed_url: the private Canvas calendar feed link; assignments: last synced copy of it;
    # hidden: courses removed from the Courses tab (they stay removed across syncs).
    return {"feed_url": "", "last_sync": None, "assignments": [], "hidden": [], "collapsed": []}


def load_data():
    """{"tasks", "subjects", "canvas", "subject_colors"}; tasks are stored in display order."""
    try:
        data = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {}
    if isinstance(data, list):
        # Oldest format: just a list of tasks, always shown sorted by due date.
        tasks = sorted(data, key=lambda t: t["due"])
        data = {"tasks": tasks, "subjects": sorted({t["subject"] for t in tasks}, key=str.lower)}
    tasks = data.get("tasks", [])
    for task in tasks:
        task.pop("priority", None)  # priorities were removed; colours come from the due date
    return {"tasks": tasks, "subjects": data.get("subjects", []),
            "canvas": {**default_canvas(), **data.get("canvas", {})},
            "subject_colors": data.get("subject_colors", {})}


def save_data(data):
    """Write via a temporary file, so a crash mid-save can't leave a half-written file."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    tmp = DATA_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2), encoding="utf-8")
    os.replace(tmp, DATA_FILE)


# ---------- Canvas calendar feed ----------
# Canvas offers every user a private calendar link (Calendar -> "Calendar Feed") in the
# standard iCalendar format. Assignments appear in it as events whose UID mentions
# "assignment" and whose title ends with the course in brackets: "Homework 5 [DD2100 ...]".

FEED_TIMEOUT = 20  # seconds
COURSE_IN_TITLE = re.compile(r"^(.*\S)\s*\[([^\[\]]+)\]\s*$")
COURSE_CODE = re.compile(r"\b([A-Z]{2,3}\d{3,4}[A-Z]?)\b")  # e.g. DD2100, SF1625


class FeedError(Exception):
    """A sync problem, with a message meant for the user."""


def normalize_feed_url(text):
    url = text.strip()
    if url.startswith("webcal://"):
        url = "https://" + url[len("webcal://"):]
    if not url.startswith("https://"):
        raise FeedError("That doesn't look like a Canvas calendar link (it should start with https://).")
    return url


def fetch_feed(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Deadlines app"})
    try:
        with urllib.request.urlopen(request, timeout=FEED_TIMEOUT) as response:
            text = response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as err:
        raise FeedError(f"Canvas didn't accept this link (error {err.code}). "
                        "Copy it again from Canvas's Calendar Feed.") from err
    except (urllib.error.URLError, TimeoutError, OSError) as err:
        raise FeedError("Couldn't reach Canvas. Check your internet connection and try again.") from err
    if "BEGIN:VCALENDAR" not in text:
        raise FeedError("That link didn't return a calendar. Copy the Calendar Feed link from Canvas.")
    return text


def parse_ics_events(text):
    """Minimal iCalendar reader: a list of {PROPERTY: (value, [params])} per VEVENT."""
    lines = []
    for raw in text.replace("\r\n", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]  # folded continuation line
        else:
            lines.append(raw)
    events, current = [], None
    for line in lines:
        if line == "BEGIN:VEVENT":
            current = {}
        elif line == "END:VEVENT" and current is not None:
            events.append(current)
            current = None
        elif current is not None and ":" in line:
            key, value = line.split(":", 1)
            name, *params = key.split(";")
            current[name.upper()] = (value, params)
    return events


def ics_text(value):
    return (value.replace("\\n", "\n").replace("\\N", "\n").replace("\\,", ",")
            .replace("\\;", ";").replace("\\\\", "\\"))


def ics_when(value, params):
    """(local date, "HH:MM" or "" for all-day) from a DTSTART value."""
    if "VALUE=DATE" in params or len(value) == 8:
        return date(int(value[:4]), int(value[4:6]), int(value[6:8])), ""
    moment = datetime.strptime(value[:15], "%Y%m%dT%H%M%S")
    if value.endswith("Z"):  # UTC: convert to this computer's time zone
        moment = moment.replace(tzinfo=timezone.utc).astimezone()
    return moment.date(), moment.strftime("%H:%M")


def canvas_assignments(text):
    """Assignments in a Canvas calendar feed, as plain dicts."""
    found = []
    for event in parse_ics_events(text):
        uid = event.get("UID", ("", []))[0]
        if "assignment" not in uid or "DTSTART" not in event:
            continue  # skip ordinary calendar events (lectures etc.)
        summary = ics_text(event.get("SUMMARY", ("", []))[0]).strip()
        match = COURSE_IN_TITLE.match(summary)
        title, course = (match.group(1), match.group(2).strip()) if match else (summary, "Other")
        code = COURSE_CODE.search(course)
        due, time = ics_when(*event["DTSTART"])
        found.append({"uid": uid, "title": title, "course": course,
                      "code": code.group(1) if code else course,
                      "due": due.isoformat(), "time": time, "url": event.get("URL", ("", []))[0]})
    return sorted(found, key=lambda a: (a["due"], a["time"], a["title"]))
