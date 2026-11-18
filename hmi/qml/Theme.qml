// Цвета и шрифты пульта. Тёмная гамма — как у пультов СДП на мостике (ночью не слепит).
pragma Singleton
import QtQuick

QtObject {
    readonly property color bg: "#161a1f"
    readonly property color panel: "#1f252c"
    readonly property color panel2: "#262d35"
    readonly property color line: "#36404a"
    readonly property color text: "#dde4ea"
    readonly property color dim: "#8a96a3"
    readonly property color accent: "#4ba3de"      // заданное: точка, курс, команды
    readonly property color vessel: "#7cc2ee"
    readonly property color ok: "#4cb874"
    readonly property color warn: "#e3b23c"
    readonly property color alarm: "#e5534b"
    readonly property color info: "#8fa7bd"
    readonly property color fb: "#e8e8e8"          // факт (обратная связь)
    readonly property color wind: "#c9a6f2"
    readonly property color dist: "#4fd1c5"        // внешнее возмущение (бирюзовый: оранжевый путался с предупреждением)
    readonly property color grid: "#29323b"        // кольца и сетка плана — тише линий рамок
    readonly property string font: "DejaVu Sans"
    readonly property string mono: "DejaVu Sans Mono"
    readonly property int fs: 15
    readonly property int fsSmall: 13
    readonly property int fsBig: 30

    function num(v, d) {           // число по-русски: запятая
        if (v === undefined || v === null || isNaN(v)) return "—"
        return Number(v).toLocaleString(Qt.locale("ru_RU"), 'f', d === undefined ? 1 : d)
    }
    function deg(v) { return num(v, 1) + "°" }
    function knots(ms) { return ms * 1.943844 }
    // шрифт для Canvas: родовые имена — если «DejaVu Sans» не установлен (Mac), холст не падает в мелкий запасной шрифт
    function cfont(px, bold, mono) { return (bold ? "bold " : "") + px + "px " + (mono ? "monospace" : "sans-serif") }
    function hdg3(v) {             // курс по-морскому, три цифры: 008,5°
        if (v === undefined || v === null || isNaN(v)) return "—"
        const s = num(((v % 360) + 360) % 360, 1)
        return ("00" + s).slice(-5) + "°"
    }
    function latlon(v, isLat) {    // 59°56,123′ с.ш. / 030°18,456′ в.д.
        if (v === undefined || v === null || isNaN(v)) return "—"
        const tm = Math.round(Math.abs(v) * 60000) / 1000          // минуты, округлённые до 0,001′ — перенос 60′ в градусы
        const d = Math.floor(tm / 60), m = tm - d * 60
        const ds = isLat ? ("0" + d).slice(-2) : ("00" + d).slice(-3)
        const ms = ("0" + num(m, 3)).slice(-6)
        return ds + "°" + ms + "′ " + (isLat ? (v >= 0 ? "с.ш." : "ю.ш.") : (v >= 0 ? "в.д." : "з.д."))
    }
    function mmss(sec) {           // 4:05
        if (sec === undefined || sec === null || isNaN(sec) || sec < 0) return "—"
        const t = Math.floor(sec), m = Math.floor(t / 60), s = t % 60
        return m + ":" + ("0" + s).slice(-2)
    }
    function bearing(v) {          // направление целыми градусами: 065°
        if (v === undefined || v === null || isNaN(v)) return "—"
        return ("00" + Math.round(((v % 360) + 360) % 360) % 360).slice(-3) + "°"
    }
    function stateColor(code) { return code === 3 ? ok : code === 2 ? accent : code === 1 ? warn : dim }
    function levelColor(l) { return l === 1 ? alarm : l === 2 ? warn : info }
}
