// Служба ядра: рабочий поток с циклом управления, снимок состояния, события, история для графиков
// и (по желанию) сетевой сервер постов оператора. Используется и окном оператора (одно приложение),
// и консольной службой sdp_core (отдельный процесс, к которому подключаются посты).
#pragma once
#include "dp/asog.hpp"
#include "dp/messages.hpp"
#include <deque>
#include <memory>
#include <set>

#include "dp/admin.hpp"
#include "dp/opnet.hpp"

namespace dp {

class CoreService {
public:
    // serverPort > 0 — открыть порт для постов оператора
    // dataDir — папка данных администратора: пароль, профиль судна, журнал изменений
    CoreService(AppCfg cfg, int serverPort = 0, std::string dataDir = "sdp_data", int pbkdf2Iterations = 150000)
        : cfg_(std::move(cfg)), port_(serverPort), admin_(std::move(dataDir), pbkdf2Iterations) {}
    ~CoreService() { stop(); }

    bool start(std::string& err) {
        // профиль судна, сохранённый администратором, заменяет описание судна и движителей из файла настроек
        {
            std::string note;
            if (auto p = admin_.loadStoredProfile(note)) {
                cfg_.vessel = effectiveVessel(*p); cfg_.thrusters = p->thrusters; if (p->plant.enabled) cfg_.plant = p->plant;
                admin_.setCurrent(*p);
                addLog("Применён профиль судна из папки данных: «" + p->vessel.name + "», состояние загрузки «" + p->loading.condition + "»");
            } else {
                if (!note.empty()) addLog(note);
                VesselProfile p0; p0.vessel = cfg_.vessel; p0.thrusters = cfg_.thrusters; p0.plant = cfg_.plant;
                admin_.setCurrent(p0);
            }
            addLog("Папка данных администратора: " + admin_.dir());
            if (!admin_.passwordSet()) addLog("Пароль администратора не задан: раздел «Параметры судна» закрыт, пока пароль не задан на этом компьютере");
        }
        if (port_ > 0) {
            server_.reset(new OpServer(port_));
            for (const auto& pr : cfg_.postRights) { PostRights r; std::string why; if (parsePostRights(pr.second, why, &r)) server_->setRights(pr.first, r); }
            if (!server_->start(err)) { server_.reset(); return false; }
            server_->setAdminHandler([this](const std::string& sid, const json::Value& v) { return admin_.handle(sid, v); },
                                     [this](const std::string& sid) { admin_.closeSession(sid); });
            server_->setChiefCheck([this](const std::string& sid) { return admin_.chiefAllowed(sid); });
        }
        running_ = true;
        th_ = std::thread([this] { run(); });
        return true;
    }
    void stop() {
        if (running_.exchange(false) && th_.joinable()) th_.join();
        if (server_) { server_->stop(); }
    }

