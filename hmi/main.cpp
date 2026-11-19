// Пульт оператора СДП: ядро 1.3 в том же процессе, интерфейс на Qt Quick (QML).
// Ключи для проверок без экрана (QT_QPA_PLATFORM=offscreen):
//   --ship <книга судна>  --sim <книга имитатора>  --cmd "<команда ядра>" (можно несколько)  --run <с> (прогнать ядро без реального времени)
//   --screenshot <файл.png>  --size <Ш>x<В>
//   --expect-ca <класс> (после нажатий: класс анализа последствий 0, 2 или 3)
//   --expect-fc <0|1> (при снимке: прогноз не рассчитан / рассчитан; при несовпадении код выхода 6)
//   --press "<надпись кнопки>" (можно несколько; нажатие кнопки на экране)  --expect-mode <код> (после нажатий: 0 — ожидание, 3 — курс, 4 — позиция; иначе код выхода 4)
//   --palette <day|dusk|night> (палитра на время запуска, в настройки не пишется)  --onboard (бортовой режим на время запуска)
//   --tab <0-8> (открыть вкладку: 0 — Главный … 8 — Настройки; для снимков вкладок)
//   --alarms <A|W> (раскрыть список тревог из строки шапки: A — аварийные, W — предупреждения; для снимков)
//   --workspace <full|watch|maneuver> (готовый набор рабочего места на время запуска, в настройки не пишется)
//   --export-recording <файл.csv> (выгрузить актуальный журнал; при снимке ошибка выгрузки даёт код 7)
//   --recording-dir <папка> (папка записи на время запуска, в настройки не пишется)
//   --expect-recording <custom|fallback> (при снимке: выбранная папка / резервная запись с предупреждением; иначе код 9)
//   --trend-demo (60 минут демонстрационной истории для снимков)  --expect-trend <5|15|60> (после нажатий: окно и число точек; иначе код 8)
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>
#include <QImage>
#include <QQmlError>
#include <QFileInfo>
#include <cstdio>
#include <clocale>
#include <functional>
#include "hmicore.h"

