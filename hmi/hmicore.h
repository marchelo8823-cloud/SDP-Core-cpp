// Связь пульта (QML) с ядром СДП: ядро работает в том же процессе, пульт раз в 0,1 с забирает его состояние
// и передаёт команды оператора теми же текстовыми командами, что и sdp_run.
#pragma once
#include <QObject>
#include <QTimer>
#include <QVariant>
#include <QStringList>
#include <deque>
#include <memory>
#include "dp/core.hpp"

class HmiCore : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap s READ s NOTIFY changed)              // сводка: состояние, режим, положение, курс, ошибки, ветер, оценка
    Q_PROPERTY(QVariantList thrusters READ thrusters NOTIFY changed)
    Q_PROPERTY(QVariantList sensors READ sensors NOTIFY changed)
    Q_PROPERTY(QVariantList alarms READ alarms NOTIFY changed)
    Q_PROPERTY(QVariantList track READ track NOTIFY changed)       // след судна: [n, e, n, e, …] за последние минуты
    Q_PROPERTY(QVariantMap hull READ hull NOTIFY shipChanged)     // корпус для рисования: длина, ширина, движители и датчики на корпусе
    Q_PROPERTY(QStringList log READ log NOTIFY logChanged)
    Q_PROPERTY(QVariantList capCurves READ capCurves NOTIFY capChanged)   // диаграмма возможностей: сценарии с предельным/рабочим ветром по направлениям
    Q_PROPERTY(QString capInfo READ capInfo NOTIFY capChanged)            // условия последнего расчёта возможностей
public:
    explicit HmiCore(QObject* parent = nullptr);
    QVariantMap s() const { return s_; }
    QVariantList thrusters() const { return thr_; }
    QVariantList sensors() const { return sen_; }
    QVariantList alarms() const { return alm_; }
    QVariantList track() const { return trk_; }
    QVariantMap hull() const { return hull_; }
    QStringList log() const { return log_; }
    QVariantList capCurves() const { return cap_; }
    QString capInfo() const { return capInfo_; }

    Q_INVOKABLE void command(const QString& line);              // любая команда ядра (как в sdp_run)
    Q_INVOKABLE void loadShip(const QString& pathOrUrl);
    Q_INVOKABLE void simStart(const QString& pathOrUrl);
    Q_INVOKABLE void ack();                                       // квитирование всех тревог (через менеджер ядра)
    Q_INVOKABLE void ackCode(const QString& code);                // квитирование одной тревоги по коду
    Q_INVOKABLE bool exportRecording(const QString& pathOrUrl);   // актуальная копия CSV-журнала; запись продолжается
    Q_INVOKABLE QVariant settingValue(const QString& key, const QVariant& fallback) const;  // настройки QML без зависимости от версии модуля QtCore
    Q_INVOKABLE void setSettingValue(const QString& key, const QVariant& value);
    // Пустой путь — внутренняя папка. Пользовательская папка сохраняется в QSettings, если persistent=true.
    Q_INVOKABLE bool setRecordingDirectory(const QString& pathOrUrl, bool persistent = true);
    // Диаграмма возможностей (capability plot): расчёт по кнопке, не каждый цикл (тяжёлый перебор направлений).
    Q_INVOKABLE void capRun(double currentMS, bool wavesWithWind, double maxWindMS);
    void runFor(double seconds);                                  // прогнать ядро без реального времени (для проверок и снимков)
    void setPaused(bool p) { paused_ = p; }

signals:
    void changed();
    void shipChanged();
    void logChanged();
    void capChanged();

private:
    void tick();
    void refresh();
    void say(const std::string& m);
    static std::string localPath(const QString& p);
    static QString internalRecordingDirectory();
    static QString newRecordingPath(const QString& directory);
    bool openRecording(const QString& directory);                // новый уникальный CSV; прежний журнал сохраняется при ошибке
    void recoverRecording(const QString& reason);                // всегда внутренняя папка, без автоматического возврата на носитель
    void checkRecording();

    QString internalRecordingDir_, recordingPath_, recordingDir_, configuredRecordingDir_;
    QString recNotice_, recWarning_;
    bool recFallback_ = false;
    int recCheck_ = 0;
    dp::Core core_;
    QTimer timer_;
    bool paused_ = false;
    QVariantMap s_, hull_;
    QVariantList thr_, sen_, alm_, trk_;
    QStringList log_;
    QVariantList cap_;
    QString capInfo_;
    std::deque<std::pair<double, double>> trail_;
    double lastTrail_ = -1e9;
};
