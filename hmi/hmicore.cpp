#include "hmicore.h"
#include <QDateTime>
#include <QUrl>
#include <cmath>

using namespace dp;

HmiCore::HmiCore(QObject* parent) : QObject(parent), core_({}, [this](const std::string& m) { say(m); }) {
    connect(&timer_, &QTimer::timeout, this, &HmiCore::tick);
    timer_.start(100);
    refresh();
}

std::string HmiCore::localPath(const QString& p) {
    const QUrl u(p);
    return (u.isLocalFile() ? u.toLocalFile() : p).toStdString();
}

void HmiCore::say(const std::string& m) {
    const QString t = QString::fromStdString(m);
    for (const QString& line : t.split('\n', Qt::SkipEmptyParts))
        log_.prepend(QString("%1  %2").arg(core_.clock(), 7, 'f', 0).arg(line));
    while (log_.size() > 300) log_.removeLast();
    emit logChanged();
}

void HmiCore::command(const QString& line) {
    const QString l = line.trimmed();
    if (l.isEmpty()) return;
    say(("> " + l).toStdString());
    const bool hadShip = core_.hasShip();
    core_.command(l.toStdString());
    if (core_.hasShip() != hadShip || l.startsWith("ship load")) { trail_.clear(); emit shipChanged(); }
    refresh();
}
void HmiCore::loadShip(const QString& p) { command("ship load " + QString::fromStdString(localPath(p))); }
void HmiCore::simStart(const QString& p) { command("sim start " + QString::fromStdString(localPath(p))); }
void HmiCore::ack() { core_.alarms().ack(core_.clock()); refresh(); }                    // квитирование через менеджер ядра: попадает и в журнал событий
void HmiCore::ackCode(const QString& c) { core_.alarms().ack(core_.clock(), c.toStdString()); refresh(); }   // по одной тревоге

// Диаграмма возможностей: «Все движители» и отказ каждого — предельный и рабочий (80 % упора) ветер по 36 направлениям.
// Расчёт по средним силам, курс постоянный, ветер/волна/течение с одного направления — оценка по модели ядра, не по правилам РС.
void HmiCore::capRun(double currentMS, bool wavesWithWind, double maxWindMS) {
    if (!core_.hasShip()) { capInfo_ = "Сначала загрузите судно"; emit capChanged(); return; }
    CapEnv e;
    e.currentMS = std::clamp(currentMS, 0.0, 5.0);
    e.maxWindMS = std::clamp(maxWindMS, 5.0, 60.0);
    e.wavesWithWind = wavesWithWind;
    const auto sc = capScenarios(*core_.ship(), e);
    QVariantList out;
    for (const auto& cv : sc) {
        QVariantMap x; x["name"] = QString::fromStdString(cv.name);
        QVariantList d, l, w;
        for (size_t i = 0; i < cv.dirDeg.size(); ++i) { d.push_back(cv.dirDeg[i]); l.push_back(cv.limitMS[i]); w.push_back(cv.workMS[i]); }
        x["dirs"] = d; x["limit"] = l; x["work"] = w;
        x["minLimit"] = cv.minLimit(); x["minWork"] = cv.minWork();
        out.push_back(x);
    }
    cap_ = out;
    capInfo_ = QString("Течение %1 м/с · %2 · шаг 10° · рассчитано t = %3 с")
        .arg(e.currentMS, 0, 'f', 1).arg(wavesWithWind ? "волны по ветру (Hs = 0,0246·V²)" : "без волн").arg(core_.clock(), 0, 'f', 0);
    emit capChanged();
}

void HmiCore::tick() {
    if (paused_) return;
    const int n = std::max(1, static_cast<int>(std::lround(core_.simSpeed())));   // ускорение имитатора: столько циклов за 0,1 с
    for (int i = 0; i < n; ++i) core_.cycle();
    refresh();
}

void HmiCore::runFor(double seconds) {
    const double until = core_.clock() + seconds;
    while (core_.clock() < until) {
        core_.cycle();
        const EngineOutput& o = core_.out();
        if (core_.hasShip() && o.est.posValid && core_.clock() - lastTrail_ >= 2.0) { trail_.push_back({o.est.n, o.est.e}); lastTrail_ = core_.clock(); if (trail_.size() > 450) trail_.pop_front(); }
    }
    refresh();
}