    void command(const std::string& line) {
        if (isChiefCommand(line) && !admin_.chiefAllowed("local")) { addLog("Команда отклонена: настройки требуют входа «Старший» (или администратора) — страница «Администрирование», вход «Старшего»"); return; }
        std::lock_guard<std::mutex> lk(qm_); cmds_.push_back(line);
    }
    OpSnap snapshot() const { std::lock_guard<std::mutex> lk(sm_); return snap_; }
    OpStatic info() const { std::lock_guard<std::mutex> lk(sm_); return info_; }
    std::vector<OpSample> history() const { std::lock_guard<std::mutex> lk(sm_); return std::vector<OpSample>(hist_.begin(), hist_.end()); }
    std::vector<std::string> takeLog() { std::lock_guard<std::mutex> lk(sm_); std::vector<std::string> r; r.swap(log_); return r; }
    bool quitRequested() const { return quit_; }
    OpServer* server() { return server_.get(); }
    // Запрос администратора из окна, в котором работает само ядро (сеанс "local"). Потокобезопасно; проверка пароля занимает доли секунды.
    std::string adminLocal(const std::string& requestJson) {
        json::Value v; std::string e;
        if (!json::parse(requestJson, v, e) || v.t != json::Value::Obj) return "{\"t\":\"adm\",\"id\":0,\"ok\":false,\"err\":\"Неверный запрос\"}";
        return admin_.handle("local", v);
    }
    AdminService& admin() { return admin_; }
    const AppCfg& cfg() const { return cfg_; }

public:
    static OpSnap makeSnap(Runtime& rt, const AppCfg& cfg) {
        const EngineOutput& o = rt.out(); const EstimatorState& es = o.est;
        OpSnap s;
        s.t = rt.clock(); s.mode = static_cast<int>(rt.engine().mode()); s.sim = cfg.simEnabled;
        s.modeText = modeName(rt.engine().mode());
        const LawType lw = rt.engine().controller().cfg().law;
        s.lawText = lw == LawType::Pid ? "ПИД" : lw == LawType::Lqr ? "LQR" : "MPC";
        s.n = es.n; s.e = es.e; s.psiDeg = rad2deg(es.psi); s.speed = std::hypot(es.vn, es.ve); s.rotDegMin = rad2deg(es.r) * 60.0; s.vn = es.vn; s.ve = es.ve;
        s.waveValid = es.wave.valid; s.waveDirValid = es.wave.valid && es.wave.dirValid; s.waveHs = es.wave.hs; s.waveTp = es.wave.tp; s.waveTz = es.wave.tz;
        s.waveFromDeg = es.wave.fromDeg; s.waveConf = es.wave.conf; s.waveSeconds = es.wave.seconds;
        s.rollDeg = rad2deg(es.roll); s.pitchDeg = rad2deg(es.pitch); s.heaveM = es.heave; s.mruCount = es.mruCount; s.mruValid = es.mruValid; s.mruDisagree = es.mruDisagree;
        {
            const FcOut& fo = o.fc; const Forecaster& fcr = rt.engine().forecast(); FcView& f = s.fc;
            f.on = fo.on; f.apply = fo.apply; f.valid = fo.valid; f.warn = fo.warn; f.dataMin = fo.dataSec / 60.0; f.conf = fo.conf; f.filled = fo.filled; f.total = fo.total; f.cellDir = fo.cellDir; f.cellSpd = fo.cellSpd;
            f.cx = fo.cellCorr.X / 1000.0; f.cy = fo.cellCorr.Y / 1000.0; f.cn = fo.cellCorr.N / 1000.0; f.sx = fo.slow.X / 1000.0; f.sy = fo.slow.Y / 1000.0; f.sn = fo.slow.N / 1000.0;
            f.hz = fo.horizonS; for (double v : fo.fx) f.fx.push_back(v / 1000.0); for (double v : fo.fy) f.fy.push_back(v / 1000.0); for (double v : fo.fn) f.fn.push_back(v / 1000.0); f.load = fo.load;
            f.map = fcr.mapKN(); f.dirBins = fcr.cfg().dirBins; f.spdBins = fcr.cfg().speedBins; f.spdStep = fcr.cfg().speedStep;
        }
        { std::vector<std::string> ids; for (const auto& ci : rt.hub().channels(rt.hubNow())) if (ci.kind == ChannelKind::Gnss || ci.kind == ChannelKind::LaserRadar || ci.kind == ChannelKind::TautWire) ids.push_back(ci.id);
          s.cal = rt.engine().estimator().calibrator().view(ids); }
        s.pivX = rt.engine().controller().pivotX(); s.pivY = rt.engine().controller().pivotY();
        s.highGain = rt.engine().controller().cfg().highGain; s.minPower = rt.engine().controller().cfg().minPower;
        if (Simulator* sm = rt.sim()) {
            const EnvCfg& ev = sm->target();
            s.simOn = true; s.simWindSpeed = ev.windSpeed; s.simWindFrom = ev.windFromDeg; s.simCurSpeed = ev.currentSpeed; s.simCurTo = ev.currentToDeg;
            s.simHs = ev.hs; s.simTp = ev.tp; s.simWaveFrom = ev.waveFromDeg;
            for (auto& id : sm->failedSensors()) s.simFailed += (s.simFailed.empty() ? "" : " ") + id;
            for (auto& id : sm->failedThrusters()) s.simThrFailed += (s.simThrFailed.empty() ? "" : " ") + id;
            s.simMods = rt.simModsText();
        }
        if (rt.plant().enabled()) {
            const PlantState& ps = rt.plantState(); const WorstCaseResult& wc = rt.worstCase();
            s.plantOn = true; s.plAvail = ps.availableKW; s.plLoad = ps.loadKW; s.plRes = ps.reserveKW; s.plResPct = ps.reservePct; s.plMinPct = rt.plant().cfg().minReservePct;
            s.plTie = ps.tieClosed; s.plWcOk = wc.ok; s.plWcRatio = wc.ratio; s.plWc = wc.what;
            for (int b = 0; b < 2; ++b) { s.plBusFail[b] = ps.busFailed[b]; s.plBusAvail[b] = ps.busAvailKW[b]; s.plBusLoad[b] = ps.busLoadKW[b]; }
            const auto& gens = rt.plant().cfg().gens;
            for (size_t i = 0; i < gens.size(); ++i) {
                PlantGenView g; g.id = gens[i].id; g.ratedKW = gens[i].ratedKW; g.bus = gens[i].bus; g.online = rt.plant().genOnline(i) && !ps.busFailed[gens[i].bus < 1 ? 0 : 1];
                g.loadPct = i < ps.genLoadPct.size() ? ps.genLoadPct[i] : 0; s.plGens.push_back(g);
            }
        }
        s.windSpeed = es.windSpeed; s.windFromRelDeg = rad2deg(es.windFromRel);
        s.windToTrueDeg = std::fmod(rad2deg(es.psi + es.windFromRel) + 180.0 + 720.0, 360.0);
        s.biasN = es.biasN; s.biasE = es.biasE;
        s.refN = o.ctl.refN; s.refE = o.ctl.refE; s.refPsiDeg = o.ctl.refPsiDeg;
        const Setpoint sp = rt.setpoint(); s.spN = sp.n; s.spE = sp.e; s.spPsiDeg = sp.psiDeg; s.spPending = rt.setpointPending();
        s.holdRadius = rt.holdRadius(); s.errDist = o.ctl.errDist; s.errHdg = o.ctl.errHdgDeg; s.errAlong = o.ctl.errAlong; s.errCross = o.ctl.errCross;
        s.tauX = o.ctl.tau.X; s.tauY = o.ctl.tau.Y; s.tauN = o.ctl.tau.N; s.capX = o.cap.X; s.capY = o.cap.Y; s.capN = o.cap.N;
        s.util = o.alloc.utilization; s.achX = o.alloc.achieved.X; s.achY = o.alloc.achieved.Y; s.achN = o.alloc.achieved.N;
        s.posValid = es.posValid; s.hdgValid = es.hdgValid; s.windValid = es.windValid; s.gnssDisagree = es.gnssDisagree; s.gyroDisagree = es.gyroDisagree;
        s.posSource = es.posSource; s.posSigma = es.posSigma; s.extJson = rt.extJson(); s.capJson = rt.capJson(); s.limitsText = rt.limitsText(); s.capRotDegMin = rt.limits().maxRotDegMin; s.capSpeedKn = rt.limits().maxSpeedKn;
        {   // окно «Датчики»: сведения о каналах, настройки систем положения, последние строки
            const auto& ec = rt.engine().estimator().cfg();
            for (const auto& ci : rt.hub().channels(rt.hubNow())) {
                ChanView c; c.id = ci.id; c.kind = static_cast<int>(ci.kind); c.kindText = ci.kindText; c.values = ci.values; c.lastReject = ci.lastReject;
                c.ox = ci.offset.x; c.oy = ci.offset.y; c.oz = ci.offset.z; c.sigma = ci.sigma; c.hz = ci.rateHz; c.age = ci.ageS > 1e8 ? -1 : ci.ageS;
                c.acc = ci.accepted; c.rej = ci.rejected; c.ign = ci.ignored;
                auto it = ec.posRef.find(ci.id); if (it != ec.posRef.end()) { c.mode = it->second.mode; c.accept = it->second.accept; }
                c.sentences = ci.accept; c.talkers = ci.talkers; c.known = ci.known; c.checksum = ci.checksum; c.minQ = ci.minQ; c.maxHdop = ci.maxHdop; c.magVar = ci.magVar; c.rollSign = ci.rollSign; c.pitchSign = ci.pitchSign; c.heaveSign = ci.heaveSign;
                c.weight = (ci.kind == ChannelKind::Gnss && ec.gnssWeight == 1) ? 1 : 0;
                c.lines = rt.hub().rawTail(ci.id, -1, 8);
                if (it != ec.posRef.end()) c.manualWeight = it->second.manualWeight;
                for (const auto& sc : es.scatter) if (sc.id == ci.id) {
                    c.sdRep = sc.sdRep; c.varBad = sc.varBad; c.state = sc.state;
                    const size_t from = sc.pts.size() > 40 ? sc.pts.size() - 40 : 0; char b[40];
                    for (size_t q = from; q < sc.pts.size(); ++q) { std::snprintf(b, sizeof b, "%s%d,%d", q > from ? ";" : "", static_cast<int>(std::lround(sc.pts[q].first * 100)), static_cast<int>(std::lround(sc.pts[q].second * 100))); c.scat += b; }
                }
                s.chans.push_back(std::move(c));
            }
            s.fusMedian = ec.medianMode; s.fusSoft = ec.softRateMS; s.fusGnssWeight = ec.gnssWeight;
            s.fusVariance = ec.varTest; s.fusWeights = ec.weightMode; s.fusVarFactor = ec.varFactor; s.fusDiverge = ec.divergeM;
        }
        s.th = rt.thrusters(); s.sensors = es.sensors; s.alarms = o.alarms; s.links = rt.linkStatus();
        {   // статус ДП (ASOG): по действующим сообщениям, числу исправных систем положения и гирокомпасов
            AsogInput ai; ai.alarms = o.alarms; ai.posValid = es.posValid; ai.hdgValid = es.hdgValid; ai.posDropout = es.posDropout; ai.dpClass = rt.dpClass();
            ai.operating = rt.engine().mode() != DpMode::Manual && rt.engine().mode() != DpMode::Standby;
            for (const auto& x : es.sensors) {
                const bool good = x.valid && (x.state == "OK" || x.state == "MEDIANW" || x.state == "JUMP" || x.state.empty());
                if (x.id.rfind("P:", 0) == 0 && good) { const auto it2 = rt.engine().estimator().cfg().posRef.find(x.id.substr(2)); if (it2 == rt.engine().estimator().cfg().posRef.end() || it2->second.mode == 0) ++ai.posUsable; }
                if (x.id.rfind("H:", 0) == 0 && x.valid) ++ai.gyroUsable;
            }
            const AsogResult ar = evaluateAsog(ai); s.asog = static_cast<int>(ar.status); s.asogName = ar.name; s.asogAction = ar.action; s.asogReasons = ar.reasons;
        }
        s.arecs = rt.alarmMgr().records(); s.evs = rt.alarmMgr().eventsSince(0, 60);
        s.audible = rt.alarmMgr().audible(); s.unacked = rt.alarmMgr().unacked(); s.activeAlarms = rt.alarmMgr().active();
        s.refLost = es.refLost; s.posDropout = es.posDropout; s.refLostS = es.refLostS;
        s.dpClass = rt.dpClass(); s.cqRunning = rt.conseqRunning();
        s.cqOk = rt.conseq().fails.empty();
        if (rt.conseqRunning()) {
            if (!rt.conseq().ran) s.cqText = "анализ выполняется";
            else if (rt.conseq().fails.empty()) s.cqText = "при любом единичном отказе удержание возможно";
            else { s.cqText = "отказ невозможно компенсировать: "; for (size_t k = 0; k < rt.conseq().fails.size(); ++k) s.cqText += (k ? ", " : "") + rt.conseq().fails[k].what; }
        }
        const LocalFrame lf = rt.frame(); s.frameValid = lf.valid();
        if (lf.valid()) lf.toGeo(0, 0, s.lat0, s.lon0);
        s.truthValid = rt.truth(s.trueN, s.trueE, s.truePsiDeg);
        return s;
    }

