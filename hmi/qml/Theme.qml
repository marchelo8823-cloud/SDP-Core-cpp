// Цвета и шрифты пульта. Тёмная гамма — как у пультов СДП на мостике (ночью не слепит). Макет — холст «Пульт СДП — новый экран» (16.11.2026).
// Цвета состояния различаются и по яркости, не только по оттенку.
pragma Singleton
import QtQuick

QtObject {
    readonly property color bg: "#0b1117"
    readonly property color panel: "#121a22"
    readonly property color panel2: "#18222c"
    readonly property color line: "#24313d"
    readonly property color text: "#e8eef4"
    readonly property color dim: "#93a4b5"
    readonly property color accent: "#5aa9ff"      // заданное: точка, курс, команды
    readonly property color vessel: "#5aa9ff"
    readonly property color ok: "#3dbe84"
    readonly property color warn: "#f5b841"
    readonly property color alarm: "#ff6259"
    readonly property color info: "#8fa7bd"
    readonly property color fb: "#e8eef4"          // факт (обратная связь)
    readonly property color plot: "#0f171e"        // фон плана и шкал
    readonly property color btnLine: "#33424f"
    readonly property color off: "#5e6c79"         // упор снят, выведено из работы
    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a === undefined ? 0.16 : a) }
    readonly property color wind: "#b9a2ff"
    readonly property color dist: "#f59a5b"        // внешнее возмущение
    readonly property string font: Qt.platform.os === "osx" ? "Helvetica Neue" : Qt.platform.os === "windows" ? "Segoe UI" : "DejaVu Sans"
    readonly property string mono: Qt.platform.os === "osx" ? "Menlo" : Qt.platform.os === "windows" ? "Consolas" : "DejaVu Sans Mono"
    readonly property int fs: 15
    readonly property int fsSmall: 13
    readonly property int fsBig: 30

    function num(v, d) {           // число по-русски: запятая
        if (v === undefined || v === null || isNaN(v)) return "—"
        return Number(v).toLocaleString(Qt.locale("ru_RU"), 'f', d === undefined ? 1 : d)
    }
    function deg(v) { return num(v, 1) + "°" }
    function knots(ms) { return ms * 1.943844 }
    function stateColor(code) { return code === 3 ? ok : code === 2 ? accent : code === 1 ? warn : dim }
    function levelColor(l) { return l === 1 ? alarm : l === 2 ? warn : info }
}
