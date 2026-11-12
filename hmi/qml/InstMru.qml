import QtQuick

// Прибор «Качка и волнение»: крен, дифферент, вертикальная качка по трём МИО и оценка волнения, которую ядро
// вычисляет из этих данных (высота, период, откуда идут волны). Радара нет, ориентация по судну и по истинному пеленгу.
Item {
    id: w
    readonly property var st: backend.s
    readonly property var mrus: { var a = []; var s = backend.sensors || []; for (var i = 0; i < s.length; ++i) if (s[i].group === "МИО") a.push(s[i]); return a }
    component Num: Column {
        property string label: ""; property string value: "—"; property string unit: ""; property color tone: Theme.text
        spacing: 0
        Text { text: parent.label; color: Theme.sub; font.pixelSize: Theme.px(11) }
        Row { spacing: 3
            Text { text: parent.parent.value; color: parent.parent.tone; font.pixelSize: Theme.px(22); font.bold: true; font.family: Theme.mono }
            Text { anchors.baseline: parent.children[0].baseline; text: parent.parent.unit; color: Theme.sub; font.pixelSize: Theme.px(11) } }
    }
    Text { x: Theme.px(10); y: Theme.px(6); text: "Качка и волнение"; color: Theme.sub; font.pixelSize: Theme.px(13) }
    Row {
        id: dots; anchors { right: parent.right; rightMargin: Theme.px(40) } y: Theme.px(8); spacing: Theme.px(4)
        Repeater { model: w.mrus
            Rectangle { required property var modelData; width: Theme.px(10); height: width; radius: width / 2
                        color: modelData.valid ? Theme.ok : Theme.bad } }
    }
    Row {
        x: Theme.px(10); y: Theme.px(28); spacing: Theme.px(18)
        Num { label: "Крен"; value: st.mruValid ? Theme.f(st.roll, 1) : "—"; unit: "°" }
        Num { label: "Дифф."; value: st.mruValid ? Theme.f(st.pitch, 1) : "—"; unit: "°" }
        Num { label: "Вертик."; value: st.mruValid ? Theme.f(st.heave, 2) : "—"; unit: "м" }
    }
    Rectangle { x: Theme.px(10); y: Theme.px(74); width: parent.width - Theme.px(20); height: 1; color: Theme.line }
    Row {
        x: Theme.px(10); y: Theme.px(80); spacing: Theme.px(18)
        Num { label: "Высота"; value: st.waveValid ? Theme.f(st.waveHs, 1) : "—"; unit: "м" }
        Num { label: "Период"; value: st.waveValid ? Theme.f(st.waveTz, 1) : "—"; unit: "с" }
        Num { label: "Откуда"; value: st.waveDirValid ? Theme.hdg(st.waveFrom) : "—"; tone: st.waveConf < 0.5 ? Theme.warn : Theme.text }
    }
    Text { x: Theme.px(10); y: parent.height - height - Theme.px(4); width: parent.width - Theme.px(20); elide: Text.ElideRight; font.pixelSize: Theme.px(11)
           color: st.mruDisagree || !st.mruValid ? Theme.warn : Theme.sub
           text: !st.mruValid ? "нет данных МИО: волны не оцениваются"
               : st.mruDisagree ? "МИО расходятся: исправных " + st.mruCount + " из " + w.mrus.length
               : !st.waveValid ? "накопление данных: " + Math.round(st.waveSec || 0) + " с из 120"
               : "МИО в норме: " + st.mruCount + " из " + w.mrus.length + (st.waveDirValid ? ", напр. " + Math.round(100 * st.waveConf) + " %" : "") }
}