    void addLog(const std::string& m) {
        { std::lock_guard<std::mutex> lk(sm_); log_.push_back(m); if (log_.size() > 500) log_.erase(log_.begin()); }
        if (server_) server_->pushLog(m);
    }

    // Новый профиль судна применяется только в режиме ожидания; пока судно в другом режиме, напоминаем раз в 30 с.
    void applyPendingProfile(Runtime& rt, std::mutex& lm, std::vector<std::string>& msgs, OpStatic& info) {
        if (!admin_.hasPending()) return;
        auto say = [&](const std::string& s) { std::lock_guard<std::mutex> lk(lm); msgs.push_back(s); };
        if (rt.engine().mode() != DpMode::Standby) {
            if (rt.clock() - lastPendingNote_ > 30.0) { lastPendingNote_ = rt.clock(); say("Профиль судна сохранён, но не применён: переведите судно в режим ожидания (standby)"); }
            return;
        }
        auto p = admin_.takePending(); if (!p) return;
        std::string why;
        if (rt.applyVessel(effectiveVessel(*p), p->thrusters, why, p->plant.enabled ? &p->plant : nullptr)) {
            say("Профиль судна применён к модели: «" + p->vessel.name + "», состояние «" + p->loading.condition + "». Оценка состояния начата заново");
            admin_.audit("core", "профиль судна применён к модели");
            info.ship = p->vessel.name; info.length = p->vessel.length; info.beam = p->vessel.beam;
            { std::lock_guard<std::mutex> lk(sm_); info_ = info; }
            if (server_) server_->setInfo(info);
        } else { say("Профиль судна не применён: " + why); admin_.audit("core", "профиль судна не применён: " + why); }
    }

