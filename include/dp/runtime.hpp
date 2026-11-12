// Рабочий контур программы: связывает имитатор или реальные входы, приём датчиков, ядро и вывод на контроллер.
// Используется и консольной программой, и окном оператора.
#pragma once
#include <deque>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <functional>

#include <algorithm>
#include <cctype>
#include "dp/messages.hpp"
#include "dp/alarms.hpp"
#include "dp/capability.hpp"
#include "dp/capture.hpp"
#include "dp/sources.hpp"
#include "dp/extlink.hpp"
#include "dp/config.hpp"
#include "dp/holdradius.hpp"
#include "dp/json.hpp"
#include "dp/plant.hpp"
#include "dp/simfeed.hpp"

namespace dp {

struct ThrusterView {
    std::string id; ThrusterType type = ThrusterType::Fixed; bool enabled = true;
    double x = 0, y = 0, fixedAngleDeg = 0;
    double cmdPct = 0, cmdAngleDeg = 0;       // команда
    double pct = 0, angleDeg = 0;             // исполнение (имитатор) или последняя команда (реальный режим)
    bool taken = true;                        // движитель взят под управление ДП оператором
    double powerKW = 0; int bus = -1;         // потребляемая мощность по упору (по кривой или T^1,5) и шина питания (0 — A, 1 — B, -1 — не задана)
};

struct RunStats { double seconds = 0, rmsPos = 0, maxPos = 0, rmsHdg = 0, maxHdg = 0; };

class Runtime {
public:
    using Say = std::function<void(const std::string&)>;

    explicit Runtime(AppCfg cfg, Say say = {}) : cfg_(std::move(cfg)), say_(std::move(say)), dt_(1.0 / cfg_.cycleHz),
        eng_(cfg_.vessel, cfg_.thrusters, cfg_.control, cfg_.est), plant_(cfg_.plant) {
        lim_.on = cfg_.limits.on; lim_.maxMoveM = cfg_.limits.move; lim_.maxSetDistM = cfg_.limits.setdist; lim_.maxHdgStepDeg = cfg_.limits.hdg; lim_.forbidModes = cfg_.limits.forbid;
        if (cfg_.simEnabled) {
            const double lat0 = cfg_.originSet ? cfg_.originLat : 60.0, lon0 = cfg_.originSet ? cfg_.originLon : 29.5;
            lf_.setOrigin(lat0, lon0); hub_.setOrigin(lat0, lon0);
            sim_ = std::make_unique<Simulator>(cfg_.vessel, cfg_.thrusters, cfg_.env, cfg_.simSensors, cfg_.seed);
            sim_->dyn().state().psi = deg2rad(cfg_.initialHeadingDeg);
            for (auto& g : cfg_.simSensors.gnss) { ChannelCfg c; c.id = g.id; c.kind = ChannelKind::Gnss; c.offset = g.offset; c.sigma = g.sigma; hub_.addChannel(c); }
            if (cfg_.simSensors.laser) { ChannelCfg c; c.id = "LASER"; c.kind = ChannelKind::LaserRadar; c.offset = {22, 0, -8}; c.sigma = cfg_.simSensors.laserSigma; hub_.addChannel(c); }
            if (cfg_.simSensors.wire) { ChannelCfg c; c.id = "WIRE"; c.kind = ChannelKind::TautWire; c.offset = {25, 0, 2}; c.sigma = cfg_.simSensors.wireSigma; hub_.addChannel(c); }
            for (int i = 1; i <= cfg_.simSensors.gyros; ++i) { ChannelCfg c; c.id = "GYRO" + std::to_string(i); c.kind = ChannelKind::Gyro; hub_.addChannel(c); }
            for (int i = 1; i <= cfg_.simSensors.anemometers; ++i) { ChannelCfg c; c.id = "WIND" + std::to_string(i); c.kind = ChannelKind::Wind; hub_.addChannel(c); }
            for (int i = 1; i <= cfg_.simSensors.mrus; ++i) { ChannelCfg c; c.id = "MRU" + std::to_string(i); c.kind = ChannelKind::Mru; hub_.addChannel(c); }
        } else {
            if (cfg_.originSet) hub_.setOrigin(cfg_.originLat, cfg_.originLon);
            for (auto& in : cfg_.inputs) {
                hub_.addChannel(in.ch);
                std::unique_ptr<Channel> ch;
                if (in.transport == "udp") ch = std::make_unique<UdpChannel>(in.port, in.bind);
                else if (in.transport == "tcp") ch = std::make_unique<TcpChannel>(in.host, in.port);
                else ch = std::make_unique<SerialChannel>(in.device, in.baud);
                const std::string id = in.ch.id;
                ch->start([this, id](const std::string& line) { hub_.ingest(id, line, monotonicSeconds()); });
                chans_.push_back(std::move(ch));
            }
        }
        for (auto& l : cfg_.links) { links_.push_back(std::make_unique<OutputLink>(l)); links_.back()->start(); }
        if (!cfg_.logFile.empty()) {
            log_.open(cfg_.logFile);
            if (!log_) say("Предупреждение: не удалось открыть журнал " + cfg_.logFile);
            else log_ << "t_s,режим,N_м,E_м,курс_град,опорная_N,опорная_E,опорный_курс_град,ошибка_м,ошибка_курса_град,tauX_Н,tauY_Н,tauN_Нм,загрузка,ветер_мс\n";
        }
        warmup_ = cfg_.simEnabled ? 10.0 : 0.0;
        opSp_ = cfg_.startSetpoint; opSpSet_ = cfg_.startSetpointGiven;
        eng_.controller().setTrack(cfg_.track);
        if (cfg_.extlink.enabled) { ext_ = std::make_unique<ExtLink>(cfg_.extlink); ext_->start(); }
    }
    ~Runtime() { stop(); }
    Runtime(const Runtime&) = delete; Runtime& operator=(const Runtime&) = delete;

    void stop() { if (ext_) ext_->stop(); saveForecast(); for (auto& l : links_) l->stop(); for (auto& c : chans_) c->stop(); }
    // Таблица прогнозирования: файл в папке данных; загружается при указании файла, сохраняется раз в 5 мин, по команде и при остановке
    void setForecastFile(const std::string& path) {
        fcFile_ = path;
        std::ifstream f(path, std::ios::binary); if (!f) return;
        std::stringstream ss; ss << f.rdbuf(); std::string why;
        if (eng_.forecast().fromJson(ss.str(), cfg_.vessel.name, cfg_.vessel.mass, why)) say("Прогнозирование: таблица загружена (накоплено " + std::to_string(static_cast<long>(eng_.forecast().dataSec() / 60)) + " мин)");
        else say("Прогнозирование: " + why);
    }
    // Запись обмена: настройки каналов хранятся в capture.json папки данных; файлы записи — в подпапке capture.
    void setCaptureDir(const std::string& dataDir) {
        capBase_ = dataDir; capFile_ = dataDir + "/capture.json";
        std::ifstream f(capFile_, std::ios::binary); if (!f) return;
        std::stringstream ss; ss << f.rdbuf(); cap::CapCfg c; std::string err;
        if (cap::parseCapCfg(ss.str(), c, err)) cap_.configure(c); else say("Каналы записи обмена: файл не прочитан (" + err + ")");
    }
    std::string capJson() const {
        std::string j = cap_.statusJson(capDetail_);
        if (srcWatch_ && !j.empty() && j.back() == '}') j.insert(j.size() - 1, ",\"src\":{\"list\":" + (srcList_.empty() ? std::string("null") : srcList_) + ",\"test\":" + srcTest_.json() + "}");
        return j;
    }
    // Связь с внешней ДП: файл в папке данных переопределяет раздел extlink из настроек
    void setExtFile(const std::string& path) {
        extFile_ = path;
        std::ifstream f(path, std::ios::binary); if (!f) return;
        std::stringstream ss; ss << f.rdbuf(); ExtLinkCfg nc; std::string err;
        if (!parseExtLink(ss.str(), nc, err)) { say("Настройки связи с внешней ДП: файл не прочитан (" + err + ")"); return; }
        if (ext_) { ext_->stop(); ext_.reset(); }
        cfg_.extlink = nc;
        if (nc.enabled) { ext_ = std::make_unique<ExtLink>(nc); ext_->start(); say("Связь с внешней ДП загружена из файла (входов " + std::to_string(nc.inputs.size()) + ")"); }
    }
    // Настройки посылок датчиков (типы предложений, talker ID, проверки, знаки МИО): файл в папке данных, пишется при каждом изменении
    void setSensorsFile(const std::string& path) {
        snFile_ = path;
        std::ifstream f(path, std::ios::binary); if (!f) return;
        std::stringstream ss; json::Value v; std::string err; ss << f.rdbuf();
        if (!json::parse(ss.str(), v, err)) { say("Настройки посылок: файл не прочитан (" + err + ")"); return; }
        int n = 0; std::string why;
        for (const auto& kv : v.o) {
            const json::Value& o = kv.second; auto str = [&](const char* k) { const json::Value* x = o.find(k); return x && x->t == json::Value::Str ? x->s : std::string(); };
            auto numv = [&](const char* k, double d) { const json::Value* x = o.find(k); return x && x->t == json::Value::Num ? x->n : d; };
            const std::string a = str("accept"), t = str("talkers");
            hub_.setParam(kv.first, "accept", a.empty() ? "default" : a, why); hub_.setParam(kv.first, "talkers", t.empty() ? "any" : t, why);
            hub_.setParam(kv.first, "check", numv("check", 1) != 0 ? "on" : "off", why);
            hub_.setParam(kv.first, "quality", std::to_string(static_cast<int>(numv("quality", 1))), why); hub_.setParam(kv.first, "hdop", std::to_string(numv("hdop", 10)), why);
            hub_.setParam(kv.first, "magvar", std::to_string(numv("magvar", 0)), why);
            hub_.setParam(kv.first, "ref", std::to_string(numv("refN", 0)) + "," + std::to_string(numv("refE", 0)), why);
            { const std::string md = str("rmode"); if (!md.empty()) hub_.setParam(kv.first, "rls.mode", md, why); }
            hub_.setParam(kv.first, "rls.az", std::to_string(numv("raz", 0)), why);
            hub_.setParam(kv.first, "brg.off", std::to_string(numv("brg", 0)), why);
            { const std::string tg = str("tg"); std::string cur; for (size_t i = 0; i <= tg.size(); ++i) { if (i == tg.size() || tg[i] == ';') { if (!cur.empty()) { for (auto& ch : cur) if (ch == ',') ch = ' '; hub_.setParam(kv.first, "target", cur, why); } cur.clear(); } else cur += tg[i]; } }
            hub_.setParam(kv.first, "rls.signa", numv("rsa", 1) < 0 ? "-1" : "1", why); hub_.setParam(kv.first, "rls.signb", numv("rsb", 1) < 0 ? "-1" : "1", why); hub_.setParam(kv.first, "rls.swap", numv("rsw", 0) != 0 ? "1" : "0", why);
            hub_.setParam(kv.first, "sign.roll", numv("rs", 1) < 0 ? "-1" : "1", why); hub_.setParam(kv.first, "sign.pitch", numv("ps", 1) < 0 ? "-1" : "1", why); hub_.setParam(kv.first, "sign.heave", numv("hs", 1) < 0 ? "-1" : "1", why);
            ++n;
        }
        if (n) say("Настройки посылок загружены (датчиков: " + std::to_string(n) + ")");
    }
    static std::string tgText(const ChannelCfg& c) {
        std::string t; char b[96];
        for (const auto& k : c.targets) { std::snprintf(b, sizeof b, "%s%d,%.3f,%.3f", t.empty() ? "" : ";", k.first, k.second.first, k.second.second); t += b; }
        return t;
    }
    bool saveSensors() {
        if (snFile_.empty()) return false;
        auto esc = [](const std::string& x) { std::string r; for (char c : x) { if (c == '"' || c == '\\') r += '\\'; r += c; } return r; };
        std::string o = "{";
        bool first = true;
        for (const auto& ci : hub_.channels(hubNow())) {
            const ChannelCfg c = hub_.cfgOf(ci.id);
            o += std::string(first ? "\n" : ",\n") + "  \"" + esc(ci.id) + "\": {\"accept\": \"" + esc(c.accept) + "\", \"talkers\": \"" + esc(c.talkers) + "\", \"check\": " + (c.requireChecksum ? "1" : "0")
               + ", \"quality\": " + std::to_string(c.minGnssQuality) + ", \"hdop\": " + std::to_string(c.maxHdop) + ", \"magvar\": " + std::to_string(c.magVarDeg)
               + ", \"refN\": " + std::to_string(c.refN) + ", \"refE\": " + std::to_string(c.refE) + ", \"rmode\": \"" + std::string(c.rlsMode == 1 ? "ne" : c.rlsMode == 2 ? "frame" : "vessel") + "\", \"raz\": " + std::to_string(c.rlsAzDeg) + ", \"brg\": " + std::to_string(c.brgOffDeg) + ", \"tg\": \"" + tgText(c) + "\", \"rsa\": " + std::to_string(static_cast<int>(c.rlsSignA)) + ", \"rsb\": " + std::to_string(static_cast<int>(c.rlsSignB)) + ", \"rsw\": " + (c.rlsSwap ? "1" : "0")
               + ", \"rs\": " + std::to_string(static_cast<int>(c.rollSign)) + ", \"ps\": " + std::to_string(static_cast<int>(c.pitchSign)) + ", \"hs\": " + std::to_string(static_cast<int>(c.heaveSign)) + "}";
            first = false;
        }
        o += "\n}\n";
        const std::string tmp = snFile_ + ".tmp";
        { std::ofstream f(tmp, std::ios::binary | std::ios::trunc); if (!f) return false; f << o; if (!f) return false; }
        std::error_code ec; std::filesystem::rename(tmp, snFile_, ec);
        return !ec;
    }
    bool saveForecast() {
        if (fcFile_.empty()) return false;
        const std::string tmp = fcFile_ + ".tmp";
        { std::ofstream o(tmp, std::ios::binary | std::ios::trunc); if (!o) return false; o << eng_.forecast().toJson(cfg_.vessel.name, cfg_.vessel.mass); if (!o) return false; }
        std::error_code ec; std::filesystem::rename(tmp, fcFile_, ec);
        if (ec) return false;
        eng_.forecast().clearDirty(); return true;
    }

