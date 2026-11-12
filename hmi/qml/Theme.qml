pragma Singleton
import QtQuick

// Оформление: 5 схем (день, сумерки, ночь, контраст, эталон) и масштаб шрифта. Меняется оператором в настройках.
QtObject {
    id: t
    property int preset: 1          // 0 день, 1 сумерки, 2 ночь, 3 контраст, 4 эталон
    property real fs: 1.0           // масштаб шрифта
    readonly property string mono: Qt.platform.os === "osx" ? "Menlo" : (Qt.platform.os === "windows" ? "Consolas" : "monospace")
    function px(n) { return Math.round(n * fs) }

    readonly property var schemes: [
        { name: "День",     bg: "#e6ecf1", panel: "#ffffff", panel2: "#f0f4f7", line: "#c5d1db", text: "#13202b", sub: "#556677", accent: "#1769c2", ok: "#1e9c52", warn: "#c98500", bad: "#d6342f", plan: "#d4e6f1", grid: "#b4c9d8", hull: "#1769c2", set: "#d6342f" },
        { name: "Сумерки",  bg: "#121a22", panel: "#1a2531", panel2: "#223141", line: "#2e4256", text: "#e3eef7", sub: "#8fa6b8", accent: "#3fb6ff", ok: "#43c07a", warn: "#f2b84b", bad: "#ff6b6b", plan: "#0b1620", grid: "#1c2d3b", hull: "#5aa9e6", set: "#ff6b6b" },
        { name: "Ночь",     bg: "#050608", panel: "#0c0f13", panel2: "#12161c", line: "#222a33", text: "#c58a55", sub: "#7a5a3c", accent: "#d9742b", ok: "#7fa85a", warn: "#d9a02b", bad: "#e0482f", plan: "#030405", grid: "#12181e", hull: "#c58a55", set: "#e0482f" },
        { name: "Контраст", bg: "#000000", panel: "#0a0a0a", panel2: "#161616", line: "#ffffff", text: "#ffffff", sub: "#cfcfcf", accent: "#ffe600", ok: "#39ff7a", warn: "#ffb000", bad: "#ff4040", plan: "#000000", grid: "#303030", hull: "#00e5ff", set: "#ff4040" },
        { name: "Эталон",   bg: "#06121f", panel: "#0a2238", panel2: "#0f2f4b", line: "#1f6f9d", text: "#e8f5ff", sub: "#86b6d6", accent: "#19b4e6", ok: "#1ed0a0", warn: "#ffd21f", bad: "#ff4d4d", plan: "#62c6ea", grid: "#8fdcf5", hull: "#16293a", set: "#e53935", ptext: "#0b2338", pok: "#0b7d49", pwarn: "#a86400" }
    ]
    readonly property var c: schemes[Math.max(0, Math.min(schemes.length - 1, preset))]
    readonly property color bg: c.bg
    readonly property color panel: c.panel
    readonly property color panel2: c.panel2
    readonly property color line: c.line
    readonly property color text: c.text
    readonly property color sub: c.sub
    readonly property color accent: c.accent
    readonly property color ok: c.ok
    readonly property color warn: c.warn
    readonly property color bad: c.bad
    readonly property color plan: c.plan
    readonly property color grid: c.grid
    readonly property color hull: c.hull
    readonly property color setpoint: c.set
    readonly property color planOk: c.pok !== undefined ? c.pok : c.ok          // «норма» на карте (на светлом море — темнее)
    readonly property color planWarn: c.pwarn !== undefined ? c.pwarn : c.warn
    readonly property color planText: c.ptext !== undefined ? c.ptext : c.text      // подписи на карте (у светлой морской карты — тёмные)

    function pad(v, n) { var s = Math.round(v).toString(); while (s.length < n) s = "0" + s; return s }
    function hdg(v) { return pad(((Math.round(v) % 360) + 360) % 360, 3) + "°" }
    // градусы и минуты: 60°01.234′N
    function geo(v, isLat, dec) {
        if (v === undefined || v === null || isNaN(v)) return "—"
        var a = Math.abs(v), d = Math.floor(a), m = (a - d) * 60, q = Math.pow(10, dec)
        m = Math.round(m * q) / q
        if (m >= 60) { m = 0; d += 1 }
        var ms = m.toFixed(dec); if (m < 10) ms = "0" + ms
        return pad(d, isLat ? 2 : 3) + "°" + ms + "′" + (isLat ? (v >= 0 ? "N" : "S") : (v >= 0 ? "E" : "W"))
    }
    // градусы, минуты, секунды: 60°00′01.2″N (dec — знаков после запятой у секунд)
    function dms(v, isLat, dec) {
        if (v === undefined || v === null || isNaN(v)) return "—"
        var a = Math.abs(v), d = Math.floor(a), mm = (a - d) * 60, m = Math.floor(mm), s = (mm - m) * 60, q = Math.pow(10, dec)
        s = Math.round(s * q) / q
        if (s >= 60) { s = 0; m += 1 }
        if (m >= 60) { m = 0; d += 1 }
        var ss = s.toFixed(dec); if (s < 10) ss = "0" + ss
        return pad(d, isLat ? 2 : 3) + "°" + pad(m, 2) + "′" + ss + "″" + (isLat ? (v >= 0 ? "N" : "S") : (v >= 0 ? "E" : "W"))
    }
    function f(v, d) { return (v === undefined || v === null || isNaN(v)) ? "—" : Number(v).toFixed(d) }

    // ---------------------------------------------------------------- единицы измерения
    // Ядро считает в СИ (м, м/с, кН); пересчёт делается только при показе. Выбор хранится в настройках поста.
    property int uSpeed: 0          // скорость судна: 0 узлы, 1 м/с, 2 км/ч
    property int uWind: 0           // ветер и течение: 0 узлы, 1 м/с
    property int uDist: 0           // расстояния: 0 метры, 1 футы, 2 метры, а от 0,5 мили — морские мили
    property int uWave: 0           // высота волны: 0 метры, 1 футы
    property int uCoord: 1          // координаты: 0 гр-мин-сек, 1 гр-мин, 2 градусы
    property int uForce: 0          // усилия: 0 кН, 1 тонны-силы, 2 kip
    readonly property var unitKeys: ["uSpeed", "uWind", "uDist", "uWave", "uCoord", "uForce"]
    // готовые наборы: «Морские», «СИ», «Узлы и футы»
    readonly property var unitSets: [[0, 0, 2, 0, 1, 0], [1, 1, 0, 0, 2, 0], [0, 0, 1, 1, 1, 2]]
    function setUnit(i, v) { if (i === 0) uSpeed = v; else if (i === 1) uWind = v; else if (i === 2) uDist = v; else if (i === 3) uWave = v; else if (i === 4) uCoord = v; else uForce = v }
    function unitAt(i) { return [uSpeed, uWind, uDist, uWave, uCoord, uForce][i] }
    function applyUnitSet(k) { for (var i = 0; i < 6; ++i) setUnit(i, unitSets[k][i]) }
    // номер набора, которому соответствует текущий выбор, или -1 («свой»)
    function unitSetIndex() { for (var k = 0; k < unitSets.length; ++k) { var ok = true; for (var i = 0; i < 6; ++i) if (unitSets[k][i] !== unitAt(i)) ok = false; if (ok) return k } return -1 }
    function loadUnits(be) { for (var i = 0; i < 6; ++i) setUnit(i, Number(be.setting("unit" + i, unitSets[0][i]))) }
    function saveUnits(be) { for (var i = 0; i < 6; ++i) be.setSetting("unit" + i, unitAt(i)) }

    function num(v, d) { return (v === undefined || v === null || isNaN(v)) ? "—" : Number(v).toFixed(d) }
    // скорость судна, м/с → текст с единицей
    function speedU() { return uSpeed === 0 ? "уз" : (uSpeed === 1 ? "м/с" : "км/ч") }
    function speedV(ms) { return uSpeed === 0 ? ms * 1.943844 : (uSpeed === 1 ? ms : ms * 3.6) }
    function speed(ms, d) { return num(speedV(ms || 0), d) + " " + speedU() }
    // ветер и течение, м/с
    function windU() { return uWind === 0 ? "уз" : "м/с" }
    function windV(ms) { return uWind === 0 ? ms * 1.943844 : ms }
    function wind(ms, d) { return num(windV(ms || 0), d) + " " + windU() }
    // расстояния, м
    function distV(m) { return uDist === 1 ? m * 3.28084 : m }
    function distU(m) { return uDist === 1 ? "фт" : (uDist === 2 && Math.abs(m || 0) >= 926 ? "миль" : "м") }
    function dist(m, d) {
        if (m === undefined || m === null || isNaN(m)) return "—"
        if (uDist === 2 && Math.abs(m) >= 926) return (m / 1852).toFixed(2) + " миль"
        return num(distV(m), d) + " " + (uDist === 1 ? "фт" : "м")
    }
    // волна, м
    function wave(m, d) { return uWave === 1 ? num((m || 0) * 3.28084, d) + " фт" : num(m || 0, d) + " м" }
    // усилия, кН
    function forceU() { return uForce === 0 ? "кН" : (uForce === 1 ? "тс" : "kip") }
    function forceV(kn) { return uForce === 0 ? kn : (uForce === 1 ? kn / 9.80665 : kn / 4.448222) }
    function force(kn, d) { return num(forceV(kn || 0), d) + " " + forceU() }
    // широта и долгота
    function coord(v, isLat, dec) {
        if (uCoord === 0) return dms(v, isLat, dec)
        if (uCoord === 1) return geo(v, isLat, dec + 1)
        if (v === undefined || v === null || isNaN(v)) return "—"
        return Math.abs(v).toFixed(dec + 4) + "°" + (isLat ? (v >= 0 ? "N" : "S") : (v >= 0 ? "E" : "W"))
    }
}
