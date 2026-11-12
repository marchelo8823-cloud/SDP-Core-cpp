import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Sdp

Window {
    id: win
    width: startClamp ? Math.min(startW, Screen.desktopAvailableWidth) : startW; height: startClamp ? Math.min(startH, Screen.desktopAvailableHeight) : startH
    minimumWidth: Math.min(1100, Screen.desktopAvailableWidth); minimumHeight: Math.min(680, Screen.desktopAvailableHeight)
    visible: true
    visibility: startFullscreen ? Window.FullScreen : Window.Windowed
    title: st.remote ? "СДП — пост " + st.station : "СДП — окно оператора"
    color: Theme.bg

    readonly property var st: backend.s
    readonly property var be: backend
    property real step: 5
    property int stepIndex: 1
    readonly property var steps: [1, 5, 10, 50]
    readonly property bool active: st.mode !== 0 && st.mode !== 1
    property bool showReadout: false
    property string workView: "unified"            // unified — единое окно, desk — «Стол», classic — «Классика»
    readonly property bool deskMode: workView !== "classic"
    // Текущая страница (кнопки — в левой колонке): work | sensors | thr | pms | cap | fc | agent | admin
    property string page: "work"
    readonly property bool sensorsPage: page === "sensors"
    readonly property bool fcPage: page === "fc"
    readonly property bool capPage: page === "cap"
    readonly property bool thrPage: page === "thr"
    readonly property bool pmsPage: page === "pms"
    readonly property bool accessPage: page === "admin"
    readonly property bool agentPage: page === "agent"
    readonly property bool workPage: page === "work"
    readonly property bool isAdmin: adminSess.admin
    readonly property var navItems: [
        { id: "work", t: "Работа", short: "Работа" }, { id: "sensors", t: "Датчики", short: "Датчики" }, { id: "thr", t: "Движители", short: "Движители" }, { id: "pms", t: "PMS", short: "PMS" },
        { id: "cap", t: "Возможности", short: "Возможности" }, { id: "fc", t: "Прогноз", short: "Прогноз" },
        { id: "agent", t: "Помощник", short: "Помощник" }, { id: "admin", t: "Администрирование", short: "Админ." }
    ]
    function setView(v) { workView = v; backend.setSetting("workView", v) }

    // ------------------------------------------------------------ компоновка
    readonly property var blocks: [
        { id: "mode", title: "Режим работы", kind: "col" }, { id: "setpoint", title: "Уставка", kind: "col" }, { id: "law", title: "Закон управления", kind: "col" }, { id: "limits", title: "Ограничения движения", kind: "col" },
        { id: "thr", title: "Движители", kind: "col" }, { id: "force", title: "Усилия", kind: "col" }, { id: "sens", title: "Датчики", kind: "col" },
        { id: "t0", title: "График: отклонение", kind: "bot" }, { id: "t1", title: "График: курс", kind: "bot" }, { id: "t2", title: "График: загрузка", kind: "bot" }, { id: "log", title: "События", kind: "bot" }
    ]
    readonly property var builtinPresets: [
        { name: "Стандартная", layout: { left: ["mode", "setpoint", "limits", "law"], right: ["thr", "force", "sens"], bottom: ["t0", "t1", "t2", "log"], leftPx: 340, rightPx: 400, bottomPx: 230 } },
        { name: "Только карта", layout: { left: [], right: [], bottom: [], leftPx: 340, rightPx: 400, bottomPx: 230 } },
        { name: "Наблюдатель", layout: { left: [], right: ["thr", "force", "sens"], bottom: ["t0", "t1", "t2", "log"], leftPx: 340, rightPx: 400, bottomPx: 230 } },
        { name: "Оператор: карта и управление", layout: { left: ["mode", "setpoint", "limits", "law"], right: ["thr"], bottom: ["t0", "log"], leftPx: 340, rightPx: 360, bottomPx: 190 } }
    ]
    property var layout: builtinPresets[0].layout
    // Проверка компоновки: неизвестные и повторяющиеся блоки отбрасываются, размеры ограничиваются, блок попадает только в допустимое место.
    function normalizeLayout(l) {
        var known = {}, seen = {}
        for (var i = 0; i < blocks.length; ++i) known[blocks[i].id] = blocks[i].kind
        function clean(a, kind) {
            var r = []
            if (!a || !a.length) return r
            for (var k = 0; k < a.length; ++k) if (known[a[k]] === kind && !seen[a[k]]) { seen[a[k]] = true; r.push(a[k]) }
            return r
        }
        function num(v, lo, hi, d) { v = Number(v); return isNaN(v) ? d : Math.max(lo, Math.min(hi, Math.round(v))) }
        var o = {}
        o.left = clean(l ? l.left : [], "col"); o.right = clean(l ? l.right : [], "col"); o.bottom = clean(l ? l.bottom : [], "bot")
        o.leftPx = num(l ? l.leftPx : 0, 240, 520, 340); o.rightPx = num(l ? l.rightPx : 0, 260, 560, 400); o.bottomPx = num(l ? l.bottomPx : 0, 120, 420, 230)
        return o
    }
    function setLayout(l) { layout = normalizeLayout(l); backend.setSetting("layout", JSON.stringify(layout)) }
    function customPresets() { try { var o = JSON.parse(String(backend.setting("layoutPresets", "{}"))); return o && typeof o === "object" ? o : {} } catch (e) { return {} } }
    function blockComp(id) {
        switch (id) {
        case "mode": return cMode; case "setpoint": return cSetpoint; case "law": return cLaw; case "limits": return cLimits
        case "thr": return cThr; case "force": return cForce; case "sens": return cSens
        case "t0": return cT0; case "t1": return cT1; case "t2": return cT2; case "log": return cLog
        }
        return null
    }

    Component.onCompleted: {
        Theme.preset = Number(backend.setting("theme", 1))
        if (String(backend.setting("themeV28", "")) !== "1") { Theme.preset = 4; backend.setSetting("theme", 4); backend.setSetting("themeV28", "1") }   // v0.28: новое оформление один раз включается само, дальше выбор за оператором
        Theme.fs = Number(backend.setting("fontScale", 1.0))
        Theme.loadUnits(backend)
        try { var saved = String(backend.setting("layout", "")); if (saved !== "") layout = normalizeLayout(JSON.parse(saved)) } catch (e) { layout = builtinPresets[0].layout }
        // v0.27: блок «Ограничения движения» один раз добавляется в сохранённую раскладку (иначе в ней его не было бы)
        if (String(backend.setting("limitsBlockAdded", "")) !== "1") {
            var has = false, ls = [layout.left, layout.right, layout.bottom]
            for (var q = 0; q < ls.length; ++q) for (var z = 0; z < ls[q].length; ++z) if (ls[q][z] === "limits") has = true
            if (!has && layout.left.length > 0) { var nl = JSON.parse(JSON.stringify(layout)); nl.left.push("limits"); layout = normalizeLayout(nl); backend.setSetting("layout", JSON.stringify(layout)) }
            backend.setSetting("limitsBlockAdded", "1")
        }
        settings.showGrid = backend.setting("showGrid", true) === true || backend.setting("showGrid", true) === "true"
        settings.showTrail = backend.setting("showTrail", true) === true || backend.setting("showTrail", true) === "true"
        settings.underlay = !(backend.setting("underlay", true) === false || backend.setting("underlay", true) === "false")
        settings.graticule = !(backend.setting("graticule", true) === false || backend.setting("graticule", true) === "false")
        settings.mapOpacity = Number(backend.setting("mapOpacity", 0.8))
        var wv = String(backend.setting("workView", ""))
        if (wv === "unified" || wv === "desk" || wv === "classic") workView = wv
        else workView = "unified"        // v0.27: единое окно по умолчанию; старые виды выбираются кнопками слева
        showReadout = backend.setting("showReadout", false) === true || backend.setting("showReadout", false) === "true"
        if (startSettings) settings.open()
        if (startLayoutEditor) layoutEd.open()
        if (startAdmin) adminPage.open()
        var m = backend.setting("lastMap", "")
        if (m !== "" && backend.mapName === "") backend.loadMap(m)
    }

    // ------------------------------------------------------------ верхняя панель
    Rectangle {
        id: top
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: Theme.px(60); color: Theme.panel
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 12
            Text { text: "СДП"; color: Theme.accent; font.pixelSize: Theme.px(24); font.bold: true }
            Text { visible: win.width >= 1300; text: st.ship; color: Theme.text; font.pixelSize: Theme.px(18); elide: Text.ElideRight; Layout.maximumWidth: st.remote ? 150 : (win.width >= 1700 ? 260 : 170) }
            Chip { visible: st.remote; tone: !st.linked ? Theme.bad : st.inCommand ? Theme.ok : Theme.warn; solid: true
                   text: !st.linked ? "НЕТ СВЯЗИ С ЯДРОМ" : "ПОСТ " + st.station + (st.inCommand ? ": УПРАВЛЕНИЕ" : ": НАБЛЮДЕНИЕ") }
            Btn { visible: st.remote && st.linked
                  text: st.inCommand ? (st.requestedFromMe ? "Передать посту " + st.requester : "Снять управление")
                                     : (st.requestedByMe ? "Принять принудительно" : "Принять управление")
                  active: st.requestedFromMe
                  onClicked: {
                      if (st.inCommand) backend.giveControl()
                      else if (st.requestedByMe || st.holder === "") { if (st.holder === "") backend.takeControl(false); else forceDlg.open() }
                      else backend.takeControl(false)
                  } }
            Chip { text: st.modeText ? st.modeText.toUpperCase() : ""; tone: win.active ? Theme.ok : Theme.sub; solid: win.active }
            Chip { text: "Закон: " + st.lawText; tone: Theme.accent }
            Btn { enabledBtn: st.canControl; text: st.highGain ? "Усиление: высокое" : "Усиление: низкое"
                  onClicked: backend.command("gain " + (st.highGain ? "low" : "high")) }
            Btn { enabledBtn: st.canControl; text: st.minPower ? "Мин. мощность: вкл" : "Мин. мощность: выкл"
                  onClicked: backend.command("minpower " + (st.minPower ? "off" : "on")) }
            Chip { text: st.sim ? "ИМИТАЦИЯ" : "РЕАЛЬНЫЕ ДАННЫЕ"; tone: st.sim ? Theme.warn : Theme.ok; solid: st.sim }
            Chip { visible: win.width >= 1700 && !st.remote && backend.alarms.length === 0 && st.posValid && st.hdgValid; text: "Данные в норме"; tone: Theme.ok }
            Chip { id: asogChip; visible: st.asogName !== undefined && st.asogName !== "" && st.asogName !== "—"
                   text: st.asogName ? st.asogName.split(" — ")[0] : ""
                   tone: st.asog === 3 ? Theme.bad : st.asog === 2 ? Theme.warn : st.asog === 1 ? Theme.accent : Theme.ok; solid: st.asog >= 2
                   HoverHandler { id: asogHover }
                   ToolTip.visible: asogHover.hovered; ToolTip.delay: 200
                   ToolTip.text: st.asogName + "\n" + st.asogAction + (st.asogReasons ? "\nПричины: " + st.asogReasons : "") + "\n(общие правила, ASOG судна важнее)" }
            Chip { visible: !st.posValid; text: "НЕТ ПОЛОЖЕНИЯ"; tone: Theme.bad; solid: true }
            Chip { visible: !st.hdgValid; text: "НЕТ КУРСА"; tone: Theme.bad; solid: true }
            Item { Layout.fillWidth: true }
            Repeater {
                model: st.links
                Chip { required property var modelData
                       text: modelData.id + (modelData.connected ? (modelData.stale ? ": команды устарели" : ": связь") : ": НЕТ СВЯЗИ")
                       tone: modelData.connected && !modelData.stale ? Theme.ok : Theme.bad }
            }
            Chip { visible: st.refLost && !st.posDropout; text: "СЧИСЛЕНИЕ " + Math.round(st.refLostS) + " с"; tone: Theme.warn; solid: true }
            Chip { visible: st.posDropout; text: "ПОТЕРЯ ПОЛОЖЕНИЯ"; tone: Theme.bad; solid: true }
            Chip { visible: st.cqRunning; text: st.cqOk ? "Последствия: ОК" : "Последствия: ОТКАЗ НЕ ПЕРЕНОСИТСЯ"; tone: st.cqOk ? Theme.ok : Theme.warn; solid: !st.cqOk }
            Chip { visible: backend.alarms.length > 0 || st.unacked > 0; text: "Тревог: " + st.activeAlarms + (st.unacked > 0 ? " (не подтв. " + st.unacked + ")" : ""); tone: Theme.bad; solid: st.unacked > 0 }
            Btn { visible: st.unacked > 0; text: "Подтвердить"; onClicked: backend.ackAlarms() }
            Btn { visible: st.audible; text: "Заглушить"; onClicked: backend.silenceAlarms() }
            Btn { text: "Класс ДП: " + (st.dpClass > 0 ? st.dpClass : "—") + " ▸"; onClicked: backend.command("class " + (st.dpClass === 0 ? 2 : st.dpClass === 2 ? 3 : 0)) }
            Text { visible: win.width > 1400; text: st.sim ? "t = " + st.simTimeText : ""; color: Theme.sub; font.pixelSize: Theme.px(15); font.family: Theme.mono }
            Text { text: st.clockText; color: Theme.text; font.pixelSize: Theme.px(22); font.family: Theme.mono }
        }
    }

    // ------------------------------------------------------------ правая колонка значков: все страницы в одном месте
    Rectangle {
        id: rail
        anchors { right: parent.right; top: top.bottom; bottom: parent.bottom }
        width: Theme.px(92)
        color: Theme.panel
        border.color: Theme.line; border.width: 1
        Flickable {
            anchors { fill: parent; margins: 6 }
            contentHeight: railCol.height; clip: true; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: railCol; width: parent.width; spacing: 4
                Repeater {
                    model: win.navItems
                    Rectangle {
                        required property var modelData
                        readonly property bool on: win.page === modelData.id
                        width: railCol.width; height: Theme.px(68); radius: 8
                        color: on ? Theme.accent : (nm.containsMouse ? Theme.panel2 : "transparent")
                        border.color: on ? Theme.accent : "transparent"
                        Column {
                            anchors.centerIn: parent; spacing: 3; width: parent.width
                            NavIcon { anchors.horizontalCenter: parent.horizontalCenter; kind: modelData.id; tone: parent.parent.on ? (Theme.preset === 3 || Theme.preset === 0 ? "#ffffff" : Theme.bg) : Theme.text }
                            Text { width: parent.width - 4; x: 2; horizontalAlignment: Text.AlignHCenter; text: modelData.short; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                   font.pixelSize: Theme.px(11); font.bold: parent.parent.on
                                   color: parent.parent.on ? (Theme.preset === 3 || Theme.preset === 0 ? "#ffffff" : Theme.bg) : Theme.text }
                        }
                        MouseArea { id: nm; anchors.fill: parent; hoverEnabled: true; onClicked: win.page = modelData.id }
                    }
                }
                Rectangle { width: railCol.width; height: 1; color: Theme.line }
                Rectangle {
                    width: railCol.width; height: Theme.px(56); radius: 8
                    color: menuPop.opened ? Theme.panel2 : (mm.containsMouse ? Theme.panel2 : "transparent")
                    Column { anchors.centerIn: parent; spacing: 2; width: parent.width
                        NavIcon { anchors.horizontalCenter: parent.horizontalCenter; kind: "menu"; tone: Theme.text }
                        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Ещё"; font.pixelSize: Theme.px(11); color: Theme.text } }
                    MouseArea { id: mm; anchors.fill: parent; hoverEnabled: true; onClicked: menuPop.opened ? menuPop.close() : menuPop.open() }
                }
            }
        }
    }

    // дополнительные кнопки: вид окна, настройки вида, имитация
    Popup {
        id: menuPop
        x: parent.width - rail.width - width - 6; y: parent.height - height - 10; padding: 12
        background: Rectangle { color: Theme.panel; radius: 10; border.color: Theme.line }
        contentItem: Column {
            spacing: 6; width: Theme.px(210)
            Text { text: "ОКНО «РАБОТА»"; color: Theme.sub; font.pixelSize: Theme.px(11); font.bold: true; font.letterSpacing: 0.8 }
            Btn { width: parent.width; text: "Единое"; active: win.workView === "unified"; onClicked: win.setView("unified") }
            Btn { width: parent.width; text: "Стол"; active: win.workView === "desk"; onClicked: win.setView("desk") }
            Btn { width: parent.width; text: "Классика"; active: win.workView === "classic"; onClicked: win.setView("classic") }
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            Btn { width: parent.width; text: "Вид и палитра…"; onClicked: { menuPop.close(); settings.open() } }
            Btn { width: parent.width; visible: st.sim; text: "Имитация…"; active: simDlg.opened; onClicked: { menuPop.close(); simDlg.opened ? simDlg.close() : simDlg.open() } }
            Btn { width: parent.width; visible: st.sim; text: "Отказы PMS…"; onClicked: { menuPop.close(); pmsDlg.opened ? pmsDlg.close() : pmsDlg.open() } }
        }
    }

    // ------------------------------------------------------------ тело
    WorkView {
        id: workPane
        visible: win.workView === "unified" && win.workPage
        anchors { left: parent.left; right: rail.left; top: top.bottom; bottom: parent.bottom; margins: 10 }
        blockComp: win.blockComp
        viewSettings: settings
        onPlanDoubleClicked: (n, e) => { confirm.tN = n; confirm.tE = e; confirm.open() }
        onOpenThr: win.page = "thr"
        onOpenMapSettings: settings.showMap()
    }

    DeskView {
        id: desk
        visible: win.workView === "desk" && win.workPage
        anchors { left: parent.left; right: rail.left; top: top.bottom; bottom: parent.bottom; margins: 10 }
        blockComp: win.blockComp
        viewSettings: settings
        onOpenSim: simDlg.opened ? simDlg.close() : simDlg.open()
        onOpenPms: pmsDlg.opened ? pmsDlg.close() : pmsDlg.open()
        onPlanDoubleClicked: (n, e) => { confirm.tN = n; confirm.tE = e; confirm.open() }
        onLeave: win.setView("classic")
        onOpenMapSettings: settings.showMap()
    }

    SensorsPage {
        id: sensorsPageView
        visible: win.sensorsPage
        anchors { left: parent.left; right: rail.left; top: top.bottom; bottom: parent.bottom; margins: 10 }
    }

    ThrusterPage {
        id: thrPageView
        visible: win.thrPage
        anchors { left: parent.left; right: rail.left; top: top.bottom; bottom: parent.bottom; margins: 10 }
        onOpenPms: win.page = "pms"
    }

    CapabilityPage {
        id: capPageView
        visible: win.capPage
        anchors { left: parent.left; right: rail.left; top: top.bottom; bottom: parent.bottom; margins: 10 }
    }

    ForecastPage {
        id: fcPageView
        visible: win.fcPage
        anchors { left: parent.left; right: rail.left; top: top.bottom; bottom: parent.bottom; margins: 10 }
    }

    PmsPage {
        id: pmsPageView
        visible: win.pmsPage
        anchors { left: parent.left; right: rail.left; top: top.bottom; bottom: parent.bottom; margins: 10 }
    }

    AccessPage {
        id: accessPageView
        sess: adminSess
        visible: win.accessPage
        anchors { left: parent.left; right: rail.left; top: top.bottom; bottom: parent.bottom; margins: 10 }
        onOpenVessel: adminPage.open()
    }

    AgentPage {
        id: agentPageView
        sess: adminSess
        visible: win.agentPage
        anchors { left: parent.left; right: rail.left; top: top.bottom; bottom: parent.bottom; margins: 10 }
    }

    Item {
        id: body
        visible: !win.deskMode && win.workPage
        anchors { left: parent.left; right: rail.left; top: top.bottom; bottom: parent.bottom; margins: 10 }

        // ---- левая колонка (состав и порядок блоков задаёт компоновка)
        Flickable {
            id: left
            visible: win.layout.left.length > 0
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: win.layout.left.length > 0 ? Math.max(Theme.px(240), Math.min(Theme.px(win.layout.leftPx), win.width * 0.36)) : 0
            contentHeight: leftCol.height; clip: true; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: leftCol; width: left.width - 10; spacing: 10
                Repeater { model: win.layout.left; Loader { required property string modelData; width: leftCol.width; sourceComponent: win.blockComp(modelData); height: item ? item.height : 0 } }
            }
        }

        // ---- правая колонка
        Flickable {
            id: right
            visible: win.layout.right.length > 0
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: win.layout.right.length > 0 ? Math.max(Theme.px(260), Math.min(Theme.px(win.layout.rightPx), win.width * 0.38)) : 0
            contentHeight: rightCol.height; clip: true; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: rightCol; width: right.width - 10; x: 10; spacing: 10
                Repeater { model: win.layout.right; Loader { required property string modelData; width: rightCol.width; sourceComponent: win.blockComp(modelData); height: item ? item.height : 0 } }
            }
        }

        // ---- центр: план + нижняя часть
        Item {
            id: centre
            anchors { left: left.right; right: right.left; top: parent.top; bottom: parent.bottom; leftMargin: win.layout.left.length > 0 ? 10 : 0 }

            Rectangle {
                id: planFrame
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: bottomRow.top; bottomMargin: win.layout.bottom.length > 0 ? 10 : 0 }
                color: Theme.plan; radius: 8; border.color: Theme.line; clip: true
                PlanView {
                    id: plan
                    anchors.fill: parent; anchors.margins: 1
                    backend: win.be
                    scale: 6
                    headUp: false
                    cBg: Theme.plan; cGrid: Theme.grid; cText: Theme.planText; cHull: Theme.hull; cAccent: Theme.accent; cOk: Theme.planOk; cWarn: Theme.planWarn; cSetpoint: Theme.setpoint
                    fontPx: Theme.px(13)
                    showGrid: settings.showGrid; showTrail: settings.showTrail; mapOpacity: settings.mapOpacity
                    onWorldDoubleClicked: (n, e) => { confirm.tN = n; confirm.tE = e; confirm.open() }
                }
                // панель управления видом
                Rectangle {
                    anchors { left: parent.left; top: parent.top; margins: 10 }
                    width: tools.width + 12; height: tools.childrenRect.height + 12; radius: 8
                    color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.9); border.color: Theme.line
                Flow {
                    id: tools; x: 6; y: 6
                    property real natural: { var w = 0; for (var i = 0; i < children.length; ++i) w += children[i].width + spacing; return w - spacing }
                    width: Math.max(Theme.px(150), Math.min(natural, planFrame.width - Theme.px(190)))   // справа остаётся место под компас
                    spacing: 6
                    Btn { text: plan.headUp ? "Курс ↑" : "Север ↑"; onClicked: plan.headUp = !plan.headUp }
                    Btn { text: "Слежение"; active: plan.follow; onClicked: plan.follow = !plan.follow }
                    Btn { text: "＋"; width: Theme.px(40); onClicked: plan.zoomBy(1.4) }
                    Btn { text: "－"; width: Theme.px(40); onClicked: plan.zoomBy(1 / 1.4) }
                    Btn { text: "Всё"; onClicked: plan.fit() }
                    Btn { text: "Показания"; active: win.showReadout; onClicked: { win.showReadout = !win.showReadout; backend.setSetting("showReadout", win.showReadout) } }
                }
                }
                Text { anchors { left: parent.left; bottom: parent.bottom; margins: 12; bottomMargin: 82 } visible: backend.mapName !== ""
                       text: "Карта: " + backend.mapName; color: Theme.sub; font.pixelSize: Theme.px(12) }
                // компактная строка главных показаний у нижнего края карты (судно она не закрывает)
                Rectangle {
                    id: strip
                    anchors { right: parent.right; bottom: parent.bottom; margins: 8 }
                    width: stripRow.width + 20; height: Theme.px(34); radius: 6
                    color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.88); border.color: Theme.line
                    Row {
                        id: stripRow; x: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 16
                        Text { text: "Откл. " + Theme.f(st.errDist, 2) + " м"; color: st.errDist > 5 ? Theme.warn : Theme.text; font.pixelSize: Theme.px(14); font.family: Theme.mono }
                        Text { text: "Курс " + Theme.hdg(st.psi) + " (" + Theme.f(st.errHdg, 1) + "°)"; color: Math.abs(st.errHdg) > 3 ? Theme.warn : Theme.text; font.pixelSize: Theme.px(14); font.family: Theme.mono }
                        Text { text: "V " + Theme.f(st.speed, 2); color: Theme.text; font.pixelSize: Theme.px(14); font.family: Theme.mono }
                    }
                }
                // крупные показания (по кнопке «Показания»)
                Rectangle {
                    visible: win.showReadout
                    anchors { right: parent.right; bottom: strip.top; margins: 10; bottomMargin: 6 }
                    width: Theme.px(250); height: readCol.height + 20; radius: 8; color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.88); border.color: Theme.line
                    Column {
                        id: readCol; x: 12; y: 10; width: parent.width - 24; spacing: 2
                        Readout { width: parent.width; label: "Курс"; value: Theme.hdg(st.psi) + "  (" + Theme.f(st.errHdg, 1) + "°)" ; tone: Math.abs(st.errHdg) > 3 ? Theme.warn : Theme.text }
                        Readout { width: parent.width; label: "Отклонение, м"; value: Theme.f(st.errDist, 2); tone: st.errDist > 5 ? Theme.warn : Theme.text }
                        Readout { width: parent.width; label: "Вдоль / поперёк, м"; value: Theme.f(st.errAlong, 1) + " / " + Theme.f(st.errCross, 1) }
                        Readout { width: parent.width; label: "Скорость, м/с"; value: Theme.f(st.speed, 2) }
                        Readout { width: parent.width; label: "Ветер, м/с"; value: st.windValid ? Theme.f(st.windSpeed, 1) + " из " + Theme.hdg(st.psi + st.windFromRel) : "—" }
                        Readout { width: parent.width; label: "Внешняя сила, кН"; value: Theme.f(st.forceKN, 1) }
                        Readout { width: parent.width; label: "Погрешность, м"; value: st.posValid ? Theme.f(st.posSigma, 2) : "—" }
                    }
                }
            }

            RowLayout {
                id: bottomRow
                visible: win.layout.bottom.length > 0
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: win.layout.bottom.length > 0 ? Theme.px(win.layout.bottomPx) : 0
                spacing: 10
                Repeater {
                    model: win.layout.bottom
                    Loader {
                        required property string modelData
                        sourceComponent: win.blockComp(modelData)
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Layout.preferredWidth: modelData === "log" ? 200 : 100
                        Layout.minimumWidth: Theme.px(modelData === "log" ? 100 : 56)
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ подтверждение перемещения уставки
    Popup {
        id: confirm
        property real tN: 0
        property real tE: 0
        modal: true; anchors.centerIn: Overlay.overlay; padding: 20
        background: Rectangle { color: Theme.panel; radius: 10; border.color: Theme.line }
        contentItem: Column {
            spacing: 14
            Text { text: "Переместить уставку?"; color: Theme.text; font.pixelSize: Theme.px(20); font.bold: true }
            Text { text: "Север " + Theme.f(confirm.tN, 1) + " м, восток " + Theme.f(confirm.tE, 1) + " м"; color: Theme.sub; font.pixelSize: Theme.px(15) }
            Row {
                spacing: 8
                Btn { text: "Переместить"; active: true; onClicked: { backend.command("set " + confirm.tN + " " + confirm.tE + " " + st.spPsi); confirm.close() } }
                Btn { text: "Отмена"; onClicked: confirm.close() }
            }
        }
    }

    Popup {
        id: forceDlg
        modal: true; anchors.centerIn: Overlay.overlay; padding: 20
        background: Rectangle { color: Theme.panel; radius: 10; border.color: Theme.bad; border.width: 2 }
        contentItem: Column {
            spacing: 14
            Text { text: "Принять управление принудительно?"; color: Theme.text; font.pixelSize: Theme.px(20); font.bold: true }
            Text { text: "Пост «" + st.holder + "» не передал управление. Управление у него будет отнято сразу."; color: Theme.sub; font.pixelSize: Theme.px(15); wrapMode: Text.Wrap; width: Theme.px(420) }
            Row {
                spacing: 8
                Btn { text: "Принять принудительно"; active: true; onClicked: { backend.takeControl(true); forceDlg.close() } }
                Btn { text: "Отмена"; onClicked: forceDlg.close() }
            }
        }
    }

    AdminPage { id: adminPage; onClosed: adminSess.refresh() }
    AdminSession { id: adminSess }
    onPageChanged: if (page === "work" && adminSess.admin) adminSess.logout()
    SimDialog { id: simDlg }
    PmsDialog { id: pmsDlg }
    SettingsPopup { id: settings; onOpenLayout: { settings.close(); layoutEd.open() } }
    LayoutEditor { id: layoutEd; layout: win.layout; blocks: win.blocks; builtin: win.builtinPresets; custom: win.customPresets()
                   onEdited: (l) => win.setLayout(l)
                   onPresetsChanged: (all) => backend.setSetting("layoutPresets", JSON.stringify(all)) }

    // ------------------------------------------------------------ блоки (переставляются редактором компоновки)
    Component {
        id: cMode
        Panel {
            width: parent ? parent.width : 0; title: "Режим работы"; height: Theme.px(130)
            enabled: st.canControl; opacity: st.canControl ? 1.0 : 0.5
            Grid {
                columns: 2; spacing: 6; width: parent.width
                Btn { width: (parent.width - 6) / 2; text: "Ожидание"; active: st.mode === 0; onClicked: backend.command("standby") }
                Btn { width: (parent.width - 6) / 2; text: "Курс"; active: st.mode === 3; onClicked: backend.command("heading") }
                Btn { width: (parent.width - 6) / 2; text: "Позиция"; active: st.mode === 4; onClicked: backend.command("position") }
                Btn { width: (parent.width - 6) / 2; text: "Трек"; active: st.mode === 5; onClicked: backend.command("track") }
            }
        }
    }

    Component {
        id: cSetpoint
        Panel {
            id: spPanel
            width: parent ? parent.width : 0; title: "Уставка"; height: Theme.px(740)
            enabled: st.canControl; opacity: st.canControl ? 1.0 : 0.5
            Column {
                width: parent.width; spacing: 6
                Readout { width: parent.width; label: "Север, м"; value: Theme.f(st.spN, 1) }
                Readout { width: parent.width; label: "Восток, м"; value: Theme.f(st.spE, 1) }
                Readout { width: parent.width; label: "Курс"; value: Theme.hdg(st.spPsi) }
                Text { visible: st.spPending; width: parent.width; wrapMode: Text.Wrap; color: Theme.warn; font.pixelSize: Theme.px(12); text: "Уставка запомнена и применится при включении режима" }
                Rectangle { width: parent.width; height: 1; color: Theme.line }
                Text { text: "Шаг, м (сдвиг по курсу судна)"; color: Theme.sub; font.pixelSize: Theme.px(13) }
                Seg { width: parent.width; model: ["1", "5", "10", "50"]; current: win.stepIndex; onPicked: (i) => { win.stepIndex = i; win.step = win.steps[i] } }
                // сдвиг новой точки относительно СУДНА (нос / корма / борта), а не сторон света; точка не применяется, пока её не подтвердили
                Item {
                    width: parent.width; height: Theme.px(176)
                    property real bw: (parent.width - 12) / 3
                    property real bh: Theme.px(44)
                    Btn { x: parent.bw + 6; y: 0; width: parent.bw; height: parent.bh; text: "▲ Нос"; onClicked: backend.proposeBody(win.step, 0) }
                    Btn { x: parent.bw + 6; y: parent.bh * 2 + 24; width: parent.bw; height: parent.bh; text: "▼ Корма"; onClicked: backend.proposeBody(-win.step, 0) }
                    Btn { x: 0; y: parent.bh + 12; width: parent.bw; height: parent.bh; text: "Левый борт"; onClicked: backend.proposeBody(0, -win.step) }
                    Btn { x: (parent.bw + 6) * 2; y: parent.bh + 12; width: parent.bw; height: parent.bh; text: "Правый борт"; onClicked: backend.proposeBody(0, win.step) }
                }
                Row {
                    spacing: 6; width: parent.width
                    Btn { width: (parent.width - 18) / 4; text: "−10°"; onClicked: backend.command("hdg " + (st.spPsi - 10)) }
                    Btn { width: (parent.width - 18) / 4; text: "−1°"; onClicked: backend.command("hdg " + (st.spPsi - 1)) }
                    Btn { width: (parent.width - 18) / 4; text: "+1°"; onClicked: backend.command("hdg " + (st.spPsi + 1)) }
                    Btn { width: (parent.width - 18) / 4; text: "+10°"; onClicked: backend.command("hdg " + (st.spPsi + 10)) }
                }
                // подтверждение новой точки
                Rectangle {
                    visible: backend.propOn; width: parent.width; height: propCol.height + 16; radius: 8; color: "transparent"; border.color: Theme.setpoint; border.width: 1
                    Column { id: propCol; x: 8; y: 8; width: parent.width - 16; spacing: 6
                        Text { text: "НОВАЯ ТОЧКА — ПОДТВЕРДИТЕ"; color: Theme.setpoint; font.pixelSize: Theme.px(12); font.bold: true }
                        Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.text; font.pixelSize: Theme.px(14); font.family: Theme.mono
                               text: "N " + Theme.f(backend.propN, 1) + "  E " + Theme.f(backend.propE, 1) + "  курс " + Theme.hdg(backend.propPsi >= 0 ? backend.propPsi : st.spPsi)
                                     + "\nсдвиг " + Theme.f(Math.hypot(backend.propN - st.spN, backend.propE - st.spE), 1) + " м от текущей уставки" }
                        Row { spacing: 6; width: parent.width
                            Btn { width: (parent.width - 6) / 2; text: "✓ Принять"; onClicked: backend.proposeAccept() }
                            Btn { width: (parent.width - 6) / 2; text: "✕ Отмена"; onClicked: backend.proposeCancel() }
                        }
                    }
                }
                Item { width: 1; height: Theme.px(20) }
                Text { text: "Ввод точных значений"; color: Theme.sub; font.pixelSize: Theme.px(13) }
                Row {
                    spacing: 6; width: parent.width
                    TextField { id: fN; width: (parent.width - 12) / 3; height: Theme.px(38); placeholderText: "Север"; placeholderTextColor: Theme.sub; color: Theme.text; font.pixelSize: Theme.px(14)
                                inputMethodHints: Qt.ImhFormattedNumbersOnly; background: Rectangle { color: Theme.panel2; border.color: Theme.line; radius: 5 } }
                    TextField { id: fE; width: (parent.width - 12) / 3; height: Theme.px(38); placeholderText: "Восток"; placeholderTextColor: Theme.sub; color: Theme.text; font.pixelSize: Theme.px(14)
                                inputMethodHints: Qt.ImhFormattedNumbersOnly; background: Rectangle { color: Theme.panel2; border.color: Theme.line; radius: 5 } }
                    TextField { id: fH; width: (parent.width - 12) / 3; height: Theme.px(38); placeholderText: "Курс"; placeholderTextColor: Theme.sub; color: Theme.text; font.pixelSize: Theme.px(14)
                                inputMethodHints: Qt.ImhFormattedNumbersOnly; background: Rectangle { color: Theme.panel2; border.color: Theme.line; radius: 5 } }
                }
                Btn { width: parent.width; text: "Задать точку (с подтверждением)"; onClicked: {
                        var n = parseFloat(fN.text.replace(",", ".")), e = parseFloat(fE.text.replace(",", ".")), h = parseFloat(fH.text.replace(",", "."))
                        if (!isNaN(n) && !isNaN(e) && !isNaN(h)) backend.propose(n, e, ((h % 360) + 360) % 360)    // сначала подтверждение
                    } }
            }
        }
    }

    Component {
        id: cLimits
        Panel {
            width: parent ? parent.width : 0; title: "Ограничения движения"; height: Theme.px(236)
            enabled: st.canControl; opacity: st.canControl ? 1.0 : 0.5
            Column {
                width: parent.width; spacing: 6
                Readout { width: parent.width; label: "Поворот"; value: st.capRot > 0 ? "до " + Theme.f(st.capRot, 1) + " °/мин" : "не ограничен"; tone: st.capRot > 0 ? Theme.warn : Theme.text }
                Readout { width: parent.width; label: "Скорость"; value: st.capSpeed > 0 ? "до " + Theme.f(st.capSpeed, 2) + " уз" : "не ограничена"; tone: st.capSpeed > 0 ? Theme.warn : Theme.text }
                Row {
                    spacing: 6; width: parent.width
                    TextField { id: fRot; width: (parent.width - 6) / 2; height: Theme.px(36); placeholderText: "°/мин"; placeholderTextColor: Theme.sub; color: Theme.text; font.pixelSize: Theme.px(14)
                                inputMethodHints: Qt.ImhFormattedNumbersOnly; background: Rectangle { color: Theme.panel2; border.color: Theme.line; radius: 5 } }
                    TextField { id: fSpd; width: (parent.width - 6) / 2; height: Theme.px(36); placeholderText: "уз"; placeholderTextColor: Theme.sub; color: Theme.text; font.pixelSize: Theme.px(14)
                                inputMethodHints: Qt.ImhFormattedNumbersOnly; background: Rectangle { color: Theme.panel2; border.color: Theme.line; radius: 5 } }
                }
                Row {
                    spacing: 6; width: parent.width
                    Btn { width: (parent.width - 6) / 2; text: "Применить"; active: true; onClicked: {
                            var r = fRot.text.replace(",", "."), v = fSpd.text.replace(",", ".")
                            if (r !== "" && !isNaN(parseFloat(r))) backend.command("rate rot " + parseFloat(r))
                            if (v !== "" && !isNaN(parseFloat(v))) backend.command("rate speed " + parseFloat(v))
                            fRot.text = ""; fSpd.text = ""
                        } }
                    Btn { width: (parent.width - 6) / 2; text: "Снять оба"; onClicked: { backend.command("rate rot off"); backend.command("rate speed off") } }
                }
                Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.sub; font.pixelSize: Theme.px(11)
                       text: "Предел действует на опорную точку. Джойстик не ограничивается." }
            }
        }
    }

    Component {
        id: cLaw
        Panel {
            width: parent ? parent.width : 0; title: "Закон управления"; height: Theme.px(90)
            enabled: st.canControl; opacity: st.canControl ? 1.0 : 0.5
            Seg { width: parent.width; model: ["ПИД", "LQR", "MPC"]; current: st.lawText === "ПИД" ? 0 : (st.lawText === "LQR" ? 1 : 2)
                  onPicked: (i) => backend.command("law " + ["pid", "lqr", "mpc"][i]) }
        }
    }

    Component {
        id: cThr
        Panel {
            width: parent ? parent.width : 0; title: "Движители"
            height: Theme.px(52) * Math.max(1, backend.thrusters.length) + Theme.px(60)
            Column {
                width: parent.width
                Repeater { model: backend.thrusters; ThrusterRow { required property var modelData; width: parent.width; d: modelData } }
            }
        }
    }

    Component {
        id: cForce
        Panel {
            width: parent ? parent.width : 0; title: "Усилия, кН"; height: Theme.px(176)
            Column {
                width: parent.width; spacing: 8
                Text { text: "запрос / возможно"; color: Theme.sub; font.pixelSize: Theme.px(11) }
                Repeater {
                    model: [{ n: "Вперёд/назад", v: st.tauX, c: st.capX }, { n: "Вправо/влево", v: st.tauY, c: st.capY }, { n: "Момент на курс", v: st.tauN, c: st.capN }]
                    Item {
                        required property var modelData
                        width: parent.width; height: Theme.px(30)
                        Text { text: modelData.n; color: Theme.sub; font.pixelSize: Theme.px(13) }
                        Text { anchors.right: parent.right; text: Theme.f(modelData.v, 0) + " / " + Theme.f(modelData.c, 0); color: Theme.text; font.pixelSize: Theme.px(13); font.family: Theme.mono }
                        Rectangle { y: Theme.px(18); width: parent.width; height: 8; radius: 4; color: Theme.panel2
                            Rectangle { x: parent.width / 2; width: 2; height: parent.height; color: Theme.sub }
                            Rectangle { height: parent.height; radius: 4
                                readonly property real fr: modelData.c > 0 ? Math.max(-1, Math.min(1, modelData.v / modelData.c)) : 0
                                x: fr >= 0 ? parent.width / 2 : parent.width / 2 + fr * parent.width / 2
                                width: Math.abs(fr) * parent.width / 2
                                color: Math.abs(fr) > 0.9 ? Theme.bad : (Math.abs(fr) > 0.7 ? Theme.warn : Theme.accent) }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: cSens
        Panel {
            width: parent ? parent.width : 0; title: "Датчики"
            height: Theme.px(26) * Math.max(1, backend.sensors.length) + Theme.px(70)
            Column {
                width: parent.width; spacing: 2
                Repeater {
                    model: backend.sensors
                    Item {
                        required property var modelData
                        width: parent.width; height: Theme.px(24)
                        Rectangle { id: dot; width: 12; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter
                            color: modelData.valid ? Theme.ok : Theme.bad }
                        Text { x: 22; anchors.verticalCenter: parent.verticalCenter; text: modelData.id; color: Theme.text; font.pixelSize: Theme.px(14) }
                        Text { visible: parent.width > Theme.px(330); x: Theme.px(130); anchors.verticalCenter: parent.verticalCenter; text: modelData.group; color: Theme.sub; font.pixelSize: Theme.px(13) }
                        Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            text: modelData.valid ? (modelData.rejected > 0 ? "отбраковок: " + modelData.rejected : "норма") : "нет данных"
                            color: modelData.valid ? (modelData.rejected > 0 ? Theme.warn : Theme.sub) : Theme.bad; font.pixelSize: Theme.px(13) }
                    }
                }
            }
        }
    }

    component TrendBlock: Panel {
        property int idx: 0
        property string unitText: ""
        anchors.fill: parent; pad: 10
        TrendView { anchors.fill: parent; anchors.topMargin: 2; backend: win.be; series: idx; unit: unitText
                    cBg: Theme.panel2; cGrid: Theme.line; cText: Theme.sub; cLine: Theme.accent; fontPx: Theme.px(11) }
    }
    Component { id: cT0; TrendBlock { title: "Откл., м"; idx: 0; unitText: "м" } }
    Component { id: cT1; TrendBlock { title: "Курс, °"; idx: 1; unitText: "°" } }
    Component { id: cT2; TrendBlock { title: "Загр., %"; idx: 2; unitText: "%" } }
    Component {
        id: cLog
        Panel {
            anchors.fill: parent; title: "События"; pad: 10
            ListView {
                anchors.fill: parent; clip: true; model: backend.log; spacing: 2
                delegate: Text { required property string modelData; width: ListView.view.width; text: modelData; wrapMode: Text.Wrap
                                 color: modelData.indexOf("ТРЕВОГА") >= 0 ? Theme.bad : Theme.text; font.pixelSize: Theme.px(13) }
            }
        }
    }
}