    // Один цикл управления.
    void cycle() {
        initTaken();
        SensorFrame fr;
        if (sim_) {
            sim_->step(dt_); t_ += dt_;
            SensorFrame raw = sim_->measure();
            for (auto& l : encodeNmea(raw, lf_)) hub_.ingest(l.channel, l.sentence, t_);
            if (plant_.enabled()) {                 // электростанция: доступная мощность по работающим генераторам и шинам
                std::vector<double> fr2; const auto& st = sim_->thrusters();
                for (size_t i = 0; i < cfg_.thrusters.size(); ++i) fr2.push_back(i < st.size() ? std::fabs(st[i].pct()) / 100.0 : 0.0);
                initTaken(); auto pth = cfg_.thrusters;   // холостая мощность ПУ — только у принятых под управление ДП
                for (size_t i = 0; i < pth.size() && i < taken_.size(); ++i) if (!taken_[i]) pth[i].idlePct = 0;
                plantSt_ = plant_.compute(pth, fr2);
                hub_.setPower(plantSt_.engineAvailKW);
            } else hub_.setPower(cfg_.simSensors.availableKW);
            for (auto f : raw.fb) { auto o = fbOverride_.find(f.id); if (o != fbOverride_.end()) { f.valid = true; f.pct = o->second; } hub_.setThrusterFb(f); }   // sim fbfault: ложная обратная связь движителя
            fr = hub_.buildFrame(t_);
        } else {
            fr = hub_.buildFrame(monotonicSeconds());
        }
        out_ = eng_.step(dt_, fr);
        if (!fcFile_.empty() && eng_.forecast().dirty() && clock() - fcSaveT_ > 300.0) { fcSaveT_ = clock(); saveForecast(); }
        if (plant_.enabled() && sim_) { plantTieAuto(); syncBusThrusters(); plantAlarms(); }
        conseqStep();
        extraAlarms();
        for (const auto& s : out_.infos) { alarms_.info(clock(), s); say(s); }
        alarms_.update(clock(), out_.alarms);
        if (sim_) sim_->applyCommands(out_.cmds);
        for (auto& l : links_) l->setCommands(out_.cmds, eng_.mode(), monotonicSeconds());

        const EstimatorState& es = out_.est;
        if (startPending_ && t_ >= warmup_ && es.hdgValid && (es.posValid || cfg_.startMode == "standby" || cfg_.startMode == "heading")) {
            startPending_ = false;
            bool okm; const DpMode m = parseMode(cfg_.startMode, okm);
            eng_.setMode(m);
            if (opSpSet_) eng_.controller().setSetpoint(opSp_);
            if (m != DpMode::Standby) modeSince_ = clock();
            if (m == DpMode::Track) eng_.controller().setTrack(cfg_.track);
            say(std::string("Режим запуска: ") + modeName(m));
        }
        const bool active = eng_.mode() != DpMode::Standby && eng_.mode() != DpMode::Manual;
        if (active && modeSince_ >= 0 && clock() - modeSince_ > 120.0) {      // статистика после переходного процесса
            double err = out_.ctl.errDist, eh = std::fabs(out_.ctl.errHdgDeg);
            if (sim_) {
                const auto& s = sim_->truth();
                err = std::hypot(s.n - out_.ctl.refN, s.e - out_.ctl.refE); eh = std::fabs(rad2deg(wrapPi(s.psi - deg2rad(out_.ctl.refPsiDeg))));
            }
            sum2_ += err * err; max_ = std::max(max_, err); h2_ += eh * eh; hmax_ = std::max(hmax_, eh); n_ += 1;
        }
        if (log_) {
            log_ << clock() << ',' << modeName(eng_.mode()) << ',' << es.n << ',' << es.e << ',' << rad2deg(es.psi) << ',' << out_.ctl.refN << ',' << out_.ctl.refE << ','
                 << out_.ctl.refPsiDeg << ',' << out_.ctl.errDist << ',' << out_.ctl.errHdgDeg << ',' << out_.ctl.tau.X << ',' << out_.ctl.tau.Y << ',' << out_.ctl.tau.N << ','
                 << out_.alloc.utilization << ',' << es.windSpeed << '\n';
            if (++cycles_ % 50 == 0) log_.flush();
        }
    }

    // Применение нового описания судна и движителей. Только в режиме ожидания: оценка состояния при этом
    // начинается заново (фильтры сходятся за несколько секунд), закон управления сохраняется.
    bool applyVessel(const VesselCfg& v, const std::vector<ThrusterCfg>& th, std::string& why, const PlantCfg* plant = nullptr) {
        if (eng_.mode() != DpMode::Standby) { why = "судно не в режиме ожидания"; return false; }
        const ControlCfg cc = eng_.controller().cfg();
        cfg_.vessel = v; cfg_.thrusters = th;
        if (plant) { cfg_.plant = *plant; plant_ = Plant(cfg_.plant); plantSt_ = {}; if (dpActive_ && plant_.cfg().tieOpenInDp) plant_.setTie(false); }
        eng_ = DpEngine(v, th, cc, cfg_.est); taken_.clear(); initTaken(); applyTal();
        eng_.controller().setTrack(cfg_.track);
        if (sim_) sim_->setVessel(v, th);
        out_ = EngineOutput{};
        opSpSet_ = false; modeSince_ = -1; n_ = sum2_ = max_ = h2_ = hmax_ = 0;
        return true;
    }

