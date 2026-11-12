import QtQuick
import QtQuick.Controls

// Окно «Прогноз сил»: таблица поправок модели ветра по направлению и силе ветра (накапливается, пока судно удерживается),
// медленная составляющая (течение) и прогноз силы и загрузки комплекса на 1, 2, 5 и 10 минут.
// ⚠ Оценка по накопленным данным и модели ядра. Порывы (секунды) не предсказываются. Не сертифицировано.
Item {
    id: pg
    readonly property var st: backend.s
    readonly property var fc: st.fc || ({})
    readonly property bool can: st.canControl === true
    property bool confirmReset: false
    property int tab: 0                                 // 0 — прогноз сил, 1 — калибровка систем положения
    readonly property var cal: st.cal || ({})
    property string confirmApply: ""
    Timer { id: caTimer; interval: 4000; onTriggered: pg.confirmApply = "" }
    Timer { id: cfTimer; interval: 4000; onTriggered: pg.confirmReset = false }
    function kn(v) { return (v === undefined ? 0 : v).toFixed(1) }
    function ratioColor(r) { return r >= 1.0 ? Theme.bad : r >= 0.8 ? Theme.warn : Theme.ok }
    onFcChanged: heat.requestPaint()

    Rectangle { anchors.fill: parent; radius: 8; color: Theme.panel; border.color: Theme.line }
    Text { x: Theme.px(16); y: Theme.px(10); text: pg.tab === 0 ? "ПРОГНОЗ СИЛ" : "КАЛИБРОВКА СИСТЕМ ПОЛОЖЕНИЯ"; color: Theme.text; font.pixelSize: Theme.px(18); font.bold: true }
    Row { x: Theme.px(420); y: Theme.px(8); spacing: Theme.px(6); z: 5
        Btn { text: "Прогноз"; px: Theme.px(13); active: pg.tab === 0; onClicked: pg.tab = 0 }
        Btn { text: "Калибровка"; px: Theme.px(13); active: pg.tab === 1; onClicked: pg.tab = 1 } }
    Text { visible: pg.tab === 0; x: Theme.px(16); y: Theme.px(36); width: parent.width - Theme.px(32); elide: Text.ElideRight
           text: "Пока судно удерживается, ядро запоминает, насколько модель ветра ошибается при разных ветрах, и по среднему и тренду прогнозирует силы и загрузку комплекса."
           color: Theme.sub; font.pixelSize: Theme.px(13) }
    Chip { anchors { right: parent.right; top: parent.top; margins: Theme.px(14) } text: "ИМИТАЦИЯ"; tone: Theme.warn; solid: true; visible: st.sim }

    // ---- управление
    Row {
        id: ctl
        visible: pg.tab === 0
        x: Theme.px(16); y: Theme.px(62); spacing: Theme.px(8)
        Btn { enabledBtn: pg.can; active: fc.on === true; text: fc.on ? "Накопление и прогноз: вкл" : "Накопление и прогноз: выкл"; onClicked: backend.command("forecast " + (fc.on ? "off" : "on")) }
        Btn { enabledBtn: pg.can && fc.on === true; active: fc.apply === true; text: fc.apply ? "Применять поправку: вкл" : "Применять поправку: выкл"; onClicked: backend.command("forecast apply " + (fc.apply ? "off" : "on")) }
        Btn { enabledBtn: pg.can; text: "Сохранить"; onClicked: backend.command("forecast save") }
        Btn { enabledBtn: pg.can; text: pg.confirmReset ? "Очистить? Нажмите ещё раз" : "Очистить таблицу"
              onClicked: { if (pg.confirmReset) { backend.command("forecast reset"); pg.confirmReset = false } else { pg.confirmReset = true; cfTimer.restart() } } }
    }

    // ---- карта таблицы
    Text { id: mapTitle; visible: pg.tab === 0; x: Theme.px(16); y: Theme.px(108); text: "Карта поправок: ветер по направлению и силе, модуль поправки, кН"; color: Theme.sub; font.pixelSize: Theme.px(13); font.bold: true }
    Canvas {
        id: heat
        visible: pg.tab === 0
        x: Theme.px(16); y: Theme.px(132); width: parent.width * 0.58; height: parent.height - Theme.px(190)
        onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d"); ctx.reset()
            var nd = fc.dirBins || 36, ns = fc.spdBins || 10, map = fc.map || []
            var lm = Theme.px(46), tm = Theme.px(4), bm = Theme.px(30)
            var cw = (width - lm) / nd, ch = (height - tm - bm) / ns
            var mx = 5
            for (var i = 0; i < map.length; ++i) if (map[i] > mx) mx = map[i]
            for (var s = 0; s < ns; ++s) for (var d = 0; d < nd; ++d) {
                var v = map.length > s * nd + d ? map[s * nd + d] : -1
                var x = lm + d * cw, y = tm + (ns - 1 - s) * ch
                if (v < 0) ctx.fillStyle = Theme.panel2
                else { var t = Math.min(1, v / mx); ctx.fillStyle = Qt.hsla(0.60 - 0.60 * t, 0.75, 0.42, 1.0) }
                ctx.fillRect(x + 0.5, y + 0.5, cw - 1, ch - 1)
            }
            // текущая ячейка
            if (fc.cellDir >= 0 && fc.cellSpd >= 0) {
                ctx.strokeStyle = Theme.text; ctx.lineWidth = 3
                ctx.strokeRect(lm + fc.cellDir * cw, tm + (ns - 1 - fc.cellSpd) * ch, cw, ch)
            }
            ctx.fillStyle = Theme.sub; ctx.font = Math.round(Theme.px(12)) + "px sans-serif"; ctx.textAlign = "right"
            for (var q = 0; q < ns; ++q) ctx.fillText((q * (fc.spdStep || 3)) + (q === ns - 1 ? "+" : "…") , lm - 6, tm + (ns - 1 - q) * ch + ch * 0.65)
            ctx.textAlign = "center"
            for (var a = 0; a < 360; a += 90) ctx.fillText(a + "°", lm + (a / 360) * nd * cw, height - bm + Theme.px(16))
            ctx.fillText("направление ветра относительно носа →", lm + (nd * cw) / 2, height - 4)
            ctx.save(); ctx.translate(12, tm + (ns * ch) / 2); ctx.rotate(-Math.PI / 2); ctx.fillText("м/с", 0, 0); ctx.restore()
        }
    }
    Text { visible: pg.tab === 0; x: Theme.px(16); y: heat.y + heat.height + Theme.px(4); width: heat.width; wrapMode: Text.WordWrap; color: Theme.sub; font.pixelSize: Theme.px(12)
           text: "Серые ячейки — данных мало (меньше 5 мин). Белая рамка — ячейка нынешних условий. Цвет — модуль поправки: от синего (малая) до красного (наибольшая в таблице)." }

    // ---- справа
    Column {
        id: rcol
        visible: pg.tab === 0
        anchors { left: heat.right; leftMargin: Theme.px(20); right: parent.right; rightMargin: Theme.px(16); top: parent.top; topMargin: Theme.px(108) }
        spacing: Theme.px(8)
        Text { text: "Накоплено"; color: Theme.sub; font.pixelSize: Theme.px(13); font.bold: true }
        Text { width: rcol.width; wrapMode: Text.WordWrap; color: Theme.text; font.pixelSize: Theme.px(14)
               text: !fc.on ? "Выключено. Включите «Накопление и прогноз»." : "Данных: " + Math.round(fc.dataMin || 0) + " мин, ячеек с данными: " + (fc.filled || 0) + " из " + (fc.total || 0) + ". Доверие к нынешней ячейке: " + Math.round(100 * (fc.conf || 0)) + " %." }
        Text { width: rcol.width; wrapMode: Text.WordWrap; color: Theme.sub; font.pixelSize: Theme.px(13)
               visible: fc.on === true
               text: "Поправка ячейки (вперёд / вбок / момент): " + pg.kn(fc.cx) + " / " + pg.kn(fc.cy) + " кН, " + pg.kn(fc.cn) + " кН·м. Медленная составляющая (течение): " + pg.kn(fc.sx) + " / " + pg.kn(fc.sy) + " кН, " + pg.kn(fc.sn) + " кН·м." }
        Item { width: 1; height: Theme.px(6) }
        Text { text: "Прогноз сил и загрузки"; color: Theme.sub; font.pixelSize: Theme.px(13); font.bold: true }
        Rectangle {
            width: rcol.width; height: Theme.px(24); color: "transparent"
            Row { anchors.fill: parent; spacing: 0
                Repeater { model: ["Через", "Вперёд, кН", "Вбок, кН", "Момент", "Загрузка"]
                           Text { width: rcol.width / 5; text: modelData; color: Theme.sub; font.pixelSize: Theme.px(12); font.bold: true; horizontalAlignment: index === 0 ? Text.AlignLeft : Text.AlignRight } } }
        }
        Repeater {
            model: (fc.valid && fc.hz) ? fc.hz.length : 0
            delegate: Rectangle {
                required property int index
                width: rcol.width; height: Theme.px(28); radius: 3; color: index % 2 ? "transparent" : Theme.panel2
                readonly property real ld: fc.load[index]
                Row { anchors.fill: parent; spacing: 0
                    Text { width: rcol.width / 5; height: parent.height; verticalAlignment: Text.AlignVCenter; text: Math.round(fc.hz[index] / 60) + " мин"; color: Theme.text; font.pixelSize: Theme.px(14); leftPadding: 4 }
                    Text { width: rcol.width / 5; height: parent.height; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; text: pg.kn(fc.fx[index]); color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(13) }
                    Text { width: rcol.width / 5; height: parent.height; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; text: pg.kn(fc.fy[index]); color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(13) }
                    Text { width: rcol.width / 5; height: parent.height; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; text: pg.kn(fc.fn[index]); color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(13) }
                    Text { width: rcol.width / 5; height: parent.height; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; rightPadding: 4; text: Math.round(100 * ld) + " %"; color: pg.ratioColor(ld); font.family: Theme.mono; font.pixelSize: Theme.px(14); font.bold: true }
                }
            }
        }
        Text { width: rcol.width; wrapMode: Text.WordWrap; color: Theme.sub; font.pixelSize: Theme.px(13); visible: fc.on === true && fc.valid !== true
               text: "Прогноз появится, когда будут данные о ветре и курсе и накопится хотя бы немного данных при удержании." }
        Text { width: rcol.width; wrapMode: Text.WordWrap; color: fc.warn ? Theme.bad : Theme.sub; font.pixelSize: Theme.px(13); font.bold: fc.warn === true; visible: fc.on === true
               text: fc.warn ? "Прогноз: нагрузка через 5 минут превысит порог. Подготовьтесь (ветер, курс, режим, резерв мощности)." : "Загрузка 100 % — предел при 80 % упора. Тревога включается, если прогноз на 5 мин выше 90 %." }
        Item { width: 1; height: Theme.px(6) }
        Text { width: rcol.width; wrapMode: Text.WordWrap; color: Theme.warn; font.pixelSize: Theme.px(12)
               text: "⚠ Оценка по накопленным данным и модели ядра, не сертифицировано. Порывы не предсказываются. Поправка таблицы ограничена 25 % возможностей комплекса и накапливается только при спокойном удержании в режиме «позиция». Таблица сохраняется в папке данных и применяется только для того же судна." }
    }

    // ------------------------------------------------------------ калибровка систем положения
    // Невязка системы = её позиция (с применёнными поправками) минус эталон; эталон — медиана остальных или выбранная система.
    // ⚠ Выравнивает системы друг относительно друга; общая ошибка всех систем не видна. Оценка по имитатору, не сертифицировано.
    Item {
        id: calBox
        visible: pg.tab === 1
        x: Theme.px(16); y: Theme.px(40); width: parent.width - Theme.px(32); height: parent.height - Theme.px(52)
        readonly property var rows: cal.s || []
        readonly property var refModel: { var r = ["Медиана"]; for (var i = 0; i < rows.length; ++i) r.push(rows[i].id); return r }
        readonly property int refIdx: { if (!cal.ref) return 0; for (var i = 0; i < rows.length; ++i) if (rows[i].id === cal.ref) return i + 1; return 0 }
        function f2(v) { return (v === undefined ? 0 : v).toFixed(2) }
        Text { width: parent.width; wrapMode: Text.WordWrap; color: Theme.sub; font.pixelSize: Theme.px(13)
               text: "Запустите сбор и держите судно как обычно. Постоянное смещение каждой системы находится сразу; ошибка места антенны — только после поворота курса не менее 30° (нужно ≥ " + (cal.minN || 300) + " отсчётов, 1 отсчёт в секунду)." }
        Row { id: cbtn; y: Theme.px(46); spacing: Theme.px(8)
            Btn { enabledBtn: pg.can; active: cal.on === true; text: cal.on ? "Остановить сбор" : "Начать сбор"; onClicked: backend.command("calib " + (cal.on ? "stop" : "start")) }
            Btn { enabledBtn: pg.can; text: "Сбросить накопленное"; onClicked: backend.command("calib reset") }
            Btn { enabledBtn: pg.can; text: pg.confirmApply === "all" ? "Применить все? Нажмите ещё раз" : "Применить все готовые"
                  onClicked: { if (pg.confirmApply === "all") { backend.command("calib apply all"); pg.confirmApply = "" } else { pg.confirmApply = "all"; caTimer.restart() } } }
        }
        Text { x: 0; y: Theme.px(94); text: "Эталон"; color: Theme.sub; font.pixelSize: Theme.px(13); font.bold: true }
        Seg { x: Theme.px(70); y: Theme.px(82); width: Math.min(parent.width * 0.7, Theme.px(110) * calBox.refModel.length); px: Theme.px(13); model: calBox.refModel; current: calBox.refIdx
              enabled: pg.can; opacity: enabled ? 1 : 0.5; onPicked: (i) => backend.command("calib ref " + (i === 0 ? "median" : calBox.rows[i - 1].id)) }
        Text { x: 0; y: Theme.px(122); width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: Theme.px(13); color: cal.enough ? Theme.sub : Theme.warn
               text: (cal.on ? "Сбор идёт. " : "Сбор остановлен. ") + "Размах курса: " + Math.round(cal.span || 0) + "° (для антенны нужно 30°)."
                     + (cal.enough ? "" : "  ⚠ Для эталона-медианы нужны три системы и больше; выберите эталон вручную.") }
        // таблица
        Rectangle { y: Theme.px(150); width: parent.width; height: Theme.px(26); color: "transparent"
            Row { anchors.fill: parent
                Repeater { model: ["Система", "Отсчётов", "Невязка N / E, м", "Смещение N / E, м", "СКО, м", "Антенна x / y, м", "Состояние", ""]
                           Text { width: calBox.width * [0.11, 0.09, 0.15, 0.15, 0.08, 0.15, 0.13, 0.14][index]; text: modelData; color: Theme.sub; font.pixelSize: Theme.px(12); font.bold: true } } } }
        Repeater {
            model: calBox.rows.length
            delegate: Rectangle {
                required property int index
                readonly property var r: calBox.rows[index]
                y: Theme.px(178) + index * Theme.px(36); width: calBox.width; height: Theme.px(34); radius: 3; color: index % 2 ? "transparent" : Theme.panel2
                Row { anchors.fill: parent
                    Text { width: calBox.width * 0.11; height: parent.height; verticalAlignment: Text.AlignVCenter; leftPadding: 4; text: r.id + (r.isRef ? " (эталон)" : ""); color: Theme.text; font.bold: true; font.pixelSize: Theme.px(14) }
                    Text { width: calBox.width * 0.09; height: parent.height; verticalAlignment: Text.AlignVCenter; text: r.n; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(13) }
                    Text { width: calBox.width * 0.15; height: parent.height; verticalAlignment: Text.AlignVCenter; text: calBox.f2(r.rn) + " / " + calBox.f2(r.re); color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(13) }
                    Text { width: calBox.width * 0.15; height: parent.height; verticalAlignment: Text.AlignVCenter; text: r.isRef ? "—" : calBox.f2(r.bn) + " / " + calBox.f2(r.be); color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(13) }
                    Text { width: calBox.width * 0.08; height: parent.height; verticalAlignment: Text.AlignVCenter; text: r.isRef ? "—" : calBox.f2(r.sigma); color: Theme.sub; font.family: Theme.mono; font.pixelSize: Theme.px(13) }
                    Text { width: calBox.width * 0.15; height: parent.height; verticalAlignment: Text.AlignVCenter; text: r.isRef ? "—" : r.fitAnt ? calBox.f2(r.dx) + " / " + calBox.f2(r.dy) : "нет поворота"; color: r.fitAnt ? Theme.text : Theme.sub; font.family: Theme.mono; font.pixelSize: Theme.px(13) }
                    Text { width: calBox.width * 0.13; height: parent.height; verticalAlignment: Text.AlignVCenter; font.pixelSize: Theme.px(13); font.bold: true
                           text: r.isRef ? "эталон" : r.ready ? "готово" : r.n > 0 ? "накопление" : "нет данных"; color: r.ready ? Theme.ok : Theme.sub }
                    Item { width: calBox.width * 0.14; height: parent.height
                        Btn { anchors.verticalCenter: parent.verticalCenter; visible: !r.isRef; enabledBtn: pg.can && r.ready; px: Theme.px(12)
                              text: pg.confirmApply === r.id ? "Ещё раз" : "Применить"
                              onClicked: { if (pg.confirmApply === r.id) { backend.command("calib apply " + r.id); pg.confirmApply = "" } else { pg.confirmApply = r.id; caTimer.restart() } } } }
                }
            }
        }
        Text { y: Theme.px(190) + calBox.rows.length * Theme.px(36); width: parent.width; wrapMode: Text.WordWrap; color: Theme.warn; font.pixelSize: Theme.px(12)
               text: "⚠ Калибровка выравнивает системы друг относительно друга; ошибка, общая для всех систем (например, поправка DGPS), не видна. При эталоне-медиане ошибка одной системы немного влияет на остальные. Применение сдвигает позицию этой системы: возможен скачок решения, плавная коррекция его сгладит. Поправки действуют до перезапуска, в файл не сохраняются. Если поправка применена без поворота курса, смещение учитывает и часть ошибки антенны — при смене курса повторите калибровку." }
    }
}