void HmiCore::refresh() {
    const EngineOutput& o = core_.out();
    const EstimatorState& es = o.est;
    QVariantMap m;
    const CoreState st = core_.state();
    m["state"] = coreStateName(st);
    m["stateCode"] = static_cast<int>(st);
    m["mode"] = modeName(core_.mode());
    m["modeCode"] = static_cast<int>(core_.mode());
    m["sim"] = core_.simRunning();
    m["simSpeed"] = core_.simSpeed();
    m["clock"] = core_.clock();
    m["hasShip"] = core_.hasShip();
    m["shipName"] = core_.ship() ? QString::fromStdString(core_.ship()->vessel.name) : QString();
    m["n"] = es.n; m["e"] = es.e; m["hdg"] = std::fmod(rad2deg(es.psi) + 360.0, 360.0);
    m["rot"] = rad2deg(es.r) * 60.0;                              // °/мин
    m["u"] = es.u; m["v"] = es.v;
    m["posValid"] = es.posValid; m["hdgValid"] = es.hdgValid; m["hdgDR"] = es.hdgDeadReckon; m["posDR"] = es.refLost;
    m["posSource"] = QString::fromStdString(es.posSource);
    // счисление: сколько секунд нет измерений, вероятный уход и погрешность фильтра; расхождение датчиков
    m["refLostS"] = es.refLostS; m["drDriftM"] = es.drDriftM; m["posUncertM"] = es.posUncertM;
    m["hdgLostS"] = es.hdgLostS; m["gyroDisagree"] = es.gyroDisagree; m["gnssDisagree"] = es.gnssDisagree;
    { double la = 0, lo = 0; const bool g = core_.geo(es.n, es.e, la, lo); m["geoValid"] = g; m["lat"] = la; m["lon"] = lo; }
    m["refN"] = o.ctl.refN; m["refE"] = o.ctl.refE; m["refHdg"] = std::fmod(o.ctl.refPsiDeg + 360.0, 360.0);
    m["errDist"] = o.ctl.errDist; m["errHdg"] = o.ctl.errHdgDeg; m["errAlong"] = o.ctl.errAlong; m["errCross"] = o.ctl.errCross;
    m["windSpeed"] = es.windSpeed; m["windFromRel"] = std::fmod(rad2deg(es.windFromRel) + 360.0, 360.0); m["windValid"] = es.windValid;
    // неизвестная сила (течение, волны и всё, что не измерено) в мировых осях — направление «куда» и величина
    m["distN"] = es.biasN; m["distE"] = es.biasE;
    m["load"] = o.alloc.utilization; m["powerKW"] = o.powerKW;
    // Прогноз ядра: текущая нагрузка считается по тому же требованию силы/момента, горизонты — уже готовый FcOut.
    double fcNow = 0;
    if (core_.hasShip()) {
        auto need = [](double req, double cap) { return std::fabs(req) < 1.0 ? 0.0 : (cap > 1e-6 ? std::fabs(req) / cap : 1e9); };
        fcNow = std::max({need(o.ctl.tau.X, o.cap.X), need(o.ctl.tau.Y, o.cap.Y), need(o.ctl.tau.N, o.cap.N)});
    }
    const FcOut& fc = o.fc;
    m["fcNow"] = fcNow; m["fcOn"] = fc.on; m["fcApply"] = fc.apply; m["fcValid"] = fc.valid;
    m["fcDataSec"] = fc.dataSec; m["fcFilled"] = fc.filled; m["fcTotal"] = fc.total; m["fcConf"] = fc.conf; m["fcWarn"] = fc.warn;
    m["fcWarnRatio"] = 0.9; m["fcClearRatio"] = 0.8; m["fcWarnHorizonS"] = 300.0;
    QVariantList fh;
    for (size_t i = 0; i < fc.horizonS.size() && i < fc.load.size(); ++i) {
        QVariantMap x; x["min"] = fc.horizonS[i] / 60.0; x["load"] = fc.load[i]; fh.push_back(x);
    }
    m["fcHorizons"] = fh;
    m["tauX"] = o.ctl.tau.X; m["tauY"] = o.ctl.tau.Y; m["tauN"] = o.ctl.tau.N;
    m["capX"] = o.cap.X; m["capY"] = o.cap.Y; m["capN"] = o.cap.N;
    m["roll"] = rad2deg(es.roll); m["pitch"] = rad2deg(es.pitch); m["heave"] = es.heave;
    m["waveHs"] = es.wave.valid ? es.wave.hs : -1.0;
    if (core_.simRunning()) { auto* sim = core_.sim(); const auto& tr = sim->truth(); m["trueN"] = tr.n; m["trueE"] = tr.e; }
    // Параметры управления и анализ последствий отказа — только показ существующего состояния ядра.
    m["pivotX"] = 0.0; m["pivotY"] = 0.0; m["gainHigh"] = false; m["gainHighK"] = 1.0;
    m["rateRotDegMin"] = 0.0; m["rateSpeedKn"] = 0.0;                 // 0 — ограничение оператора выключено
    if (DpEngine* eng = core_.engine()) {
        const Controller& ct = eng->controller();
        m["pivotX"] = ct.pivotX(); m["pivotY"] = ct.pivotY();
        m["gainHigh"] = ct.cfg().highGain; m["gainHighK"] = ct.cfg().gainHighK;
        m["rateRotDegMin"] = ct.capRot() * 60.0; m["rateSpeedKn"] = ct.capSpeed() / 0.514444;
        const ForecastCfg& fcfg = eng->forecast().cfg();
        m["fcWarnRatio"] = fcfg.warnRatio; m["fcClearRatio"] = fcfg.clearRatio; m["fcWarnHorizonS"] = fcfg.warnHorizonS;
        const Consequence& ca = eng->consequence();
        m["caClass"] = ca.dpClass(); m["caRan"] = ca.ran(); m["caAge"] = ca.ran() ? core_.clock() - ca.lastRunT() : -1.0; m["caSingle"] = ca.singleFailures();
        QVariantList gl; bool bad = false;
        for (const auto& g : ca.groups()) {
            QVariantMap x; x["name"] = QString::fromStdString(g.name); x["ids"] = QString::fromStdString(Consequence::join(g.ids));
            x["force"] = g.forcePct; x["moment"] = g.momentPct; x["holds"] = g.holds; x["alarm"] = g.alarm; bad = bad || g.alarm;
            gl.push_back(x);
        }
        m["caGroups"] = gl; m["caAlarm"] = bad;
    } else { m["caClass"] = 0; m["caRan"] = false; m["caGroups"] = QVariantList(); m["caAlarm"] = false; }
    s_ = m;

    QVariantList th;
    QVariantMap busKW;                                          // мощность по группам отказа (ГРЩ), кВт
    if (const AppCfg* cfg = core_.ship()) {
        for (size_t i = 0; i < cfg->thrusters.size(); ++i) {
            const ThrusterCfg& t = cfg->thrusters[i];
            QVariantMap x;
            x["id"] = QString::fromStdString(t.id);
            x["type"] = t.type == ThrusterType::Azimuth ? "поворотный" : t.type == ThrusterType::Tunnel ? "туннельный" : "неповоротный";
            x["azimuth"] = t.type == ThrusterType::Azimuth;
            x["x"] = t.x; x["y"] = t.y;
            x["enabled"] = t.enabled; x["taken"] = core_.taken(i);
            x["maxKN"] = t.maxForward / 1000.0;
            double cmdPct = 0, cmdAng = 0, fbPct = 0, fbAng = 0; bool fb = false, failed = false;
            if (i < o.cmds.size()) { cmdPct = o.cmds[i].pct; cmdAng = o.cmds[i].angleDeg; }
            if (core_.simRunning() && i < core_.sim()->thrusters().size()) {
                const auto& ts = core_.sim()->thrusters()[i]; fbPct = ts.pct(); fbAng = ts.angleDeg(); fb = true; failed = ts.failed() || !ts.cfg().enabled;
            }
            x["cmdPct"] = cmdPct; x["cmdAng"] = std::fmod(cmdAng + 360.0, 360.0);
            x["fbPct"] = fbPct; x["fbAng"] = std::fmod(fbAng + 360.0, 360.0); x["fb"] = fb; x["failed"] = failed;
            x["thrustKN"] = (fbPct >= 0 ? fbPct / 100.0 * t.maxForward : fbPct / 100.0 * t.maxReverse) / 1000.0;
            // мощность и обороты — оценка по упору и кривой движителя (как powerKW ядра), не измерение
            const double frac = std::fabs(fb ? fbPct : cmdPct) / 100.0;
            const bool runs = t.enabled && !failed;
            x["powerKW"] = runs ? thrusterPowerKW(t, frac) : 0.0;
            x["powerMaxKW"] = t.powerMaxKW;
            x["rpmPct"] = runs ? thrusterRpmPct(t, frac) : 0.0;
            x["group"] = QString::fromStdString(t.failGroups);
            if (!t.failGroups.empty()) { const QString g = QString::fromStdString(t.failGroups); busKW[g] = busKW.value(g).toDouble() + x["powerKW"].toDouble(); }
            th.push_back(x);
        }
    }
    thr_ = th;
    s_["busKW"] = busKW;

    QVariantList sn;
    const std::vector<ChannelInfo> chans = core_.hub() ? core_.hub()->channels(core_.clock()) : std::vector<ChannelInfo>();   // один раз за обновление
    for (const auto& ss : es.sensors) {
        QVariantMap x; const QString id = QString::fromStdString(ss.id);
        const QString k = id.left(1);
        x["kind"] = k == "P" ? "положение" : k == "H" ? "курс" : k == "W" ? "ветер" : k == "M" ? "качка" : "?";
        x["id"] = id.mid(2); x["valid"] = ss.valid; x["age"] = ss.ageS < 1e8 ? ss.ageS : -1.0;
        x["state"] = QString::fromStdString(ss.state); x["rejected"] = ss.rejected;
        // последние показания канала числами (только показ)
        {
            for (const auto& ci : chans) {
                if (QString::fromStdString(ci.id) != x["id"].toString()) continue;
                x["hdgDeg"] = ci.hdgDeg;
                x["dHdg"] = std::remainder(ci.hdgDeg - rad2deg(es.psi), 360.0);   // расхождение с курсом решения
                x["windMs"] = ci.windMs; x["windFromRel"] = std::fmod(ci.windFromRelDeg + 360.0, 360.0);
                x["roll"] = ci.rollDeg; x["pitch"] = ci.pitchDeg;
                x["gnssQ"] = ci.gnssQ; x["gnssSats"] = ci.gnssSats; x["gnssHdop"] = ci.gnssHdop; x["gstSigma"] = ci.gstSigma;
                break;
            }
        }
        for (const auto& sc : es.scatter) if (QString::fromStdString(sc.id) == x["id"].toString() || QString::fromStdString(sc.id) == id) { x["sdRep"] = sc.sdRep; break; }
        sn.push_back(x);
    }
    sen_ = sn;

    QVariantList al;
    for (const auto& r : core_.alarms().records()) {   // динамическая страница менеджера тревог ядра (как в sdp_run)
        QVariantMap x; const QString code = QString::fromStdString(r.code);
        x["code"] = code; x["text"] = QString::fromStdString(r.text); x["level"] = r.prio;   // 0 авария, 1 тревога, 2 предупреждение, 3 инфо
        x["acked"] = r.acked; x["gone"] = r.state == dp::AlarmNormal;                        // условие ушло, ждёт квитирования
        x["tFirst"] = r.tFirst; x["count"] = r.count;                                        // время появления и число повторов (только показ)
        al.push_back(x);
    }
    // по важности, внутри класса — новые сверху (последнее сообщение в ряду шапки, как в K-Pos)
    std::stable_sort(al.begin(), al.end(), [](const QVariant& a, const QVariant& b) {
        const QVariantMap ma = a.toMap(), mb = b.toMap();
        if (ma["level"].toInt() != mb["level"].toInt()) return ma["level"].toInt() < mb["level"].toInt();
        return ma["tFirst"].toDouble() > mb["tFirst"].toDouble();
    });
    alm_ = al;

    if (core_.hasShip() && es.posValid && core_.clock() - lastTrail_ >= 2.0) { trail_.push_back({es.n, es.e}); lastTrail_ = core_.clock(); if (trail_.size() > 450) trail_.pop_front(); }
    QVariantList tk; for (const auto& p : trail_) { tk.push_back(p.first); tk.push_back(p.second); }
    trk_ = tk;

    QVariantMap h;
    if (const AppCfg* cfg = core_.ship()) {
        h["length"] = cfg->vessel.length; h["beam"] = cfg->vessel.beam;
        QVariantList hs; for (const auto& t : cfg->thrusters) { QVariantMap x; x["id"] = QString::fromStdString(t.id); x["x"] = t.x; x["y"] = t.y; x["azimuth"] = t.type == ThrusterType::Azimuth; hs.push_back(x); }
        h["thrusters"] = hs;
        QVariantList ps; for (const auto& p : cfg->pivotPresets) { QVariantMap x; x["name"] = QString::fromStdString(p.name); x["x"] = p.x; x["y"] = p.y; ps.push_back(x); }
        h["pivotPresets"] = ps;                                 // именованные точки из книги судна, только для выбора на пульте
    }
    if (h != hull_) { hull_ = h; emit shipChanged(); }
    emit changed();
}