    // Команда оператора (та же строка, что вводится в консоли).
    void command(const std::string& line) {
        std::istringstream is(line); std::string c; is >> c;
        if (c.empty()) return;
        if (c != "watch") watchAt_ = clock();   // любое действие оператора подтверждает бдительность
        const EstimatorState& es = out_.est;
        const bool activeNow = eng_.mode() != DpMode::Standby && eng_.mode() != DpMode::Manual;
        auto base = [&]() { if (opSpSet_) return opSp_; if (activeNow) return eng_.controller().setpoint(); return eng_.controller().holdFromCrp(es.n, es.e, rad2deg(es.psi)); };
        auto setSp = [&](const Setpoint& sp) {
            if (lim_.on) {   // ограничения оператора: размер шага уставки, удаление от судна, шаг курса
                const Setpoint b0 = base(); std::string why;
                const double step = std::hypot(sp.n - b0.n, sp.e - b0.e), away = std::hypot(sp.n - es.n, sp.e - es.e);
                double dh = std::fmod(sp.psiDeg - b0.psiDeg, 360.0); if (dh > 180) dh -= 360; if (dh < -180) dh += 360;
                char b[160];
                if (lim_.maxMoveM > 0 && step > lim_.maxMoveM + 1e-9) { std::snprintf(b, sizeof b, "сдвиг уставки %.1f м больше допустимого %.0f м", step, lim_.maxMoveM); why = b; }
                else if (lim_.maxSetDistM > 0 && away > lim_.maxSetDistM + 1e-9) { std::snprintf(b, sizeof b, "уставка в %.0f м от судна, допустимо %.0f м", away, lim_.maxSetDistM); why = b; }
                else if (lim_.maxHdgStepDeg > 0 && std::fabs(dh) > lim_.maxHdgStepDeg + 1e-9) { std::snprintf(b, sizeof b, "смена курса на %.0f° больше допустимых %.0f°", std::fabs(dh), lim_.maxHdgStepDeg); why = b; }
                if (!why.empty()) { say("Отклонено ограничением оператора: " + why + " (меняет администратор: limits)"); return; }
            }
            opSp_ = sp; opSpSet_ = true;
            if (activeNow) eng_.controller().setSetpoint(sp);
            else { char b[160]; std::snprintf(b, sizeof b, "Уставка запомнена: N=%.1f E=%.1f курс=%.1f°; применится при включении режима.", sp.n, sp.e, sp.psiDeg); say(b); }
        };
        auto enter = [&](DpMode m) {
            startPending_ = false;
            eng_.setMode(m); modeSince_ = clock();
            if (opSpSet_) eng_.controller().setSetpoint(opSp_);
            if (m == DpMode::Track) eng_.controller().setTrack(cfg_.track);
            n_ = sum2_ = max_ = h2_ = hmax_ = 0;
        };
        if (lim_.on && (c == "position" || c == "heading" || c == "track" || c == "follow" || c == "joystick" || c == "joy")
            && std::find(lim_.forbidModes.begin(), lim_.forbidModes.end(), c) != lim_.forbidModes.end()) {
            say("Режим «" + c + "» запрещён ограничениями оператора (разрешает администратор: limits allow " + c + ")"); return;
        }
        if (c == "quit" || c == "exit") quit_ = true;
        else if (c == "src") {        // источники данных: src list | src test <JSON линии> [секунд] | src watch on|off
            std::string w; is >> w;
            if (w == "watch") { std::string v; is >> v; srcWatch_ = v == "on"; if (srcWatch_ && srcList_.empty()) srcList_ = src::listJson(); return; }
            if (w == "list" || w.empty()) { srcList_ = src::listJson(); say("Список портов и сетевых интерфейсов обновлён"); return; }
            if (w == "test") {
                std::string rest; std::getline(is, rest); double sec = 5;
                const size_t br = rest.rfind('}'); if (br != std::string::npos && br + 1 < rest.size()) { try { sec = std::stod(rest.substr(br + 1)); } catch (...) {} rest.erase(br + 1); }
                if (sec < 1) sec = 1; if (sec > 30) sec = 30;
                json::Value v; std::string e; cap::EpCfg ep;
                if (!json::parse(rest, v, e)) { say("Проверка линии: ошибка в описании, " + e); return; }
                json::Report rep; json::Obj o(&v, "линия", &rep); std::string err;
                if (!cap::parseEp(o, ep, err) || !rep.errors.empty()) { say("Проверка линии: " + (err.empty() ? rep.errors.front() : err)); return; }
                if (cap_.recording()) { say("Проверка линии не запущена: идёт запись обмена (порт может быть занят)"); return; }
                if (srcTest_.start(ep, sec, err)) say("Проверка линии запущена на " + std::to_string(static_cast<int>(sec)) + " с: " + src::LineTest::describe(ep)); else say("Проверка линии: " + err);
                return;
            }
            say("Формат: src list | src test <JSON линии> [секунд] | src watch on|off");
        }
        else if (c == "cap") {        // запись обмена: cap status|watch on|off|setup <JSON>|clear|start [метка]|stop|mark <текст>|report|replay <папка|last> <канал> <адрес> <порт> [скорость]|replay stop
            std::string w; is >> w;
            if (w == "watch") { std::string v; is >> v; capDetail_ = v == "on"; return; }
            if (w.empty() || w == "status") {
                const auto cfg = cap_.config();
                say(std::string("Запись обмена: ") + (cap_.recording() ? "ИДЁТ, папка " + cap_.sessionDir() : "не идёт") + "; каналов " + std::to_string(cfg.ch.size()) + (cap_.notice().empty() ? "" : "; " + cap_.notice()));
                return;
            }
            if (w == "setup") {
                std::string rest; std::getline(is, rest); cap::CapCfg nc; std::string err;
                if (cap_.recording()) { say("Каналы записи не изменены: сначала остановите запись (cap stop)"); return; }
                if (!cap::parseCapCfg(rest, nc, err)) { say("Каналы записи не изменены: " + err); return; }
                cap_.configure(nc); saveCapCfg(nc);
                say("Каналы записи применены: " + std::to_string(nc.ch.size())); return;
            }
            if (w == "clear") {
                if (cap_.recording()) { say("Сначала остановите запись (cap stop)"); return; }
                cap::CapCfg nc; cap_.configure(nc); saveCapCfg(nc); say("Каналы записи удалены"); return;
            }
            if (w == "start") {
                std::string label; std::getline(is, label); while (!label.empty() && label[0] == ' ') label.erase(0, 1);
                std::string err; std::filesystem::path base(cap_.config().dir);
                if (base.is_relative()) base = std::filesystem::path(capBase_) / base;
                if (cap_.recording()) { say("Запись уже идёт"); return; }
                if (cap_.start(base.string(), label, err)) say("Запись обмена НАЧАТА: " + cap_.sessionDir()); else say("Запись не начата: " + err);
                return;
            }
            if (w == "stop") { if (!cap_.recording() && cap_.sessionDir().empty()) { say("Запись не идёт"); return; } const std::string d = cap_.sessionDir(); cap_.stop(); say("Запись обмена остановлена. Файлы: " + d + " (exchange.csv, exchange.pcap, report.txt, registers.csv)"); return; }
            if (w == "mark") { std::string t; std::getline(is, t); while (!t.empty() && t[0] == ' ') t.erase(0, 1); if (t.empty()) { say("cap mark <текст метки>"); return; } cap_.mark(t); say("Метка записана: " + t); return; }
            if (w == "report") { std::string d; if (cap_.writeReportsNow(d)) say("Отчёт и таблица регистров записаны в " + d); else say("Нет записи для отчёта"); return; }
            if (w == "replay") {
                std::string a; is >> a;
                if (a == "stop") { cap_.stopReplay(); say("Воспроизведение остановлено"); return; }
                std::string ch, host; int port = 0; double sp = 1.0; is >> ch >> host >> port; if (!(is >> sp)) sp = 1.0;
                std::string dir = a == "last" ? cap_.sessionDir() : a, err;
                if (dir.empty() || ch.empty() || host.empty() || port <= 0) { say("cap replay <папка|last> <канал> <адрес> <порт> [скорость]"); return; }
                if (cap_.startReplay(dir, ch, host, port, sp, err)) say("Воспроизведение записи начато"); else say("Воспроизведение не начато: " + err);
                return;
            }
            say("cap: status | watch on|off | setup <JSON> | clear | start [метка] | stop | mark <текст> | report | replay <папка|last> <канал> <адрес> <порт> [скорость]");
        }
        else if (c == "ext") {        // ext [status] | active on <код>|off | send <шаблон> [имя=значение…] | inject <строка> | tpl
            std::string w; is >> w;
            if (w == "setup" || w == "clear") {     // настройка связи из окна оператора: ext setup <JSON> | ext clear — применяется сразу, хранится в extlink.json
                ExtLinkCfg nc; std::string err;
                if (w == "clear") { nc = ExtLinkCfg(); nc.enabled = false; }
                else {
                    std::string rest; std::getline(is, rest);
                    if (!parseExtLink(rest, nc, err)) { say("Связь с внешней ДП не изменена: " + err); return; }
                }
                if (ext_) { ext_->stop(); ext_.reset(); }
                cfg_.extlink = nc;
                if (nc.enabled) { ext_ = std::make_unique<ExtLink>(nc); ext_->start(); }
                extSt_ = ExtStatus();
                if (!extFile_.empty()) { std::ofstream f(extFile_, std::ios::binary | std::ios::trunc); if (f) f << extLinkToJson(nc); else say("Предупреждение: настройки связи не сохранены в " + extFile_); }
                say(nc.enabled ? "Связь с внешней ДП применена: входов " + std::to_string(nc.inputs.size()) + ", поставщик " + nc.vendor + " (режим только приём)" : "Связь с внешней ДП выключена");
                return;
            }
            if (!ext_) say("Связь с внешней ДП не настроена (страница «Администрирование», вкладка «Внешняя ДП»)");
            else if (w.empty() || w == "status") say(extText());
            else if (w == "tpl") { std::string s = "Шаблоны отправки:"; for (auto& t : ext_->cfg().templates) s += "\n  " + t.name + " = " + t.text; say(ext_->cfg().templates.empty() ? "Шаблонов отправки нет" : s); }
            else if (w == "active") {
                std::string st, code; is >> st >> code; std::string why;
                if (st == "off") { ext_->setActive(false, "", why); say("Внешняя ДП: активный режим ВЫКЛЮЧЕН (только приём)"); }
                else if (st == "on") { if (ext_->setActive(true, code, why)) say("Внешняя ДП: АКТИВНЫЙ РЕЖИМ ВКЛЮЧЁН вручную — команды будут уходить в чужую систему (ext send)"); else say("Активный режим не включён: " + why); }
                else say("Формат: ext active on <код>|off");
            }
            else if (w == "send") {
                std::string tpl; is >> tpl; std::map<std::string, std::string> vars; std::string kv;
                const Setpoint b = base(); char t[48];
                std::snprintf(t, sizeof t, "%.2f", b.n); vars["n"] = t; std::snprintf(t, sizeof t, "%.2f", b.e); vars["e"] = t; std::snprintf(t, sizeof t, "%.1f", b.psiDeg); vars["psi"] = t;
                while (is >> kv) { const size_t eq = kv.find('='); if (eq != std::string::npos) vars[kv.substr(0, eq)] = kv.substr(eq + 1); }
                std::string out, why;
                if (ext_->send(tpl, vars, out, why)) say("Отправлено во внешнюю ДП: " + out); else say("Не отправлено: " + why);
            }
            else if (w == "inject") { std::string rest; std::getline(is, rest); if (!rest.empty() && rest[0] == ' ') rest.erase(0, 1); ext_->inject(rest, monotonicSeconds()); say("Строка передана во вход внешней ДП"); }
            else say("Формат: ext [status|tpl] | ext active on <код>|off | ext send <шаблон> [имя=значение…] | ext inject <строка>");
        }
        else if (c == "limits") {     // limits | limits on|off | move <м>|off | setdist <м>|off | hdg <°>|off | forbid <режим> | allow <режим>
            std::string w, v; is >> w >> v;
            auto numv = [&](double& x) { if (v == "off") { x = 0; return true; } try { size_t k = 0; x = std::stod(v, &k); return k == v.size() && x > 0; } catch (...) { return false; } };
            bool ok = true;
            if (w.empty()) ok = true;
            else if (w == "on" || w == "off") lim_.on = (w == "on");
            else if (w == "move") ok = numv(lim_.maxMoveM);
            else if (w == "setdist") ok = numv(lim_.maxSetDistM);
            else if (w == "hdg") ok = numv(lim_.maxHdgStepDeg);
            else if (w == "forbid") { if (v == "position" || v == "heading" || v == "track" || v == "follow" || v == "joystick") { if (std::find(lim_.forbidModes.begin(), lim_.forbidModes.end(), v) == lim_.forbidModes.end()) lim_.forbidModes.push_back(v); } else ok = false; }
            else if (w == "allow") { lim_.forbidModes.erase(std::remove(lim_.forbidModes.begin(), lim_.forbidModes.end(), v), lim_.forbidModes.end()); }
            else ok = false;
            if (!ok) say("Формат: limits [on|off|move <м>|setdist <м>|hdg <°>|forbid|allow <position|heading|track|follow|joystick>]; число или off");
            else { if (!w.empty()) saveLimits(); say(limitsText()); }
        }
        else if (c == "rate") {       // rate | rate rot <°/мин>|off | rate speed <узлов>|off — максимальная скорость поворота и скорость перемещения; ставит оператор
            std::string w, v; is >> w >> v;
            if (w.empty()) { say(motionText()); }
            else if ((w == "rot" || w == "speed") && !v.empty()) {
                double x = 0; bool ok = true;
                if (v == "off") x = 0; else { try { size_t k = 0; x = std::stod(v, &k); ok = k == v.size(); } catch (...) { ok = false; } }
                const double lo = w == "rot" ? 0.5 : 0.05, hi = w == "rot" ? 600 : 30;   // °/мин, узлы
                if (!ok || (x != 0 && (x < lo || x > hi))) say(std::string("Значение вне допустимого диапазона: ") + (w == "rot" ? "0,5…600 °/мин" : "0,05…30 уз") + " или off");
                else { (w == "rot" ? lim_.maxRotDegMin : lim_.maxSpeedKn) = x; applyMotionCaps(); saveLimits(); say(motionText()); }
            } else say("Формат: rate | rate rot <°/мин>|off | rate speed <узлов>|off");
        }
        else if (c == "help") say(helpText());
        else if (c == "thr_take" || c == "thr_release") { std::string w; is >> w; if (w.empty()) say("Формат: thr_take|thr_release <id|all>"); else takeThrusters(w, c == "thr_take"); }
        else if (c == "standby") { startPending_ = false; eng_.setMode(DpMode::Standby); modeSince_ = -1; opSpSet_ = false; }
        else if (c == "position" || c == "heading" || c == "track") {
            bool okm; const DpMode m = parseMode(c, okm);
            if (takenCount() == 0) { say("Режим не включён: нет движителей под управлением ДП. Сначала возьмите движители под управление."); return; }
            if (!es.hdgValid || (m != DpMode::AutoHeading && !es.posValid)) { say("Режим не включён: нет достоверных данных датчиков."); return; }
            if (!opSpSet_ && m != DpMode::Track) opSp_ = eng_.controller().holdFromCrp(es.n, es.e, rad2deg(es.psi));
            enter(m);
        }
        else if (c == "set") { double n, e, h; if (is >> n >> e >> h) setSp({n, e, h}); else say("Формат: set <север> <восток> <курс>"); }
        else if (c == "pivot") {       // pivot <вдоль м> <поперёк м> — центр вращения: точка судна, которую удерживает уставка положения
            double px = 0, py = 0; std::string a1; is >> a1; bool numeric = false;
            try { size_t k = 0; px = std::stod(a1, &k); numeric = !a1.empty() && k == a1.size(); } catch (...) {}
            bool okp = false;
            if (numeric) okp = static_cast<bool>(is >> py);
            else okp = pivotByName(a1, px, py);
            if (!okp) say("Формат: pivot <вдоль, м (+ к носу)> <поперёк, м (+ к правому борту)> | pivot center|bow|stern|<имя из pivotPresets> (список: pivots)");
            else if (std::fabs(px) > 300 || std::fabs(py) > 100) say("Центр вращения вне допустимых пределов (|вдоль| ≤ 300, |поперёк| ≤ 100 м)");
            else {
                Controller& ct = eng_.controller();
                const Setpoint prev = opSpSet_ ? opSp_ : Setpoint{es.n, es.e, rad2deg(es.psi)};
                if (activeNow) { ct.setPivot(px, py); if (opSpSet_) opSp_ = ct.setpoint(); }
                else {   // режим не включён: переносим сохранённую уставку, судно «остаётся на месте»
                    const Setpoint crp = ct.crpFromHold(prev); ct.setPivotIdle(px, py);
                    if (opSpSet_) { opSp_ = ct.holdFromCrp(crp.n, crp.e, crp.psiDeg); }
                }
                say("Центр вращения: вдоль " + std::to_string(px).substr(0, std::to_string(px).find('.') + 2) + " м, поперёк " + std::to_string(py).substr(0, std::to_string(py).find('.') + 2) + " м");
            }
        }
        else if (c == "move") { double dn, de, dh = 0; if (is >> dn >> de) { is >> dh; const Setpoint b = base(); setSp({b.n + dn, b.e + de, b.psiDeg + dh}); } else say("Формат: move <dС> <dВ> [dКурс]"); }
        else if (c == "hdg") {
            std::string w; is >> w; double h = 0; bool isNum = false;
            try { size_t k = 0; h = std::stod(w, &k); isNum = !w.empty() && k == w.size(); } catch (...) {}
            if (w == "accept") {
                if (hdgPend_) { hdgPend_ = false; const Setpoint b = base(); setSp({b.n, b.e, hdgPendVal_}); say("Смена курса принята оператором"); } else say("Нет смены курса, ожидающей подтверждения");
            } else if (w == "cancel") {
                if (hdgPend_) { hdgPend_ = false; say("Смена курса отменена оператором"); } else say("Нет смены курса, ожидающей подтверждения");
            } else if (isNum) {
                const Setpoint b = base();
                if (hdgConfirmDeg_ > 0 && activeNow && std::fabs(wrapDeg(h - b.psiDeg)) > hdgConfirmDeg_) {
                    hdgPend_ = true; hdgPendVal_ = h; hdgPendAt_ = clock();
                    char bb[200]; std::snprintf(bb, sizeof bb, "Смена курса на %.1f° (на %.1f°) ждёт подтверждения: hdg accept или hdg cancel (60 с)", h, wrapDeg(h - b.psiDeg)); say(bb);
                } else setSp({b.n, b.e, h});
            } else say("Формат: hdg <курс> | hdg accept | hdg cancel");
        }
        else if (c == "hdgconfirm") {   // hdgconfirm <градусы>|off — смена курса больше этого порога требует подтверждения
            std::string w; is >> w; double d = 0;
            if (w == "off") { hdgConfirmDeg_ = 0; hdgPend_ = false; say("Подтверждение смены курса выключено"); }
            else { try { size_t k = 0; d = std::stod(w, &k); if (k != w.size() || d < 5 || d > 180) throw 1; hdgConfirmDeg_ = d; char bb[120]; std::snprintf(bb, sizeof bb, "Смена курса больше %.0f° требует подтверждения (hdg accept)", d); say(bb); } catch (...) { say("Формат: hdgconfirm <5…180°>|off"); } }
        }
        else if (c == "watch") {        // watch on <минуты> | off | reset — таймер бдительности оператора
            std::string w; is >> w;
            if (w == "on") { double m = 10; if (!(is >> m)) m = 10; if (m < 1 || m > 60) say("Формат: watch on <1…60 минут>"); else { watchOn_ = true; watchPeriodS_ = m * 60.0; watchAt_ = clock(); char bb[120]; std::snprintf(bb, sizeof bb, "Таймер бдительности включён: подтверждение каждые %.0f мин (watch reset)", m); say(bb); } }
            else if (w == "off") { watchOn_ = false; say("Таймер бдительности выключен"); }
            else if (w == "reset") { watchAt_ = clock(); say(watchOn_ ? "Бдительность подтверждена" : "Таймер бдительности выключен (watch on <минуты>)"); }
            else say("Формат: watch on <минуты> | watch off | watch reset");
        }
        else if (c == "sentwatch") {    // sentwatch <секунды>|off — тревога, если принимаемое предложение датчика замолчало
            std::string w; is >> w;
            if (w == "off") { sentTimeoutS_ = 0; say("Контроль посылок датчиков выключен"); }
            else { try { size_t k = 0; const double d = std::stod(w, &k); if (k != w.size() || d < 2 || d > 600) throw 1; sentTimeoutS_ = d; char bb[120]; std::snprintf(bb, sizeof bb, "Тревога, если посылка датчика молчит дольше %.0f с", d); say(bb); } catch (...) { say("Формат: sentwatch <2…600 с>|off"); } }
        }
        else if (c == "hypot") {      // hypot [fail=PU1,VRK_P] [bus=A|B] [limit=%] [wind=м/с] [from=°] [cur=м/с] [radius=м] — гипотетический анализ возможностей и дрейфа
            HypotCase h; std::string t; bool ok = true;
            while (is >> t) {
                const size_t eq = t.find('='); if (eq == std::string::npos) { ok = false; break; }
                const std::string k = t.substr(0, eq), v = t.substr(eq + 1);
                try {
                    if (k == "fail") { std::istringstream q(v); std::string id; while (std::getline(q, id, ',')) if (!id.empty()) h.failed.push_back(id); }
                    else if (k == "bus") { if (v == "A") h.deadBus[0] = true; else if (v == "B") h.deadBus[1] = true; else ok = false; }
                    else if (k == "limit") h.thrustLimitPct = std::stod(v);
                    else if (k == "wind") h.windMS = std::stod(v);
                    else if (k == "from") h.windFromDeg = std::stod(v);
                    else if (k == "cur") h.currentMS = std::stod(v);
                    else if (k == "radius") h.radiusM = std::stod(v);
                    else ok = false;
                } catch (...) { ok = false; }
            }
            if (!ok) say("Формат: hypot [fail=PU1,VRK_P] [bus=A|B] [limit=%] [wind=м/с] [from=°] [cur=м/с] [radius=м]");
            else {
                const DriftResult d = capHypot(cfg_, h);
                char b[260]; std::snprintf(b, sizeof b, "Гипотеза: ветер %.0f м/с с %.0f°, течение %.1f м/с. %s. Не добирается %.0f кН, момент %.0f кН·м", h.windMS, h.windFromDeg, h.currentMS, d.note.c_str(), d.residualN / 1000, d.yawResidualNm / 1000);
                say(b);
            }
        }
        else if (c == "pivots") {     // список готовых точек вращения
            std::string s = "Точки вращения: center (мидель), bow (нос, +" + std::to_string(static_cast<int>(cfg_.vessel.length / 2)) + " м), stern (корма)";
            for (const auto& p : cfg_.pivotPresets) s += ", " + p.name;
            say(s);
        }
        else if (c == "tal") {        // tal normal|lowbias|highbias|portahead|stbdahead — режим логики распределения тяги колонок (TAL)
            std::string m; is >> m;
            if (m == "normal" || m == "lowbias" || m == "highbias" || m == "portahead" || m == "stbdahead") { talMode_ = m; applyTal(); say("Режим TAL: " + m); }
            else say("Формат: tal normal|lowbias|highbias|portahead|stbdahead (сейчас: " + talMode_ + ")");
        }
        else if (c == "autoexcl") {   // autoexcl on|off — автоснятие движителя с управления ДП при расхождении обратной связи (возврат только вручную: thr_take)
            std::string w; is >> w; if (w == "on" || w == "off") { autoExcl_ = (w == "on"); say(autoExcl_ ? "Автоснятие неисправного движителя включено" : "Автоснятие неисправного движителя выключено"); } else say("Формат: autoexcl on|off");
        }
        else if (c == "holdarea") {   // holdarea <радиус м>|off|warn <%>|stop <%> — зона удержания
            std::string w; is >> w; ControlCfg cc = eng_.controller().cfg(); double v = 0;
            auto num = [&](const std::string& t) { try { size_t k = 0; v = std::stod(t, &k); return k == t.size(); } catch (...) { return false; } };
            if (w == "off") cc.holdAreaM = 0;
            else if (w == "warn" || w == "stop") { std::string t; is >> t; if (!num(t) || v < 0 || v > 100) { say("holdarea warn|stop <0…100 % радиуса>"); return; } (w == "warn" ? cc.holdWarnPct : cc.holdStopPct) = v; }
            else if (num(w) && v >= 1 && v <= 500) cc.holdAreaM = v;
            else { say("Формат: holdarea <радиус 1…500 м> | off | warn <%> | stop <%>"); return; }
            eng_.controller().configure(cc); cfg_.control.holdAreaM = cc.holdAreaM; cfg_.control.holdWarnPct = cc.holdWarnPct; cfg_.control.holdStopPct = cc.holdStopPct;
            if (cc.holdAreaM > 0) { char b[200]; std::snprintf(b, sizeof b, "Зона удержания: радиус %.0f м, предупреждение %.0f %%, остановка %.0f %%", cc.holdAreaM, cc.holdWarnPct, cc.holdStopPct); say(b); } else say("Зона удержания выключена");
        }
        else if (c == "pivotreset") { std::string w; is >> w; if (w == "on" || w == "off") { pivotResetOn_ = (w == "on"); say(pivotResetOn_ ? "Сброс точки вращения при выходе из режима ДП включён (через 5 с)" : "Сброс точки вращения выключен"); } else say("Формат: pivotreset on|off"); }
        else if (c == "sim") {
            if (!sim_) { say("Команды имитации доступны только в режиме имитации."); return; }
            std::string w; is >> w; EnvCfg& env = sim_->target();   // фактическая среда плавно догоняет заданную
            auto sensorKnown = [&](const std::string& id) { for (auto& p : simIds()) if (p == id) return true; return false; };
            if (w == "wind") { double sp, fr; if (is >> sp >> fr) { env.windSpeed = clampd(sp, 0, 60); env.windFromDeg = fr; } else say("Формат: sim wind <м/с> <откуда°>"); }
            else if (w == "current") { double sp, to; if (is >> sp >> to) { env.currentSpeed = clampd(sp, 0, 5); env.currentToDeg = to; } else say("Формат: sim current <м/с> <куда°>"); }
            else if (w == "wave") { double hs, tp, fr; if (is >> hs >> tp >> fr) { env.hs = clampd(hs, 0, 15); env.tp = clampd(tp, 2, 20); env.waveFromDeg = fr; } else say("Формат: sim wave <Hs м> <Tp с> <откуда°>"); }
            else if (w == "off" || w == "on") { std::string id; is >> id; if (sensorKnown(id)) sim_->failSensor(id, w == "off"); else say("Нет такого датчика: " + id); }
            else if (w == "thr") { std::string st, id; is >> st >> id; if (!sim_->failThrusterById(id, st == "off")) say("Нет такого движителя: " + id); }
            else if (w == "jump") { std::string id; double dn, de; if (is >> id >> dn >> de) { if (std::fabs(dn) < 1e-9 && std::fabs(de) < 1e-9) sim_->clearJump(id); else sim_->jumpSensor(id, dn, de); } else say("Формат: sim jump <GNSS1> <дС м> <дВ м> (0 0 — снять)"); }
            else if (w == "freeze") { std::string id, st; if (is >> id >> st) { if (sensorKnown(id)) sim_->freezeSensor(id, st == "on"); else say("Нет такого датчика: " + id); } else say("Формат: sim freeze <ID> on|off"); }
            else if (w == "fbfault") { std::string id, v; if (is >> id >> v) { if (v == "off") fbOverride_.erase(id); else { try { fbOverride_[id] = std::stod(v); } catch (...) { say("Формат: sim fbfault <движитель> <упор %>|off"); } } } else say("Формат: sim fbfault <движитель> <упор %>|off"); }
            else if (w == "noise") { std::string id; double k; if (is >> id >> k) sim_->noiseScale(id, clampd(k, 1, 50)); else say("Формат: sim noise <ID> <во сколько раз больше шум>"); }
            else if (w == "gyro") { std::string id; double d; if (is >> id >> d) sim_->gyroOffset(id, clampd(d, -30, 30)); else say("Формат: sim gyro <GYRO1> <сдвиг°>"); }
            else if (w == "mru") { std::string id; double r, p, h; if (is >> id >> r >> p >> h) sim_->biasMru(id, deg2rad(clampd(r, -20, 20)), deg2rad(clampd(p, -20, 20)), clampd(h, -5, 5)); else say("Формат: sim mru <MRU1> <крен°> <дифферент°> <heave м>"); }
            else if (w == "reset") {
                for (auto& id : simIds()) { sim_->failSensor(id, false); sim_->clearJump(id); sim_->freezeSensor(id, false); fbOverride_.clear(); sim_->noiseScale(id, 1); sim_->gyroOffset(id, 0); sim_->biasMru(id, 0, 0, 0); }
                for (auto& t : cfg_.thrusters) sim_->failThrusterById(t.id, false);
            }
            else say("sim: wind, current, wave, off|on <ID>, thr off|on <ID>, jump, noise, gyro, mru, reset");
        }
        else if (c == "plant") {
            if (!sim_ || !plant_.enabled()) { say("Электростанция не описана (раздел plant в настройках) или нет имитации."); return; }
            std::string w; is >> w;
            auto busIdx = [](const std::string& b) { return b == "A" || b == "a" ? 0 : b == "B" || b == "b" ? 1 : -1; };
            if (w == "gen") { std::string st, id; is >> st >> id; if (!plant_.setGen(id, st == "on")) say("Нет такого генератора: " + id); }
            else if (w == "bus") { std::string st, b; is >> st >> b; const int bi = busIdx(b); if (bi < 0) say("Формат: plant bus off|on A|B"); else { plant_.setBus(bi, st == "off"); syncBusThrusters(); } }
            else if (w == "tie") { std::string st; is >> st; plant_.setTie(st == "close"); }
            else if (w == "reset") { plant_.reset(); if (dpActive_ && plant_.cfg().tieOpenInDp) plant_.setTie(false); syncBusThrusters(); }
            else say("plant: gen off|on <ID>, bus off|on A|B, tie open|close, reset");
        }
        else if (c == "sensor") {      // sensor <ID> offset x y z | sensor <ID> sigma s
            std::string id, w; is >> id >> w;
            if (w == "offset") { double x, y, z; if (is >> x >> y >> z) { if (std::fabs(x) > 500 || std::fabs(y) > 100 || std::fabs(z) > 100) say("Смещение вне допустимых пределов (|x| ≤ 500, |y| ≤ 100, |z| ≤ 100 м)"); else if (!hub_.setOffset(id, x, y, z)) say("Нет такого датчика: " + id); } else say("Формат: sensor <ID> offset <x нос> <y правый борт> <z вниз>"); }
            else if (w == "sigma") { double s; if (is >> s) { if (!hub_.setSigma(id, s)) say("Нет такого датчика или значение вне 0,001…1000: " + id); } else say("Формат: sensor <ID> sigma <СКО>"); }
            else if (w == "accept" || w == "talkers" || w == "check" || w == "quality" || w == "hdop" || w == "magvar" || w == "sign" || w == "ref" || w == "rls" || w == "target" || w == "brg") {
                // лазерный радар: sensor <ID> ref N E | rls signa|signb 1|-1 | rls swap 0|1
                // настройка посылок: sensor <ID> accept GGA,RMC|default | talkers GP,GN|any | check on|off | quality N | hdop X | magvar ° | sign roll|pitch|heave 1|-1
                std::string val; std::getline(is, val); while (!val.empty() && val.front() == ' ') val.erase(val.begin()); while (!val.empty() && (val.back() == ' ' || val.back() == '\r')) val.pop_back();
                std::string key = w, why;
                if (w == "sign" || w == "rls" || w == "brg") { std::istringstream q(val); std::string ax, v2; q >> ax >> v2; key = w + "." + ax; val = v2; }
                if (!hub_.setParam(id, key, val, why)) say(why);
                else { say("Датчик " + id + ": " + w + " = " + (val.empty() ? "по умолчанию" : val)); saveSensors(); }
            }
            else say("sensor: <ID> offset x y z | sigma s | accept LIST|default | talkers LIST|any | check on|off | quality N | hdop X | magvar ° | sign roll|pitch|heave 1|-1");
        }
        else if (c == "ref") {         // ref <ID> mode enable|monitor|disable | accept narrow|normal|wide
            std::string id, w, v; is >> id >> w >> v; PosRefCfg& pc = eng_.estimatorMut().cfgMut().posRef[id];
            if (w == "mode") { if (v == "enable") pc.mode = 0; else if (v == "monitor") pc.mode = 1; else if (v == "disable") pc.mode = 2; else if (v == "mobile") pc.mode = 3; else say("mode: enable, monitor, mobile, disable"); }
            else if (w == "weight") {   // ref <ID> weight 1..10 — ручной вес (действует при fusion weights manual); для всех GNSS сразу — fusion gnssweight
                try { const int k = std::stoi(v); if (k >= 1 && k <= 10) { pc.manualWeight = k; say("Вес " + id + ": " + std::to_string(k) + (eng_.estimator().cfg().weightMode == 1 ? "" : " (действует при fusion weights manual)")); } else say("weight: от 1 до 10 (5 — нейтральный)"); }
                catch (...) { say("Формат: ref <ID> weight 1..10"); }
            }
            else if (w == "auto") {   // auto on|off|now — первое измерение системы задаёт начало координат (относительные системы)
                if (v == "on") { pc.autoRef = true; eng_.estimatorMut().rearmAutoRef(id); say("Автоначало " + id + ": включено, ждёт первого измерения"); }
                else if (v == "off") { pc.autoRef = false; say("Автоначало " + id + ": выключено"); }
                else if (v == "now") { pc.autoRef = true; eng_.estimatorMut().rearmAutoRef(id); say("Автоначало " + id + ": по следующему измерению"); }
                else say("auto: on, off, now");
            }
            else if (w == "accept") { if (v == "narrow") pc.accept = 0; else if (v == "normal") pc.accept = 1; else if (v == "wide") pc.accept = 2; else say("accept: narrow, normal, wide"); }
            else say("ref: <ID> mode|accept <значение>");
        }
        else if (c == "fusion") {      // fusion median off|warn|reject | soft <м/с> | gnssweight normal|reduced
            std::string w, v; is >> w >> v; EstimatorCfg& ec = eng_.estimatorMut().cfgMut();
            if (w == "median") { if (v == "off") ec.medianMode = 0; else if (v == "warn") ec.medianMode = 1; else if (v == "reject") ec.medianMode = 2; else say("median: off, warn, reject"); }
            else if (w == "soft") { try { const double s = std::stod(v); if (s >= 0 && s <= 10) ec.softRateMS = s; else say("soft: от 0 до 10 м/с (0 — выкл.)"); } catch (...) { say("Формат: fusion soft <м/с>"); } }
            else if (w == "freeze") { try { const int n = v == "off" ? 0 : std::stoi(v); if (n == 0 || (n >= 3 && n <= 1000)) { ec.freezeCount = n; say(n ? "Тест заморозки: " + std::to_string(n) + " одинаковых измерений подряд" : "Тест заморозки выключен"); } else say("freeze: от 3 до 1000 или off"); } catch (...) { say("Формат: fusion freeze <N>|off"); } }
            else if (w == "gnssweight") { if (v == "normal") ec.gnssWeight = 0; else if (v == "reduced") ec.gnssWeight = 1; else say("gnssweight: normal, reduced"); }
            else if (w == "variance") {   // fusion variance off|warn|factor <k>
                if (v == "off") { ec.varTest = 0; say("Тест дисперсии: выключен"); }
                else if (v == "warn") { ec.varTest = 1; say("Тест дисперсии: предупреждение при разбросе больше ×" + std::to_string(ec.varFactor).substr(0, 4) + " заявленного СКО"); }
                else if (v == "factor") { double k = 0; if (is >> k && k >= 1.5 && k <= 20) { ec.varFactor = k; say("Тест дисперсии: порог ×" + std::to_string(k).substr(0, 4)); } else say("factor: от 1,5 до 20"); }
                else say("variance: off, warn, factor <k>");
            }
            else if (w == "weights") { if (v == "normal") ec.weightMode = 0; else if (v == "manual") ec.weightMode = 1; else if (v == "auto") ec.weightMode = 2; else say("weights: normal, manual (ref <ID> weight 1..10), auto (по повторяемости)"); if (v == "normal" || v == "manual" || v == "auto") say("Веса систем положения: " + v); }
            else if (w == "diverge") { if (v == "off") { ec.divergeM = 0; say("Тест расхождения: выключен"); } else { try { const double m = std::stod(v); if (m >= 0.5 && m <= 500) { ec.divergeM = m; say("Тест расхождения: предупреждение при расхождении систем больше " + v + " м"); } else say("diverge: off или 0,5…500 м"); } catch (...) { say("Формат: fusion diverge off|<м>"); } } }
            else say("fusion: median off|warn|reject, soft <м/с>, gnssweight normal|reduced, variance off|warn|factor <k>, weights normal|manual|auto, diverge off|<м>");
        }
        else if (c == "ack") { std::string code; is >> code; alarms_.ack(clock(), code); }
        else if (c == "silence") alarms_.silence();
        else if (c == "msg") {         // msg <код>|all — описание сообщения, последствия и действия (словарь сообщений)
            std::string code; is >> code;
            if (code.empty()) say("Формат: msg <код сообщения> | msg all");
            else if (code == "all") say(messagesMarkdown());
            else { const MsgInfo m = adviceFor(code); say(m.title.empty() ? "Нет описания для «" + code + "»" : messageText(m)); }
        }
        else if (c == "class") {       // class 0|2|3 — анализ последствий отказа (DP class 2/3), как «DP Class» в K-Pos
            int k = -1; if (is >> k && (k == 0 || k == 2 || k == 3)) { dpClass_ = k; cfg_.dpClass = k; }
            else say("Формат: class 0|2|3 (0 — анализ последствий выключен)");
        }
        else if (c == "gain") {        // gain high|low — усиление контуров (High/Low gain)
            std::string m; is >> m; ControlCfg cc = eng_.controller().cfg();
            if (m == "high") cc.highGain = true; else if (m == "low") cc.highGain = false; else { say("Формат: gain high|low"); return; }
            eng_.controller().configure(cc); cfg_.control.highGain = cc.highGain;
            say(cc.highGain ? "Усиление: высокое (High gain)" : "Усиление: низкое (Low gain)");
        }
        else if (c == "minpower") {    // minpower on|off — минимальная мощность
            std::string m; is >> m; ControlCfg cc = eng_.controller().cfg();
            if (m == "on") cc.minPower = true; else if (m == "off") cc.minPower = false; else { say("Формат: minpower on|off"); return; }
            eng_.controller().configure(cc); cfg_.control.minPower = cc.minPower;
            say(cc.minPower ? "Минимальная мощность включена" : "Минимальная мощность выключена");
        }
        else if (c == "radius") {      // radius <м> | off — радиус удержания
            std::string w; is >> w; double r = 0;
            if (w == "off" || w == "0") setHoldRadius(0);
            else { try { r = std::stod(w); } catch (...) { r = -1; }
                   if (r >= kHoldRadiusMin && r <= kHoldRadiusMax) setHoldRadius(r); else say("Формат: radius <от 0.5 до 50 м> | off"); }
        }
        else if (c == "forecast") {    // forecast on|off | apply on|off | reset | save — прогнозирование внешних сил
            std::string a, b; is >> a >> b; ForecastCfg fc = eng_.forecast().cfg();
            if (a == "on" || a == "off") { fc.enabled = a == "on"; eng_.forecast().configure(fc); say(fc.enabled ? "Прогнозирование включено (накопление и прогноз)" : "Прогнозирование выключено"); }
            else if (a == "apply" && (b == "on" || b == "off")) { fc.apply = b == "on"; eng_.forecast().configure(fc); say(fc.apply ? "Поправка таблицы применяется к силе ветра" : "Поправка таблицы не применяется (только накопление и прогноз)"); }
            else if (a == "reset") { eng_.forecast().reset(); say("Таблица прогнозирования очищена"); }
            else if (a == "save") { say(saveForecast() ? "Таблица прогнозирования сохранена" : "Таблица прогнозирования не сохранена (нет файла или ошибка записи)"); }
            else say("Формат: forecast on|off | forecast apply on|off | forecast reset | forecast save");
        }
        else if (c == "calib") {       // calib start|stop|reset | ref <ID|median> | apply <ID|all> — калибровка систем положения
            std::string a, b; is >> a >> b; Calibrator& cal = eng_.estimatorMut().calibrator();
            if (a == "start") { cal.start(); say("Калибровка: сбор запущен"); }
            else if (a == "stop") { cal.stop(); say("Калибровка: сбор остановлен"); }
            else if (a == "reset") { cal.reset(); say("Калибровка: накопленное сброшено"); }
            else if (a == "ref") { if (b.empty()) say("Формат: calib ref <ID|median>"); else { cal.setRef(b); say(cal.ref().empty() ? "Калибровка: эталон — медиана остальных систем" : "Калибровка: эталон — " + cal.ref()); } }
            else if (a == "apply") {
                std::vector<std::string> ids; for (const auto& ci : hub_.channels(hubNow())) if (ci.kind == ChannelKind::Gnss || ci.kind == ChannelKind::LaserRadar || ci.kind == ChannelKind::TautWire) ids.push_back(ci.id);
                const CalView v = cal.view(ids); int done = 0;
                for (const auto& x : v.s) {
                    if (b != "all" && b != x.id) continue;
                    if (!x.ready || x.isRef) { if (b == x.id) say("Калибровка " + x.id + ": нет готовой поправки (мало отсчётов, нет эталона или это эталон)"); continue; }
                    PosRefCfg& pc = eng_.estimatorMut().cfgMut().posRef[x.id]; pc.biasN += x.bn; pc.biasE += x.be;
                    if (x.fitAnt) for (const auto& ci : hub_.channels(hubNow())) if (ci.id == x.id) hub_.setOffset(x.id, ci.offset.x + x.dx, ci.offset.y + x.dy, ci.offset.z);
                    ++done;
                }
                if (done) { cal.reset(); cal.start(); say("Калибровка: поправки применены (" + std::to_string(done) + "), сбор начат заново"); }
                else if (b == "all") say("Калибровка: нет готовых поправок");
            }
            else say("Формат: calib start|stop|reset | calib ref <ID|median> | calib apply <ID|all>");
        }
        else if (c == "hdglimit") {    // hdglimit <1…45°> | off — предел курса
            std::string w; is >> w; double d = 0;
            if (w == "off" || w == "0") { eng_.setHdgLimit(0); say("Предел курса выключен"); }
            else { try { d = std::stod(w); } catch (...) { d = -1; }
                   if (d >= 1.0 && d <= 45.0) { eng_.setHdgLimit(d); say("Предел курса: " + std::to_string(d).substr(0, std::to_string(d).find('.') + 2) + "°"); }
                   else say("Формат: hdglimit <от 1 до 45°> | off"); }
        }
        else if (c == "law") {
            std::string l; is >> l; ControlCfg cc = eng_.controller().cfg();   // настройки по радиусу сохраняются: меняется только закон
            if (l == "pid") cc.law = LawType::Pid; else if (l == "lqr") cc.law = LawType::Lqr; else if (l == "mpc") cc.law = LawType::Mpc; else { say("Законы: pid, lqr, mpc"); return; }
            eng_.controller().configure(cc); say("Закон управления: " + l);
        } else if (c == "status") statusRequested_ = true;
        else say("Неизвестная команда «" + c + "», help — список команд.");
    }