int main(int argc, char** argv) {
    QGuiApplication app(argc, argv);
    // Excel, JSON и NMEA используют десятичную точку независимо от языка системы; QLocale интерфейса не меняется.
    std::setlocale(LC_NUMERIC, "C");
    app.setApplicationName("SDP HMI");
    app.setOrganizationName("SDP");
    QStringList a = app.arguments();
    QString shot; int w = 1920, h = 1080; QStringList presses; int expectMode = -1, expectCa = -1, expectFc = -1, expectTrend = -1;
    QString paletteArg; bool onboardArg = false;   // временно, на время запуска (проверки и снимки); в настройки не пишется
    int tabArg = -1;                               // открыть вкладку (для снимков)
    QString alarmsArg;                             // раскрытый список тревог шапки: A или W (для снимков)
    QString workspaceArg;                          // готовый набор: full, watch или maneuver (для проверок и снимков)
    QString recordingDirArg, expectRecording;      // проверка выбранной папки и резервного режима без смены настроек пользователя
    bool exportOk = true, trendDemo = false;
    HmiCore core;
    for (int i = 1; i < a.size(); ++i) {
        auto next = [&]() { return i + 1 < a.size() ? a[++i] : QString(); };
        const QString k = a[i];
        if (k == "--ship") {
            core.loadShip(next());
            if (!core.property("s").toMap().value("hasShip").toBool()) {
                const QStringList log = core.property("log").toStringList();
                for (auto it = log.crbegin(); it != log.crend(); ++it) std::fprintf(stderr, "%s\n", it->toUtf8().constData());
                std::fprintf(stderr, "Не удалось загрузить судно, переданное ключом --ship\n");
                return 10;
            }
        }
        else if (k == "--sim") core.simStart(next());
        else if (k == "--cmd") core.command(next());
        else if (k == "--run") core.runFor(next().toDouble());
        else if (k == "--screenshot") shot = next();
        else if (k == "--press") presses << next();
        else if (k == "--expect-mode") expectMode = next().toInt();
        else if (k == "--expect-ca") expectCa = next().toInt();
        else if (k == "--expect-fc") expectFc = next().toInt();
        else if (k == "--expect-trend") expectTrend = next().toInt();
        else if (k == "--size") { const QStringList p = next().split('x'); if (p.size() == 2) { w = p[0].toInt(); h = p[1].toInt(); } }
        else if (k == "--palette") paletteArg = next();
        else if (k == "--onboard") onboardArg = true;
        else if (k == "--tab") tabArg = next().toInt();
        else if (k == "--alarms") alarmsArg = next();
        else if (k == "--workspace") workspaceArg = next();
        else if (k == "--trend-demo") trendDemo = true;
        else if (k == "--recording-dir") { recordingDirArg = next(); core.setRecordingDirectory(recordingDirArg, false); }
        else if (k == "--expect-recording") expectRecording = next();
        else if (k == "--export-recording") {
            const QString path = next(); exportOk = core.exportRecording(path);
            std::fprintf(exportOk ? stdout : stderr, exportOk ? "запись выгружена: %s\n" : "не удалось выгрузить запись: %s\n", path.toUtf8().constData());
        }
    }
    QQmlApplicationEngine eng;
    int qmlWarnings = 0;   // ошибки и предупреждения QML: при проверке со снимком — код выхода 3
    QObject::connect(&eng, &QQmlApplicationEngine::warnings, [&](const QList<QQmlError>& ws) {
        for (const auto& w : ws) { ++qmlWarnings; std::fprintf(stderr, "QML: %s\n", w.toString().toUtf8().constData()); }
    });
    eng.rootContext()->setContextProperty("core", &core);
    eng.rootContext()->setContextProperty("cliPalette", paletteArg);
    eng.rootContext()->setContextProperty("cliOnboard", onboardArg);
    eng.rootContext()->setContextProperty("cliAlarmsExpand", alarmsArg);
    eng.rootContext()->setContextProperty("cliWorkspace", workspaceArg);
    eng.rootContext()->setContextProperty("cliTrendDemo", trendDemo);
    eng.load(QUrl("qrc:/qml/Main.qml"));
    if (eng.rootObjects().isEmpty()) return 1;
    auto* win = qobject_cast<QQuickWindow*>(eng.rootObjects().first());
    if (win) { win->resize(w, h); }
    if (tabArg >= 0 && win)
        if (QObject* tb = win->findChild<QObject*>("tabbar")) tb->setProperty("currentIndex", tabArg);   // открыть вкладку для снимка
    // нажатия кнопок по надписи (кнопки с подтверждением ищутся по label, обычные — по text)
    auto press = [&](const QString& t) -> bool {
        for (QObject* o : win->findChildren<QObject*>()) {
            if (!o->metaObject()->indexOfSignal("clicked()") || !o->property("visible").toBool() || !o->property("enabled").toBool()) continue;
            const QVariant lab = o->property("label");
            if ((lab.isValid() && lab.toString() == t) || (!lab.isValid() && o->property("text").toString() == t)) { QMetaObject::invokeMethod(o, "clicked"); return true; }
        }
        std::fprintf(stderr, "кнопка «%s» не найдена\n", t.toUtf8().constData()); return false;
    };
    int exitPress = 0;
    if (!presses.isEmpty() && win) {
        QTimer::singleShot(800, [&]() {
            for (const QString& p : presses) { if (!press(p)) exitPress = 5; core.runFor(0.5); }
            const int m = core.property("s").toMap().value("modeCode").toInt();
            std::printf("режим после нажатий: %d\n", m);
            if (expectMode >= 0 && m != expectMode) { std::fprintf(stderr, "ожидался режим %d\n", expectMode); exitPress = 4; }
            const int ca = core.property("s").toMap().value("caClass").toInt();
            if (expectCa >= 0 && ca != expectCa) { std::fprintf(stderr, "ожидался класс анализа последствий %d, а не %d\n", expectCa, ca); exitPress = 4; }
            if (expectTrend >= 0) {
                const int tw = win->property("trendWin").toInt(), points = win->property("trendPoints").toInt();
                if (tw != expectTrend || (trendDemo && points != expectTrend * 60)) {
                    std::fprintf(stderr, "ожидалось окно трендов %d мин и %d точек, получено %d мин и %d точек\n", expectTrend, expectTrend * 60, tw, points); exitPress = 8;
                }
            }
            if (shot.isEmpty()) QCoreApplication::exit(exitPress ? exitPress : qmlWarnings ? 3 : 0);
        });
    }
    if (!shot.isEmpty() && win) {
        if (expectRecording != "fallback") core.setPaused(true);   // при резерве ядро продолжает писать в новый внутренний CSV
        QTimer::singleShot(1500, [&]() {
            bool fcOk = true, recordingOk = true;
            if (expectFc >= 0) {
                const bool valid = core.property("s").toMap().value("fcValid").toBool();
                fcOk = valid == (expectFc != 0);
                if (!fcOk) std::fprintf(stderr, "ожидался fcValid=%d, а не %d\n", expectFc, valid ? 1 : 0);
            }
            if (!expectRecording.isEmpty()) {
                const QVariantMap rs = core.property("s").toMap();
                const bool active = rs.value("recActive").toBool(), fallback = rs.value("recFallback").toBool();
                const QString actual = rs.value("recDir").toString(), warning = rs.value("recWarning").toString();
                const bool sameDir = QFileInfo(actual).absoluteFilePath() == QFileInfo(recordingDirArg).absoluteFilePath();
                if (expectRecording == "custom") recordingOk = active && !fallback && sameDir;
                else if (expectRecording == "fallback") recordingOk = active && fallback && !sameDir && !warning.isEmpty();
                else recordingOk = false;
                std::printf("запись: папка=%s; файл=%s; резерв=%d; активна=%d; предупреждение=%s\n",
                            actual.toUtf8().constData(), rs.value("recFile").toString().toUtf8().constData(), fallback ? 1 : 0, active ? 1 : 0, warning.toUtf8().constData());
                if (!recordingOk) std::fprintf(stderr, "не выполнено ожидание записи: %s\n", expectRecording.toUtf8().constData());
            }
            const QImage img = win->grabWindow();
            const bool ok = img.save(shot);
            std::fprintf(ok ? stdout : stderr, ok ? "снимок: %s\n" : "не удалось сохранить снимок %s\n", shot.toUtf8().constData());
            QCoreApplication::exit(!ok ? 2 : !fcOk ? 6 : !exportOk ? 7 : exitPress ? exitPress : qmlWarnings ? 3 : !recordingOk ? 9 : 0);
        });
    }
    return app.exec();
}
