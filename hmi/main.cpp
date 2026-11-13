// Пульт оператора СДП: ядро 1.3 в том же процессе, интерфейс на Qt Quick (QML).
// Ключи для проверок без экрана (QT_QPA_PLATFORM=offscreen):
//   --ship <книга судна>  --sim <книга имитатора>  --cmd "<команда ядра>" (можно несколько)  --run <с> (прогнать ядро без реального времени)
//   --screenshot <файл.png>  --size <Ш>x<В>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>
#include <QImage>
#include <QQmlError>
#include <cstdio>
#include "hmicore.h"

int main(int argc, char** argv) {
    QGuiApplication app(argc, argv);
    app.setApplicationName("SDP HMI");
    app.setOrganizationName("SDP");
    QStringList a = app.arguments();
    QString shot; int w = 1920, h = 1080;
    HmiCore core;
    for (int i = 1; i < a.size(); ++i) {
        auto next = [&]() { return i + 1 < a.size() ? a[++i] : QString(); };
        const QString k = a[i];
        if (k == "--ship") core.loadShip(next());
        else if (k == "--sim") core.simStart(next());
        else if (k == "--cmd") core.command(next());
        else if (k == "--run") core.runFor(next().toDouble());
        else if (k == "--screenshot") shot = next();
        else if (k == "--size") { const QStringList p = next().split('x'); if (p.size() == 2) { w = p[0].toInt(); h = p[1].toInt(); } }
    }
    QQmlApplicationEngine eng;
    int qmlWarnings = 0;   // ошибки и предупреждения QML: при проверке со снимком — код выхода 3
    QObject::connect(&eng, &QQmlApplicationEngine::warnings, [&](const QList<QQmlError>& ws) {
        for (const auto& w : ws) { ++qmlWarnings; std::fprintf(stderr, "QML: %s\n", w.toString().toUtf8().constData()); }
    });
    eng.rootContext()->setContextProperty("core", &core);
    eng.load(QUrl("qrc:/qml/Main.qml"));
    if (eng.rootObjects().isEmpty()) return 1;
    auto* win = qobject_cast<QQuickWindow*>(eng.rootObjects().first());
    if (win) { win->resize(w, h); }
    if (!shot.isEmpty() && win) {
        core.setPaused(true);
        QTimer::singleShot(1500, [&]() {
            const QImage img = win->grabWindow();
            const bool ok = img.save(shot);
            std::fprintf(ok ? stdout : stderr, ok ? "снимок: %s\n" : "не удалось сохранить снимок %s\n", shot.toUtf8().constData());
            QCoreApplication::exit(!ok ? 2 : qmlWarnings ? 3 : 0);
        });
    }
    return app.exec();
}