    // Идентификаторы датчиков имитатора (для команд sim)
    std::vector<std::string> simIds() const {
        std::vector<std::string> r;
        if (!sim_) return r;
        const SimSensorsCfg& sc = sim_->sensors();
        for (const auto& g : sc.gnss) r.push_back(g.id);
        if (sc.laser) r.push_back("LASER");
        if (sc.wire) r.push_back("WIRE");
        for (int i = 1; i <= sc.gyros; ++i) r.push_back("GYRO" + std::to_string(i));
        for (int i = 1; i <= sc.anemometers; ++i) r.push_back("WIND" + std::to_string(i));
        for (int i = 1; i <= sc.mrus; ++i) r.push_back("MRU" + std::to_string(i));
        return r;
    }
    // Текст активных искажений для показа оператору
    std::string simModsText() const {
        if (!sim_) return "";
        std::string t; char b[96];
        for (auto& j : sim_->jumps()) { std::snprintf(b, sizeof b, "%s сдвиг %+.1f/%+.1f м; ", j.first.c_str(), j.second.first, j.second.second); t += b; }
        for (auto& j : sim_->gyroOffsets()) { std::snprintf(b, sizeof b, "%s сдвиг %+.1f°; ", j.first.c_str(), rad2deg(j.second)); t += b; }
        for (auto& j : sim_->mruOffsets()) if (std::fabs(j.second[0]) + std::fabs(j.second[1]) + std::fabs(j.second[2]) > 1e-9) { std::snprintf(b, sizeof b, "%s смещение %+.1f°/%+.1f°/%+.1f м; ", j.first.c_str(), rad2deg(j.second[0]), rad2deg(j.second[1]), j.second[2]); t += b; }
        for (auto& id : simIds()) if (sim_->noiseScaleOf(id) > 1.0001) { std::snprintf(b, sizeof b, "%s шум ×%.0f; ", id.c_str(), sim_->noiseScaleOf(id)); t += b; }
        return t;
    }