    void run() {
        std::mutex lm; std::vector<std::string> msgs;
        Runtime rt(cfg_, [&](const std::string& s) { std::lock_guard<std::mutex> lk(lm); msgs.push_back(s); });
        rt.setForecastFile(admin_.dir() + "/forecast.json");
        rt.setSensorsFile(admin_.dir() + "/sensors.json");
        rt.setLimitsFile(admin_.dir() + "/limits.json");
        rt.setExtFile(admin_.dir() + "/extlink.json");
        rt.setCaptureDir(admin_.dir());
        const double dt = rt.dt();
        const double speed = cfg_.simEnabled ? cfg_.simSpeed : 1.0;
        std::set<std::string> prevAlarms;
        double nextSample = 0;
        OpStatic info; info.ship = cfg_.vessel.name; info.length = cfg_.vessel.length; info.beam = cfg_.vessel.beam; info.cycleHz = cfg_.cycleHz; info.sim = cfg_.simEnabled;
        for (auto& w : rt.track().wp) info.track.push_back({w.e, w.n});
        { std::lock_guard<std::mutex> lk(sm_); info_ = info; }
        if (server_) server_->setInfo(info);
        auto next = std::chrono::steady_clock::now();
        auto lastSnap = next - std::chrono::seconds(1), lastNet = lastSnap;
        while (running_) {
            next += std::chrono::microseconds(static_cast<long long>(1e6 * dt / speed));
            std::vector<std::string> q;
            { std::lock_guard<std::mutex> lk(qm_); q.swap(cmds_); }
            if (server_) { auto c = server_->takeCommands(); q.insert(q.end(), c.begin(), c.end()); for (auto& e : server_->takeEvents()) { std::lock_guard<std::mutex> lk(sm_); log_.push_back(e); } }
            for (auto& c : q) rt.command(c);
            applyPendingProfile(rt, lm, msgs, info);
            rt.cycle();
            const EngineOutput& o = rt.out();
            std::set<std::string> now;
            for (auto& a : o.alarms) now.insert(a.code);
            for (auto& a : o.alarms) if (!prevAlarms.count(a.code)) { std::lock_guard<std::mutex> lk(lm); msgs.push_back("ТРЕВОГА: " + a.text); }
            for (auto& c : prevAlarms) if (!now.count(c)) { std::lock_guard<std::mutex> lk(lm); msgs.push_back("Тревога снята: " + c); }
            prevAlarms = now;
            if (rt.clock() >= nextSample) {
                nextSample = rt.clock() + 1.0;
                OpSample p; p.t = rt.clock(); p.e = o.est.e; p.n = o.est.n; p.err = o.ctl.errDist; p.hdg = o.ctl.errHdgDeg; p.util = 100 * o.alloc.utilization; p.wind = o.est.windSpeed;
                { std::lock_guard<std::mutex> lk(sm_); hist_.push_back(p); if (hist_.size() > 600) hist_.pop_front(); }
                if (server_) server_->pushSample(p);
            }
            const auto tnow = std::chrono::steady_clock::now();
            if (tnow - lastSnap >= std::chrono::milliseconds(50)) {
                lastSnap = tnow;
                OpSnap s = makeSnap(rt, cfg_);
                std::vector<std::string> m; { std::lock_guard<std::mutex> lk(lm); m.swap(msgs); }
                if (server_ && tnow - lastNet >= std::chrono::milliseconds(100)) { lastNet = tnow; if (server_->hasClients()) server_->pushSnap(s); }
                { std::lock_guard<std::mutex> lk(sm_); snap_ = std::move(s); }
                for (auto& x : m) addLog(x);
            }
            if (rt.quitRequested()) { quit_ = true; break; }
            std::this_thread::sleep_until(next);
            if (std::chrono::steady_clock::now() > next + std::chrono::seconds(1)) next = std::chrono::steady_clock::now();
        }
        rt.stop();
    }

    AppCfg cfg_; int port_;
    AdminService admin_;
    double lastPendingNote_ = -1e9;
    std::unique_ptr<OpServer> server_;
    std::thread th_;
    std::atomic<bool> running_{false}, quit_{false};
    mutable std::mutex sm_, qm_;
    OpSnap snap_; OpStatic info_;
    std::deque<OpSample> hist_;
    std::vector<std::string> log_, cmds_;
};

}  // namespace dp
