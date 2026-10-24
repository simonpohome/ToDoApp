// Deadlines for Android: the whole app (Qt Quick, no Python). The same features as the PC version
// (../Main.qml), laid out for a phone: a bottom tab bar, the add form as a bottom sheet, long-press
// to reorder cards, swipe the calendar between months, pull down on Courses to sync with Canvas.
import QtQuick
// The Basic style by name: a plain "QtQuick.Controls" makes the .apk carry every style (~13 MB more).
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Shapes
import QtCore
import "logic.js" as Logic

ApplicationWindow {
    id: root
    width: 390
    height: 844
    visible: true
    title: "Deadlines"
    color: bg
    // On the phone, draw behind the status and navigation bars; the safe-area insets keep
    // everything clear of them.
    flags: Qt.platform.os === "android" ? (Qt.Window | Qt.ExpandedClientAreaHint) : Qt.Window
    // ApplicationWindow keeps its content inside the safe area by itself; let it reach the top and
    // bottom edges instead (the page colour and the dimmed backdrop go behind the bars) and keep
    // the header, tab bar and add-form clear of the bars with topInset / bottomInset below.
    topPadding: 0
    bottomPadding: 0
    // The rounded font (Nunito, see fonts/OFL.txt) is the app's default font, set in main.cpp
    // (or preview.py), so every Text uses it without saying so.

    // ---------- Look ----------
    // Light or dark: "system" follows the phone; "light"/"dark" are picked in Settings. (Only read
    // the phone's scheme: asking Qt to switch it on Android made the window stop drawing.)
    property string theme: "system"
    readonly property bool dark: theme === "dark"
                                 || (theme === "system" && Qt.styleHints.colorScheme === Qt.ColorScheme.Dark)
    // The phone's status/navigation bar icons: light on the dark look, dark on the light one.
    function applyBars() { if (hasWidget) widgetBridge.setDarkBars(dark) }
    onDarkChanged: applyBars()
    onThemeChanged: if (loaded) updateWidget()   // the home-screen widget switches along

    // Light: the soft blue page with white cards. Dark: a deep blue-grey page with lighter cards,
    // and the same pastels a little softer so they don't glow.
    readonly property color bg: dark ? "#121821" : "#e3eefb"
    readonly property color cardColor: dark ? "#1d2430" : "#ffffff"
    readonly property color textColor: dark ? "#eef2f7" : "#1c1c1e"
    readonly property color muted: dark ? "#8b95a5" : "#8e8e93"
    readonly property color line: dark ? "#2d3746" : "#dde6f1"         // ring tracks, connectors, pressed states
    readonly property color field: dark ? "#262f3c" : "#eff5fc"        // input fields inside cards
    readonly property color accent: dark ? "#e7a0bd" : "#f5a8c5"       // pastel pink
    readonly property color accentHover: dark ? "#f1b8cf" : "#f08db5"
    readonly property color accentText: dark ? "#5c1534" : "#7a2348"   // deep pink text on the pink accent
    readonly property color doneColor: dark ? "#5c6676" : "#c7c7cc"
    readonly property color green: dark ? "#7cc795" : "#8fd6a5"        // more than a week left
    readonly property color yellow: dark ? "#e3c66c" : "#f5d77a"       // 3-7 days left
    readonly property color red: dark ? "#e39595" : "#f2a0a0"          // 2 days or less
    readonly property color purple: dark ? "#b29de6" : "#c4b1f5"       // no due date
    readonly property color overdueText: dark ? "#f08e90" : "#d9686b"
    readonly property color deleteX: "#9b1c1c"
    readonly property color tabTrack: dark ? "#19202a" : "#d2e2f6"
    readonly property color tagText: "#1c1c1e"   // text on the pastel subject tags, in both modes
    // The pill behind the chosen tab / setting. (In dark mode lighter than what it sits on, so it
    // stands out the way the light one does.)
    readonly property color selectedOnCard: dark ? "#333d4e" : field
    readonly property color selectedOnField: dark ? "#3c4758" : cardColor
    readonly property int autoSyncMinutes: 30
    // Subject colours: new subjects take the first unused one (kept clear of the green/yellow/red
    // that mean time left, and of the pink accent).
    readonly property var subjectPalette: ["#a9c8f5", "#cdb8f3", "#8fd8cf", "#f8c18b", "#f4b4d6",
                                           "#c2e39a", "#e6d3b3", "#b8c3d9", "#e3b8ef", "#9fdcf0"]

    // Space taken by the status bar, camera cutout and navigation bar (0 on a PC).
    readonly property real topInset: contentItem.SafeArea.margins.top
    readonly property real bottomInset: contentItem.SafeArea.margins.bottom

    // ---------- State ----------
    property string currentTab: "mine"
    property bool formOpen: false
    property var subjects: []
    property var subjectColors: ({})   // lowercase subject -> "#rrggbb"
    property string calDay: isoDate(today())   // Calendar tab: the selected day and shown month
    property int calMonth: new Date().getMonth()
    property int calYear: new Date().getFullYear()
    property var canvas: defaultCanvas()
    property bool syncing: false
    property string syncMessage: ""
    property bool loaded: false
    property int rev: 0               // bumped on every change; bindings that read the models use it
    property Item draggedCard: null
    property var lastDeleted: null    // {index, task} for "Undo"

    ListModel { id: tasks }   // display order; each task has a nested "steps" list

    // ---------- Helpers ----------
    function pad(n) { return String(n).padStart(2, "0") }
    function uid() { let s = ""; for (let i = 0; i < 32; i++) s += Math.floor(Math.random() * 16).toString(16); return s }
    function today() { const t = new Date(); t.setHours(0, 0, 0, 0); return t }
    function parseDate(iso) { const p = iso.split("-"); return new Date(p[0], p[1] - 1, p[2]) }
    function isoDate(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }
    // Deadlines may have no date (due ""): they're purple, say "No due date", and sort last.
    function daysLeft(iso) { return iso ? Math.round((parseDate(iso) - today()) / 86400000) : NaN }
    function relative(n) {
        if (n === 0) return "today"
        if (n === 1) return "tomorrow"
        if (n === -1) return "yesterday"
        return n > 0 ? "in " + n + " days" : (-n) + " days ago"
    }
    function timeColor(iso) { if (!iso) return purple; const n = daysLeft(iso); return n > 7 ? green : n > 2 ? yellow : red }
    function whenText(iso, time) { return iso ? Qt.formatDate(parseDate(iso), "ddd d MMM") + (time ? " " + time : "") : "No due date" }
    function overdue(iso) { return !!iso && daysLeft(iso) < 0 }
    function blend(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }
    function progressColor(p) { return p <= 50 ? blend(red, yellow, p / 50) : blend(yellow, green, (p - 50) / 50) }
    function progressOf(steps, done) {
        if (steps.count === 0) return done ? 100 : 0
        let n = 0
        for (let i = 0; i < steps.count; i++) if (steps.get(i).done) n++
        return Math.round(100 * n / steps.count)
    }
    function doneStepIds(t) {
        const ids = []
        for (let s = 0; s < t.steps.count; s++) if (t.steps.get(s).done) ids.push(t.steps.get(s).stepId)
        return ids
    }
    function colorKey(subject) { return subject.trim().toLowerCase() }
    function subjectColor(subject) { return subjectColors[colorKey(subject)] || line }
    function ensureColor(subject) {
        const key = colorKey(subject)
        if (!key || subjectColors[key]) return
        const used = Object.values(subjectColors)
        const free = subjectPalette.filter(c => used.indexOf(c) < 0)
        const next = Object.assign({}, subjectColors)
        next[key] = free.length ? free[0] : subjectPalette[used.length % subjectPalette.length]
        subjectColors = next
    }
    function setSubjectColor(subject, color) {
        const next = Object.assign({}, subjectColors)
        next[colorKey(subject)] = color
        subjectColors = next
        changed()
    }

    // ---------- Loading & saving ----------
    // Saved on the phone as one JSON text, in the same format as the PC version's deadlines.json.
    // (setValue() writes straight away; a bound property would only be written on a timer, which a
    // phone can cut short by closing the app in the background.)
    Settings { id: store }

    function defaultCanvas() { return { feed_url: "", last_sync: null, assignments: [], hidden: [], collapsed: [] } }
    function fromJson(t) {
        return {
            taskId: t.id || uid(), subject: t.subject || "", assignment: t.assignment || "",
            due: t.due || "", time: t.time || "", done: !!t.done, collapsed: !!t.collapsed,
            pinned: !!t.pinned, canvasUid: t.canvas_uid || "",
            stepsBeforeDone: t.steps_before_done ? JSON.stringify(t.steps_before_done) : "",
            steps: (t.subtasks || []).map(s => ({ stepId: s.id || uid(), text: s.text, done: !!s.done }))
        }
    }
    function toJson(t) {
        const steps = []
        for (let s = 0; s < t.steps.count; s++) {
            const st = t.steps.get(s)
            steps.push({ id: st.stepId, text: st.text, done: st.done })
        }
        const o = { id: t.taskId, subject: t.subject, assignment: t.assignment, due: t.due, done: t.done, subtasks: steps }
        if (t.time) o.time = t.time
        if (t.collapsed) o.collapsed = true
        if (t.pinned) o.pinned = true
        if (t.canvasUid) o.canvas_uid = t.canvasUid
        if (t.stepsBeforeDone) o.steps_before_done = JSON.parse(t.stepsBeforeDone)
        return o
    }
    function serialize() {
        const out = []
        for (let i = 0; i < tasks.count; i++) out.push(toJson(tasks.get(i)))
        return JSON.stringify({ tasks: out, subjects: subjects, canvas: canvas, subject_colors: subjectColors })
    }
    function changed() { rev++; if (loaded) saveTimer.restart() }
    function saveNow() {
        if (!loaded) return
        saveTimer.stop()
        store.setValue("data", serialize())
        store.sync()
        updateWidget()
    }

    // ---------- Home-screen widget (Android) ----------
    // main.cpp provides "widgetBridge" on the phone; the PC preview has none.
    readonly property bool hasWidget: typeof widgetBridge !== "undefined" && Qt.platform.os === "android"
    function updateWidget() {
        if (!hasWidget) return
        // The list as the Deadlines tab shows it. Dates stay dates: the widget works out
        // "today" / "in 3 days" itself, so they stay right while the app is closed.
        const out = []
        for (let i = 0; i < tasks.count; i++) {
            const t = tasks.get(i)
            out.push({ subject: t.subject, assignment: t.assignment, due: t.due, time: t.time,
                       done: t.done, pinned: t.pinned, color: String(subjectColor(t.subject)) })
        }
        // The appearance setting too, so the widget is light or dark like the app (System: the
        // widget follows the phone by itself).
        widgetBridge.update(JSON.stringify({ theme: theme, tasks: out }))
    }
    Timer { id: saveTimer; interval: 300; onTriggered: saveNow() }

    Component.onCompleted: {
        let data = {}
        try { data = JSON.parse(store.value("data", "") || "{}") } catch (e) { console.warn("Saved data unreadable:", e) }
        for (const t of (data.tasks || [])) insertTask(tasks.count, fromJson(t))
        subjects = data.subjects || []
        canvas = Object.assign(defaultCanvas(), data.canvas || {})
        subjectColors = data.subject_colors || {}
        for (const s of subjects) ensureColor(s)
        for (let i = 0; i < tasks.count; i++) ensureColor(tasks.get(i).subject)
        theme = store.value("theme", "system")
        applyBars()
        loaded = true
        rev++
        updateWidget()   // a widget placed before the app ever ran gets the list straight away
        if (canvas.feed_url) startupSync.start()
    }
    // A phone app can be closed at any time once it's in the background, so save on the way out.
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state !== Qt.ApplicationActive) saveNow()
            else if (canvas.feed_url && minutesSinceSync() >= autoSyncMinutes) syncCanvas()
        }
    }
    // Android's back button: close whatever is open first; only leave the app from the list.
    onClosing: (close) => {
        if (goBack()) close.accepted = false
        else saveNow()
    }
    function goBack() {
        // A floating keyboard leaves back to the app: put the keyboard away first.
        if (Qt.inputMethod.visible) { Qt.inputMethod.hide(); return true }
        if (colorPopup.opened) { colorPopup.close(); return true }
        if (settingsSheet.opened) { settingsSheet.close(); return true }
        if (formOpen) { formOpen = false; return true }
        if (currentTab !== "mine") { currentTab = "mine"; return true }
        return false
    }
    // The back button (and Esc on a PC preview), caught here rather than left to Qt: with a Drawer in
    // the app, an unhandled back press closed the whole app even with a sheet open.
    // One press can arrive twice (the key itself and Android's back callback, a few ms apart), so a
    // second one right after counts as the same press, or it would close the sheet and then leave.
    property double lastBack: 0
    Shortcut {
        sequences: ["Back", "Esc"]
        onActivated: {
            const now = Date.now()
            if (now - lastBack < 300) return
            lastBack = now
            if (goBack()) return
            saveNow()
            if (hasWidget) widgetBridge.moveToBack()   // to the background, as Android apps do
        }
    }

    // ---------- My deadlines ----------
    property bool stepsRoleKnown: false
    function insertTask(i, task) {
        // The very first task decides that "steps" is a list. If that task has no steps, an
        // empty list would leave it undecided, so insert one placeholder step and remove it.
        const teach = !stepsRoleKnown && task.steps.length === 0
        if (teach) task.steps = [{ stepId: "", text: "", done: false }]
        tasks.insert(i, task)
        if (teach) tasks.get(i).steps.remove(0)
        stepsRoleKnown = true
    }
    // Where a deadline belongs by date: by due date and time (no time = end of that day), and
    // deadlines without a date after all the dated ones.
    function dateKey(t) { return t.due ? t.due + " " + (t.time || "24:00") : "9999" }
    // The headings in the list: the pinned ones together, then one heading per due date.
    function groupOf(t) { return t.pinned ? "pinned" : t.due || "none" }
    function groupTitle(key) {
        if (key === "pinned") return "Pinned"
        if (key === "none") return "No due date"
        const n = daysLeft(key), day = Qt.formatDate(parseDate(key), "ddd d MMM")
        return n === 0 ? "Today · " + day : n === 1 ? "Tomorrow · " + day : n === -1 ? "Yesterday · " + day : day
    }
    // Pinned deadlines are always the first ones in the list.
    function pinnedCount() { let n = 0; while (n < tasks.count && tasks.get(n).pinned) n++; return n }
    function addTask(subject, assignment, due, time, canvasUid) {
        // Below the pinned ones, by date; the manual order of the rest is kept.
        const key = dateKey({ due: due, time: time })
        let i = pinnedCount()
        while (i < tasks.count && dateKey(tasks.get(i)) <= key) i++
        insertTask(i, { taskId: uid(), subject: subject, assignment: assignment, due: due, time: time || "",
                        done: false, collapsed: false, pinned: false, canvasUid: canvasUid || "",
                        stepsBeforeDone: "", steps: [] })
        if (!subjects.some(s => s.toLowerCase() === subject.toLowerCase())) subjects = subjects.concat([subject])
        ensureColor(subject)
        changed()
        return i
    }
    function deleteTask(i) {
        lastDeleted = { index: i, task: toJson(tasks.get(i)) }
        snackbar.show("Deleted “" + tasks.get(i).assignment + "”", true)
        const slot = repeater.itemAt(i)
        if (slot) slot.children[0].leave()   // animates out, then removes it from the model
        else removeTask(i)
    }
    // Runs here rather than in the card: removing the card ends its own script context.
    function removeTask(i) { tasks.remove(i); changed() }
    function undoDelete() {
        if (!lastDeleted) return
        insertTask(Math.min(lastDeleted.index, tasks.count), fromJson(lastDeleted.task))
        lastDeleted = null
        changed()
    }
    function toggleTask(i) {
        const t = tasks.get(i)
        if (!t.done) {
            // Completing ticks every step; remember which were ticked so a second tap undoes it exactly.
            tasks.setProperty(i, "stepsBeforeDone", JSON.stringify(doneStepIds(t)))
            tasks.setProperty(i, "done", true)
            for (let s = 0; s < t.steps.count; s++) t.steps.setProperty(s, "done", true)
        } else {
            const ticked = t.stepsBeforeDone ? JSON.parse(t.stepsBeforeDone) : []
            tasks.setProperty(i, "done", false)
            tasks.setProperty(i, "stepsBeforeDone", "")
            for (let s = 0; s < t.steps.count; s++) t.steps.setProperty(s, "done", ticked.indexOf(t.steps.get(s).stepId) >= 0)
        }
        changed()
    }
    function toggleStep(i, s) {
        const t = tasks.get(i)
        const before = doneStepIds(t)
        t.steps.setProperty(s, "done", !t.steps.get(s).done)
        let all = true
        for (let k = 0; k < t.steps.count; k++) all = all && t.steps.get(k).done
        if (all && !t.done) tasks.setProperty(i, "stepsBeforeDone", JSON.stringify(before))  // undo = last tick
        else if (!all) tasks.setProperty(i, "stepsBeforeDone", "")
        tasks.setProperty(i, "done", all)
        changed()
    }
    function addStep(i, text) {
        const t = tasks.get(i)
        t.steps.append({ stepId: uid(), text: text, done: false })
        tasks.setProperty(i, "done", false)
        tasks.setProperty(i, "stepsBeforeDone", "")
        changed()
    }
    function deleteStep(i, s) {
        const t = tasks.get(i)
        t.steps.remove(s)
        if (t.steps.count > 0) {
            let all = true
            for (let k = 0; k < t.steps.count; k++) all = all && t.steps.get(k).done
            tasks.setProperty(i, "done", all)
        }
        changed()
    }
    function toggleCollapsed(i) { tasks.setProperty(i, "collapsed", !tasks.get(i).collapsed); changed() }
    function togglePinned(i) {
        if (!tasks.get(i).pinned) {
            // Pinned: to the very top.
            tasks.setProperty(i, "pinned", true)
            tasks.move(i, 0, 1)
        } else {
            // Unpinned: back below the pinned ones, where its date belongs.
            tasks.setProperty(i, "pinned", false)
            tasks.move(i, tasks.count - 1, 1)
            const key = dateKey(tasks.get(tasks.count - 1))
            let j = pinnedCount()
            while (j < tasks.count - 1 && dateKey(tasks.get(j)) <= key) j++
            tasks.move(tasks.count - 1, j, 1)
        }
        changed()
    }
    // After a card is dragged: keep the pinned ones above the rest (in the order they're in).
    function keepPinnedFirst() {
        let k = 0
        for (let i = 0; i < tasks.count; i++) {
            if (!tasks.get(i).pinned) continue
            if (i !== k) tasks.move(i, k, 1)
            k++
        }
    }
    function removeSubject(name) { subjects = subjects.filter(s => s !== name); changed() }
    readonly property int upcoming: { rev; let n = 0; for (let i = 0; i < tasks.count; i++) if (!tasks.get(i).done) n++; return n }

    // ---------- Calendar ----------
    readonly property var tasksByDay: {   // "YYYY-MM-DD" -> that day's deadlines, by time
        rev
        const days = {}
        for (let i = 0; i < tasks.count; i++) {
            const t = tasks.get(i)
            ;(days[t.due] = days[t.due] || []).push({ index: i, subject: t.subject, assignment: t.assignment,
                                                     due: t.due, time: t.time, done: t.done })
        }
        for (const d in days) days[d].sort((a, b) => a.time.localeCompare(b.time) || a.index - b.index)
        return days
    }
    readonly property var dayTasks: tasksByDay[calDay] || []
    readonly property var monthSubjects: {   // subjects due in the shown month, for the legend
        const prefix = calYear + "-" + pad(calMonth + 1)
        const seen = {}
        for (const d in tasksByDay) if (d.startsWith(prefix))
            for (const t of tasksByDay[d]) seen[colorKey(t.subject)] = seen[colorKey(t.subject)] || t.subject
        return Object.values(seen).sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()))
    }
    function shiftCalMonth(step) {
        const d = new Date(calYear, calMonth + step, 1)
        calMonth = d.getMonth(); calYear = d.getFullYear()
    }
    function calendarToday() {
        const t = today()
        calMonth = t.getMonth(); calYear = t.getFullYear(); calDay = isoDate(t)
    }

    // ---------- Canvas ----------
    readonly property var addedUids: {
        rev
        const set = {}
        for (let i = 0; i < tasks.count; i++) if (tasks.get(i).canvasUid) set[tasks.get(i).canvasUid] = true
        return set
    }
    readonly property var courseData: {
        rev
        const now = isoDate(today())
        const groups = {}
        for (const a of canvas.assignments) if (a.due >= now) (groups[a.course] = groups[a.course] || []).push(a)
        const shown = Object.keys(groups).filter(c => canvas.hidden.indexOf(c) < 0)
        shown.sort((a, b) => (groups[a][0].code + a).localeCompare(groups[b][0].code + b))
        return shown.map(c => ({ course: c, code: groups[c][0].code, items: groups[c] }))
    }
    readonly property var removedCourses: {
        rev
        const now = isoDate(today())
        const live = {}
        for (const a of canvas.assignments) if (a.due >= now) live[a.course] = true
        return canvas.hidden.filter(c => live[c])
    }
    function setCanvas(changes) { canvas = Object.assign({}, canvas, changes); changed() }
    function minutesSinceSync() { return canvas.last_sync ? (new Date() - new Date(canvas.last_sync)) / 60000 : Infinity }
    function connectCanvas(text) {
        const r = Logic.normalizeFeedUrl(text)
        if (r.error) { syncMessage = r.error; rev++; return }
        setCanvas({ feed_url: r.url })
        syncCanvas()
    }
    function disconnectCanvas() {
        // Deadlines already added to "My deadlines" stay; they just stop updating.
        syncMessage = ""
        setCanvas({ feed_url: "", last_sync: null, assignments: [] })
    }
    property var feedRequest: null
    function syncCanvas() {
        if (!canvas.feed_url || syncing) return
        syncing = true
        syncMessage = "Syncing with Canvas…"
        const xhr = new XMLHttpRequest()
        feedRequest = xhr
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || feedRequest !== xhr) return
            feedRequest = null
            feedTimeout.stop()
            if (xhr.status === 200) {
                if (xhr.responseText.indexOf("BEGIN:VCALENDAR") < 0)
                    finishSync({ error: "That link didn't return a calendar. Copy the Calendar Feed link from Canvas." })
                else {
                    try { finishSync({ assignments: Logic.canvasAssignments(xhr.responseText) }) }
                    catch (e) { finishSync({ error: "Sync failed: " + e }) }
                }
            } else if (xhr.status === 0) {
                finishSync({ error: "Couldn't reach Canvas. Check your internet connection and try again." })
            } else {
                finishSync({ error: "Canvas didn't accept this link (error " + xhr.status + "). Copy it again from Canvas's Calendar Feed." })
            }
        }
        xhr.open("GET", canvas.feed_url)
        xhr.send()
        feedTimeout.restart()
    }
    Timer {   // give up on a download that hangs (the request then finishes with "Couldn't reach Canvas")
        id: feedTimeout
        interval: 20000
        onTriggered: if (feedRequest) feedRequest.abort()
    }
    function finishSync(result) {
        syncing = false
        if (result.error) {
            syncMessage = result.error
            if (!canvas.last_sync) setCanvas({ feed_url: "" })   // never worked: let them paste it again
            else rev++
            return
        }
        syncMessage = ""
        const now = new Date()
        setCanvas({ assignments: result.assignments, last_sync: isoDate(now) + "T" + pad(now.getHours()) + ":" + pad(now.getMinutes()) })
        // Keep added deadlines in step with Canvas (e.g. a moved due date), keeping steps and ticks.
        const byUid = {}
        for (const a of result.assignments) byUid[a.uid] = a
        for (let i = 0; i < tasks.count; i++) {
            const a = byUid[tasks.get(i).canvasUid]
            if (!a) continue
            tasks.setProperty(i, "due", a.due)
            tasks.setProperty(i, "time", a.time)
            tasks.setProperty(i, "assignment", a.title)
        }
        changed()
    }
    function addFromCanvas(items) {
        for (const a of items) if (!addedUids[a.uid]) addTask(a.code, a.title, a.due, a.time, a.uid)
    }
    function toggleCourseSetting(key, course) {
        const list = canvas[key].slice()
        const at = list.indexOf(course)
        if (at >= 0) list.splice(at, 1); else list.push(course)
        const changes = {}
        changes[key] = list
        setCanvas(changes)
    }
    Timer { id: startupSync; interval: 400; onTriggered: syncCanvas() }
    Timer { interval: autoSyncMinutes * 60000; repeat: true; running: true; onTriggered: syncCanvas() }

    // ---------- Reusable pieces ----------
    // Buttons use a MouseArea rather than a TapHandler: a MouseArea keeps the tap to itself, so a
    // button on top of another tap area (a card, a chip) never triggers both.
    component RoundIcon: Item {
        // Round button drawing a "+" or "×" (turn: 45) from two rounded bars.
        id: icon
        property color fill: "transparent"
        property color pressedFill: line
        property color mark: muted
        property real turn: 0
        property real barLength: width * 0.38
        signal clicked()
        width: 36; height: 36
        Rectangle {
            anchors.fill: parent; radius: width / 2
            color: iconTap.pressed ? icon.pressedFill : icon.fill
            Behavior on color { ColorAnimation { duration: 100 } }
        }
        Item {
            anchors.centerIn: parent; width: icon.barLength; height: icon.barLength
            rotation: icon.turn
            Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
            Repeater {
                model: 2
                Rectangle {
                    required property int index
                    anchors.centerIn: parent
                    width: icon.barLength; height: Math.max(2, icon.width * 0.07); radius: height / 2
                    rotation: index * 90
                    color: icon.mark
                }
            }
        }
        MouseArea { id: iconTap; anchors.fill: parent; onClicked: icon.clicked() }
    }

    component Chevron: Shape {
        // A chevron pointing right; turn it (rotation) to point elsewhere.
        id: chevron
        width: 12; height: 12
        property color stroke: muted
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: chevron.stroke; strokeWidth: 2.2; fillColor: "transparent"
            capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
            startX: 4; startY: 1.5
            PathLine { x: 8.5; y: 6 }
            PathLine { x: 4; y: 10.5 }
        }
    }

    component CheckMark: Shape {
        // A tick, drawn (the ✓ character isn't in every font).
        id: tick
        property color stroke: "white"
        width: 12; height: 12
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: tick.stroke; strokeWidth: 2.2; fillColor: "transparent"
            capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
            startX: tick.width * 0.12; startY: tick.height * 0.52
            PathLine { x: tick.width * 0.4; y: tick.height * 0.78 }
            PathLine { x: tick.width * 0.88; y: tick.height * 0.24 }
        }
    }

    component PinIcon: Shape {
        // A push pin.
        id: pinIcon
        property color stroke: muted
        width: 20; height: 20
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: pinIcon.stroke; strokeWidth: 2; fillColor: "transparent"
            capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
            scale: Qt.size(pinIcon.width / 24, pinIcon.height / 24)
            PathSvg { path: "M 8.5 4 L 15.5 4 M 9.5 4 L 9.5 10 L 6.5 13.5 L 17.5 13.5 L 14.5 10 L 14.5 4 M 12 13.5 L 12 20.5" }
        }
    }

    component PinButton: Item {
        // Round button with a pin; pink while the deadline is pinned to the top.
        id: pinButton
        property bool pinned: false
        signal clicked()
        width: 36; height: 36
        Rectangle {
            anchors.fill: parent; radius: width / 2
            color: pinButton.pinned ? accent : pinTap.pressed ? line : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        PinIcon { anchors.centerIn: parent; stroke: pinButton.pinned ? accentText : muted }
        MouseArea { id: pinTap; anchors.fill: parent; onClicked: pinButton.clicked() }
    }

    component SettingsIcon: Shape {
        // Two sliders: the usual "settings" sign.
        id: settingsIcon
        property color stroke: muted
        width: 22; height: 22
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: settingsIcon.stroke; strokeWidth: 2; fillColor: "transparent"
            capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
            scale: Qt.size(settingsIcon.width / 24, settingsIcon.height / 24)
            PathSvg { path: "M 4 8 L 20 8 M 4 16 L 20 16" }
        }
        ShapePath {
            strokeColor: settingsIcon.stroke; strokeWidth: 2; fillColor: cardColor
            scale: Qt.size(settingsIcon.width / 24, settingsIcon.height / 24)
            PathAngleArc { centerX: 9; centerY: 8; radiusX: 2.6; radiusY: 2.6; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            strokeColor: settingsIcon.stroke; strokeWidth: 2; fillColor: cardColor
            scale: Qt.size(settingsIcon.width / 24, settingsIcon.height / 24)
            PathAngleArc { centerX: 15; centerY: 16; radiusX: 2.6; radiusY: 2.6; startAngle: 0; sweepAngle: 360 }
        }
    }

    component Segmented: Rectangle {
        // A pill switch between a few choices, like the tab bar: [[value, label], ...].
        id: seg
        property var options: []
        property string value: ""
        signal picked(string value)
        readonly property real optionWidth: (width - 8) / Math.max(1, options.length)
        implicitHeight: 44
        radius: height / 2
        color: field
        Rectangle {
            y: 4; width: seg.optionWidth; height: seg.height - 8; radius: height / 2; color: selectedOnField
            x: 4 + Math.max(0, seg.options.findIndex(o => o[0] === seg.value)) * width
            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }
        Row {
            anchors.fill: parent; anchors.margins: 4
            Repeater {
                model: seg.options
                Item {
                    required property var modelData
                    width: seg.optionWidth; height: seg.height - 8
                    Text {
                        anchors.centerIn: parent
                        text: modelData[1]; font.pixelSize: 14; font.bold: true
                        color: seg.value === modelData[0] ? textColor : muted
                    }
                    MouseArea { anchors.fill: parent; onClicked: seg.picked(modelData[0]) }
                }
            }
        }
    }

    component Pill: Rectangle {
        // Small rounded text button.
        id: pill
        property alias text: pillLabel.text
        property color fill: field
        property color pressedFill: line
        property color labelColor: textColor
        property bool bold: true
        signal clicked()
        implicitWidth: pillLabel.implicitWidth + 30
        implicitHeight: 36
        radius: height / 2
        color: pillTap.pressed && enabled ? pressedFill : fill
        opacity: enabled ? 1 : 0.5
        Text { id: pillLabel; anchors.centerIn: parent; font.pixelSize: 13; font.bold: pill.bold; color: pill.labelColor }
        MouseArea { id: pillTap; anchors.fill: parent; onClicked: pill.clicked() }
    }

    component BigButton: Rectangle {
        // Full-width pink button ("Add deadline", "Connect").
        id: big
        property alias text: bigLabel.text
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 50; radius: 25
        color: bigTap.pressed ? accentHover : accent
        Text { id: bigLabel; anchors.centerIn: parent; font.bold: true; font.pixelSize: 15; color: accentText }
        MouseArea { id: bigTap; anchors.fill: parent; onClicked: big.clicked() }
    }

    component Field: TextField {
        id: f
        property bool invalid: false
        Layout.fillWidth: true
        implicitHeight: 48
        leftPadding: 20; rightPadding: 20
        color: textColor
        placeholderTextColor: muted
        font.pixelSize: 15
        selectByMouse: true
        background: Rectangle { radius: 24; color: field; border.width: f.invalid ? 2 : 0; border.color: red }
        onTextChanged: invalid = false
    }

    component Pie: Item {
        // Filled progress pie, red -> yellow -> green; a smiley at 100%.
        id: pie
        property int pct: 0
        width: 40; height: 40
        Rectangle { anchors.fill: parent; radius: width / 2; color: pie.pct >= 100 ? progressColor(100) : line }
        Shape {
            anchors.fill: parent
            visible: pie.pct > 0 && pie.pct < 100
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"
                fillColor: progressColor(pie.pct)
                startX: pie.width / 2; startY: pie.height / 2
                PathAngleArc {
                    centerX: pie.width / 2; centerY: pie.height / 2
                    radiusX: pie.width / 2; radiusY: pie.height / 2
                    startAngle: -90; sweepAngle: 3.6 * pie.pct
                }
                PathLine { x: pie.width / 2; y: pie.height / 2 }
            }
        }
        Item {
            anchors.fill: parent
            visible: pie.pct >= 100
            Repeater {
                model: [0.36, 0.64]
                Rectangle {
                    required property real modelData
                    x: pie.width * modelData - 3; y: pie.height * 0.38 - 3; width: 6; height: 6; radius: 3; color: "white"
                }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "white"; strokeWidth: 2.8; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: pie.width / 2; centerY: pie.height / 2; radiusX: pie.width * 0.22; radiusY: pie.width * 0.22; startAngle: 25; sweepAngle: 130 }
                }
            }
        }
    }

    component Stopwatch: Shape {
        // Small stopwatch marking previously used subjects.
        width: 16; height: 16
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: muted; strokeWidth: 1.6; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: 8; centerY: 9.5; radiusX: 5.8; radiusY: 5.8; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            strokeColor: muted; strokeWidth: 1.6; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            startX: 8; startY: 3.7; PathLine { x: 8; y: 1.6 }
            PathMove { x: 6.2; y: 1.2 } PathLine { x: 9.8; y: 1.2 }
            PathMove { x: 8; y: 9.5 } PathLine { x: 10.4; y: 7.1 }
        }
    }

    component SubjectPill: Rectangle {
        // The subject as a tag in its colour; tap to choose another colour.
        id: tag
        property string subject: ""
        property bool faded: false
        implicitWidth: tagText.implicitWidth + 18
        implicitHeight: 24
        radius: height / 2
        color: subjectColor(subject)
        opacity: faded ? 0.45 : 1
        Text {
            id: tagText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, tag.width - 18)
            text: tag.subject; elide: Text.ElideRight
            font.pixelSize: 12; font.bold: true; color: tagText
        }
        // A MouseArea rather than a TapHandler, so the tap doesn't also reach the card underneath.
        MouseArea {
            anchors.fill: parent
            anchors.margins: -6   // a bigger target than the tag itself
            onClicked: colorPopup.openFor(tag.subject)
        }
    }

    component MonthArrow: Item {
        // Round button with a big chevron for changing month: direction -1 = back, 1 = forward.
        id: arrow
        property int direction: 1
        signal clicked()
        width: 44; height: 44
        Rectangle {
            anchors.fill: parent; radius: width / 2
            color: arrowTap.pressed ? line : "transparent"
        }
        Chevron {
            anchors.centerIn: parent; width: 14; height: 14
            rotation: arrow.direction < 0 ? 180 : 0
            stroke: textColor
        }
        MouseArea { id: arrowTap; anchors.fill: parent; onClicked: arrow.clicked() }
    }

    component TabIcon: Shape {
        // Line icons for the tab bar: "list", "calendar" or "courses".
        id: tabIcon
        property string kind: "list"
        property color stroke: muted
        width: 24; height: 24
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: tabIcon.stroke; strokeWidth: 2; fillColor: "transparent"
            capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
            PathSvg {
                path: tabIcon.kind === "list"
                    ? "M 4 6.5 L 4.01 6.5 M 9 6.5 L 20 6.5 M 4 12 L 4.01 12 M 9 12 L 20 12 M 4 17.5 L 4.01 17.5 M 9 17.5 L 20 17.5"
                    : tabIcon.kind === "calendar"
                    ? "M 6 4.5 L 18 4.5 Q 20.5 4.5 20.5 7 L 20.5 18 Q 20.5 20.5 18 20.5 L 6 20.5 Q 3.5 20.5 3.5 18 L 3.5 7 Q 3.5 4.5 6 4.5 M 3.5 9.5 L 20.5 9.5 M 8 2.5 L 8 6 M 16 2.5 L 16 6 M 8 14 L 8.01 14 M 12 14 L 12.01 14 M 16 14 L 16.01 14"
                    : "M 2.5 9 L 12 4.5 L 21.5 9 L 12 13.5 Z M 6.5 11 L 6.5 16 Q 12 19.5 17.5 16 L 17.5 11 M 21.5 9 L 21.5 14"
            }
        }
    }

    component CalendarPicker: Rectangle {
        // Month calendar with round day cells; weeks start on Monday.
        id: cal
        property date selected: new Date(NaN)
        property int month: new Date().getMonth()
        property int year: new Date().getFullYear()
        signal picked(date day)
        radius: 24; color: field
        implicitHeight: calCol.implicitHeight + 20
        function show(d) {
            const base = isNaN(d.getTime()) ? new Date() : d
            month = base.getMonth(); year = base.getFullYear()
        }
        ColumnLayout {
            id: calCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                MonthArrow {
                    direction: -1
                    onClicked: { if (cal.month === 0) { cal.month = 11; cal.year-- } else cal.month-- }
                }
                Text {
                    Layout.preferredWidth: 140; horizontalAlignment: Text.AlignHCenter
                    text: Qt.locale("en_GB").standaloneMonthName(cal.month) + " " + cal.year
                    font.bold: true; color: textColor
                }
                MonthArrow {
                    onClicked: { if (cal.month === 11) { cal.month = 0; cal.year++ } else cal.month++ }
                }
                Item { Layout.fillWidth: true }
            }
            DayOfWeekRow {
                Layout.fillWidth: true
                locale: Qt.locale("en_GB")
                delegate: Text {
                    required property string shortName
                    text: shortName.slice(0, 2); color: muted; font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                }
            }
            // MonthGrid always splits its height into 6 rows. Give it the height of 6 full rows and
            // show only the weeks this month needs (4-6; the rest are next month's days, clipped away).
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: grid.weeks * 40
                clip: true
            MonthGrid {
                id: grid
                readonly property int weeks: {
                    const offset = (new Date(cal.year, cal.month, 1).getDay() + 6) % 7   // Monday = 0
                    const days = new Date(cal.year, cal.month + 1, 0).getDate()
                    return Math.ceil((offset + days) / 7)
                }
                width: parent.width
                height: 6 * 40
                // When the 1st is a Monday, Qt starts the grid with the week before; skip that row.
                y: -leadRows * 40
                readonly property int leadRows: new Date(cal.year, cal.month, 1).getDay() === 1 ? 1 : 0
                spacing: 0
                month: cal.month; year: cal.year
                locale: Qt.locale("en_GB")
                delegate: Item {
                    id: dayCell
                    required property var model
                    implicitHeight: 40
                    readonly property bool isSelected: !isNaN(cal.selected.getTime())
                        && model.date.getTime() === cal.selected.getTime()
                    readonly property bool inMonth: model.month === grid.month
                    // Hide other months' days with opacity, not visible: invisible cells are left out
                    // of the grid, which would shift every day into the wrong weekday column.
                    opacity: inMonth ? 1 : 0
                    enabled: inMonth
                    Rectangle {
                        anchors.centerIn: parent; width: 36; height: 36; radius: 18
                        color: dayCell.isSelected ? accent : dayTap.pressed ? line : "transparent"
                        border.width: dayCell.model.today && !dayCell.isSelected ? 2 : 0
                        border.color: accent
                    }
                    Text {
                        anchors.centerIn: parent
                        text: dayCell.model.day
                        font.bold: dayCell.isSelected || dayCell.model.today
                        color: dayCell.isSelected ? accentText : dayCell.model.date < today() ? muted : textColor
                    }
                    TapHandler { id: dayTap; onTapped: cal.picked(dayCell.model.date) }
                }
            }
            }
        }
    }

    component ClockFace: Item {
        // Round clock for picking a time by tapping or dragging. Hours: 1-12 on the outer ring,
        // 13-23 and 00 on the inner ring. Minutes: one ring, any minute by angle.
        id: clock
        property bool minuteMode: false
        property int hour: 0
        property int minute: 0
        signal picked()       // hour or minute changed by tapping/dragging
        signal hourPicked()   // finger lifted after choosing an hour: on to the minutes
        signal minutePicked() // finger lifted after choosing a minute: the time is done
        width: 260; height: 260
        readonly property real r: width / 2
        readonly property real outerR: r - 24
        readonly property real innerR: r - 62
        readonly property real angle: minuteMode ? minute * 6 : (hour % 12) * 30   // degrees from 12 o'clock
        readonly property real handLength: minuteMode || (hour >= 1 && hour <= 12) ? outerR : innerR

        function pick(x, y) {
            const dx = x - r, dy = y - r
            const degrees = (Math.atan2(dx, -dy) * 180 / Math.PI + 360) % 360
            if (minuteMode) {
                minute = Math.round(degrees / 6) % 60
            } else {
                const i = Math.round(degrees / 30) % 12
                const inner = Math.hypot(dx, dy) < (outerR + innerR) / 2
                hour = inner ? (i === 0 ? 0 : i + 12) : (i === 0 ? 12 : i)
            }
            picked()
        }

        Rectangle { anchors.fill: parent; radius: width / 2; color: cardColor }
        Rectangle {   // the hand
            x: clock.r - 1; y: clock.r - clock.handLength
            width: 2; height: clock.handLength
            transformOrigin: Item.Bottom; rotation: clock.angle
            antialiasing: true; color: accent
        }
        Rectangle { x: clock.r - 4; y: clock.r - 4; width: 8; height: 8; radius: 4; color: accent }
        Rectangle {   // the pink knob behind the chosen number
            readonly property real rad: clock.angle * Math.PI / 180
            width: 38; height: 38; radius: 19; color: accent
            x: clock.r + clock.handLength * Math.sin(rad) - 19
            y: clock.r - clock.handLength * Math.cos(rad) - 19
        }
        Repeater {   // outer ring: hours 1-12, or minutes 00-55
            model: 12
            Text {
                required property int index
                readonly property int value: clock.minuteMode ? index * 5 : (index === 0 ? 12 : index)
                readonly property real rad: index * 30 * Math.PI / 180
                x: clock.r + clock.outerR * Math.sin(rad) - width / 2
                y: clock.r - clock.outerR * Math.cos(rad) - height / 2
                text: clock.minuteMode ? pad(value) : value
                font.pixelSize: 16; font.bold: true
                color: (clock.minuteMode ? clock.minute : clock.hour) === value ? accentText : textColor
            }
        }
        Repeater {   // inner ring: hours 13-23 and 00
            model: 12
            Text {
                required property int index
                readonly property int value: index === 0 ? 0 : index + 12
                readonly property real rad: index * 30 * Math.PI / 180
                visible: !clock.minuteMode
                x: clock.r + clock.innerR * Math.sin(rad) - width / 2
                y: clock.r - clock.innerR * Math.cos(rad) - height / 2
                text: pad(value)
                font.pixelSize: 13; font.bold: true
                color: clock.hour === value ? accentText : muted
            }
        }
        MouseArea {
            anchors.fill: parent
            preventStealing: true   // dragging round the clock mustn't scroll the sheet
            onPressed: (mouse) => clock.pick(mouse.x, mouse.y)
            onPositionChanged: (mouse) => clock.pick(mouse.x, mouse.y)
            onReleased: clock.minuteMode ? clock.minutePicked() : clock.hourPicked()
        }
    }

    component TimeDigits: TextField {
        // One of the two big "HH : MM" boxes above the clock; type into it, or tap it to pick on the clock.
        id: digits
        property bool active: false   // the half of the time the clock is showing
        implicitWidth: 72; implicitHeight: 56
        padding: 0
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        font.pixelSize: 30; font.bold: true
        color: active ? accentText : textColor
        selectionColor: accentHover; selectedTextColor: accentText
        maximumLength: 2
        inputMethodHints: Qt.ImhDigitsOnly
        background: Rectangle { radius: 18; color: digits.active ? accent : "transparent" }
        onActiveFocusChanged: if (activeFocus) Qt.callLater(selectAll)   // typing replaces what's there
    }

    Popup {
        // Choose a subject's colour (opened by tapping a subject tag).
        id: colorPopup
        property string subject: ""
        function openFor(subject) { colorPopup.subject = subject; open() }
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        modal: true
        dim: true
        padding: 20
        background: Rectangle { radius: 24; color: cardColor }
        contentItem: Column {
            spacing: 14
            Text { text: "Colour for " + colorPopup.subject; font.pixelSize: 15; font.bold: true; color: textColor }
            Grid {
                columns: 5; spacing: 12
                Repeater {
                    model: subjectPalette
                    Rectangle {
                        id: swatch
                        required property string modelData
                        width: 40; height: 40; radius: 20; color: modelData
                        CheckMark {
                            anchors.centerIn: parent
                            width: 16; height: 16; stroke: tagText
                            visible: subjectColors[colorKey(colorPopup.subject)] === swatch.modelData
                        }
                        MouseArea { anchors.fill: parent; onClicked: { setSubjectColor(colorPopup.subject, swatch.modelData); colorPopup.close() } }
                    }
                }
            }
        }
    }

    // ---------- Layout ----------
    // Header: logo, title and how many deadlines are still open.
    RowLayout {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top
                  leftMargin: 20; rightMargin: 20; topMargin: topInset + 14 }
        spacing: 12
        Rectangle {
            width: 42; height: 42; radius: 12; color: green
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "white"; strokeWidth: 4; fillColor: "transparent"
                    capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                    startX: 11.5; startY: 22
                    PathLine { x: 18.4; y: 28.9 }
                    PathLine { x: 31; y: 15.2 }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text { text: "Deadlines"; font.pixelSize: 28; font.bold: true; color: textColor }
            Text {
                Layout.fillWidth: true
                text: tasks.count ? upcoming + " upcoming" : "Nothing due yet"
                font.pixelSize: 13; color: muted; elide: Text.ElideRight
            }
        }
        // Settings (light/dark), kept out of the way in the corner.
        Item {
            width: 44; height: 44
            Rectangle {
                anchors.fill: parent; radius: width / 2
                color: settingsTap.pressed ? line : cardColor
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            SettingsIcon { anchors.centerIn: parent; stroke: textColor }
            MouseArea { id: settingsTap; anchors.fill: parent; onClicked: settingsSheet.open() }
        }
    }

    Drawer {
        // Settings, as a sheet from the bottom (swipe it down or tap outside to close).
        id: settingsSheet
        edge: Qt.BottomEdge
        width: root.width
        height: settingsCol.implicitHeight + 56 + bottomInset
        interactive: opened   // swipe down to close; no opening by swiping up from the screen edge
        dim: true
        background: Rectangle {
            color: cardColor; radius: 28
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 28; color: cardColor }
        }
        ColumnLayout {
            id: settingsCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20; topMargin: 14 }
            spacing: 12
            Rectangle { Layout.alignment: Qt.AlignHCenter; width: 44; height: 5; radius: 2.5; color: line }
            Text { text: "Settings"; font.pixelSize: 20; font.bold: true; color: textColor }
            Text { Layout.topMargin: 4; text: "Appearance"; font.pixelSize: 14; font.bold: true; color: textColor }
            Segmented {
                Layout.fillWidth: true
                options: [["system", "System"], ["light", "Light"], ["dark", "Dark"]]
                value: theme
                onPicked: (value) => { theme = value; store.setValue("theme", value); store.sync() }
            }
            Text {
                Layout.fillWidth: true; wrapMode: Text.Wrap
                text: "System follows your phone's light or dark setting."
                font.pixelSize: 13; color: muted
            }
        }
    }

    // The three tabs side by side: swipe between them, or tap the tab bar (which slides there).
    readonly property var tabKeys: ["mine", "calendar", "courses"]
    onCurrentTabChanged: pages.setCurrentIndex(tabKeys.indexOf(currentTab))
    SwipeView {
        id: pages
        anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; topMargin: 12 }
        clip: true
        onCurrentIndexChanged: currentTab = tabKeys[currentIndex]
        // Where the pages are, following the finger: 0 = Deadlines, 1 = Calendar, 2 = Courses
        // (in between while swiping). The tab bar's pill and the + button follow it.
        readonly property real position: width > 0 ? contentItem.contentX / width : currentIndex
        // Room at the bottom of each page for the tab bar (and the + button) floating over it.
        readonly property real bottomRoom: tabBar.height + bottomInset + 100

        // ===== My deadlines =====
        // A Column in a scroll area (like the PC version): every card's position is recalculated
        // whenever anything changes and the "move" transition glides cards there.
        Flickable {
            id: list
            contentWidth: width
            contentHeight: column.implicitHeight + pages.bottomRoom
            clip: true
            interactive: draggedCard === null
            boundsBehavior: Flickable.DragOverBounds

            // On the page itself, not in the scrolling content: wherever the list was scrolled
            // to before the last card went, the hint stays in view.
            Text {
                parent: list
                anchors.horizontalCenter: parent.horizontalCenter
                y: 120
                visible: tasks.count === 0
                text: "No deadlines yet.\nTap + to add one."
                horizontalAlignment: Text.AlignHCenter; color: muted; font.pixelSize: 16; lineHeight: 1.2
            }

            // While dragging a card near the top or bottom, scroll that way.
            Timer {
                interval: 16; repeat: true
                running: draggedCard !== null
                onTriggered: {
                    const c = draggedCard
                    const maxY = Math.max(0, list.contentHeight - list.height)
                    if (c.y < 40) list.contentY = Math.max(0, list.contentY - 10)
                    else if (c.y + c.height > list.height - pages.bottomRoom + 60)
                        list.contentY = Math.min(maxY, list.contentY + 10)
                }
            }

            Column {
                id: column
                x: 16
                width: list.width - 32
                spacing: 12
                // (New cards fade in by themselves, see "appear": an "add" transition here gets cut
                // short when several cards arrive at once and leaves them half see-through.)
                move: Transition { NumberAnimation { property: "y"; duration: 240; easing.type: Easing.OutCubic } }

                Repeater {
                    id: repeater
                    model: loaded ? tasks : null

                    // Each card sits in a drop slot; dragging a card over another slot moves it there.
                    delegate: DropArea {
                        id: slot
                        required property int index
                        required property var model
                        width: column.width
                        height: head.height + card.implicitHeight * card.leaveScale
                        clip: card.leaveScale < 1
                        // A date heading over the first card of each day (and over the pinned ones).
                        readonly property string group: groupOf(slot.model)
                        readonly property bool groupStart: { rev; return slot.index === 0 || groupOf(tasks.get(slot.index - 1)) !== group }
                        Text {
                            id: head
                            visible: slot.groupStart
                            height: visible ? implicitHeight : 0
                            topPadding: slot.index > 0 ? 10 : 0
                            bottomPadding: 8
                            leftPadding: 6
                            text: groupTitle(slot.group)
                            font.pixelSize: 13; font.bold: true
                            color: slot.group === "pinned" ? textColor : overdue(slot.group) ? overdueText : muted
                        }
                        opacity: 0
                        scale: 0.96
                        Component.onCompleted: appear.start()
                        ParallelAnimation {
                            id: appear
                            NumberAnimation { target: slot; property: "opacity"; to: 1; duration: 240 }
                            NumberAnimation { target: slot; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                        }
                        onEntered: (drag) => {
                            const from = drag.source.taskIndex
                            if (from !== undefined && from !== slot.index) tasks.move(from, slot.index, 1)
                        }

                        Rectangle {
                            id: card
                            readonly property int taskIndex: slot.index
                            // (steps can be briefly missing while a deleted card animates out)
                            readonly property int stepCount: { rev; return slot.model.steps ? slot.model.steps.count : 0 }
                            readonly property int pct: { rev; return slot.model.steps ? progressOf(slot.model.steps, slot.model.done) : 0 }
                            readonly property color mark: slot.model.done ? doneColor : timeColor(slot.model.due)
                            property bool addingStep: false
                            property bool held: false       // long-pressed: being dragged to a new place
                            property real holdOffset: 0     // where the finger is on the card
                            property real leaveScale: 1     // shrinks to 0 while the card is deleted
                            // Closing the steps also closes the new-step input.
                            readonly property bool collapsed: slot.model.collapsed
                            onCollapsedChanged: if (collapsed) { stepInput.text = ""; addingStep = false }

                            function leave() {   // fade and shrink away, then really delete
                                if (leaving.running) return
                                leaving.start()
                            }
                            SequentialAnimation {
                                id: leaving
                                ParallelAnimation {
                                    NumberAnimation { target: card; property: "opacity"; to: 0; duration: 180 }
                                    NumberAnimation { target: card; property: "leaveScale"; to: 0; duration: 220; easing.type: Easing.InOutCubic }
                                }
                                ScriptAction { script: root.removeTask(slot.index) }
                            }
                            function openStepInput() {
                                if (slot.model.collapsed) toggleCollapsed(slot.index)
                                addingStep = true
                                stepInput.forceActiveFocus()
                            }

                            anchors.left: slot.left
                            anchors.top: head.bottom
                            width: slot.width
                            implicitHeight: content.implicitHeight + 28
                            height: implicitHeight
                            radius: 24
                            color: cardColor
                            border.width: 2
                            border.color: slot.model.done ? cardColor : mark

                            Drag.active: held
                            Drag.source: card
                            Drag.hotSpot.x: width / 2
                            Drag.hotSpot.y: height / 2

                            states: State {
                                when: card.held
                                ParentChange { target: card; parent: list }
                                AnchorChanges { target: card; anchors.left: undefined; anchors.top: undefined }
                                PropertyChanges { target: card; x: 16; z: 100; border.width: 4; scale: 1.03 }
                            }
                            transitions: Transition {
                                to: ""
                                ParentAnimation { AnchorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                NumberAnimation { property: "scale"; duration: 160 }
                            }

                            ColumnLayout {
                                id: content
                                anchors { left: parent.left; right: parent.right; top: parent.top
                                          leftMargin: 18; rightMargin: 14; topMargin: 14 }
                                spacing: 0

                                // Subject/date, title and progress: tap to tick, long-press to move the card.
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: Math.max(infoCol.implicitHeight, cardPie.height)
                                    // Below the text, so the subject tag on top gets its own taps.
                                    MouseArea {
                                        id: grab
                                        anchors.fill: parent
                                        pressAndHoldInterval: 350
                                        preventStealing: card.held
                                        onClicked: toggleTask(slot.index)
                                        onPressAndHold: (mouse) => {
                                            card.holdOffset = grab.mapToItem(card, mouse.x, mouse.y).y
                                            card.held = true
                                            draggedCard = card
                                        }
                                        onPositionChanged: (mouse) => {
                                            if (!card.held) return
                                            const p = grab.mapToItem(list, mouse.x, mouse.y)
                                            card.y = Math.max(0, Math.min(list.height - card.height, p.y - card.holdOffset))
                                        }
                                        function drop() {
                                            if (!card.held) return
                                            card.Drag.drop()
                                            card.held = false
                                            draggedCard = null
                                            keepPinnedFirst()
                                            changed()   // save the new order
                                        }
                                        onReleased: drop()
                                        onCanceled: drop()
                                    }
                                    ColumnLayout {
                                        id: infoCol
                                        anchors { left: parent.left; right: cardPie.left; top: parent.top; rightMargin: 10 }
                                        spacing: 4
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            PinIcon {   // shows this one is pinned to the top
                                                visible: slot.model.pinned
                                                width: 16; height: 16
                                                stroke: slot.model.done ? doneColor : textColor
                                            }
                                            Rectangle { width: 10; height: 10; radius: 5; color: card.mark }
                                            SubjectPill {
                                                Layout.maximumWidth: 130
                                                subject: slot.model.subject
                                                faded: slot.model.done
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                // (the date is in the heading above, except for pinned ones)
                                                text: slot.model.pinned ? whenText(slot.model.due, slot.model.time) : slot.model.time
                                                font.pixelSize: 13
                                                font.strikeout: slot.model.done
                                                color: slot.model.done ? doneColor
                                                     : overdue(slot.model.due) ? overdueText : muted
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: slot.model.assignment
                                            wrapMode: Text.Wrap
                                            font.pixelSize: 17; font.bold: true
                                            font.strikeout: slot.model.done
                                            color: slot.model.done ? doneColor : textColor
                                        }
                                        Text {
                                            visible: slot.model.due !== ""   // (no date: nothing to count down)
                                            text: relative(daysLeft(slot.model.due))
                                            font.pixelSize: 13
                                            color: slot.model.done ? doneColor : overdue(slot.model.due) ? overdueText : muted
                                        }
                                    }
                                    Pie { id: cardPie; anchors.right: parent.right; anchors.top: parent.top; pct: card.pct }
                                }

                                // Steps, joined to the task by a line; slide shut with "Hide steps".
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: card.stepCount > 0 && !slot.model.collapsed ? stepsCol.implicitHeight + 8 : 0
                                    clip: true
                                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    Rectangle { x: 4; y: 8; width: 2; height: Math.max(0, stepsCol.implicitHeight - 20); color: line }
                                    ColumnLayout {
                                        id: stepsCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 4; topMargin: 8 }
                                        spacing: 0
                                        Repeater {
                                            model: slot.model.steps
                                            delegate: RowLayout {
                                                id: step
                                                required property int index
                                                required property string text
                                                required property bool done
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 42
                                                spacing: 10
                                                Rectangle { width: 14; height: 2; color: line }
                                                Rectangle {
                                                    width: 24; height: 24; radius: 12
                                                    color: step.done ? card.mark : "transparent"
                                                    border.width: 2; border.color: card.mark
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                    CheckMark { anchors.centerIn: parent; visible: step.done }
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: step.text
                                                    elide: Text.ElideRight
                                                    font.strikeout: step.done
                                                    color: step.done ? doneColor : textColor
                                                }
                                                RoundIcon {
                                                    width: 34; height: 34; turn: 45
                                                    mark: doneColor; pressedFill: field
                                                    onClicked: deleteStep(slot.index, step.index)
                                                }
                                                // The whole row (except ×) ticks the step: an easy target for a thumb.
                                                TapHandler { onTapped: toggleStep(slot.index, step.index) }
                                            }
                                        }
                                    }
                                }

                                // New-step input, opened with "+ Step".
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: card.addingStep ? 50 : 0
                                    clip: true
                                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                    Field {
                                        id: stepInput
                                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                        implicitHeight: 42
                                        placeholderText: "New step, then Enter"
                                        // An explicit Enter key on every field: left to itself, Qt shows
                                        // "Next" on Android when another field follows, and turns that key
                                        // into Tab (focus moves on, nothing is added). Return adds the step
                                        // and closes the input ("+ Step" opens it again).
                                        EnterKey.type: Qt.EnterKeyReturn
                                        background: Rectangle { radius: 21; color: field }
                                        onAccepted: {
                                            if (text.trim()) addStep(slot.index, text.trim())
                                            text = ""
                                            card.addingStep = false
                                            focus = false
                                            Qt.inputMethod.hide()
                                        }
                                        Keys.onEscapePressed: { text = ""; card.addingStep = false }
                                        onActiveFocusChanged: if (!activeFocus && !text.trim()) card.addingStep = false
                                    }
                                }

                                // Card actions: show/hide steps, add a step, pin, delete.
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 8
                                    spacing: 8
                                    Pill {
                                        visible: card.stepCount > 0
                                        text: slot.model.collapsed ? "Show " + card.stepCount + " step" + (card.stepCount > 1 ? "s" : "")
                                                                   : "Hide steps"
                                        bold: false; labelColor: muted
                                        implicitHeight: 32
                                        onClicked: toggleCollapsed(slot.index)
                                    }
                                    Pill {
                                        text: "+ Step"
                                        bold: false; labelColor: muted
                                        implicitHeight: 32
                                        onClicked: card.openStepInput()
                                    }
                                    Item { Layout.fillWidth: true }
                                    PinButton {
                                        pinned: slot.model.pinned
                                        onClicked: togglePinned(slot.index)
                                    }
                                    RoundIcon {
                                        width: 36; height: 36; turn: 45
                                        pressedFill: red; mark: muted
                                        onClicked: deleteTask(slot.index)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ===== Calendar =====
        // The month with a dot per deadline in its subject's colour (swipe sideways for other months);
        // below it, the chosen day's deadlines.
        Flickable {
            id: calendarView
            contentWidth: width
            contentHeight: calendarCol.implicitHeight + pages.bottomRoom
            clip: true
            boundsBehavior: Flickable.DragOverBounds

            ColumnLayout {
                id: calendarCol
                x: 16
                width: calendarView.width - 32
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: monthCol.implicitHeight + 24
                    radius: 24; color: cardColor
                    ColumnLayout {
                        id: monthCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 6
                        // Arrows either side of the month; "Today" off to the right.
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 44
                            Row {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: -todayButton.width / 2 + 8
                                MonthArrow { direction: -1; onClicked: shiftCalMonth(-1) }
                                Text {
                                    width: 140; anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Qt.locale("en_GB").standaloneMonthName(calMonth) + " " + calYear
                                    font.pixelSize: 16; font.bold: true; color: textColor
                                }
                                MonthArrow { onClicked: shiftCalMonth(1) }
                            }
                            Pill {
                                id: todayButton
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: "Today"; bold: false; implicitHeight: 32
                                onClicked: calendarToday()
                            }
                        }
                        DayOfWeekRow {
                            Layout.fillWidth: true
                            locale: Qt.locale("en_GB")
                            delegate: Text {
                                required property string shortName
                                text: shortName.slice(0, 2); color: muted; font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                        // Sized like the date picker's grid: 6 full rows, clipped to this month's weeks.
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: bigGrid.weeks * bigGrid.rowHeight
                            clip: true
                        MonthGrid {
                            id: bigGrid
                            readonly property int weeks: {
                                const offset = (new Date(calYear, calMonth, 1).getDay() + 6) % 7   // Monday = 0
                                return Math.ceil((offset + new Date(calYear, calMonth + 1, 0).getDate()) / 7)
                            }
                            readonly property int rowHeight: 58
                            width: parent.width
                            height: 6 * rowHeight
                            // When the 1st is a Monday, Qt starts the grid with the week before; skip that row.
                            y: -leadRows * rowHeight
                            readonly property int leadRows: new Date(calYear, calMonth, 1).getDay() === 1 ? 1 : 0
                            spacing: 0
                            month: calMonth; year: calYear
                            locale: Qt.locale("en_GB")
                            delegate: Item {
                                id: bigCell
                                required property var model
                                implicitHeight: bigGrid.rowHeight
                                readonly property string iso: isoDate(new Date(model.year, model.month, model.day))
                                readonly property var items: tasksByDay[iso] || []
                                readonly property bool isSelected: iso === calDay
                                // Other months' days: hidden with opacity (see the date picker).
                                opacity: model.month === bigGrid.month ? 1 : 0
                                enabled: model.month === bigGrid.month
                                Rectangle {
                                    // Every day has a soft box of its own; darker while pressed.
                                    anchors.fill: parent; anchors.margins: 2; radius: 14
                                    color: monthSwipe.pressedIso === bigCell.iso ? line : field
                                    border.width: bigCell.isSelected ? 2 : 0; border.color: accent
                                }
                                Rectangle {
                                    id: dayNumber
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 6; width: 26; height: 26; radius: 13
                                    color: bigCell.model.today ? accent : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: bigCell.model.day
                                        font.bold: true; font.pixelSize: 14
                                        color: bigCell.model.today ? accentText
                                             : bigCell.iso < isoDate(today()) ? muted : textColor
                                    }
                                }
                                // A dot per deadline in its subject's colour (titles don't fit on a phone;
                                // tap the day to see them).
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: dayNumber.bottom; anchors.topMargin: 6
                                    spacing: 3
                                    Repeater {
                                        model: bigCell.items.slice(0, 3)
                                        Rectangle {
                                            required property var modelData
                                            width: 8; height: 8; radius: 4
                                            color: modelData.done ? doneColor : subjectColor(modelData.subject)
                                        }
                                    }
                                    Text {
                                        visible: bigCell.items.length > 3
                                        height: 8; verticalAlignment: Text.AlignVCenter
                                        text: "+"; font.pixelSize: 11; font.bold: true; color: muted
                                    }
                                }
                            }
                        }
                            // Over the month: tap a day to choose it, swipe sideways for another month.
                            // A sideways drag here is kept from the page swipe (preventStealing) as soon
                            // as it's clearly sideways; an up/down drag still scrolls the page.
                            MouseArea {
                                id: monthSwipe
                                anchors.fill: parent
                                property real startX: 0
                                property real startY: 0
                                property bool sideways: false
                                property string pressedIso: ""   // the day under the finger (drawn darker)
                                function dayAt(x, y) {
                                    const p = mapToItem(bigGrid.contentItem, x, y)
                                    const cell = bigGrid.contentItem.childAt(p.x, p.y)
                                    return cell && cell.enabled ? cell.iso : ""
                                }
                                onPressed: (mouse) => {
                                    startX = mouse.x; startY = mouse.y
                                    sideways = false; preventStealing = false
                                    pressedIso = dayAt(mouse.x, mouse.y)
                                }
                                onPositionChanged: (mouse) => {
                                    const dx = mouse.x - startX, dy = mouse.y - startY
                                    if (!sideways && Math.abs(dx) > 6 && Math.abs(dx) > Math.abs(dy)) {
                                        sideways = true
                                        preventStealing = true
                                        pressedIso = ""
                                    }
                                }
                                onReleased: (mouse) => {
                                    const dx = mouse.x - startX
                                    if (sideways && dx < -50) shiftCalMonth(1)
                                    else if (sideways && dx > 50) shiftCalMonth(-1)
                                    else if (!sideways && pressedIso) calDay = pressedIso
                                    pressedIso = ""
                                    preventStealing = false
                                }
                                onCanceled: { pressedIso = ""; preventStealing = false }   // the page took it (scrolling)
                            }
                        }
                        // Which colour is which subject this month.
                        Flow {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            visible: monthSubjects.length > 0
                            spacing: 6
                            Repeater {
                                model: monthSubjects
                                SubjectPill { required property string modelData; subject: modelData }
                            }
                        }
                    }
                }

                // The chosen day.
                Text {
                    Layout.leftMargin: 6; Layout.topMargin: 6
                    text: Qt.formatDate(parseDate(calDay), "dddd d MMMM") + "  ·  " + relative(daysLeft(calDay))
                    font.pixelSize: 16; font.bold: true; color: textColor
                }
                Text {
                    Layout.leftMargin: 6
                    visible: dayTasks.length === 0
                    text: "Nothing due this day."
                    color: muted
                }
                Repeater {
                    model: dayTasks
                    Rectangle {
                        id: dayRow
                        required property var modelData
                        readonly property color mark: modelData.done ? doneColor : timeColor(modelData.due)
                        Layout.fillWidth: true
                        implicitHeight: 56; radius: 22; color: cardColor
                        border.width: 2; border.color: modelData.done ? cardColor : mark
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 16
                            spacing: 10
                            Rectangle {   // tick it off from here too
                                width: 24; height: 24; radius: 12
                                color: dayRow.modelData.done ? dayRow.mark : "transparent"
                                border.width: 2; border.color: dayRow.mark
                                CheckMark { anchors.centerIn: parent; visible: dayRow.modelData.done }
                            }
                            SubjectPill {
                                Layout.maximumWidth: 110
                                subject: dayRow.modelData.subject
                                faded: dayRow.modelData.done
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: dayRow.modelData.assignment
                                font.bold: true; font.strikeout: dayRow.modelData.done
                                color: dayRow.modelData.done ? doneColor : textColor
                            }
                            Text {
                                visible: dayRow.modelData.time !== ""
                                text: dayRow.modelData.time; font.pixelSize: 13; color: muted
                            }
                        }
                        TapHandler { onTapped: toggleTask(dayRow.modelData.index) }
                    }
                }
            }
        }

        // ===== Courses (Canvas) =====
        ListView {
            id: courseList
            model: courseData
            spacing: 12
            clip: true
            boundsBehavior: Flickable.DragOverBounds
            // Pull down past the top and let go to sync.
            readonly property bool pulledFar: verticalOvershoot < -80
            onDragEnded: if (pulledFar && canvas.feed_url) syncCanvas()

            header: Item {
                width: courseList.width
                height: headerCol.implicitHeight + 12
                // Shown above the list while pulling down.
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: -height - 18
                    visible: !!canvas.feed_url && courseList.verticalOvershoot < -20
                    text: courseList.pulledFar ? "Release to sync" : "Pull to sync"
                    color: muted; font.pixelSize: 13
                }
                ColumnLayout {
                    id: headerCol
                    x: 16
                    width: parent.width - 32
                    spacing: 10

                    // Not connected: how to find the link, and where to paste it.
                    Rectangle {
                        Layout.fillWidth: true
                        visible: !canvas.feed_url
                        implicitHeight: connectCol.implicitHeight + 40
                        radius: 24; color: cardColor
                        ColumnLayout {
                            id: connectCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20; topMargin: 18 }
                            spacing: 8
                            Text { text: "Connect Canvas"; font.pixelSize: 19; font.bold: true; color: textColor }
                            Text {
                                Layout.fillWidth: true; wrapMode: Text.Wrap; color: textColor; lineHeight: 1.3
                                // The Canvas app doesn't show the feed link, so this goes through the website.
                                text: "1.  Open Canvas in your phone's web browser and log in.\n"
                                    + "2.  Go to Calendar, and at the bottom tap “Calendar Feed”.\n"
                                    + "3.  Copy the link and paste it here."
                            }
                            Text {
                                Layout.fillWidth: true; wrapMode: Text.Wrap; color: muted; font.pixelSize: 13
                                text: "The link is private: it shows your deadlines without logging in, so keep it to yourself."
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                spacing: 8
                                Field {
                                    id: feedInput
                                    placeholderText: "Calendar Feed link"
                                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                                    EnterKey.type: Qt.EnterKeyGo   // (see stepInput: never left to Qt)
                                    onAccepted: connectCanvas(text)
                                }
                                Pill {
                                    text: "Paste"; implicitHeight: 48
                                    onClicked: { feedInput.selectAll(); feedInput.paste() }
                                }
                            }
                            Text {
                                Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 13
                                visible: syncMessage !== ""
                                text: syncMessage
                                color: syncing ? muted : overdueText
                            }
                            BigButton { Layout.topMargin: 6; text: "Connect"; onClicked: connectCanvas(feedInput.text) }
                        }
                    }

                    // Connected: status, Sync, Disconnect.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        visible: !!canvas.feed_url
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            font.pixelSize: 13
                            color: syncMessage && !syncing ? overdueText : muted
                            text: syncMessage ? syncMessage
                                : canvas.last_sync ? "Synced " + Qt.formatDateTime(new Date(canvas.last_sync), "ddd d MMM, HH:mm")
                                : "Not synced yet"
                        }
                        Pill { text: "Sync"; fill: cardColor; pressedFill: field; enabled: !syncing; onClicked: syncCanvas() }
                        Pill {
                            text: "Disconnect"; fill: "transparent"; pressedFill: tabTrack
                            labelColor: muted; bold: false
                            onClicked: disconnectCanvas()
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 30
                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                        visible: !!canvas.feed_url && !!canvas.last_sync && courseData.length === 0
                        text: "No upcoming assignments in your Canvas calendar."
                        color: muted; font.pixelSize: 15
                    }
                }
            }

            footer: Item {
                width: courseList.width
                height: (removedCourses.length ? 48 : 12) + pages.bottomRoom
                Pill {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 4
                    visible: removedCourses.length > 0
                    text: "Restore " + removedCourses.length + " removed course" + (removedCourses.length > 1 ? "s" : "")
                    fill: "transparent"; pressedFill: tabTrack; labelColor: muted; bold: false
                    onClicked: { for (const c of removedCourses) toggleCourseSetting("hidden", c) }
                }
            }

            delegate: Item {
                id: courseSlot
                required property var modelData
                width: courseList.width
                height: courseCard.height
                Rectangle {
                    id: courseCard
                    readonly property var modelData: courseSlot.modelData
                    readonly property bool collapsed: canvas.collapsed.indexOf(modelData.course) >= 0
                    readonly property var missing: modelData.items.filter(a => !addedUids[a.uid])
                    x: 16
                    width: parent.width - 32
                    height: courseCol.implicitHeight + 28
                    radius: 24; color: cardColor
                    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    // Tap the course's name to open or close its list (the × on top takes its own taps).
                    MouseArea {
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        height: 64
                        onClicked: toggleCourseSetting("collapsed", courseCard.modelData.course)
                    }

                    ColumnLayout {
                        id: courseCol
                        anchors { left: parent.left; right: parent.right; top: parent.top
                                  leftMargin: 18; rightMargin: 12; topMargin: 14 }
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Rectangle {   // the subject colour, once the course has deadlines in "My deadlines"
                                visible: !!subjectColors[colorKey(courseCard.modelData.code)]
                                Layout.rightMargin: 4
                                width: 12; height: 12; radius: 6; color: subjectColor(courseCard.modelData.code)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text { text: courseCard.modelData.code; font.pixelSize: 17; font.bold: true; color: textColor }
                                Text {
                                    Layout.fillWidth: true; elide: Text.ElideRight
                                    font.pixelSize: 13; color: muted
                                    text: courseCard.modelData.items.length + " upcoming"
                                        + (courseCard.modelData.course !== courseCard.modelData.code ? "  ·  " + courseCard.modelData.course : "")
                                }
                            }
                            // Tapping the course name opens or closes its list.
                            Item {
                                width: 36; height: 36
                                Chevron {
                                    anchors.centerIn: parent
                                    rotation: courseCard.collapsed ? 0 : 90
                                    Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                }
                            }
                            RoundIcon {   // remove the course from this tab (stays removed when syncing)
                                turn: 45; pressedFill: red
                                onClicked: toggleCourseSetting("hidden", courseCard.modelData.course)
                            }
                        }
                        Pill {
                            visible: courseCard.missing.length > 0
                            text: "Add all " + courseCard.missing.length + " to My deadlines"
                            onClicked: addFromCanvas(courseCard.missing)
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: courseCard.collapsed ? 0 : itemsCol.implicitHeight + 6
                            clip: true
                            Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            ColumnLayout {
                                id: itemsCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 6 }
                                spacing: 10
                                Repeater {
                                    model: courseCard.modelData.items
                                    RowLayout {
                                        id: row
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 12
                                        Rectangle {
                                            Layout.leftMargin: 2
                                            width: 10; height: 10; radius: 5; color: timeColor(row.modelData.due)
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Text { Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: row.modelData.title; color: textColor }
                                            Text {
                                                Layout.fillWidth: true; elide: Text.ElideRight
                                                font.pixelSize: 13; color: muted
                                                text: whenText(row.modelData.due, row.modelData.time) + "  ·  " + relative(daysLeft(row.modelData.due))
                                            }
                                        }
                                        Pill {
                                            visible: !addedUids[row.modelData.uid]
                                            text: "+ Add"
                                            onClicked: addFromCanvas([row.modelData])
                                        }
                                        Row {
                                            visible: !!addedUids[row.modelData.uid]
                                            Layout.rightMargin: 8
                                            spacing: 4
                                            CheckMark { anchors.verticalCenter: parent.verticalCenter; stroke: muted }
                                            Text { text: "Added"; color: muted; font.pixelSize: 13 }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------- Floating: + button, Undo bar, tab bar ----------
    RoundIcon {
        id: fab
        anchors { right: parent.right; rightMargin: 20; bottom: tabBar.top; bottomMargin: 16 }
        width: 60; height: 60
        // Belongs to Deadlines: fades and shrinks away as you swipe to another tab.
        opacity: Math.max(0, 1 - Math.abs(pages.position) * 2)
        scale: 0.6 + 0.4 * opacity
        visible: opacity > 0
        enabled: opacity > 0.5
        fill: accent; pressedFill: accentHover; mark: "white"
        barLength: 22
        onClicked: formOpen = true
        // A soft shadow so it floats above the cards.
        Rectangle { z: -1; anchors.fill: parent; anchors.topMargin: 3; radius: width / 2; color: "#33000000"; scale: 1.02 }
    }

    Rectangle {
        // A short message at the bottom for a few seconds, e.g. "Deleted …  Undo".
        id: snackbar
        function show(text, canUndo) { snackText.text = text; undoable = canUndo; shown = true; snackTimer.restart() }
        property bool shown: false
        property bool undoable: false
        anchors { left: parent.left; right: parent.right; leftMargin: 16; rightMargin: currentTab === "mine" ? 92 : 16
                  bottom: tabBar.top; bottomMargin: 18 }
        height: Math.max(52, snackText.implicitHeight + 26); radius: 18
        color: dark ? "#3a4555" : "#1c1c1e"
        opacity: shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Timer { id: snackTimer; interval: 4500; onTriggered: { snackbar.shown = false; lastDeleted = null } }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 6
            Text { id: snackText; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; color: "white"; font.pixelSize: 14 }
            Pill {
                visible: snackbar.undoable
                text: "Undo"; fill: "transparent"; pressedFill: "#33ffffff"; labelColor: accent
                onClicked: { undoDelete(); snackbar.shown = false }
            }
        }
    }

    Rectangle {
        // The tab bar: a white rounded bar with a soft pill sliding behind the chosen tab.
        id: tabBar
        readonly property var keys: ["mine", "calendar", "courses"]
        readonly property real tabWidth: (width - 12) / keys.length
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                  leftMargin: 16; rightMargin: 16; bottomMargin: bottomInset + 12 }
        height: 66; radius: 33
        color: cardColor
        border.width: 1; border.color: line
        Rectangle {
            y: 6; width: tabBar.tabWidth; height: tabBar.height - 12; radius: height / 2; color: selectedOnCard
            // Follows the pages as they move (with the finger, or sliding after a tap).
            x: 6 + Math.max(0, Math.min(tabBar.keys.length - 1, pages.position)) * width
        }
        Row {
            anchors.fill: parent; anchors.margins: 6
            Repeater {
                model: [["mine", "list", "Deadlines"], ["calendar", "calendar", "Calendar"], ["courses", "courses", "Courses"]]
                Item {
                    id: tab
                    required property var modelData
                    readonly property bool current: currentTab === modelData[0]
                    width: tabBar.tabWidth; height: tabBar.height - 12
                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        TabIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            kind: tab.modelData[1]
                            stroke: tab.current ? textColor : muted
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tab.modelData[2]; font.pixelSize: 11; font.bold: true
                            color: tab.current ? textColor : muted
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: currentTab = tab.modelData[0] }
                }
            }
        }
    }

    // ---------- Add form: a bottom sheet ----------
    Item {
        id: sheet
        anchors.fill: parent
        z: 50
        visible: dim.opacity > 0
        // How far the on-screen keyboard reaches over the window (0 if Android already made room).
        // Android reports the keyboard in physical pixels; the layout uses device-independent ones.
        readonly property real pixelScale: Qt.platform.os === "android" ? Screen.devicePixelRatio : 1
        readonly property real keyboardOverlap: Qt.inputMethod.visible
            ? Math.max(0, root.height - Qt.inputMethod.keyboardRectangle.y / pixelScale) : 0
        // Room to keep free at the bottom: the keyboard when it's up (it covers the gesture bar too),
        // otherwise the gesture/navigation bar.
        readonly property real bottomSpace: Math.max(bottomInset, keyboardOverlap)

        Rectangle {
            id: dim
            anchors.fill: parent
            color: "#000000"
            opacity: formOpen ? 0.32 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }
            // Taps above the sheet close it (taps on the sheet's own empty space land here too).
            MouseArea { anchors.fill: parent; onClicked: (mouse) => { if (mouse.y < panel.y) formOpen = false } }
        }

        Rectangle {
            id: panel
            width: parent.width
            // One fixed height, so the sheet never moves while it's open: room for the fields plus the
            // tallest panel (the clock; the calendar is smaller), the button bar, and the navigation
            // bar. (Shorter screens: as tall as fits; the fields scroll.) The keyboard doesn't change
            // it either: the button bar rises above the keyboard and the fields scroll.
            readonly property real fieldsHeight: formTitle.height + subjectField.height + assignmentField.height
                                                 + dateRow.height + 4 * formCol.spacing
            readonly property real openHeight: Math.min(
                grabber.height + fieldsHeight + formCol.spacing + timePanel.implicitHeight + 16
                    + formFooter.height + bottomInset,
                root.height - topInset - 24)
            // Rounded top corners; the bottom corners sit below the screen edge.
            height: openHeight + 40
            y: formOpen ? root.height - height + 40 + dragDown : root.height
            Behavior on y { enabled: !sheetDrag.active; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            radius: 28
            color: cardColor
            property real dragDown: 0

            // Grab handle: drag the top of the sheet down to close it.
            Item {
                id: grabber
                width: parent.width; height: 34
                Rectangle { anchors.centerIn: parent; width: 44; height: 5; radius: 2.5; color: line }
                DragHandler {
                    id: sheetDrag
                    target: null
                    xAxis.enabled: false
                    onActiveTranslationChanged: panel.dragDown = Math.max(0, activeTranslation.y)
                    onActiveChanged: if (!active) {
                        if (panel.dragDown > 100) formOpen = false
                        panel.dragDown = 0
                    }
                }
            }

            // "Add deadline", always at the bottom of the sheet (above the keyboard when it's up).
            Item {
                id: formFooter
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                          bottomMargin: 40 + sheet.bottomSpace }
                height: 70
                BigButton {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: 20; rightMargin: 20 }
                    text: "Add deadline"
                    onClicked: form.submit()
                }
            }

            Flickable {
                id: formFlick
                anchors { left: parent.left; right: parent.right; top: grabber.bottom; bottom: formFooter.top }
                contentWidth: width
                contentHeight: formCol.implicitHeight + 16
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                function reveal(item) {   // scroll so a just-opened panel is in view
                    const y = item.mapToItem(formCol, 0, 0).y
                    contentY = Math.max(0, Math.min(y + item.height - height + 16, contentHeight - height))
                }

                ColumnLayout {
                    id: formCol
                    x: 20
                    width: formFlick.width - 40
                    spacing: 10

                    // The form's state and actions (kept here, beside the fields they use).
                    QtObject {
                        id: form
                        property date chosen: new Date(NaN)
                        property string chosenTime: ""   // "HH:MM", or "" for no time
                        readonly property bool hasDate: !isNaN(chosen.getTime())
                        property bool calendarOpen: false
                        property bool timeOpen: false
                        property bool pickingMinute: false   // the clock shows minutes (else hours)
                        readonly property var matches: {
                            const typed = subjectField.text.trim().toLowerCase()
                            const m = subjects.filter(s => s.toLowerCase().indexOf(typed) >= 0)
                                              .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()))
                            return (m.length === 1 && m[0].toLowerCase() === typed) ? [] : m.slice(0, 6)
                        }
                        readonly property bool showSuggestions: subjectField.activeFocus && matches.length > 0

                        function reset() {
                            subjectField.text = ""; assignmentField.text = ""
                            subjectField.invalid = false; assignmentField.invalid = false
                            chosen = new Date(NaN); calendarOpen = false
                            chosenTime = ""; timeOpen = false
                            formFlick.contentY = 0
                        }
                        function openCalendar() {
                            calendarPicker.show(chosen)
                            timeOpen = false
                            calendarOpen = !calendarOpen
                            root.contentItem.forceActiveFocus()   // leave the text fields (hides the keyboard)
                            if (calendarOpen) revealLater.target = calendarArea
                        }
                        function openTime() {
                            // Start at the chosen time, or 23:59 (when most deadlines are due), on the hours.
                            const [h, m] = (chosenTime || "23:59").split(":").map(Number)
                            clock.hour = h; clock.minute = m
                            hourInput.text = pad(h); minuteInput.text = pad(m)
                            calendarOpen = false
                            timeOpen = true
                            pickingMinute = false
                            root.contentItem.forceActiveFocus()   // the clock first; tap a box to type instead
                            revealLater.target = timeArea
                        }
                        function toMinutes() {
                            pickingMinute = true
                            if (hourInput.activeFocus) minuteInput.forceActiveFocus()
                        }
                        function setTime() {
                            chosenTime = pad(clock.hour) + ":" + pad(clock.minute)
                            timeOpen = false
                            root.contentItem.forceActiveFocus()
                        }
                        function submit() {
                            subjectField.invalid = subjectField.text.trim() === ""
                            assignmentField.invalid = assignmentField.text.trim() === ""
                            if (subjectField.invalid) { subjectField.forceActiveFocus(); return }
                            if (assignmentField.invalid) { assignmentField.forceActiveFocus(); return }
                            // The date is optional (no date: it goes last, in purple); a time needs a date.
                            const due = hasDate ? isoDate(chosen) : ""
                            const i = addTask(subjectField.text.trim(), assignmentField.text.trim(), due, due ? chosenTime : "", "")
                            formOpen = false
                            Qt.callLater(ensureCardVisible, i)
                        }
                    }
                    Timer {   // reveal a panel once it has finished opening
                        id: revealLater
                        property Item target: null
                        interval: 260
                        onTargetChanged: if (target) restart()
                        onTriggered: { formFlick.reveal(target); target = null }
                    }
                    Connections {
                        target: root
                        function onFormOpenChanged() { if (!root.formOpen) { form.reset(); root.contentItem.forceActiveFocus() } }
                    }

                    Text { id: formTitle; text: "New deadline"; font.pixelSize: 20; font.bold: true; color: textColor }

                    Field {
                        id: subjectField; placeholderText: "Subject"
                        EnterKey.type: Qt.EnterKeyReturn   // on to Assignment, keyboard stays (see stepInput)
                        onAccepted: assignmentField.forceActiveFocus()
                        onActiveFocusChanged: if (activeFocus) { form.calendarOpen = false; form.timeOpen = false }
                    }
                    // Previous subjects: white chips with a stopwatch; tap to use, × to forget.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: form.showSuggestions ? chipsCol.implicitHeight + 16 : 0
                        visible: Layout.preferredHeight > 0
                        clip: true
                        radius: 22; color: field
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        ColumnLayout {
                            id: chipsCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                            spacing: 6
                            Text { text: "Previous subjects"; font.pixelSize: 12; color: muted; Layout.leftMargin: 8 }
                            Repeater {
                                model: form.matches
                                Rectangle {
                                    id: chip
                                    required property string modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 42; radius: 21; color: cardColor
                                    // Below the row, so the × gets its own taps.
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: { subjectField.text = chip.modelData; assignmentField.forceActiveFocus() }
                                    }
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 4
                                        spacing: 8
                                        Stopwatch {}
                                        Rectangle { width: 10; height: 10; radius: 5; color: subjectColor(chip.modelData) }
                                        Text { Layout.fillWidth: true; text: chip.modelData; color: textColor; elide: Text.ElideRight }
                                        RoundIcon {
                                            turn: 45; pressedFill: field
                                            onClicked: removeSubject(chip.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Field {
                        id: assignmentField; placeholderText: "Assignment"
                        EnterKey.type: Qt.EnterKeyDone   // keyboard away, calendar open (see stepInput)
                        onAccepted: form.openCalendar()
                        onActiveFocusChanged: if (activeFocus) { form.calendarOpen = false; form.timeOpen = false }
                    }

                    // Due date (optional; opens the calendar) and a time (opens the clock; needs a date).
                    RowLayout {
                        id: dateRow
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 48; radius: 24
                            color: dueTap.pressed ? line : field
                            Text {
                                anchors { left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 44
                                          verticalCenter: parent.verticalCenter }
                                elide: Text.ElideRight
                                text: form.hasDate ? Qt.formatDate(form.chosen, "ddd d MMMM yyyy") : "Due date (optional)"
                                color: form.hasDate ? textColor : muted
                            }
                            MouseArea { id: dueTap; anchors.fill: parent; onClicked: form.openCalendar() }
                            RoundIcon {   // remove the date again (and its time)
                                anchors.right: parent.right; anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                visible: form.hasDate
                                turn: 45; pressedFill: line
                                onClicked: {
                                    form.chosen = new Date(NaN); form.chosenTime = ""
                                    form.calendarOpen = false; form.timeOpen = false
                                }
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: 118
                            implicitHeight: 48; radius: 24
                            enabled: form.hasDate   // a time only means something on a day
                            opacity: enabled ? 1 : 0.45
                            color: timeTap.pressed ? line : field
                            Text {
                                anchors.verticalCenter: parent.verticalCenter; x: 20
                                text: form.chosenTime || "Time"
                                font.bold: form.chosenTime !== ""
                                color: form.chosenTime ? textColor : muted
                            }
                            MouseArea {
                                id: timeTap
                                anchors.fill: parent
                                onClicked: {
                                    if (form.timeOpen) { form.timeOpen = false; root.contentItem.forceActiveFocus() }
                                    else form.openTime()
                                }
                            }
                            RoundIcon {   // remove the time again
                                anchors.right: parent.right; anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                visible: form.chosenTime !== ""
                                turn: 45; pressedFill: line
                                onClicked: { form.chosenTime = ""; form.timeOpen = false }
                            }
                        }
                    }
                    Item {
                        id: calendarArea
                        Layout.fillWidth: true
                        Layout.preferredHeight: form.calendarOpen ? calendarPicker.implicitHeight : 0
                        visible: Layout.preferredHeight > 0   // clip alone let the arrows show through when shut
                        clip: true
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        CalendarPicker {
                            id: calendarPicker
                            width: parent.width
                            selected: form.chosen
                            onPicked: (day) => { form.chosen = day; form.calendarOpen = false }
                        }
                    }
                    // Time: tap the hour then the minute on the clock (that sets it), or tap a box and type
                    // (19 00, 19:00 or 1900, then Enter).
                    Item {
                        id: timeArea
                        Layout.fillWidth: true
                        Layout.preferredHeight: form.timeOpen ? timePanel.implicitHeight : 0
                        visible: form.timeOpen || Layout.preferredHeight > 0
                        clip: true
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Rectangle {
                            id: timePanel
                            width: parent.width
                            implicitHeight: timeCol.implicitHeight + 28
                            radius: 24; color: field
                            ColumnLayout {
                                id: timeCol
                                anchors { top: parent.top; topMargin: 14; horizontalCenter: parent.horizontalCenter }
                                spacing: 10
                                Row {
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: 4
                                    TimeDigits {
                                        id: hourInput
                                        EnterKey.type: Qt.EnterKeyDone   // sets the time (see stepInput)
                                        active: !form.pickingMinute
                                        validator: RegularExpressionValidator { regularExpression: /([01]?\d|2[0-3])?/ }   // 0-23
                                        onActiveFocusChanged: if (activeFocus) form.pickingMinute = false
                                        onTextEdited: {
                                            if (text !== "") clock.hour = Number(text)
                                            if (text.length === 2) form.toMinutes()   // "19" typed: on to the minutes
                                        }
                                        // A space, ":" or "." also moves on, so "7 30" and "7:30" work.
                                        Keys.onPressed: (event) => {
                                            if (event.key === Qt.Key_Space || event.text === ":" || event.text === ".") {
                                                form.toMinutes()
                                                event.accepted = true
                                            }
                                        }
                                        onAccepted: form.setTime()
                                        onEditingFinished: text = pad(clock.hour)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: ":"; font.pixelSize: 30; font.bold: true; color: textColor
                                    }
                                    TimeDigits {
                                        id: minuteInput
                                        EnterKey.type: Qt.EnterKeyDone
                                        active: form.pickingMinute
                                        validator: RegularExpressionValidator { regularExpression: /([0-5]?\d)?/ }   // 0-59
                                        onActiveFocusChanged: if (activeFocus) form.pickingMinute = true
                                        onTextEdited: if (text !== "") clock.minute = Number(text)
                                        onAccepted: form.setTime()
                                        onEditingFinished: text = pad(clock.minute)
                                    }
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Pick the " + (form.pickingMinute ? "minute" : "hour") + ", or tap the numbers to type"
                                    font.pixelSize: 12; color: muted
                                }
                                ClockFace {
                                    id: clock
                                    Layout.alignment: Qt.AlignHCenter
                                    minuteMode: form.pickingMinute
                                    onPicked: { hourInput.text = pad(hour); minuteInput.text = pad(minute) }
                                    onHourPicked: form.toMinutes()
                                    // Picking the minute sets the time (shown on the Time button) and closes
                                    // the clock; the deadline itself is only added with "Add deadline".
                                    onMinutePicked: form.setTime()
                                }
                                Row {
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: 8
                                    Pill {
                                        text: "Clear"; fill: "transparent"; pressedFill: line; labelColor: muted; bold: false
                                        onClicked: { form.chosenTime = ""; form.timeOpen = false }
                                    }
                                    Pill {
                                        text: "Set time"; fill: accent; pressedFill: accentHover; labelColor: accentText
                                        onClicked: form.setTime()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Scroll the card list so a card is in view (used after adding one).
    function ensureCardVisible(i) {
        const slot = repeater.itemAt(i)
        if (!slot) return
        const y = slot.y
        if (y < list.contentY) list.contentY = y
        else if (y + slot.height > list.contentY + list.height - pages.bottomRoom)
            list.contentY = Math.min(y + slot.height - list.height + pages.bottomRoom, Math.max(0, list.contentHeight - list.height))
    }
    Component.onDestruction: saveNow()
}