    static const char* helpText() {
        return "Команды оператора:\n"
               "  standby                    ожидание (команды на движители не выдаются)\n"
               "  position                   удержание позиции в текущей точке\n"
               "  heading                    удержание курса\n"
               "  track                      движение по треку из настроек\n"
               "  set <север> <восток> <курс>  новая уставка (м от начала координат, градусы)\n"
               "  move <dС> <dВ> [dКурс]     сместить уставку относительно текущей\n"
               "  hdgconfirm <°>|off         смена курса больше порога ждёт подтверждения: hdg accept | hdg cancel\n"
               "  watch on <мин>|off|reset   таймер бдительности оператора (любая команда его сбрасывает)\n"
               "  sentwatch <с>|off          тревога, если принимаемая посылка датчика замолчала\n"
               "  pivotreset on|off          сброс точки вращения через 5 с после выхода из режима ДП\n"
               "  ext [status|tpl|active on <код>|off|send <шаблон>|inject <строка>|setup <JSON>|clear]  связь с внешней ДП (Praxis, Kongsberg); setup/clear — настройка из окна\n"
               "  rate [rot <°/мин>|off|speed <узлов>|off]  ограничения движения: макс. скорость поворота и перемещения (ставит оператор, только уменьшают заданное в настройках)\n"
               "  src [list|test <JSON линии> [секунд]|watch on|off]  физические источники: COM/USB-порты, сетевые интерфейсы, проверка линии (только слушает)\n"
               "  cap [status|setup <JSON>|clear|start [метка]|stop|mark <текст>|report|replay last <канал> <адрес> <порт> [скорость]|replay stop|watch on|off]  запись обмена с внешней системой (UDP/TCP/COM, Modbus)\n"
               "  limits [on|off|move|setdist|hdg|forbid|allow]  ограничения оператора (меняет администратор)\n"
               "  pivot center|bow|stern|<имя>  точка вращения по названию (список: pivots; свои — pivotPresets в конфигурации)\n"
               "  hypot fail=… bus=A|B limit=% wind=м/с from=° cur=м/с radius=м  гипотетический анализ: держит ли, дрейф, время до радиуса\n"
               "  tal normal|lowbias|highbias|portahead|stbdahead  режим логики распределения тяги колонок\n"
               "  autoexcl on|off            автоснятие движителя с управления при расхождении обратной связи\n"
               "  holdarea <R м>|off|warn <%>|stop <%>  зона удержания (радиус, предупреждение, остановка)\n"
               "  ref <ID> auto on|off|now   автоначало относительной системы по текущему решению\n"
               "  fusion freeze <N>|off      тест заморозки: N одинаковых измерений подряд\n"
               "  fusion variance off|warn|factor <k>  тест дисперсии (повторяемости) систем положения\n"
               "  fusion weights normal|manual|auto    веса систем: обычные, ручные 1–10 (ref <ID> weight), по повторяемости\n"
               "  fusion diverge off|<м>     тест расхождения: предупреждение, если две системы расходятся больше предела\n"
               "  ref <ID> mode enable|monitor|mobile|disable  режим системы (mobile — не участвует в удержании)\n"
               "  sensor <ID> brg off <°>    поправка нуля пеленга Fanbeam или азимута Artemis\n"
               "  msg <код>|all              описание сообщения: последствия и действия (словарь сообщений)\n"
               "  hdg <курс>                 новый курс\n"
               "  law pid|lqr|mpc            сменить закон управления\n"
               "  gain high|low              усиление контуров: высокое / низкое (High/Low gain)\n"
               "  minpower on|off            минимальная мощность: малые отклонения не отрабатываются\n"
               "  forecast on|off|reset|save  прогнозирование сил: накопление таблицы поправок и прогноз нагрузки; forecast apply on|off\n"
               "  hdglimit <1…45°>|off       предел курса: предупреждение при 80 %, аларм при выходе\n"
               "  plant ...                  электростанция (имитация): gen off|on <ID>, bus off|on A|B, tie open|close, reset\n"
               "  sim ...                    имитация: wind, current, wave, off|on <ID>, thr off|on <ID>, jump, noise, gyro, mru, reset\n"
               "  status                     показать состояние\n"
               "  quit                       выход\n";
    }

