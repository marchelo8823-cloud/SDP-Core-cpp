import QtQuick
import QtQuick.Controls

// Электростанция (PMS, имитация): генераторы, две шины, секционный выключатель, резерв мощности и проверка наихудшего отказа.
// Кнопки отказов идут командами «plant …» в ядро. Данные имитации, не от реальной PMS ⚠.
Popup {
    id: pop
    modal: false; focus: true
    x: Math.max(8, (Overlay.overlay ? Overlay.overlay.width : 800) - width - 12); y: Theme.px(60)
    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 24 : 640, Theme.px(640))
    height: Math.min(col.implicitHeight + Theme.px(32), Overlay.overlay ? Overlay.overlay.height - Theme.px(80) : 700)
    padding: Theme.px(14)
    closePolicy: Popup.CloseOnEscape
    readonly property var st: backend.s
    function cmd(s) { backend.command("plant " + s) }
    function kw(v) { return Math.round(v).toLocaleString(Qt.locale("ru_RU"), "f", 0) + " кВт" }
    background: Rectangle { color: Theme.panel; radius: 10; border.color: Theme.warn; border.width: 2 }

    contentItem: Flickable {
        clip: true; contentWidth: width; contentHeight: col.implicitHeight; boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        Column {
            id: col
            width: parent.width - Theme.px(8); spacing: Theme.px(8)
            Row { spacing: Theme.px(10)
                Text { text: "PMS — электростанция"; color: Theme.text; font.pixelSize: Theme.px(20); font.bold: true }
                Chip { text: "ИМИТАЦИЯ, НЕ РЕАЛЬНАЯ PMS"; tone: Theme.warn; solid: true } }
            Text { visible: !st.plantOn; width: parent.width; wrapMode: Text.Wrap; color: Theme.bad; font.pixelSize: Theme.px(14)
                   text: "Электростанция не описана в настройках (раздел plant) — доступная мощность не ограничена." }

            Column { visible: st.plantOn; width: parent.width; spacing: Theme.px(8)
                Column { width: parent.width
                    Readout { width: parent.width; label: "Доступно"; value: pop.kw(st.plAvail) }
                    Readout { width: parent.width; label: "Потребление"; value: pop.kw(st.plLoad) }
                    Readout { width: parent.width; label: "Резерв"; value: pop.kw(st.plRes) + " (" + st.plResPct.toFixed(0) + " %)"
                              tone: st.plRes < 0 ? Theme.bad : st.plResPct < st.plMinPct ? Theme.warn : Theme.ok }
                }
                Rectangle { width: parent.width; height: wcTxt.implicitHeight + Theme.px(12); radius: 6; color: Theme.panel2
                            border.color: st.plWcOk ? Theme.ok : Theme.warn
                    Text { id: wcTxt; x: Theme.px(8); y: Theme.px(6); width: parent.width - Theme.px(16); wrapMode: Text.Wrap; font.pixelSize: Theme.px(14)
                           color: st.plWcOk ? Theme.ok : Theme.warn
                           text: st.plWcOk ? "Наихудший отказ: удержание сохраняется"
                                           : (st.plWcRatio >= 10 ? "Наихудший отказ: при потере " + st.plWc + " тяги не остаётся, удержание невозможно"
                                                : "Наихудший отказ: при потере " + st.plWc + " удержание невозможно (нужно " + Math.round(100 * st.plWcRatio) + " % возможностей)") } }

                Text { text: "Генераторы"; color: Theme.sub; font.pixelSize: Theme.px(14); font.bold: true }
                Repeater {
                    model: st.plGens
                    Rectangle {
                        required property var modelData
                        width: col.width; height: grow.implicitHeight + Theme.px(10); radius: 6; color: Theme.panel2; border.color: modelData.online ? Theme.line : Theme.bad
                        Flow { id: grow; x: Theme.px(8); y: Theme.px(5); width: parent.width - Theme.px(16); spacing: 6
                            Text { width: Theme.px(400); height: Theme.px(34); elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; font.pixelSize: Theme.px(14); font.bold: true
                                   color: modelData.online ? Theme.text : Theme.bad
                                   text: modelData.id + " · шина " + modelData.bus + " · " + pop.kw(modelData.rated) + (modelData.online ? " · " + modelData.load.toFixed(0) + " %" : " · СТОП") }
                            Btn { text: modelData.online ? "Отключить" : "Запустить"; danger: modelData.online; active: !modelData.online; implicitHeight: Theme.px(34)
                                  onClicked: pop.cmd("gen " + (modelData.online ? "off " : "on ") + modelData.id) }
                        }
                    }
                }

                Text { text: "Шины и секционный выключатель"; color: Theme.sub; font.pixelSize: Theme.px(14); font.bold: true }
                Flow { width: parent.width; spacing: 6
                    Btn { text: st.plFailA ? "Шина A: ОТКАЗ — восстановить" : "Отказ шины A (" + pop.kw(st.plLoadA) + ")"; danger: !st.plFailA; active: st.plFailA; onClicked: pop.cmd("bus " + (st.plFailA ? "on A" : "off A")) }
                    Btn { text: st.plFailB ? "Шина B: ОТКАЗ — восстановить" : "Отказ шины B (" + pop.kw(st.plLoadB) + ")"; danger: !st.plFailB; active: st.plFailB; onClicked: pop.cmd("bus " + (st.plFailB ? "on B" : "off B")) }
                    Btn { text: st.plTie ? "Секционный: замкнут — разомкнуть" : "Секционный: разомкнут — замкнуть"; active: !st.plTie; onClicked: pop.cmd("tie " + (st.plTie ? "open" : "close")) }
                }
                Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.sub; font.pixelSize: Theme.px(12)
                       text: "Отказ шины выводит из строя её движители. Пока движители не перераспределяются автоматически ⚠. Мощность движителя считается по P ≈ T^1,5 или по кривой из профиля." }
            }
            Row { spacing: 8; anchors.right: parent.right
                Btn { text: "Восстановить всё"; onClicked: pop.cmd("reset") }
                Btn { text: "Закрыть"; active: true; onClicked: pop.close() }
            }
        }
    }
}
