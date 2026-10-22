// Canvas calendar feed logic for the phone app: the same rules as the PC version's core.py.
//
// Canvas offers every user a private calendar link (Calendar -> "Calendar Feed") in the
// standard iCalendar format. Assignments appear in it as events whose UID mentions
// "assignment" and whose title ends with the course in brackets: "Homework 5 [DD2100 ...]".
.pragma library

const COURSE_IN_TITLE = /^(.*\S)\s*\[([^\[\]]+)\]\s*$/
const COURSE_CODE = /\b([A-Z]{2,3}\d{3,4}[A-Z]?)\b/   // e.g. DD2100, SF1625

function pad(n) { return String(n).padStart(2, "0") }

function isoDate(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }

// {url} or {error: message for the user}
function normalizeFeedUrl(text) {
    let url = text.trim()
    if (url.startsWith("webcal://")) url = "https://" + url.slice("webcal://".length)
    if (!url.startsWith("https://"))
        return { error: "That doesn't look like a Canvas calendar link (it should start with https://)." }
    return { url: url }
}

// Minimal iCalendar reader: a list of {PROPERTY: [value, [params]]} per VEVENT.
function parseIcsEvents(text) {
    const lines = []
    for (const raw of text.replace(/\r\n/g, "\n").split("\n")) {
        if ((raw[0] === " " || raw[0] === "\t") && lines.length) lines[lines.length - 1] += raw.slice(1)   // folded line
        else lines.push(raw)
    }
    const events = []
    let current = null
    for (const line of lines) {
        if (line === "BEGIN:VEVENT") current = {}
        else if (line === "END:VEVENT" && current !== null) { events.push(current); current = null }
        else if (current !== null && line.indexOf(":") >= 0) {
            const at = line.indexOf(":")
            const [name, ...params] = line.slice(0, at).split(";")
            current[name.toUpperCase()] = [line.slice(at + 1), params]
        }
    }
    return events
}

function icsText(value) {
    return value.split("\\n").join("\n").split("\\N").join("\n").split("\\,").join(",")
                .split("\\;").join(";").split("\\\\").join("\\")
}

// {due: "YYYY-MM-DD", time: "HH:MM" or "" for all-day} from a DTSTART value, in this phone's time zone.
function icsWhen(value, params) {
    const y = +value.slice(0, 4), mo = +value.slice(4, 6) - 1, d = +value.slice(6, 8)
    if (params.indexOf("VALUE=DATE") >= 0 || value.length === 8)
        return { due: isoDate(new Date(y, mo, d)), time: "" }
    const h = +value.slice(9, 11), mi = +value.slice(11, 13), s = +value.slice(13, 15)
    const moment = value.endsWith("Z") ? new Date(Date.UTC(y, mo, d, h, mi, s)) : new Date(y, mo, d, h, mi, s)
    return { due: isoDate(moment), time: pad(moment.getHours()) + ":" + pad(moment.getMinutes()) }
}

// Assignments in a Canvas calendar feed, as plain objects sorted by due date and time.
function canvasAssignments(text) {
    const found = []
    for (const event of parseIcsEvents(text)) {
        const uid = (event.UID || [""])[0]
        if (uid.indexOf("assignment") < 0 || !event.DTSTART) continue   // skip lectures etc.
        const summary = icsText((event.SUMMARY || [""])[0]).trim()
        const match = COURSE_IN_TITLE.exec(summary)
        const title = match ? match[1] : summary
        const course = match ? match[2].trim() : "Other"
        const code = COURSE_CODE.exec(course)
        const when = icsWhen(event.DTSTART[0], event.DTSTART[1])
        found.push({ uid: uid, title: title, course: course, code: code ? code[1] : course,
                     due: when.due, time: when.time, url: (event.URL || [""])[0] })
    }
    const key = a => a.due + " " + a.time + " " + a.title
    return found.sort((a, b) => key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0)
}