    // --- доступ для интерфейсов
    const AppCfg& cfg() const { return cfg_; }
    double dt() const { return dt_; }
    double clock() const { return sim_ ? t_ : monotonicSeconds(); }
    const EngineOutput& out() const { return out_; }
    DpEngine& engine() { return eng_; }
    Simulator* sim() { return sim_.get(); }
    double holdRadius() const { return holdR_; }
    // Радиус удержания, м (0 — выключен): меняет настройки закона по радиусу и включает предупреждение/аларм выхода за радиус.
    void setHoldRadius(double r) {
        holdR_ = r > 0 ? r : 0;
        ControlCfg cc = eng_.controller().cfg();
        const ControlCfg t = tuneForRadius(baseCtl_, holdR_);      // только поля, зависящие от радиуса; закон, усиление и минимальная мощность остаются
        cc.wnPos = t.wnPos; cc.posTolM = t.posTolM; cc.velTolMS = t.velTolMS; cc.posDeadM = t.posDeadM; cc.biasFilterS = t.biasFilterS;
        eng_.controller().configure(cc); eng_.setHoldRadius(holdR_);
        say(holdR_ > 0 ? "Радиус удержания: " + std::to_string(holdR_).substr(0, std::to_string(holdR_).find('.') + 2) + " м" : std::string("Радиус удержания выключен"));
    }
    SensorHub& hub() { return hub_; }
    double hubNow() const { return sim_ ? t_ : monotonicSeconds(); }
    LocalFrame frame() const { return sim_ ? lf_ : hub_.frame(); }
    bool quitRequested() const { return quit_; }
    bool takeStatusRequest() { const bool r = statusRequested_; statusRequested_ = false; return r; }
    Setpoint setpoint() { return eng_.mode() == DpMode::Standby || eng_.mode() == DpMode::Manual ? (opSpSet_ ? opSp_ : eng_.controller().holdFromCrp(out_.est.n, out_.est.e, rad2deg(out_.est.psi))) : eng_.controller().setpoint(); }
    bool setpointPending() { return opSpSet_ && (eng_.mode() == DpMode::Standby || eng_.mode() == DpMode::Manual); }
    const TrackCfg& track() const { return cfg_.track; }
    std::vector<LinkStatus> linkStatus() const { std::vector<LinkStatus> r; for (auto& l : links_) r.push_back(l->status()); return r; }
    RunStats stats() const {
        RunStats s; s.seconds = n_ * dt_;
        if (n_ > 0) { s.rmsPos = std::sqrt(sum2_ / n_); s.maxPos = max_; s.rmsHdg = std::sqrt(h2_ / n_); s.maxHdg = hmax_; }
        return s;
    }
    // Взятие движителей под управление ДП. При запуске в ожидании (startMode = standby) ни один не взят; в остальных случаях — все (как раньше).
    void initTaken() {
        if (taken_.size() == cfg_.thrusters.size()) return;
        taken_.assign(cfg_.thrusters.size(), cfg_.startMode == "standby" ? 0 : 1);
        for (size_t i = 0; i < taken_.size(); ++i) eng_.setThrusterEnabled(i, cfg_.thrusters[i].enabled && taken_[i]);
    }
    int takenCount() { initTaken(); int n = 0; for (char c : taken_) n += c ? 1 : 0; return n; }
    void takeThrusters(const std::string& which, bool take) {
        initTaken(); int hit = 0;
        for (size_t i = 0; i < cfg_.thrusters.size(); ++i) {
            if (which != "all" && cfg_.thrusters[i].id != which) continue;
            ++hit; taken_[i] = take ? 1 : 0;
            eng_.setThrusterEnabled(i, cfg_.thrusters[i].enabled && taken_[i]);
            say(std::string(take ? "Под управлением ДП: " : "Снят с управления ДП: ") + cfg_.thrusters[i].id);
        }
        if (!hit) say("Нет такого движителя: " + which);
        if (!take && takenCount() == 0 && eng_.mode() != DpMode::Standby && eng_.mode() != DpMode::Manual) {
            eng_.setMode(DpMode::Standby); modeSince_ = -1; opSpSet_ = false;
            say("Все движители сняты с управления: режим ожидания.");
        }
    }
    std::vector<ThrusterView> thrusters() {
        initTaken();
        std::vector<ThrusterView> v;
        const auto& th = cfg_.thrusters;
        for (size_t i = 0; i < th.size(); ++i) {
            ThrusterView t; t.id = th[i].id; t.type = th[i].type; t.enabled = th[i].enabled; t.taken = taken_[i] != 0; t.x = th[i].x; t.y = th[i].y; t.fixedAngleDeg = rad2deg(thrusterBaseAngle(th[i]));
            if (i < out_.cmds.size()) { t.cmdPct = out_.cmds[i].pct; t.cmdAngleDeg = out_.cmds[i].angleDeg; }
            if (sim_ && i < sim_->thrusters().size()) { t.pct = sim_->thrusters()[i].pct(); t.angleDeg = sim_->thrusters()[i].angleDeg(); }
            else { t.pct = t.cmdPct; t.angleDeg = t.cmdAngleDeg; }
            { ThrusterCfg pc = th[i]; if (!t.taken) pc.idlePct = 0; t.powerKW = th[i].enabled ? thrusterPowerKW(pc, std::fabs(t.pct) / 100.0) : 0.0; } t.bus = th[i].bus;
            v.push_back(t);
        }
        return v;
    }
    // «Истинное» положение (только имитатор), для проверки оценки
    bool truth(double& n, double& e, double& psiDeg) const {
        if (!sim_) return false;
        n = sim_->truth().n; e = sim_->truth().e; psiDeg = rad2deg(sim_->truth().psi); return true;
    }

