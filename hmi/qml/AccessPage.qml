import QtQuick
import QtQuick.Controls

// Администрирование: одна страница и один вход для всего, что защищено паролем
// (планировщик судна, ограничения оператора, настройка связи с внешней ДП, параметры судна, пароли).
// Просмотр доступен всем; изменения — после входа администратора. Вход «Старшего» нужен только для настроек датчиков и расчётов,
// если администратор задал пароль «Старшего». Все проверки выполняет ядро: здесь только удобство.
Item {
    id: pg
    property var sess: null
    signal openVessel()
    property int tab: 0
    readonly property bool isAdmin: sess ? sess.admin : false

    Panel {
        id: bar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: barCol.height + Theme.px(52)
        title: "Вход"
        Column {
            id: barCol; width: parent.width; spacing: Theme.px(8)
            Row { spacing: 10; visible: !pg.isAdmin
                TextField { id: pw; width: Theme.px(280); echoMode: TextInput.Password; placeholderText: "Пароль администратора"; placeholderTextColor: Theme.sub; color: Theme.text; font.pixelSize: Theme.px(14)
                            enabled: pg.sess && pg.sess.lockSec <= 0 && pg.sess.pwSet
                            background: Rectangle { color: Theme.panel2; radius: 5; border.color: Theme.line }
                            onAccepted: { pg.sess.login(text); text = "" } }
                Btn { text: "Войти"; active: true; enabledBtn: pg.sess && !pg.sess.busy && pg.sess.pwSet && pg.sess.lockSec <= 0; onClicked: { pg.sess.login(pw.text); pw.text = "" } }
                Text { anchors.verticalCenter: parent.verticalCenter; width: Theme.px(560); wrapMode: Text.Wrap; font.pixelSize: Theme.px(13)
                       color: pg.sess && pg.sess.msgBad ? Theme.bad : Theme.sub
                       text: pg.sess && pg.sess.msg !== "" ? pg.sess.msg : (pg.sess && !pg.sess.pwSet ? "Пароль администратора ещё не задан: задайте его на вкладке «Судно и пароли»." : "Просмотр доступен всем; изменения — после входа.") }
            }
            Row { spacing: 10; visible: pg.isAdmin
                Chip { text: "Администратор: вход выполнен"; tone: Theme.ok }
                Btn { text: "Выйти"; onClicked: pg.sess.logout() }
                Text { anchors.verticalCenter: parent.verticalCenter; width: Theme.px(560); wrapMode: Text.Wrap; color: Theme.sub; font.pixelSize: Theme.px(13)
                       text: "Сеанс закрывается через 10 минут простоя и при возврате на страницу «Работа». Все изменения пишутся в журнал." }
            }
            Row { spacing: 10; visible: pg.sess && pg.sess.chiefSet
                Chip { text: pg.sess && pg.sess.chief ? "«Старший»: вход выполнен" : "«Старший»: не выполнен"; tone: pg.sess && pg.sess.chief ? Theme.ok : Theme.warn }
                TextField { id: cpw; visible: !(pg.sess && pg.sess.chief); width: Theme.px(280); echoMode: TextInput.Password; placeholderText: "Пароль «Старшего»"; placeholderTextColor: Theme.sub; color: Theme.text; font.pixelSize: Theme.px(14)
                            background: Rectangle { color: Theme.panel2; radius: 5; border.color: Theme.line }
                            onAccepted: { pg.sess.chiefLogin(text); text = "" } }
                Btn { visible: !(pg.sess && pg.sess.chief); text: "Войти «Старшим»"; enabledBtn: pg.sess && !pg.sess.busy && pg.sess.lockSec <= 0; onClicked: { pg.sess.chiefLogin(cpw.text); cpw.text = "" } }
                Btn { visible: pg.sess && pg.sess.chief && !pg.isAdmin; text: "Выйти"; onClicked: pg.sess.chiefLogout() }
                Text { anchors.verticalCenter: parent.verticalCenter; width: Theme.px(480); wrapMode: Text.Wrap; color: Theme.sub; font.pixelSize: Theme.px(13)
                       text: "Нужен для настроек датчиков и расчётов (страница «Датчики»). Администратору отдельный вход не нужен." }
            }
        }
    }

    Seg {
        id: tabs
        anchors { left: parent.left; top: bar.bottom; topMargin: Theme.px(10) }
        width: Math.min(parent.width, Theme.px(1100)); px: Theme.px(14)
        model: ["Планировщик судна", "Ограничения", "Внешняя ДП: связь", "Запись обмена", "Источники данных", "Судно и пароли"]
        current: pg.tab; onPicked: (i) => pg.tab = i
    }

    Item {
        id: content
        anchors { left: parent.left; right: parent.right; top: tabs.bottom; bottom: parent.bottom; topMargin: Theme.px(10) }
        PlannerPage { anchors.fill: parent; embedded: true; sess: pg.sess; visible: pg.visible && pg.tab === 0 }
        LimitsPage  { anchors.fill: parent; embedded: true; sess: pg.sess; visible: pg.visible && pg.tab === 1 }
        ExtLinkPage { anchors.fill: parent; embedded: true; sess: pg.sess; visible: pg.visible && pg.tab === 2 }
        CapturePage { anchors.fill: parent; embedded: true; sess: pg.sess; visible: pg.visible && pg.tab === 3 }
        SourcesPage { anchors.fill: parent; embedded: true; sess: pg.sess; visible: pg.visible && pg.tab === 4 }
        Panel {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: vCol.height + Theme.px(52)
            visible: pg.tab === 5
            title: "Параметры судна и пароли"
            Column { id: vCol; width: parent.width; spacing: Theme.px(10)
                Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.sub; font.pixelSize: Theme.px(14)
                       text: "Полный профиль судна (корпус, движители, присоединённые массы, загрузка), пароль администратора, пароль «Старшего» и журнал администратора. Окно открывается поверх страницы; вход, выполненный выше, действует и в нём." }
                Row { spacing: 8
                    Btn { text: "Открыть параметры судна…"; active: true; onClicked: pg.openVessel() }
                }
            }
        }
    }
}
