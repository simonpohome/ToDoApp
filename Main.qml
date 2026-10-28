// Deadlines: the whole interface (Qt Quick). Python side: main.py (saving, Canvas sync).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes

ApplicationWindow {
    id: root
    width: 560
    height: 600
    minimumWidth: 320
    minimumHeight: 160
    visible: true
    title: "Deadlines"
    color: bg
    // On a Mac the title bar is see-through over the light blue page (as main.py tints it on
    // Windows); the page itself still starts below it, where the window's safe area begins.
    flags: Qt.platform.os === "osx" || Qt.platform.os === "macos"
           ? (Qt.Window | Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint) : Qt.Window
    font.family: appFont
    font.pixelSize: 13

    // ---------- Look ----------
    readonly property color bg: "#e3eefb"           // light blue page
    readonly property color cardColor: "#ffffff"
    readonly property color textColor: "#1c1c1e"
    readonly property color muted: "#8e8e93"
    readonly property color line: "#dde6f1"         // ring tracks, connectors, hovers
    readonly property color field: "#eff5fc"        // input fields inside white cards
    readonly property color accent: "#f5a8c5"       // pastel pink
    readonly property color accentHover: "#f08db5"
    readonly property color accentText: "#7a2348"   // deep pink text on the pink accent
    readonly property color doneColor: "#c7c7cc"
    readonly property color green: "#8fd6a5"        // more than a week left
    readonly property color yellow: "#f5d77a"       // 3-7 days left
    readonly property color red: "#f2a0a0"          // 2 days or less
    readonly property color overdueText: "#d9686b"
    readonly property color deleteX: "#9b1c1c"
    readonly property color tabTrack: "#d2e2f6"
    readonly property color tabHover: "#c6d9f1"
    readonly property int autoSyncMinutes: 30
    // Subject colours: new subjects take the first unused one (kept clear of the green/yellow/red
    // that mean time left, and of the pink accent).
    readonly property var subjectPalette: ["#a9c8f5", "#cdb8f3", "#8fd8cf", "#f8c18b", "#f4b4d6",
                                           "#c2e39a", "#e6d3b3", "#b8c3d9", "#e3b8ef", "#9fdcf0"]

    // ---------- State ----------
    property string currentTab: "mine"
    property bool formOpen: false
    property var subjects: []
    property var subjectColors: ({})   // lowercase subject -> "#rrggbb"
    property string calDay: isoDate(today())   // Calendar tab: the selected day and shown month
    property int calMonth: new Date().getMonth()
    property int calYear: new Date().getFullYear()
    property var canvas: ({ feed_url: "", last_sync: null, assignments: [], hidden: [], collapsed: [] })
    property bool syncing: false
    property string syncMessage: ""
    property string saveError: ""
    property bool loaded: false
    property int rev: 0               // bumped on every change; bindings that read the models use it
    property Item draggedCard: null

    ListModel { id: tasks }   // display order; each task has a nested "steps" list

    // ---------- Helpers ----------
    function pad(n) { return String(n).padStart(2, "0") }
    function uid() { let s = ""; for (let i = 0; i < 32; i++) s += Math.floor(Math.random() * 16).toString(16); return s }
    function today() { const t = new Date(); t.setHours(0, 0, 0, 0); return t }
    function parseDate(iso) { const p = iso.split("-"); return new Date(p[0], p[1] - 1, p[2]) }
    function isoDate(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }
    function daysLeft(iso) { return Math.round((parseDate(iso) - today()) / 86400000) }
    function relative(n) {
        if (n === 0) return "today"
        if (n === 1) return "tomorrow"
        if (n === -1) return "yesterday"
        return n > 0 ? "in " + n + " days" : (-n) + " days ago"
    }
    function timeColor(iso) { const n = daysLeft(iso); return n > 7 ? green : n > 2 ? yellow : red }
    function whenText(iso, time) { return Qt.formatDate(parseDate(iso), "ddd dd MMM") + (time ? " " + time : "") }
    function blend(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }
    function progressColor(p) { return p <= 50 ? blend(red, yellow, p / 50) : blend(yellow, green, (p - 50) / 50) }
    function progressOf(steps, done) {
        if (steps.count === 0) return done ? 100 : 0
        let n = 0
        for (let i = 0; i < steps.count; i++) if (steps.get(i).done) n++
        return Math.round(100 * n / steps.count)
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
    function doneStepIds(t) {
        const ids = []
        for (let s = 0; s < t.steps.count; s++) if (t.steps.get(s).done) ids.push(t.steps.get(s).stepId)
        return ids
    }

    // ---------- Loading & saving ----------
    function fromJson(t) {
        return {
            taskId: t.id || uid(), subject: t.subject || "", assignment: t.assignment || "",
            due: t.due, time: t.time || "", done: !!t.done, collapsed: !!t.collapsed,
            canvasUid: t.canvas_uid || "",
            stepsBeforeDone: t.steps_before_done ? JSON.stringify(t.steps_before_done) : "",
            steps: (t.subtasks || []).map(s => ({ stepId: s.id || uid(), text: s.text, done: !!s.done }))
        }
    }
    function serialize() {
        const out = []
        for (let i = 0; i < tasks.count; i++) {
            const t = tasks.get(i)
            const steps = []
            for (let s = 0; s < t.steps.count; s++) {
                const st = t.steps.get(s)
                steps.push({ id: st.stepId, text: st.text, done: st.done })
            }
            const o = { id: t.taskId, subject: t.subject, assignment: t.assignment, due: t.due, done: t.done, subtasks: steps }
            if (t.time) o.time = t.time
            if (t.collapsed) o.collapsed = true
            if (t.canvasUid) o.canvas_uid = t.canvasUid
            if (t.stepsBeforeDone) o.steps_before_done = JSON.parse(t.stepsBeforeDone)
            out.push(o)
        }
        return JSON.stringify({ tasks: out, subjects: subjects, canvas: canvas, subject_colors: subjectColors })
    }
    function changed() { rev++; if (loaded) saveTimer.restart() }
    function saveNow() {
        saveError = ""   // a failed save sets it again (saveFailed arrives before save() returns)
        backend.save(serialize())
    }
    Timer { id: saveTimer; interval: 300; onTriggered: saveNow() }

    Component.onCompleted: {
        const data = JSON.parse(backend.load())
        for (const t of data.tasks) insertTask(tasks.count, fromJson(t))
        subjects = data.subjects
        canvas = data.canvas
        subjectColors = data.subject_colors
        for (const s of subjects) ensureColor(s)   // subjects from before colours existed
        for (let i = 0; i < tasks.count; i++) ensureColor(tasks.get(i).subject)
        loaded = true
        rev++
        saveNow()   // writes older data files back in the current format
        if (canvas.feed_url) startupSync.start()
    }
    onClosing: if (loaded) { saveTimer.stop(); saveNow() }

    // ---------- My deadlines ----------
    property bool stepsRoleKnown: false
    function insertTask(i, task) {
        // The very first task decides that "steps" is a list. If that task has no steps, an
        // empty list would leave it undecided, so insert one placeholder step and remove it.
        // (Only needed once; later tasks can have empty lists.)
        const teach = !stepsRoleKnown && task.steps.length === 0
        if (teach) task.steps = [{ stepId: "", text: "", done: false }]
        tasks.insert(i, task)
        if (teach) tasks.get(i).steps.remove(0)
        stepsRoleKnown = true
    }
    function addTask(subject, assignment, due, time, canvasUid) {
        // By due date and time (no time = end of that day); the manual order of the rest is kept.
        const when = t => t.due + " " + (t.time || "24:00")
        const key = when({ due: due, time: time })
        let i = 0
        while (i < tasks.count && when(tasks.get(i)) <= key) i++
        insertTask(i, { taskId: uid(), subject: subject, assignment: assignment, due: due, time: time || "",
                        done: false, collapsed: false, canvasUid: canvasUid || "", stepsBeforeDone: "", steps: [] })
        if (!subjects.some(s => s.toLowerCase() === subject.toLowerCase())) subjects = subjects.concat([subject])
        ensureColor(subject)
        changed()
        return i
    }
    function deleteTask(i) {
        const slot = repeater.itemAt(i)
        if (slot) slot.children[0].leave()   // animates out, then removes it from the model
        else removeTask(i)
    }
    // Runs here rather than in the card: removing the card ends its own script context.
    function removeTask(i) { tasks.remove(i); changed() }
    function toggleTask(i) {
        const t = tasks.get(i)
        if (!t.done) {
            // Completing ticks every step; remember which were ticked so a second click undoes it exactly.
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
    function connectCanvas(text) {
        const r = JSON.parse(backend.normalizeFeedUrl(text))
        if (r.error) { syncMessage = r.error; rev++; return }
        setCanvas({ feed_url: r.url })
        syncCanvas()
    }
    function disconnectCanvas() {
        // Deadlines already added to "My deadlines" stay; they just stop updating.
        syncMessage = ""
        setCanvas({ feed_url: "", last_sync: null, assignments: [] })
    }
    function syncCanvas() {
        if (!canvas.feed_url || syncing) return
        syncing = true
        syncMessage = "Syncing with Canvas…"
        backend.sync(canvas.feed_url)
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
    Connections {
        target: backend
        function onSyncFinished(json) { root.finishSync(JSON.parse(json)) }
        function onSaveFailed(message) { root.saveError = message }
    }
    Timer { id: startupSync; interval: 400; onTriggered: syncCanvas() }
    Timer { interval: autoSyncMinutes * 60000; repeat: true; running: true; onTriggered: syncCanvas() }

    // Esc closes the add form (only while it's open, so Esc still reaches a card's step input).
    Shortcut { sequence: "Esc"; enabled: formOpen; onActivated: formOpen = false }

    // ---------- Reusable pieces ----------
    component RoundIcon: Item {
        // Round hover button drawing a "+" or "×" (turn: 45) from two rounded bars.
        id: icon
        property color fill: "transparent"
        property color hoverFill: line
        property color mark: muted
        property color hoverMark: textColor
        property real turn: 0
        property real barLength: width * 0.42
        signal clicked()
        width: 28; height: 28
        Rectangle {
            anchors.fill: parent; radius: width / 2
            color: iconHover.hovered ? icon.hoverFill : icon.fill
            Behavior on color { ColorAnimation { duration: 120 } }
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
                    width: icon.barLength; height: Math.max(2, icon.width * 0.075); radius: height / 2
                    rotation: index * 90
                    color: iconHover.hovered ? icon.hoverMark : icon.mark
                }
            }
        }
        HoverHandler { id: iconHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: icon.clicked() }
    }

    component MonthArrow: Item {
        // Round button with a big chevron for changing month: direction -1 = back, 1 = forward.
        id: arrow
        property int direction: 1
        signal clicked()
        width: 36; height: 36
        Rectangle {
            anchors.fill: parent; radius: width / 2
            color: arrowHover.hovered ? line : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Shape {
            anchors.centerIn: parent; width: 14; height: 14
            rotation: arrow.direction < 0 ? 180 : 0
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: textColor; strokeWidth: 2.5; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                startX: 4.5; startY: 1.5
                PathLine { x: 10; y: 7 }
                PathLine { x: 4.5; y: 12.5 }
            }
        }
        HoverHandler { id: arrowHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: arrow.clicked() }
    }

    component ClockFace: Item {
        // Round clock for picking a time by clicking or dragging. Hours: 1-12 on the outer ring,
        // 13-23 and 00 on the inner ring. Minutes: one ring, any minute by angle.
        id: clock
        property bool minuteMode: false
        property int hour: 0
        property int minute: 0
        signal picked()       // hour or minute changed by clicking/dragging
        signal hourPicked()   // mouse let go after choosing an hour: on to the minutes
        signal minutePicked() // mouse let go after choosing a minute: the time is done
        width: 224; height: 224
        readonly property real r: width / 2
        readonly property real outerR: r - 22
        readonly property real innerR: r - 58
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
            width: 34; height: 34; radius: 17; color: accent
            x: clock.r + clock.handLength * Math.sin(rad) - 17
            y: clock.r - clock.handLength * Math.cos(rad) - 17
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
                font.pixelSize: 14; font.bold: true
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
                font.pixelSize: 12; font.bold: true
                color: clock.hour === value ? accentText : muted
            }
        }
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onPressed: (mouse) => clock.pick(mouse.x, mouse.y)
            onPositionChanged: (mouse) => clock.pick(mouse.x, mouse.y)
            onReleased: clock.minuteMode ? clock.minutePicked() : clock.hourPicked()
        }
    }

    component TimeDigits: TextField {
        // One of the two big "HH : MM" boxes above the clock; type into it, or click it to pick on the clock.
        id: digits
        property bool active: false   // the half of the time the clock is showing
        implicitWidth: 66; implicitHeight: 50
        padding: 0
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        font.pixelSize: 28; font.bold: true
        color: active ? accentText : textColor
        selectionColor: accentHover; selectedTextColor: accentText
        maximumLength: 2
        inputMethodHints: Qt.ImhDigitsOnly
        background: Rectangle {
            radius: 16
            color: digits.active ? accent : digitsHover.hovered ? line : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        HoverHandler { id: digitsHover; cursorShape: Qt.IBeamCursor }
        onActiveFocusChanged: if (activeFocus) Qt.callLater(selectAll)   // typing replaces what's there
    }

    component Chevron: Item {
        // Round button with a chevron: down when open, right when closed.
        id: chev
        property bool open: true
        signal clicked()
        width: 26; height: 26
        Rectangle { anchors.fill: parent; radius: 13; color: chevHover.hovered ? line : field }
        Shape {
            anchors.centerIn: parent; width: 10; height: 10
            rotation: chev.open ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: chevHover.hovered ? textColor : muted; strokeWidth: 2; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                startX: 3; startY: 1
                PathLine { x: 7.5; y: 5 }
                PathLine { x: 3; y: 9 }
            }
        }
        HoverHandler { id: chevHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: chev.clicked() }
    }

    component Pill: Rectangle {
        // Small rounded text button.
        id: pill
        property alias text: pillLabel.text
        property color fill: field
        property color hoverFill: line
        property color labelColor: textColor
        property bool bold: true
        signal clicked()
        implicitWidth: pillLabel.implicitWidth + 28
        implicitHeight: 28
        radius: height / 2
        color: pillHover.hovered && enabled ? hoverFill : fill
        opacity: enabled ? 1 : 0.5
        Text { id: pillLabel; anchors.centerIn: parent; font.pixelSize: 12; font.bold: pill.bold; color: pill.labelColor }
        HoverHandler { id: pillHover; cursorShape: pill.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { onTapped: if (pill.enabled) pill.clicked() }
    }

    component BigButton: Rectangle {
        // Full-width pink button ("Add deadline", "Connect").
        id: big
        property alias text: bigLabel.text
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 42; radius: 21
        color: bigHover.hovered ? accentHover : accent
        Text { id: bigLabel; anchors.centerIn: parent; font.bold: true; font.pixelSize: 12; color: accentText }
        HoverHandler { id: bigHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: big.clicked() }
    }

    component Field: TextField {
        id: f
        property bool invalid: false
        Layout.fillWidth: true
        implicitHeight: 40
        leftPadding: 18; rightPadding: 18
        color: textColor
        placeholderTextColor: muted
        font.pixelSize: 13
        selectByMouse: true
        background: Rectangle { radius: 20; color: field; border.width: f.invalid ? 2 : 0; border.color: red }
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
        // The subject as a tag in its colour; click to choose another colour.
        id: tag
        property string subject: ""
        property bool faded: false
        implicitWidth: tagText.implicitWidth + 16
        implicitHeight: 20
        radius: height / 2
        color: subjectColor(subject)
        opacity: faded ? 0.45 : 1
        Text {
            id: tagText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, tag.width - 16)
            text: tag.subject; elide: Text.ElideRight
            font.pixelSize: 11; font.bold: true; color: textColor
        }
        // A MouseArea rather than a TapHandler, so the press doesn't also reach the card underneath.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: colorPopup.openFor(tag.subject, tag)
        }
    }

    Popup {
        id: colorPopup
        property string subject: ""
        function openFor(subject, item) {
            colorPopup.subject = subject
            parent = item
            x = 0; y = item.height + 6
            open()
        }
        padding: 12
        background: Rectangle { radius: 18; color: cardColor; border.width: 1; border.color: line }
        contentItem: Column {
            spacing: 10
            Text { text: "Colour for " + colorPopup.subject; font.pixelSize: 12; font.bold: true; color: textColor }
            Grid {
                columns: 5; spacing: 8
                Repeater {
                    model: subjectPalette
                    Rectangle {
                        id: swatch
                        required property string modelData
                        width: 26; height: 26; radius: 13; color: modelData
                        scale: swatchHover.hovered ? 1.12 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            visible: subjectColors[colorKey(colorPopup.subject)] === swatch.modelData
                            text: "✓"; font.bold: true; color: textColor
                        }
                        HoverHandler { id: swatchHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { setSubjectColor(colorPopup.subject, swatch.modelData); colorPopup.close() } }
                    }
                }
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
                    // Fixed width, so the arrows stay put as the month name changes length.
                    Layout.preferredWidth: 130; horizontalAlignment: Text.AlignHCenter
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
                    text: shortName.slice(0, 2); color: muted; font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                }
            }
            // MonthGrid always splits its height into 6 rows. Give it the height of 6 full rows and
            // show only the weeks this month needs (4-6; the rest are next month's days, clipped away).
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: grid.weeks * 32
                clip: true
            MonthGrid {
                id: grid
                readonly property int weeks: {
                    const offset = (new Date(cal.year, cal.month, 1).getDay() + 6) % 7   // Monday = 0
                    const days = new Date(cal.year, cal.month + 1, 0).getDate()
                    return Math.ceil((offset + days) / 7)
                }
                width: parent.width
                height: 6 * 32
                // When the 1st is a Monday, Qt starts the grid with the week before; skip that row.
                y: -leadRows * 32
                readonly property int leadRows: new Date(cal.year, cal.month, 1).getDay() === 1 ? 1 : 0
                spacing: 0
                month: cal.month; year: cal.year
                locale: Qt.locale("en_GB")
                delegate: Item {
                    id: dayCell
                    required property var model
                    implicitHeight: 32
                    readonly property bool isSelected: !isNaN(cal.selected.getTime())
                        && model.date.getTime() === cal.selected.getTime()
                    readonly property bool inMonth: model.month === grid.month
                    // Hide other months' days with opacity, not visible: invisible cells are left out
                    // of the grid, which would shift every day into the wrong weekday column.
                    opacity: inMonth ? 1 : 0
                    enabled: inMonth
                    Rectangle {
                        anchors.centerIn: parent; width: 30; height: 30; radius: 15
                        color: dayCell.isSelected ? accent : dayHover.hovered ? line : "transparent"
                        border.width: dayCell.model.today && !dayCell.isSelected ? 2 : 0
                        border.color: accent
                    }
                    Text {
                        anchors.centerIn: parent
                        text: dayCell.model.day
                        font.bold: dayCell.isSelected || dayCell.model.today
                        color: dayCell.isSelected ? accentText : dayCell.model.date < today() ? muted : textColor
                    }
                    HoverHandler { id: dayHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: cal.picked(dayCell.model.date) }
                }
            }
            }
        }
    }

    // ---------- Layout ----------
    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 6
        spacing: 10

        // Header: logo, title, count, and the pink "+" (turns into "×" while the form is open).
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 24; Layout.rightMargin: 32
            spacing: 12
            Rectangle {
                width: 40; height: 40; radius: 11; color: green
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: "white"; strokeWidth: 4; fillColor: "transparent"
                        capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                        startX: 11; startY: 21
                        PathLine { x: 17.5; y: 27.5 }
                        PathLine { x: 29.5; y: 14.5 }
                    }
                }
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Text { text: "Deadlines"; font.pixelSize: 28; font.bold: true; color: textColor }
                Text {
                    Layout.fillWidth: true
                    text: saveError || (tasks.count ? upcoming + " upcoming" : "")
                    font.pixelSize: 13; color: saveError ? overdueText : muted; elide: Text.ElideRight
                }
            }
            RoundIcon {
                width: 48; height: 48
                visible: currentTab === "mine"
                fill: accent; hoverFill: accentHover; mark: "white"; hoverMark: "white"
                barLength: 20
                turn: formOpen ? 45 : 0
                onClicked: formOpen = !formOpen
            }
        }

        // Tab switch: the white pill slides between the tabs.
        Rectangle {
            id: tabs
            readonly property var keys: ["mine", "calendar", "courses"]
            readonly property real tabWidth: (width - 6) / keys.length
            Layout.leftMargin: 20
            width: Math.min(330, root.width - 40); height: 34; radius: 17; color: tabTrack
            Rectangle {
                y: 3; width: tabs.tabWidth; height: 28; radius: 14; color: cardColor
                x: 3 + tabs.keys.indexOf(currentTab) * width
                Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
            Row {
                anchors.fill: parent; anchors.margins: 3
                Repeater {
                    model: [["mine", "My deadlines"], ["calendar", "Calendar"], ["courses", "Courses"]]
                    Item {
                        required property var modelData
                        width: tabs.tabWidth; height: 28
                        Text {
                            anchors.centerIn: parent; text: modelData[1]; font.bold: true; font.pixelSize: 12
                            color: currentTab === modelData[0] ? textColor : muted
                            Behavior on color { ColorAnimation { duration: 180 } }
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { currentTab = modelData[0]; if (currentTab !== "mine") formOpen = false } }
                    }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: ["mine", "courses", "calendar"].indexOf(currentTab)   // the order of the pages below

            // ===== My deadlines =====
            ColumnLayout {
                spacing: 0

                // Add form: slides open under the header.
                Item {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16; Layout.rightMargin: 24
                    Layout.preferredHeight: formOpen ? formCard.implicitHeight + 12 : 0
                    clip: true
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                    Rectangle {
                        id: formCard
                        width: parent.width
                        implicitHeight: formCol.implicitHeight + 40
                        radius: 30; color: cardColor
                        property date chosen: new Date(NaN)
                        property string chosenTime: ""   // "HH:MM", or "" for no time
                        property bool dateInvalid: false
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
                            chosen = new Date(NaN); dateInvalid = false; calendarOpen = false
                            chosenTime = ""; timeOpen = false
                        }
                        function openTime() {
                            // Start at the chosen time, or 23:59 (when most deadlines are due), on the hours,
                            // with the hour box ready for typing.
                            const [h, m] = (chosenTime || "23:59").split(":").map(Number)
                            clock.hour = h; clock.minute = m
                            hourInput.text = pad(h); minuteInput.text = pad(m)
                            calendarOpen = false
                            timeOpen = true
                            pickingMinute = false
                            hourInput.forceActiveFocus()
                        }
                        function toMinutes() {
                            pickingMinute = true
                            minuteInput.forceActiveFocus()
                        }
                        function setTime() {
                            chosenTime = pad(clock.hour) + ":" + pad(clock.minute)
                            timeOpen = false
                            root.contentItem.forceActiveFocus()
                        }
                        function submit() {
                            subjectField.invalid = subjectField.text.trim() === ""
                            assignmentField.invalid = assignmentField.text.trim() === ""
                            dateInvalid = isNaN(chosen.getTime())
                            if (subjectField.invalid) { subjectField.forceActiveFocus(); return }
                            if (assignmentField.invalid) { assignmentField.forceActiveFocus(); return }
                            if (dateInvalid) return
                            const i = addTask(subjectField.text.trim(), assignmentField.text.trim(), isoDate(chosen), chosenTime, "")
                            formOpen = false
                            reset()
                            Qt.callLater(list.ensureVisible, i)
                        }
                        Connections {
                            target: root
                            function onFormOpenChanged() {
                                if (root.formOpen) subjectField.forceActiveFocus()
                                else formCard.reset()
                            }
                        }

                        ColumnLayout {
                            id: formCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20; topMargin: 18 }
                            spacing: 8
                            Text { text: "New deadline"; font.pixelSize: 17; font.bold: true; color: textColor }

                            Field {
                                id: subjectField; placeholderText: "Subject"
                                onAccepted: formCard.submit()
                                onActiveFocusChanged: if (activeFocus) { formCard.calendarOpen = false; formCard.timeOpen = false }
                            }
                            // Previous subjects: white chips with a stopwatch; click to use, × to forget.
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: formCard.showSuggestions ? chipsCol.implicitHeight + 16 : 0
                                visible: Layout.preferredHeight > 0
                                clip: true
                                radius: 20; color: field
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                ColumnLayout {
                                    id: chipsCol
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                    spacing: 4
                                    Text { text: "Previous subjects"; font.pixelSize: 11; color: muted; Layout.leftMargin: 8 }
                                    Repeater {
                                        model: formCard.matches
                                        Rectangle {
                                            id: chip
                                            required property string modelData
                                            Layout.fillWidth: true
                                            implicitHeight: 32; radius: 16; color: cardColor
                                            RowLayout {
                                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 4
                                                spacing: 8
                                                Stopwatch {}
                                                Rectangle { width: 10; height: 10; radius: 5; color: subjectColor(chip.modelData) }
                                                Text { Layout.fillWidth: true; text: chip.modelData; color: textColor; elide: Text.ElideRight }
                                                RoundIcon {
                                                    turn: 45; hoverFill: field
                                                    onClicked: removeSubject(chip.modelData)
                                                }
                                            }
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            TapHandler {
                                                onTapped: { subjectField.text = chip.modelData; assignmentField.forceActiveFocus() }
                                            }
                                        }
                                    }
                                }
                            }
                            Field {
                                id: assignmentField; placeholderText: "Assignment"
                                onAccepted: formCard.submit()
                                onActiveFocusChanged: if (activeFocus) { formCard.calendarOpen = false; formCard.timeOpen = false }
                            }

                            // Due date (opens the calendar) and an optional time (opens the clock).
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 40; radius: 20
                                    color: dueHover.hovered ? line : field
                                    border.width: formCard.dateInvalid ? 2 : 0; border.color: red
                                    Text {
                                        anchors { left: parent.left; right: parent.right; leftMargin: 18; rightMargin: 12
                                                  verticalCenter: parent.verticalCenter }
                                        elide: Text.ElideRight
                                        text: isNaN(formCard.chosen.getTime()) ? "Due date" : Qt.formatDate(formCard.chosen, "ddd dd MMMM yyyy")
                                        color: isNaN(formCard.chosen.getTime()) ? muted : textColor
                                    }
                                    HoverHandler { id: dueHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: {
                                            calendarPicker.show(formCard.chosen)
                                            formCard.timeOpen = false
                                            formCard.calendarOpen = !formCard.calendarOpen
                                            root.contentItem.forceActiveFocus()   // leave the text fields
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.preferredWidth: 112
                                    implicitHeight: 40; radius: 20
                                    color: timeHover.hovered ? line : field
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter; x: 18
                                        text: formCard.chosenTime || "Time"
                                        font.bold: formCard.chosenTime !== ""
                                        color: formCard.chosenTime ? textColor : muted
                                    }
                                    HoverHandler { id: timeHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: {
                                            if (formCard.timeOpen) {
                                                formCard.timeOpen = false
                                                root.contentItem.forceActiveFocus()
                                            } else {
                                                formCard.openTime()
                                            }
                                        }
                                    }
                                    RoundIcon {   // remove the time again
                                        anchors.right: parent.right; anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 24; height: 24
                                        visible: formCard.chosenTime !== ""
                                        turn: 45; hoverFill: field
                                        onClicked: { formCard.chosenTime = ""; formCard.timeOpen = false }
                                    }
                                }
                            }
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: formCard.calendarOpen ? calendarPicker.implicitHeight : 0
                                visible: Layout.preferredHeight > 0   // clip alone let the arrows show through when shut
                                clip: true
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                CalendarPicker {
                                    id: calendarPicker
                                    width: parent.width
                                    selected: formCard.chosen
                                    onPicked: (day) => { formCard.chosen = day; formCard.dateInvalid = false; formCard.calendarOpen = false }
                                }
                            }
                            // Time: type it in the "HH : MM" boxes (19 00, 19:00 or 1900, then Enter), or click
                            // the clock: first the hour, then the minute, which sets it.
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: formCard.timeOpen ? timePanel.implicitHeight : 0
                                // Visible straight away when opening, so the hour box can take the typing.
                                visible: formCard.timeOpen || Layout.preferredHeight > 0
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
                                                active: !formCard.pickingMinute
                                                validator: RegularExpressionValidator { regularExpression: /([01]?\d|2[0-3])?/ }   // 0-23
                                                onActiveFocusChanged: if (activeFocus) formCard.pickingMinute = false
                                                onTextEdited: {
                                                    if (text !== "") clock.hour = Number(text)
                                                    if (text.length === 2) formCard.toMinutes()   // "19" typed: on to the minutes
                                                }
                                                // A space, ":" or "." also moves on, so "7 30" and "7:30" work.
                                                Keys.onPressed: (event) => {
                                                    if (event.key === Qt.Key_Space || event.text === ":" || event.text === ".") {
                                                        formCard.toMinutes()
                                                        event.accepted = true
                                                    }
                                                }
                                                onAccepted: formCard.setTime()
                                                onEditingFinished: text = pad(clock.hour)
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: ":"; font.pixelSize: 28; font.bold: true; color: textColor
                                            }
                                            TimeDigits {
                                                id: minuteInput
                                                active: formCard.pickingMinute
                                                validator: RegularExpressionValidator { regularExpression: /([0-5]?\d)?/ }   // 0-59
                                                onActiveFocusChanged: if (activeFocus) formCard.pickingMinute = true
                                                onTextEdited: if (text !== "") clock.minute = Number(text)
                                                onAccepted: formCard.setTime()
                                                onEditingFinished: text = pad(clock.minute)
                                            }
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "Type it, or pick the " + (formCard.pickingMinute ? "minute" : "hour") + " on the clock"
                                            font.pixelSize: 11; color: muted
                                        }
                                        ClockFace {
                                            id: clock
                                            Layout.alignment: Qt.AlignHCenter
                                            minuteMode: formCard.pickingMinute
                                            onPicked: { hourInput.text = pad(hour); minuteInput.text = pad(minute) }
                                            onHourPicked: formCard.toMinutes()
                                            // Picking the minute sets the time (shown on the Time button) and closes
                                            // the clock; the deadline itself is only added with "Add deadline".
                                            onMinutePicked: formCard.setTime()
                                        }
                                        Row {
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: 8
                                            Pill {
                                                text: "Clear"; fill: "transparent"; hoverFill: line; labelColor: muted; bold: false
                                                onClicked: { formCard.chosenTime = ""; formCard.timeOpen = false }
                                            }
                                            Pill {
                                                text: "Set time"; fill: accent; hoverFill: accentHover; labelColor: accentText
                                                onClicked: formCard.setTime()
                                            }
                                        }
                                    }
                                }
                            }
                            BigButton { Layout.topMargin: 8; text: "Add deadline"; onClicked: formCard.submit() }
                        }
                    }
                }

                // The card list: a Column in a scroll area. The Column recalculates every card's
                // position whenever anything changes (add, delete, a height change, a move) and the
                // "move" transition glides cards there. (ListView kept stale positions when a card
                // changed height during its own animations.) Mouse buttons drag cards; wheel and
                // touchpad scroll smoothly.
                Flickable {
                    id: list
                    objectName: "list"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 16; Layout.rightMargin: 6
                    contentWidth: width
                    contentHeight: column.implicitHeight + 12
                    clip: true
                    acceptedButtons: Qt.NoButton
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    function ensureVisible(i) {
                        const item = repeater.itemAt(i)
                        if (!item) return
                        if (item.y < contentY) contentY = item.y
                        else if (item.y + item.height > contentY + height)
                            contentY = Math.min(item.y + item.height - height + 12, Math.max(0, contentHeight - height))
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: tasks.count === 0
                        text: "No deadlines yet.\nPress + to add one."
                        horizontalAlignment: Text.AlignHCenter; color: muted; font.pixelSize: 14
                    }

                    // While dragging a card near the top or bottom, scroll that way.
                    Timer {
                        interval: 16; repeat: true
                        running: draggedCard !== null
                        onTriggered: {
                            const c = draggedCard
                            if (c.y < 30) list.contentY = Math.max(0, list.contentY - 8)
                            else if (c.y + c.height > list.height - 30)
                                list.contentY = Math.min(Math.max(0, list.contentHeight - list.height), list.contentY + 8)
                        }
                    }

                    Column {
                        id: column
                        width: list.width - 10
                        spacing: 12
                        add: Transition {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 240 }
                            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 260; easing.type: Easing.OutCubic }
                        }
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
                        height: card.implicitHeight * card.leaveScale
                        clip: card.leaveScale < 1
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
                            readonly property bool compact: width < 330
                            property bool addingStep: false
                            property real leaveScale: 1   // shrinks to 0 while the card is deleted
                            // Closing the steps also closes the new-step input.
                            readonly property bool collapsed: slot.model.collapsed
                            onCollapsedChanged: if (collapsed) { stepInput.text = ""; addingStep = false }
                            // Named handles to the header buttons (used by the tests).
                            readonly property alias chevronButton: chevronButton
                            readonly property alias plusButton: plusButton
                            readonly property alias pie: pie

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
                            anchors.top: slot.top
                            width: slot.width
                            implicitHeight: content.implicitHeight + 30
                            height: implicitHeight
                            radius: 24
                            color: cardColor
                            border.width: 2
                            border.color: slot.model.done ? cardColor : mark

                            Drag.active: grab.drag.active
                            Drag.source: card
                            Drag.hotSpot.x: width / 2
                            Drag.hotSpot.y: height / 2

                            states: State {
                                when: grab.drag.active
                                ParentChange { target: card; parent: list }
                                AnchorChanges { target: card; anchors.left: undefined; anchors.top: undefined }
                                PropertyChanges { target: card; z: 100; border.width: 4 }
                            }
                            transitions: Transition {
                                to: ""
                                ParentAnimation { AnchorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            }

                            ColumnLayout {
                                id: content
                                anchors { left: parent.left; right: parent.right; top: parent.top
                                          leftMargin: 18; rightMargin: 12; topMargin: 15 }
                                // No spacing here: the steps and step-input areas include their own top
                                // gap, so a closed area takes up no space at all.
                                spacing: 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    // Subject/date and title: click to tick, drag to move the card.
                                    Item {
                                        Layout.fillWidth: true
                                        implicitHeight: infoCol.implicitHeight
                                        // Below the text, so the subject tag on top gets its own clicks.
                                        MouseArea {
                                            id: grab
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            drag.target: card
                                            drag.axis: Drag.YAxis
                                            drag.minimumY: 0
                                            drag.maximumY: list.height - card.height
                                            onClicked: toggleTask(slot.index)
                                            onReleased: if (card.Drag.active) card.Drag.drop()
                                            drag.onActiveChanged: {
                                                draggedCard = drag.active ? card : null
                                                if (!drag.active) changed()   // save the new order
                                            }
                                        }
                                        ColumnLayout {
                                            id: infoCol
                                            anchors { left: parent.left; right: parent.right; top: parent.top }
                                            spacing: 2
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                Rectangle { width: 10; height: 10; radius: 5; color: card.mark }
                                                SubjectPill {
                                                    Layout.maximumWidth: card.compact ? 90 : 160
                                                    subject: slot.model.subject
                                                    faded: slot.model.done
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                    text: whenText(slot.model.due, slot.model.time)
                                                          + (card.compact ? "" : "  ·  " + relative(daysLeft(slot.model.due)))
                                                    font.pixelSize: 12
                                                    font.strikeout: slot.model.done
                                                    color: slot.model.done ? doneColor
                                                         : daysLeft(slot.model.due) < 0 ? overdueText : muted
                                                }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: slot.model.assignment
                                                wrapMode: Text.Wrap
                                                font.pixelSize: 16; font.bold: true
                                                font.strikeout: slot.model.done
                                                color: slot.model.done ? doneColor : textColor
                                            }
                                        }
                                    }
                                    Chevron {
                                        id: chevronButton
                                        visible: card.stepCount > 0
                                        open: !slot.model.collapsed
                                        onClicked: toggleCollapsed(slot.index)
                                    }
                                    RoundIcon {
                                        id: plusButton
                                        width: 26; height: 26
                                        fill: field; hoverFill: line
                                        onClicked: card.openStepInput()
                                    }
                                    Pie { id: pie; visible: !card.compact; pct: card.pct }
                                    RoundIcon {
                                        turn: 45; hoverFill: red; hoverMark: deleteX
                                        onClicked: deleteTask(slot.index)
                                    }
                                }

                                // Steps, joined to the task by a line; slide shut with the chevron.
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: card.stepCount > 0 && !slot.model.collapsed ? stepsCol.implicitHeight + 6 : 0
                                    clip: true
                                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    Rectangle { x: 4; y: 6; width: 2; height: Math.max(0, stepsCol.implicitHeight - 14); color: line }
                                    ColumnLayout {
                                        id: stepsCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 4; topMargin: 6 }
                                        spacing: 0
                                        Repeater {
                                            model: slot.model.steps
                                            delegate: RowLayout {
                                                id: step
                                                required property int index
                                                required property string text
                                                required property bool done
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 28
                                                spacing: 8
                                                Rectangle { width: 14; height: 2; color: line }
                                                Rectangle {
                                                    width: 20; height: 20; radius: 10
                                                    color: step.done ? card.mark : "transparent"
                                                    border.width: 2; border.color: card.mark
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                    Text { anchors.centerIn: parent; visible: step.done; text: "✓"; color: "white"; font.pixelSize: 12; font.bold: true }
                                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                    TapHandler { onTapped: toggleStep(slot.index, step.index) }
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: step.text
                                                    elide: Text.ElideRight
                                                    font.strikeout: step.done
                                                    color: step.done ? doneColor : textColor
                                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                    TapHandler { onTapped: toggleStep(slot.index, step.index) }
                                                }
                                                RoundIcon {
                                                    width: 22; height: 22; turn: 45
                                                    mark: doneColor; hoverMark: textColor; hoverFill: field
                                                    onClicked: deleteStep(slot.index, step.index)
                                                }
                                            }
                                        }
                                    }
                                }

                                // New-step input, opened with the small "+".
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: card.addingStep ? 40 : 0
                                    clip: true
                                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                    Field {
                                        id: stepInput
                                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                        implicitHeight: 34
                                        placeholderText: "New step, press Enter"
                                        background: Rectangle { radius: 17; color: field }
                                        onAccepted: {
                                            if (text.trim()) { addStep(slot.index, text.trim()); text = "" }
                                        }
                                        Keys.onEscapePressed: { text = ""; card.addingStep = false }
                                        onActiveFocusChanged: if (!activeFocus && !text.trim()) card.addingStep = false
                                    }
                                }
                            }
                        }
                    }
                    }   // Repeater
                    }   // Column
                }   // Flickable
            }

            // ===== Courses (Canvas) =====
            ListView {
                id: courseList
                objectName: "courseList"
                Layout.leftMargin: 16; Layout.rightMargin: 6
                model: courseData
                spacing: 12
                clip: true
                acceptedButtons: Qt.NoButton
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                header: Item {
                    width: courseList.width - 10
                    height: headerCol.implicitHeight + 12
                    ColumnLayout {
                        id: headerCol
                        width: parent.width
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
                                spacing: 6
                                Text { text: "Connect Canvas"; font.pixelSize: 17; font.bold: true; color: textColor }
                                Text {
                                    Layout.fillWidth: true; wrapMode: Text.Wrap; color: textColor; lineHeight: 1.3
                                    text: "1.  In Canvas, open Calendar from the menu on the left.\n"
                                        + "2.  At the bottom right, click “Calendar Feed”.\n"
                                        + "3.  Copy the link and paste it here."
                                }
                                Text {
                                    Layout.fillWidth: true; wrapMode: Text.Wrap; color: muted; font.pixelSize: 12
                                    text: "The link is private: it shows your deadlines without logging in, so keep it to yourself."
                                }
                                Field {
                                    id: feedInput
                                    Layout.topMargin: 6
                                    placeholderText: "Paste the Calendar Feed link"
                                    onAccepted: connectCanvas(text)
                                }
                                Text {
                                    Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 12
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
                                font.pixelSize: 12
                                color: syncMessage && !syncing ? overdueText : muted
                                text: syncMessage ? syncMessage
                                    : canvas.last_sync ? "Synced " + Qt.formatDateTime(new Date(canvas.last_sync), "ddd dd MMM, HH:mm")
                                    : "Not synced yet"
                            }
                            Pill { text: "Sync"; fill: cardColor; hoverFill: field; enabled: !syncing; onClicked: syncCanvas() }
                            Pill {
                                text: "Disconnect"; fill: "transparent"; hoverFill: tabHover
                                labelColor: muted; bold: false
                                onClicked: disconnectCanvas()
                            }
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 30
                            visible: !!canvas.feed_url && !!canvas.last_sync && courseData.length === 0
                            text: "No upcoming assignments in your Canvas calendar."
                            color: muted; font.pixelSize: 14
                        }
                    }
                }

                footer: Item {
                    width: courseList.width - 10
                    height: removedCourses.length ? 44 : 12
                    Pill {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 4
                        visible: removedCourses.length > 0
                        text: "Restore " + removedCourses.length + " removed course" + (removedCourses.length > 1 ? "s" : "")
                        fill: "transparent"; hoverFill: tabHover; labelColor: muted; bold: false
                        onClicked: { for (const c of removedCourses) toggleCourseSetting("hidden", c) }
                    }
                }

                delegate: Rectangle {
                    id: courseCard
                    required property var modelData
                    readonly property bool collapsed: canvas.collapsed.indexOf(modelData.course) >= 0
                    readonly property var missing: modelData.items.filter(a => !addedUids[a.uid])
                    width: ListView.view.width - 10
                    height: courseCol.implicitHeight + 26
                    radius: 24; color: cardColor
                    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        id: courseCol
                        anchors { left: parent.left; right: parent.right; top: parent.top
                                  leftMargin: 18; rightMargin: 12; topMargin: 14 }
                        spacing: 4
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
                                Text { text: courseCard.modelData.code; font.pixelSize: 16; font.bold: true; color: textColor }
                                Text {
                                    Layout.fillWidth: true; elide: Text.ElideRight
                                    font.pixelSize: 12; color: muted
                                    text: courseCard.modelData.items.length + " upcoming"
                                        + (courseCard.modelData.course !== courseCard.modelData.code ? "  ·  " + courseCard.modelData.course : "")
                                }
                            }
                            Chevron {
                                open: !courseCard.collapsed
                                onClicked: toggleCourseSetting("collapsed", courseCard.modelData.course)
                            }
                            Pill {
                                visible: courseCard.missing.length > 0
                                text: "Add all"
                                onClicked: addFromCanvas(courseCard.missing)
                            }
                            RoundIcon {   // remove the course from this tab (stays removed when syncing)
                                turn: 45; hoverFill: red; hoverMark: deleteX
                                onClicked: toggleCourseSetting("hidden", courseCard.modelData.course)
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: courseCard.collapsed ? 0 : itemsCol.implicitHeight + 6
                            clip: true
                            Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            ColumnLayout {
                                id: itemsCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 6 }
                                spacing: 8
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
                                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: row.modelData.title; color: textColor }
                                            Text {
                                                Layout.fillWidth: true; elide: Text.ElideRight
                                                font.pixelSize: 12; color: muted
                                                text: whenText(row.modelData.due, row.modelData.time) + "  ·  " + relative(daysLeft(row.modelData.due))
                                            }
                                        }
                                        Pill {
                                            visible: !addedUids[row.modelData.uid]
                                            text: "+ Add"
                                            onClicked: addFromCanvas([row.modelData])
                                        }
                                        Text {
                                            visible: !!addedUids[row.modelData.uid]
                                            Layout.rightMargin: 8
                                            text: "✓ Added"; color: muted; font.pixelSize: 12
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ===== Calendar =====
            // The month with a dot per deadline in its subject's colour; below it, the chosen day's deadlines.
            Flickable {
                id: calendarView
                Layout.leftMargin: 16; Layout.rightMargin: 6
                contentWidth: width
                contentHeight: calendarCol.implicitHeight + 12
                clip: true
                acceptedButtons: Qt.NoButton
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: calendarCol
                    width: calendarView.width - 10
                    spacing: 10

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: monthCol.implicitHeight + 28
                        radius: 24; color: cardColor
                        ColumnLayout {
                            id: monthCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                            spacing: 6
                            // Arrows either side of the month, centred; "Today" off to the right.
                            // (In a narrow window they move left of centre and shrink rather than run into it.)
                            Item {
                                id: monthHeader
                                Layout.fillWidth: true
                                implicitHeight: 36
                                readonly property real room: width - todayButton.width - 8   // left of "Today"
                                Row {
                                    id: monthNav
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: Math.max(0, Math.min((monthHeader.width - width) / 2, monthHeader.room - width))
                                    spacing: 6
                                    MonthArrow { direction: -1; onClicked: shiftCalMonth(-1) }
                                    Text {
                                        // Fixed width, so the arrows stay put as the month name changes length.
                                        width: Math.min(150, monthHeader.room - 84)
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        text: Qt.locale("en_GB").standaloneMonthName(calMonth) + " " + calYear
                                        font.pixelSize: 16; font.bold: true; color: textColor
                                    }
                                    MonthArrow { onClicked: shiftCalMonth(1) }
                                }
                                Pill {
                                    id: todayButton
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    text: "Today"; bold: false
                                    onClicked: calendarToday()
                                }
                            }
                            DayOfWeekRow {
                                Layout.fillWidth: true
                                locale: Qt.locale("en_GB")
                                delegate: Text {
                                    required property string shortName
                                    text: shortName.slice(0, 2); color: muted; font.pixelSize: 11
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
                                readonly property int rowHeight: 92   // day number + 3 lines of deadlines
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
                                    // Room for 3 lines: all of them, or 2 and a "+N more" line.
                                    readonly property var shown: items.length <= 3 ? items : items.slice(0, 2)
                                    readonly property bool isSelected: iso === calDay
                                    // Titles get cut short in narrow cells, so hovering shows them in full.
                                    ToolTip.visible: bigHover.hovered && items.length > 0
                                    ToolTip.delay: 400
                                    ToolTip.text: items.map(t => t.subject + ": " + t.assignment + (t.time ? " (" + t.time + ")" : "")).join("\n")
                                    // Other months' days: hidden with opacity (see the date picker).
                                    opacity: model.month === bigGrid.month ? 1 : 0
                                    enabled: model.month === bigGrid.month
                                    Rectangle {
                                        // Every day has a soft box of its own; darker under the mouse.
                                        anchors.fill: parent; anchors.margins: 2; radius: 14
                                        color: bigHover.hovered ? line : field
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        border.width: bigCell.isSelected ? 2 : 0; border.color: accent
                                    }
                                    Rectangle {
                                        id: dayNumber
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 5; width: 24; height: 24; radius: 12
                                        color: bigCell.model.today ? accent : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: bigCell.model.day
                                            font.bold: true
                                            color: bigCell.model.today ? accentText
                                                 : bigCell.iso < isoDate(today()) ? muted : textColor
                                        }
                                    }
                                    // Each deadline: a small white rounded chip with its subject's colour dot
                                    // and the assignment title (like the "Previous subjects" chips).
                                    Column {
                                        anchors { left: parent.left; right: parent.right; top: dayNumber.bottom
                                                  leftMargin: 5; rightMargin: 5; topMargin: 4 }
                                        spacing: 2
                                        Repeater {
                                            model: bigCell.shown
                                            Rectangle {
                                                id: entry
                                                required property var modelData
                                                width: parent.width
                                                height: 17; radius: height / 2
                                                color: cardColor
                                                opacity: entry.modelData.done ? 0.6 : 1
                                                Rectangle {
                                                    id: entryDot
                                                    x: 5; anchors.verticalCenter: parent.verticalCenter
                                                    width: 7; height: 7; radius: 3.5
                                                    color: entry.modelData.done ? doneColor : subjectColor(entry.modelData.subject)
                                                }
                                                Text {
                                                    anchors { left: entryDot.right; right: parent.right; leftMargin: 4; rightMargin: 6
                                                              verticalCenter: parent.verticalCenter }
                                                    text: entry.modelData.assignment
                                                    elide: Text.ElideRight
                                                    font.pixelSize: 11; font.bold: true
                                                    font.strikeout: entry.modelData.done
                                                    color: entry.modelData.done ? doneColor : textColor
                                                }
                                            }
                                        }
                                        Text {
                                            visible: bigCell.items.length > bigCell.shown.length
                                            width: parent.width; elide: Text.ElideRight
                                            leftPadding: 5
                                            text: "+" + (bigCell.items.length - bigCell.shown.length) + " more"
                                            font.pixelSize: 11; font.bold: true; color: muted
                                        }
                                    }
                                    HoverHandler { id: bigHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: calDay = bigCell.iso }
                                }
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
                        Layout.leftMargin: 6; Layout.topMargin: 4
                        text: Qt.formatDate(parseDate(calDay), "dddd d MMMM") + "  ·  " + relative(daysLeft(calDay))
                        font.pixelSize: 14; font.bold: true; color: textColor
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
                            implicitHeight: 48; radius: 20; color: cardColor
                            border.width: 2; border.color: modelData.done ? cardColor : mark
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 16
                                spacing: 10
                                Rectangle {   // tick it off from here too
                                    width: 20; height: 20; radius: 10
                                    color: dayRow.modelData.done ? dayRow.mark : "transparent"
                                    border.width: 2; border.color: dayRow.mark
                                    Text { anchors.centerIn: parent; visible: dayRow.modelData.done; text: "✓"; color: "white"; font.pixelSize: 12; font.bold: true }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: toggleTask(dayRow.modelData.index) }
                                }
                                SubjectPill {
                                    Layout.maximumWidth: 140
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
                                    text: dayRow.modelData.time; font.pixelSize: 12; color: muted
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