    const Plant& plant() const { return plant_; }
    const PlantState& plantState() const { return plantSt_; }
    const WorstCaseResult& worstCase() const { return wc_; }
    const AlarmMgr& alarmMgr() const { return alarms_; }
    int dpClass() const { return dpClass_; }
    bool conseqRunning() const { return cqRunning_; }
    const ConseqResult& conseq() const { return cq_; }

private:
    // Отказ шины выводит из строя её движители в имитаторе; восстановление шины возвращает их.
    void syncBusThrusters() {
        if (!sim_) return;
        for (int b = 0; b < 2; ++b) {
            const bool dead = plant_.busDead(b);
            if (dead == busDeadLast_[b]) continue;
            busDeadLast_[b] = dead;
            for (auto& t : cfg_.thrusters) if (t.bus == b) sim_->failThrusterById(t.id, dead);
        }
    }
    // В режимах ДП секционный выключатель размыкается (шины работают раздельно, DP-2), при возврате в ожидание — как в настройках.
    // Ручная команда plant tie действует до следующей смены режима.
    void plantTieAuto() {
        const DpMode m = eng_.mode();
        const bool act = m != DpMode::Standby && m != DpMode::Manual;
        if (act != dpActive_) {
            dpActive_ = act;
            if (plant_.cfg().tieOpenInDp) { plant_.setTie(act ? false : plant_.cfg().tieClosed); say(act ? "PMS: режим ДП — секционный выключатель разомкнут, шины раздельно" : "PMS: ожидание — секционный выключатель по настройкам"); }
        }
    }
    // Тревоги электростанции: низкий резерв, нехватка мощности, наихудший отказ (проверяется раз в секунду).
    void plantAlarms() {
        const PlantState& p = plantSt_;
        const DpMode m = eng_.mode();
        const bool act = m != DpMode::Standby && m != DpMode::Manual;
        for (int b = 0; b < 2; ++b) if (plant_.busDead(b)) out_.alarms.push_back({b ? "BUS_DEAD_B" : "BUS_DEAD_A", std::string("Шина ") + (b ? "B" : "A") + " обесточена: её движители и потребители потеряны", true});
        if (p.availableKW <= 0) out_.alarms.push_back({"BLACKOUT", "Потеря электропитания: нет работающих генераторов", true});
        if (act && plant_.tieClosed()) out_.alarms.push_back({"TIE_CLOSED", "В режиме ДП секционный выключатель замкнут (требуется разомкнутый)", false});
        if (p.reserveKW < 0) out_.alarms.push_back({"POWER_SHORT", "Мощности электростанции не хватает: нагрузка выше располагаемой", true});
        else if (p.reservePct < plant_.cfg().minReservePct) {
            char b[120]; std::snprintf(b, sizeof b, "Низкий резерв мощности: %.0f кВт (%.0f %%), порог %.0f %%", p.reserveKW, p.reservePct, plant_.cfg().minReservePct);
            out_.alarms.push_back({"LOW_RESERVE", b, false});
        }
        if (clock() - wcAt_ >= 1.0) {
            wcAt_ = clock();
            wc_ = act ? plant_.worstCase(cfg_.thrusters, out_.ctl.tau) : WorstCaseResult{};
        }
        if (act && !wc_.ok && dpClass_ < 2) {         // при включённом анализе последствий (класс 2/3) его сообщения заменяют эту тревогу
            char b[160];
            if (wc_.ratio >= 10) std::snprintf(b, sizeof b, "Наихудший отказ: при потере %s тяги не остаётся, удержание невозможно", wc_.what.c_str());
            else std::snprintf(b, sizeof b, "Наихудший отказ: при потере %s удержание невозможно (нужно %.0f %% возможностей)", wc_.what.c_str(), 100.0 * wc_.ratio);
            out_.alarms.push_back({"WORST_CASE", b, false});
        }
    }
    // Добавочные тревоги (по образцу тренажёра): бдительность, потеря посылок, слабая тяга по курсу, подтверждение смены курса; сброс точки вращения.
public:
    // Связь с внешней ДП: состояние (JSON для окна оператора) и текст для консоли
    std::string extJson() const {
        if (!ext_) return "{\"configured\":false,\"cfg\":" + extLinkToJson(cfg_.extlink) + "}";
        const ExtStatus& s = extSt_; auto q = [](const std::string& x) { return "\"" + vio::esc(x) + "\""; };
        std::string j = "{\"configured\":true,\"cfg\":" + extLinkToJson(ext_->cfg()) + ",\"vendor\":" + q(s.vendor) + ",\"active\":" + (s.active ? "true" : "false") + ",\"linked\":" + (s.linked ? "true" : "false")
            + ",\"age\":" + vio::num(std::min(s.ageS, 1e6)) + ",\"havePos\":" + (s.havePos ? "true" : "false") + ",\"haveHdg\":" + (s.haveHdg ? "true" : "false")
            + ",\"n\":" + vio::num(s.n) + ",\"e\":" + vio::num(s.e) + ",\"psi\":" + vio::num(s.psiDeg) + ",\"dPos\":" + vio::num(s.dPosM) + ",\"dHdg\":" + vio::num(s.dHdgDeg)
            + ",\"lines\":" + std::to_string(s.lines) + ",\"sent\":" + std::to_string(s.sent) + ",\"fields\":{";
        bool first = true; for (auto& kv : s.fields) { j += std::string(first ? "" : ",") + q(kv.first) + ":" + vio::num(kv.second); first = false; }
        j += "},\"note\":" + q(s.note) + ",\"sig\":[";
        for (size_t i = 0; i < s.sig.size(); ++i) { const ExtSignal& g = s.sig[i];
            j += std::string(i ? "," : "") + "{\"name\":" + q(g.name) + ",\"group\":" + q(g.group) + ",\"unit\":" + q(g.unit) + ",\"ch\":" + q(g.ch) + ",\"cmp\":" + q(g.cmp)
               + ",\"has\":" + (g.has ? "true" : "false") + ",\"v\":" + vio::num(g.value) + ",\"age\":" + vio::num(std::min(g.ageS, 1e6))
               + ",\"ours\":" + (g.haveOurs ? vio::num(g.ours) : std::string("null")) + ",\"d\":" + vio::num(g.delta) + "}"; }
        j += "],\"raw\":[";
        for (size_t i = 0; i < s.raw.size(); ++i) j += std::string(i ? "," : "") + q(s.raw[i]);
        return j + "],\"templates\":" + std::to_string(ext_->cfg().templates.size()) + "}";
    }
    std::string extText() const {
        const ExtStatus& s = extSt_; char b[260];
        std::snprintf(b, sizeof b, "Внешняя ДП (%s): %s, режим %s; принято строк %lld, отправлено %lld; расхождение положения %.1f м, курса %.1f°",
            s.vendor.c_str(), s.linked ? "связь есть" : "нет данных", s.active ? "АКТИВНЫЙ" : "только приём", s.lines, s.sent, s.dPosM, s.dHdgDeg);
        return b;
    }
    // Ограничения оператора: размер шага уставки, удаление от судна, шаг курса, запрещённые режимы. Меняет только администратор (право setup).
    struct OperatorLimits { bool on = false; double maxMoveM = 0, maxSetDistM = 0, maxHdgStepDeg = 0; double maxRotDegMin = 0, maxSpeedKn = 0; std::vector<std::string> forbidModes; };   // maxRotDegMin, maxSpeedKn — ограничения движения, которые ставит сам оператор (0 — нет)
    std::string limitsText() const {
        auto f = [](double x) { if (x <= 0) return std::string("не ограничен"); char b[40]; std::snprintf(b, sizeof b, "%.0f", x); return std::string(b); };
        std::string s = std::string("Ограничения оператора: ") + (lim_.on ? "ВКЛЮЧЕНЫ" : "выключены") + "; шаг уставки " + f(lim_.maxMoveM) + " м; удаление уставки от судна " + f(lim_.maxSetDistM) + " м; шаг курса " + f(lim_.maxHdgStepDeg) + "°; запрещены режимы: ";
        if (lim_.forbidModes.empty()) s += "нет"; else for (size_t i = 0; i < lim_.forbidModes.size(); ++i) s += (i ? ", " : "") + lim_.forbidModes[i];
        return s;
    }
    void applyMotionCaps() { eng_.controller().setMotionCaps(lim_.maxSpeedKn * 0.514444, lim_.maxRotDegMin / 60.0); }
    std::string motionText() const {
        char a[48], b[48];
        if (lim_.maxRotDegMin > 0) std::snprintf(a, sizeof a, "%.1f °/мин", lim_.maxRotDegMin); else std::snprintf(a, sizeof a, "не ограничен");
        if (lim_.maxSpeedKn > 0) std::snprintf(b, sizeof b, "%.2f уз", lim_.maxSpeedKn); else std::snprintf(b, sizeof b, "не ограничена");
        return std::string("Ограничения движения: поворот ") + a + ", скорость " + b;
    }
    const OperatorLimits& limits() const { return lim_; }
    void setLimits(const OperatorLimits& l) { lim_ = l; }
    void setLimitsFile(const std::string& path) {
        limFile_ = path; std::ifstream f(path, std::ios::binary); if (!f) return;
        std::stringstream ss; ss << f.rdbuf(); json::Value v; std::string e; if (!json::parse(ss.str(), v, e) || v.t != json::Value::Obj) return;
        auto n = [&](const char* k) { const json::Value* p = v.find(k); return p && p->t == json::Value::Num ? p->n : 0.0; };
        const json::Value* on = v.find("on"); lim_.on = on && on->t == json::Value::Bool && on->b;
        lim_.maxMoveM = n("move"); lim_.maxSetDistM = n("setdist"); lim_.maxHdgStepDeg = n("hdg"); lim_.maxRotDegMin = n("rot"); lim_.maxSpeedKn = n("speed"); lim_.forbidModes.clear();
        if (const json::Value* a = v.find("forbid")) if (a->t == json::Value::Arr) for (auto& x : a->a) if (x.t == json::Value::Str) lim_.forbidModes.push_back(x.s);
        applyMotionCaps();
    }
    bool saveLimits() {
        if (limFile_.empty()) return true;
        std::ofstream f(limFile_, std::ios::binary | std::ios::trunc); if (!f) return false;
        f << "{\"on\":" << (lim_.on ? "true" : "false") << ",\"move\":" << lim_.maxMoveM << ",\"setdist\":" << lim_.maxSetDistM << ",\"hdg\":" << lim_.maxHdgStepDeg << ",\"rot\":" << lim_.maxRotDegMin << ",\"speed\":" << lim_.maxSpeedKn << ",\"forbid\":[";
        for (size_t i = 0; i < lim_.forbidModes.size(); ++i) f << (i ? "," : "") << "\"" << lim_.forbidModes[i] << "\"";
        f << "]}\n"; return true;
    }
private:
    bool pivotByName(std::string a, double& x, double& y) {
        std::transform(a.begin(), a.end(), a.begin(), [](unsigned char ch) { return std::tolower(ch); });
        if (a == "center" || a == "centre" || a == "midship") { x = 0; y = 0; return true; }
        if (a == "bow") { x = cfg_.vessel.length / 2; y = 0; return true; }
        if (a == "stern") { x = -cfg_.vessel.length / 2; y = 0; return true; }
        for (const auto& p : cfg_.pivotPresets) {
            std::string n = p.name; std::transform(n.begin(), n.end(), n.begin(), [](unsigned char ch) { return std::tolower(ch); });
            if (n == a) { x = p.x; y = p.y; return true; }
        }
        return false;
    }
    // Режимы TAL: готовые наборы предпочтительного угла и предварительного упора колонок. Основа — значения из конфигурации.
    // ⚠ Наша трактовка, не копия NavDP: lowbias — без предупора; highbias — колонки с каждого борта предупором наружу (поперёк), попарно взаимно гасят друг друга;
    //   portahead/stbdahead — колонки названного борта предупором вперёд, другого борта — назад.
    void applyTal() {
        const auto& th = cfg_.thrusters;
        for (size_t i = 0; i < th.size(); ++i) {
            if (th[i].type != ThrusterType::Azimuth) continue;
            double pref = th[i].prefDeg, pct = th[i].preloadPct;
            const bool port = th[i].y < 0;
            if (talMode_ == "lowbias") { pref = 1e9; pct = 0; }
            else if (talMode_ == "highbias") { pct = 20; pref = port ? -90 : 90; }
            else if (talMode_ == "portahead" || talMode_ == "stbdahead") { pct = 20; pref = ((talMode_ == "portahead") == port) ? 0 : 180; }
            eng_.setThrusterPreload(i, pref, pct);
        }
    }
    void extraAlarms() {
        const DpMode m = eng_.mode();
        const bool act = m != DpMode::Standby && m != DpMode::Manual;
        // связь с внешней ДП: потеря данных и расхождение с нашим решением
        if (ext_) {
            extSt_ = ext_->status(monotonicSeconds(), out_.est.n, out_.est.e, rad2deg(out_.est.psi), frame());
            { bool need = false; for (auto& g : extSt_.sig) if (!g.cmp.empty()) need = true;
              if (need) {     // сверка с нашими величинами движителей: <id>.cmdPct|cmdAngle|pct|angle|powerKW
                  const auto tv = thrusters();
                  for (auto& g : extSt_.sig) {
                      const size_t dot = g.cmp.find('.'); if (dot == std::string::npos) continue;
                      const std::string id = g.cmp.substr(0, dot), k = g.cmp.substr(dot + 1);
                      for (auto& t : tv) if (t.id == id) {
                          g.haveOurs = true;
                          g.ours = k == "cmdPct" ? t.cmdPct : k == "cmdAngle" ? t.cmdAngleDeg : k == "pct" ? t.pct : k == "angle" ? t.angleDeg : k == "powerKW" ? t.powerKW : (g.haveOurs = false, 0.0);
                          if (g.haveOurs && g.has) g.delta = g.value - g.ours;
                      }
                  } } }
            const ExtLinkCfg& xc = ext_->cfg();
            if (extSt_.lines > 0 && !extSt_.linked) out_.alarms.push_back({"EXT_LOST", "Внешняя ДП: нет данных " + std::to_string(static_cast<int>(extSt_.ageS)) + " с", false});
            if (extSt_.linked && extSt_.havePos && extSt_.dPosM > xc.posAlarmM) { char b[160]; std::snprintf(b, sizeof b, "Внешняя ДП: положение расходится с нашим на %.1f м (порог %.0f м)", extSt_.dPosM, xc.posAlarmM); out_.alarms.push_back({"EXT_POS_DIFF", b, false}); }
            if (extSt_.linked && extSt_.haveHdg && std::fabs(extSt_.dHdgDeg) > xc.hdgAlarmDeg) { char b[160]; std::snprintf(b, sizeof b, "Внешняя ДП: курс расходится с нашим на %.1f° (порог %.0f°)", extSt_.dHdgDeg, xc.hdgAlarmDeg); out_.alarms.push_back({"EXT_HDG_DIFF", b, false}); }
        }
        // зона удержания
        if (eng_.controller().cfg().holdAreaM > 0 && m == DpMode::AutoPosition) {
            const Setpoint hsp = eng_.controller().crpFromHold(eng_.controller().setpoint());   // уставка точки управления: зона считается от неё, а не от плавно движущейся опорной точки
            const double R0 = eng_.controller().cfg().holdAreaM, d = std::hypot(out_.est.n - hsp.n, out_.est.e - hsp.e);
            if (d > R0) { char b[160]; std::snprintf(b, sizeof b, "Зона удержания: судно вышло за радиус %.0f м (отклонение %.1f м)", R0, d); out_.alarms.push_back({"HOLD_AREA_EXIT", b, true}); }
            else if (d > eng_.controller().cfg().holdWarnPct / 100.0 * R0) { char b[160]; std::snprintf(b, sizeof b, "Зона удержания: отклонение %.1f м — граница предупреждения (%.0f %% от %.0f м)", d, eng_.controller().cfg().holdWarnPct, R0); out_.alarms.push_back({"HOLD_AREA_WARN", b, false}); }
        }
        // автоснятие неисправного движителя (обратная связь расходится с командой): возврат — только вручную
        if (autoExcl_) {
            std::vector<std::string> bad;
            for (const auto& a : out_.alarms) if (a.code.rfind("THR_FB_MISMATCH_", 0) == 0) bad.push_back(a.code.substr(16));
            for (const auto& id : bad) for (size_t i = 0; i < cfg_.thrusters.size() && i < taken_.size(); ++i)
                if (cfg_.thrusters[i].id == id && taken_[i]) { out_.infos.push_back("Движитель " + id + " автоматически снят с управления ДП (обратная связь расходится); вернуть можно только вручную: thr_take " + id); takeThrusters(id, false); }
        }
        // таймер бдительности: считается только в режимах ДП; любая команда оператора сбрасывает его
        if (watchOn_ && act) { if (clock() - watchAt_ > watchPeriodS_) out_.alarms.push_back({"WATCH_TIMER", "Таймер бдительности: подтвердите присутствие оператора (watch reset или любое действие)", false}); }
        else watchAt_ = clock();
        // потеря посылки: тип предложения из списка приёма приходил, но замолчал
        for (const auto& st : hub_.staleSentences(hubNow(), sentTimeoutS_)) {
            char b[160]; std::snprintf(b, sizeof b, "Датчик %s: нет посылки %s дольше %.0f с", st.first.c_str(), st.second.c_str(), sentTimeoutS_);
            out_.alarms.push_back({"SENT_LOST_" + st.first + "_" + st.second, b, false});
        }
        // слабая тяга по курсу: курс отклонён больше чем на 5° дольше 15 с, а распределитель работает на пределе (усилие не достигает запроса или загрузка выше 95 %)
        const bool yawAct = m == DpMode::AutoPosition || m == DpMode::AutoHeading;
        if (yawAct && std::fabs(out_.ctl.errHdgDeg) > 5.0 && (out_.alloc.saturated || out_.alloc.utilization > 0.95)) yawLowS_ += dt_; else yawLowS_ = 0;
        if (yawLowS_ >= 15.0) out_.alarms.push_back({"HDG_THRUST_LOW", "Слабая тяга по курсу: курс отклонён более чем на 5°, а движители работают на пределе", false});
        // смена курса ждёт подтверждения
        if (hdgPend_) {
            if (!yawAct) hdgPend_ = false;
            else if (clock() - hdgPendAt_ > 60.0) { hdgPend_ = false; out_.infos.push_back("Смена курса не подтверждена за 60 с и отменена"); }
            else { char b[140]; std::snprintf(b, sizeof b, "Подтвердите смену курса на %.1f° (hdg accept) или отмените (hdg cancel)", hdgPendVal_); out_.alarms.push_back({"HDG_CONFIRM", b, false}); }
        }
        // сброс точки вращения через 5 с после выхода из режима ДП
        const bool dpOn = m == DpMode::AutoPosition || m == DpMode::AutoHeading || m == DpMode::Joystick || m == DpMode::FollowTarget;
        if (wasDpOn_ && !dpOn) pivotResetAt_ = clock();
        if (dpOn) pivotResetAt_ = -1;
        wasDpOn_ = dpOn;
        if (pivotResetOn_ && pivotResetAt_ >= 0 && clock() - pivotResetAt_ >= 5.0) {
            pivotResetAt_ = -1;
            if (std::fabs(eng_.controller().pivotX()) > 1e-9 || std::fabs(eng_.controller().pivotY()) > 1e-9) { command("pivot 0 0"); out_.infos.push_back("Точка вращения сброшена в центр управления (режим ДП выключен)"); }
        }
    }
    // Анализ последствий отказа (K-Pos, глава 18): включён при классе 2/3 в режиме авто-позиции и после выхода на уставку; раз в минуту.
    // Потребность — сглаженное усилие регулятора (≈ внешняя сила, которую нужно компенсировать).
    void conseqStep() {
        const double dt = dt_;
        const Wrench& tau = out_.ctl.tau;
        const double a = dt / (30.0 + dt);
        tauAvg_.X += a * (tau.X - tauAvg_.X); tauAvg_.Y += a * (tau.Y - tauAvg_.Y); tauAvg_.N += a * (tau.N - tauAvg_.N);
        const bool act = eng_.mode() == DpMode::AutoPosition && dpClass_ >= 2;
        if (!act) {
            if (cqRunning_) { cqRunning_ = false; cq_ = ConseqResult{}; out_.infos.push_back("Анализ последствий отказа остановлен"); }
            return;
        }
        if (!cqRunning_) { cqRunning_ = true; cqAt_ = -1e9; tauAvg_ = tau; out_.infos.push_back("Анализ последствий отказа запущен, класс " + std::to_string(dpClass_)); }
        const Setpoint sp = eng_.controller().crpFromHold(eng_.controller().setpoint());   // уставка точки управления
        const bool present = std::hypot(out_.ctl.refN - sp.n, out_.ctl.refE - sp.e) < 1.0 && std::fabs(wrapDeg(out_.ctl.refPsiDeg - sp.psiDeg)) < 2.0;
        if (!present) return;                                  // при смене положения или курса расчёт приостанавливается, прежний результат сохраняется
        if (clock() - cqAt_ >= cqIntervalS_) { cqAt_ = clock(); cq_ = plant_.consequences(cfg_.thrusters, tauAvg_); }
        for (const auto& f : cq_.fails) {
            char b[200];
            if (f.ratio >= 10) std::snprintf(b, sizeof b, "Анализ последствий: потеря %s — %s, удержание невозможно", f.what.c_str(), f.power ? "мощности не остаётся" : "упора не остаётся");
            else std::snprintf(b, sizeof b, "Анализ последствий: потеря %s — %s (нужно %.0f %% возможностей)", f.what.c_str(), f.power ? "мощности недостаточно" : "упора недостаточно", 100.0 * f.ratio);
            out_.alarms.push_back({f.power ? "CQ_POWER" : "CQ_THRUST", b, false, PrioWarning});
        }
    }
    static double wrapDeg(double d) { d = std::fmod(d + 180.0, 360.0); if (d < 0) d += 360.0; return d - 180.0; }
    void say(const std::string& s) const { if (say_) say_(s); }

    AppCfg cfg_;
    std::string snFile_;                       // файл настроек посылок датчиков
    std::string fcFile_; double fcSaveT_ = 0;   // файл таблицы прогнозирования и время последнего сохранения
    ControlCfg baseCtl_ = cfg_.control; double holdR_ = 0;   // базовые настройки закона (до подстройки под радиус) и радиус удержания
    Say say_;
    double dt_;
    DpEngine eng_;
    SensorHub hub_;
    std::vector<std::unique_ptr<Channel>> chans_;
    std::vector<std::unique_ptr<OutputLink>> links_;
    std::unique_ptr<Simulator> sim_;
    LocalFrame lf_;
    EngineOutput out_;
    std::vector<char> taken_;                  // движители, взятые оператором под управление ДП (по порядку cfg_.thrusters)
    bool dpActive_ = false; bool busDeadLast_[2] = {false, false};
    AlarmMgr alarms_{5.0};
    int dpClass_ = 0; bool cqRunning_ = false; ConseqResult cq_; double cqAt_ = -1e9, cqIntervalS_ = 60.0; Wrench tauAvg_{};
    Plant plant_; PlantState plantSt_; WorstCaseResult wc_; double wcAt_ = -10;
    // добавочные тревоги: бдительность оператора, потеря посылок, слабая тяга по курсу, подтверждение смены курса; сброс точки вращения
    bool watchOn_ = false; double watchPeriodS_ = 600, watchAt_ = 0;
    double sentTimeoutS_ = 10;
    double hdgConfirmDeg_ = 0; bool hdgPend_ = false; double hdgPendVal_ = 0, hdgPendAt_ = -1e9;
    double yawLowS_ = 0;
    std::unique_ptr<ExtLink> ext_; ExtStatus extSt_; std::string extFile_;
    src::LineTest srcTest_; std::string srcList_; bool srcWatch_ = false;
    cap::Capture cap_; bool capDetail_ = false; std::string capBase_, capFile_;
    void saveCapCfg(const cap::CapCfg& c) { if (capFile_.empty()) return; std::ofstream f(capFile_, std::ios::binary | std::ios::trunc); if (f) f << cap::capCfgToJson(c); else say("Предупреждение: каналы записи не сохранены в " + capFile_); }
    OperatorLimits lim_; std::string limFile_;
    std::map<std::string, double> fbOverride_;   // ложная обратная связь движителей (имитация)
    std::string talMode_ = "normal"; bool autoExcl_ = false;
    bool pivotResetOn_ = true; double pivotResetAt_ = -1; bool wasDpOn_ = false;
    std::ofstream log_;
    double t_ = 0, warmup_ = 0, modeSince_ = -1, n_ = 0, sum2_ = 0, max_ = 0, h2_ = 0, hmax_ = 0;
    bool startPending_ = true, quit_ = false, statusRequested_ = false, opSpSet_ = false;
    Setpoint opSp_;
    long long cycles_ = 0;
};

}  // namespace dp
