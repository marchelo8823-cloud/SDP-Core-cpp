// Загрузка настроек программы из JSON: судно, движители, регуляторы, входы датчиков, линии вывода, имитатор.
#pragma once
#include <fstream>
#include <sstream>

#include "dp/hub.hpp"
#include "dp/json.hpp"
#include "dp/output.hpp"
#include "dp/rights.hpp"
#include "dp/sim.hpp"
#include "dp/vesselio.hpp"

namespace dp {

struct InputCfg {
    ChannelCfg ch;
    std::string transport = "udp";     // udp | tcp | serial
    std::string host = "127.0.0.1", bind = "0.0.0.0", device;
    int port = 0, baud = 4800;
};

// Связь с работающей системой ДП другого изготовителя (Praxis, Kongsberg…): по умолчанию только приём и сравнение, команды не отправляются.
struct ExtField { std::string name, prefix; int index = 0; double scale = 1.0;
                  std::string group = "other", unit, ch, cmp; };   // group: feedback (обратная связь движителей) | command (команды на движители) | power (энергосистема) | alarm (тревоги и состояния) | other; ch — только из этого входа (пусто — из любого); cmp — наша величина для сверки: <движитель>.cmdPct|cmdAngle|pct|angle|powerKW   // поле собственной посылки: строка начинается с prefix, index — номер поля через запятую (0 — сам заголовок)
struct ExtLimit { std::string var; double lo = -1e18, hi = 1e18; };
struct ExtTemplate { std::string name, text; double minIntervalS = 0.5; std::vector<ExtLimit> limits; };   // limits — допустимые значения подстановок {var}; minIntervalS — не чаще одной отправки за это время                                      // шаблон исходящей строки; подстановки {n} {e} {psi} (уставка), {x}, {y}, {v}
struct ExtLinkCfg {
    bool enabled = false;
    std::string vendor = "generic";          // praxis | kongsberg | generic — пометка для оператора; разбор задают inputs и fields
    std::vector<InputCfg> inputs;            // входы NMEA от чужой системы (положение, курс), как inputs
    std::vector<ExtField> fields;            // дополнительные поля из собственных посылок (уставка, режим, нагрузки…)
    std::string txTransport = "udp", txHost = "127.0.0.1"; int txPort = 0;   // куда уходят команды в активном режиме
    std::vector<ExtTemplate> templates;
    double posAlarmM = 10.0, hdgAlarmDeg = 3.0, lostS = 10.0;   // пороги расхождения и потери данных
};

struct AppCfg {
    VesselCfg vessel;
    std::vector<ThrusterCfg> thrusters;
    ControlCfg control;
    EstimatorCfg est;
    // имитатор
    bool simEnabled = true;
    double simSpeed = 1.0;
    EnvCfg env;
    SimSensorsCfg simSensors;
    PlantCfg plant;                    // электростанция (необязательна)
    unsigned seed = 11;
    double initialHeadingDeg = 0;
    // входы и выходы
    std::vector<InputCfg> inputs;
    std::vector<LinkCfg> links;
    bool originSet = false; double originLat = 0, originLon = 0;
    struct PivotPreset { std::string name; double x = 0, y = 0; };
    struct Limits { bool on = false; double move = 0, setdist = 0, hdg = 0; std::vector<std::string> forbid; } limits;   // ограничения оператора (начальные; меняются командой limits)
    ExtLinkCfg extlink;
    std::vector<PivotPreset> pivotPresets;   // именованные точки вращения (кран, рубка…), в связанных осях: вдоль (+ нос), поперёк (+ правый борт)
    std::vector<std::pair<std::string, std::string>> postRights;   // права постов: имя поста → список прав (control, ack, setup или view); не перечисленные посты имеют все права
    // программа
    double cycleHz = 10;
    double statusPeriodS = 5;
    std::string logFile;
    std::string startMode = "standby";
    int dpClass = 0;                 // класс ДП для анализа последствий отказа: 0 — выключен, 2 или 3 (как в K-Pos)
    TrackCfg track;
    Setpoint startSetpoint; bool startSetpointGiven = false;
};

inline DpMode parseMode(const std::string& s, bool& ok) {
    ok = true;
    if (s == "standby") return DpMode::Standby;
    if (s == "manual") return DpMode::Manual;
    if (s == "joystick") return DpMode::Joystick;
    if (s == "heading") return DpMode::AutoHeading;
    if (s == "position") return DpMode::AutoPosition;
    if (s == "track") return DpMode::Track;
    if (s == "follow") return DpMode::FollowTarget;
    if (s == "autopilot") return DpMode::Autopilot;
    ok = false; return DpMode::Standby;
}
inline const char* modeName(DpMode m) {
    switch (m) {
        case DpMode::Standby: return "ожидание"; case DpMode::Manual: return "ручной"; case DpMode::Joystick: return "джойстик";
        case DpMode::AutoHeading: return "удержание курса"; case DpMode::AutoPosition: return "удержание позиции"; case DpMode::Track: return "движение по треку";
        case DpMode::FollowTarget: return "движение за целью"; case DpMode::Autopilot: return "автопилот";
    }
    return "?";
}

inline void readInput(json::Obj& o, std::vector<InputCfg>& dst) {
        InputCfg in; ChannelCfg& c = in.ch;
        c.id = o.str("id", "");
        const std::string k = o.str("kind", "gnss");
        if (k == "gnss") c.kind = ChannelKind::Gnss; else if (k == "laser") c.kind = ChannelKind::LaserRadar; else if (k == "wire") c.kind = ChannelKind::TautWire;
        else if (k == "gyro") c.kind = ChannelKind::Gyro; else if (k == "wind") c.kind = ChannelKind::Wind; else if (k == "mru") c.kind = ChannelKind::Mru;
        else o.error("вид датчика «" + k + "» неизвестен (gnss, laser, wire, gyro, wind, mru)");
        c.sigma = o.num("sigma", c.sigma);
        auto off = o.nums("offset"); if (off.size() == 3) c.offset = V3{off[0], off[1], off[2]}; else if (!off.empty()) o.error("offset задаётся тремя числами [x, y, z]");
        c.minGnssQuality = o.integer("minGnssQuality", 1); c.maxHdop = o.num("maxHdop", 10.0); c.requireChecksum = o.boolean("requireChecksum", true);
        c.rollSign = o.num("rollSign", 1); c.pitchSign = o.num("pitchSign", 1); c.heaveSign = o.num("heaveSign", 1);
        auto t = o.obj("transport");
        in.transport = t.str("type", "udp"); in.host = t.str("host", "127.0.0.1"); in.bind = t.str("bind", "0.0.0.0");
        in.device = t.str("device", ""); in.port = t.integer("port", 0); in.baud = t.integer("baud", 4800);
        if (in.transport != "udp" && in.transport != "tcp" && in.transport != "serial") t.error("транспорт «" + in.transport + "» неизвестен (udp, tcp, serial)");
        if (in.transport == "serial" && in.device.empty()) t.error("не задан device (например COM3 или /dev/cu.usbserial-XXXX)");
        if (in.transport != "serial" && in.port <= 0) t.error("не задан port");
        t.finish();
        if (c.id.empty()) o.error("не задан id датчика");
        o.finish();
        dst.push_back(in);
    }

inline void readExtLink(json::Obj& o, ExtLinkCfg& xo) {
    ExtLinkCfg& x = xo; x = ExtLinkCfg(); x.enabled = o.boolean("enabled", true);
        x.vendor = o.str("vendor", "generic"); x.posAlarmM = o.num("posAlarmM", 10); x.hdgAlarmDeg = o.num("hdgAlarmDeg", 3); x.lostS = o.num("lostS", 10);
        for (auto i : o.objs("inputs")) readInput(i, x.inputs);
        for (auto f : o.objs("fields")) { ExtField ef; ef.name = f.str("name", ""); ef.prefix = f.str("prefix", ""); ef.index = f.integer("index", 1); ef.scale = f.num("scale", 1.0);
            ef.group = f.str("group", "other"); ef.unit = f.str("unit", ""); ef.ch = f.str("ch", ""); ef.cmp = f.str("cmp", "");
            if (ef.group != "feedback" && ef.group != "command" && ef.group != "power" && ef.group != "alarm" && ef.group != "other") f.error("группа сигнала «" + ef.group + "» неизвестна (feedback, command, power, alarm, other)");
            if (ef.name.empty() || ef.prefix.empty()) f.error("поле extlink.fields: нужны name и prefix");
            f.finish(); x.fields.push_back(ef); }
        for (auto tpl : o.objs("templates")) { ExtTemplate et; et.name = tpl.str("name", ""); et.text = tpl.str("text", ""); et.minIntervalS = tpl.num("minIntervalS", 0.5); for (auto l : tpl.objs("limits")) { ExtLimit el; el.var = l.str("name", ""); el.lo = l.num("min", -1e18); el.hi = l.num("max", 1e18); if (el.var.empty()) l.error("предел: нужен name"); l.finish(); et.limits.push_back(el); } if (et.name.empty() || et.text.empty()) tpl.error("шаблон: нужны name и text"); tpl.finish(); x.templates.push_back(et); }
        { auto t = o.obj("tx"); x.txTransport = t.str("type", "udp"); x.txHost = t.str("host", "127.0.0.1"); x.txPort = t.integer("port", 0); if (x.txTransport != "udp" && x.txTransport != "tcp") t.error("tx: udp или tcp"); t.finish(); }
        o.finish();
}

// Настройки связи с внешней ДП из текста JSON (команда «ext setup», файл extlink.json в папке данных).
inline bool parseExtLink(const std::string& text, ExtLinkCfg& out, std::string& err) {
    json::Value root; std::string perr;
    if (!json::parse(text, root, perr)) { err = "ошибка в тексте настроек связи, " + perr; return false; }
    json::Report rep; json::Obj o(&root, "extlink", &rep);
    ExtLinkCfg c; readExtLink(o, c);
    if (!rep.errors.empty()) { err = rep.errors.front(); return false; }
    for (auto& in : c.inputs) for (auto& in2 : c.inputs) if (&in != &in2 && in.ch.id == in2.ch.id) { err = "повторяется id входа «" + in.ch.id + "»"; return false; }
    if (c.posAlarmM <= 0 || c.hdgAlarmDeg <= 0 || c.lostS <= 0) { err = "пороги расхождения и потери данных должны быть больше нуля"; return false; }
    out = c; return true;
}
inline std::string extLinkToJson(const ExtLinkCfg& c) {
    auto q = [](const std::string& x) { std::string r = "\""; for (char ch : x) { if (ch == '"' || ch == '\\') r += '\\'; r += ch; } return r + "\""; };
    auto n = [](double v) { char b[40]; std::snprintf(b, sizeof b, "%.6g", v); return std::string(b); };
    std::string j = "{\"enabled\":" + std::string(c.enabled ? "true" : "false") + ",\"vendor\":" + q(c.vendor) + ",\"posAlarmM\":" + n(c.posAlarmM) + ",\"hdgAlarmDeg\":" + n(c.hdgAlarmDeg) + ",\"lostS\":" + n(c.lostS) + ",\"inputs\":[";
    for (size_t i = 0; i < c.inputs.size(); ++i) {
        const InputCfg& in = c.inputs[i]; const char* k = in.ch.kind == ChannelKind::Gyro ? "gyro" : in.ch.kind == ChannelKind::LaserRadar ? "laser" : "gnss";
        j += std::string(i ? "," : "") + "{\"id\":" + q(in.ch.id) + ",\"kind\":\"" + k + "\",\"sigma\":" + n(in.ch.sigma) + ",\"transport\":{\"type\":" + q(in.transport) + ",\"port\":" + std::to_string(in.port)
            + ",\"host\":" + q(in.host) + ",\"bind\":" + q(in.bind) + ",\"device\":" + q(in.device) + ",\"baud\":" + std::to_string(in.baud) + "}}";
    }
    j += "],\"fields\":[";
    for (size_t i = 0; i < c.fields.size(); ++i) j += std::string(i ? "," : "") + "{\"name\":" + q(c.fields[i].name) + ",\"prefix\":" + q(c.fields[i].prefix) + ",\"index\":" + std::to_string(c.fields[i].index) + ",\"scale\":" + n(c.fields[i].scale) + ",\"group\":" + q(c.fields[i].group) + ",\"unit\":" + q(c.fields[i].unit) + ",\"ch\":" + q(c.fields[i].ch) + ",\"cmp\":" + q(c.fields[i].cmp) + "}";
    j += "],\"templates\":[";
    for (size_t i = 0; i < c.templates.size(); ++i) j += std::string(i ? "," : "") + "{\"name\":" + q(c.templates[i].name) + ",\"text\":" + q(c.templates[i].text) + ",\"minIntervalS\":" + n(c.templates[i].minIntervalS) + ",\"limits\":[" + [&] { std::string r; for (size_t k = 0; k < c.templates[i].limits.size(); ++k) r += std::string(k ? "," : "") + "{\"name\":" + q(c.templates[i].limits[k].var) + ",\"min\":" + n(c.templates[i].limits[k].lo) + ",\"max\":" + n(c.templates[i].limits[k].hi) + "}"; return r; }() + "]}";
    return j + "],\"tx\":{\"type\":" + q(c.txTransport) + ",\"host\":" + q(c.txHost) + ",\"port\":" + std::to_string(c.txPort) + "}}";
}

inline bool loadConfig(const std::string& path, AppCfg& cfg, json::Report& rep) {
    std::ifstream f(path, std::ios::binary);
    if (!f) { rep.errors.push_back("не удалось открыть файл настроек: " + path); return false; }
    std::stringstream ss; ss << f.rdbuf();
    json::Value root; std::string perr;
    if (!json::parse(ss.str(), root, perr)) { rep.errors.push_back("ошибка в файле настроек, " + perr); return false; }
    json::Obj R(&root, "настройки", &rep);

    // --- судно
    { auto o = R.obj("vessel"); readVessel(o, cfg.vessel); }
    // --- движители
    {
        for (auto o : R.objs("thrusters")) {
            ThrusterCfg t;
            readThruster(o, t);
            cfg.thrusters.push_back(t);
        }
        if (cfg.thrusters.empty()) rep.errors.push_back("не описан ни один движитель (thrusters)");
    }
    // --- электростанция (необязательна)
    { const json::Value* pv = root.find("plant");
      if (pv) {
        auto o = R.obj("plant"); PlantCfg& pc = cfg.plant; pc.enabled = true;
        pc.tieClosed = o.boolean("tieClosed", true); pc.tieOpenInDp = o.boolean("tieOpenInDp", true); pc.minReservePct = o.num("minReservePct", 15.0);
        pc.serviceKW[0] = o.num("serviceKW_A", 0); pc.serviceKW[1] = o.num("serviceKW_B", 0);
        for (auto g : o.objs("generators")) {
            GeneratorCfg gc; gc.id = g.str("id", ""); gc.ratedKW = g.num("ratedKW", 0); gc.online = g.boolean("online", true);
            const std::string bs = g.str("bus", "A");
            if (bs == "A") gc.bus = 0; else if (bs == "B") gc.bus = 1; else g.error("шина генератора — «A» или «B»");
            if (gc.id.empty()) g.error("не задан id генератора");
            if (!(gc.ratedKW > 0 && gc.ratedKW <= 1e5)) g.error("ratedKW генератора должен быть от 0 до 100 000 кВт");
            g.finish(); pc.gens.push_back(gc);
        }
        if (pc.gens.empty()) o.error("в plant не описан ни один генератор (generators)");
        if (!(pc.minReservePct >= 0 && pc.minReservePct <= 100)) o.error("minReservePct должен быть от 0 до 100");
        o.finish();
      } }
    // --- регуляторы
    { auto o = R.obj("control"); ControlCfg& c = cfg.control;
      const std::string law = o.str("law", "pid");
      if (law == "pid") c.law = LawType::Pid; else if (law == "lqr") c.law = LawType::Lqr; else if (law == "mpc") c.law = LawType::Mpc; else o.error("закон «" + law + "» неизвестен (pid, lqr, mpc)");
      c.wnPos = o.num("wnPos", c.wnPos); c.zetaPos = o.num("zetaPos", c.zetaPos); c.wnHdg = o.num("wnHdg", c.wnHdg); c.zetaHdg = o.num("zetaHdg", c.zetaHdg);
      c.posTolM = o.num("posTolM", c.posTolM); c.velTolMS = o.num("velTolMS", c.velTolMS); c.hdgTolDeg = o.num("hdgTolDeg", c.hdgTolDeg); c.rotTolDegS = o.num("rotTolDegS", c.rotTolDegS);
      c.effortFrac = o.num("effortFrac", c.effortFrac); c.mpcHorizon = o.integer("mpcHorizon", c.mpcHorizon); c.mpcStepS = o.num("mpcStepS", c.mpcStepS);
      c.mpcRateWeight = o.num("mpcRateWeight", c.mpcRateWeight); c.forceFilterS = o.num("forceFilterS", c.forceFilterS); c.biasLimitFrac = o.num("biasLimitFrac", c.biasLimitFrac); c.biasFilterS = o.num("biasFilterS", c.biasFilterS);
      c.windFeedForward = o.boolean("windFeedForward", c.windFeedForward); c.waveFeedForward = o.boolean("waveFeedForward", c.waveFeedForward); c.refMaxSpeed = o.num("refMaxSpeed", c.refMaxSpeed); c.refAccel = o.num("refAccel", c.refAccel);
      c.highGain = o.boolean("highGain", c.highGain); c.gainHighK = clampd(o.num("gainHighK", c.gainHighK), 1.0, 2.0);
      c.holdAreaM = std::max(0.0, o.num("holdAreaM", c.holdAreaM)); c.holdWarnPct = clampd(o.num("holdWarnPct", c.holdWarnPct), 10, 100); c.holdStopPct = clampd(o.num("holdStopPct", c.holdStopPct), 0, 90);
      c.minPower = o.boolean("minPower", c.minPower); c.minPosDeadM = std::max(0.0, o.num("minPosDeadM", c.minPosDeadM)); c.minHdgDeadDeg = std::max(0.0, o.num("minHdgDeadDeg", c.minHdgDeadDeg));
      c.posDeadM = std::max(0.0, o.num("posDeadM", c.posDeadM)); c.hdgDeadDeg = std::max(0.0, o.num("hdgDeadDeg", c.hdgDeadDeg));
      c.predict.enabled = o.boolean("predict", c.predict.enabled); c.predict.meanS = std::max(1.0, o.num("predictMeanS", c.predict.meanS));
      c.predict.trendS = std::max(1.0, o.num("predictTrendS", c.predict.trendS)); c.predict.horizonS = std::max(0.0, o.num("predictHorizonS", c.predict.horizonS));
      c.predict.trendLimitFrac = clampd(o.num("predictTrendLimit", c.predict.trendLimitFrac), 0.0, 1.0); c.predict.trendFloor = std::max(0.0, o.num("predictTrendFloor", c.predict.trendFloor));
      c.refMaxRotDegS = o.num("refMaxRotDegS", c.refMaxRotDegS); c.refRotAccelDegS2 = o.num("refRotAccelDegS2", c.refRotAccelDegS2);
      o.finish();
    }
    { auto o = R.obj("estimator"); EstimatorCfg& e = cfg.est;
      e.posTimeoutS = o.num("posTimeoutS", e.posTimeoutS); e.posDropoutS = std::max(e.posTimeoutS, o.num("posDropoutS", e.posDropoutS)); e.deadReckonMaxS = std::max(0.0, o.num("deadReckonMaxS", e.deadReckonMaxS)); e.hdgTimeoutS = o.num("hdgTimeoutS", e.hdgTimeoutS); e.windTimeoutS = o.num("windTimeoutS", e.windTimeoutS);
      e.gateSigma = o.num("gateSigma", e.gateSigma); e.resetAfterRejects = o.integer("resetAfterRejects", e.resetAfterRejects);
      e.gnssDisagreeM = o.num("gnssDisagreeM", e.gnssDisagreeM); e.gyroDisagreeDeg = o.num("gyroDisagreeDeg", e.gyroDisagreeDeg); e.windFilterS = o.num("windFilterS", e.windFilterS);
      { const std::string mm = o.str("medianTest", "off");
        if (mm == "off") e.medianMode = 0; else if (mm == "warn") e.medianMode = 1; else if (mm == "reject") e.medianMode = 2; else o.error("medianTest: off, warn или reject"); }
      e.medianFrac = clampd(o.num("medianFrac", e.medianFrac), 0.1, 1.0); e.medianHystFrac = clampd(o.num("medianHystFrac", e.medianHystFrac), 0.1, 1.0); e.medianHoldS = clampd(o.num("medianHoldS", e.medianHoldS), 0.0, 120.0); e.reducedGnssWeightRatio = clampd(o.num("reducedGnssWeightRatio", e.reducedGnssWeightRatio), 0.01, 1.0);
      { const std::string gw = o.str("gnssWeight", "normal"); if (gw == "normal") e.gnssWeight = 0; else if (gw == "reduced") e.gnssWeight = 1; else o.error("gnssWeight: normal или reduced"); }
      e.acceptSigmaNarrow = std::max(1.0, o.num("acceptSigmaNarrow", e.acceptSigmaNarrow)); e.acceptSigmaWide = std::max(e.gateSigma, o.num("acceptSigmaWide", e.acceptSigmaWide));
      e.freezeCount = static_cast<int>(std::max(0.0, o.num("freezeCount", e.freezeCount)));
      { const std::string vt = o.str("varianceTest", "off"); if (vt == "off") e.varTest = 0; else if (vt == "warn") e.varTest = 1; else o.error("varianceTest: off или warn"); }
      e.varFactor = clampd(o.num("varianceFactor", e.varFactor), 1.5, 20.0); e.varWindow = static_cast<int>(clampd(o.num("varianceWindow", e.varWindow), 10, 300)); e.varMinSamples = static_cast<int>(clampd(o.num("varianceMinSamples", e.varMinSamples), 5, 100));
      { const std::string wm = o.str("weightMode", "normal"); if (wm == "normal") e.weightMode = 0; else if (wm == "manual") e.weightMode = 1; else if (wm == "auto") e.weightMode = 2; else o.error("weightMode: normal, manual или auto"); }
      e.divergeM = std::max(0.0, o.num("divergeM", e.divergeM));
      e.softRateMS = std::max(0.0, o.num("softRateMS", e.softRateMS)); e.softStartM = std::max(0.0, o.num("softStartM", e.softStartM));
      for (auto r : o.objs("posRef")) {
        PosRefCfg pc; const std::string id = r.str("id", ""); if (id.empty()) r.error("в posRef не задан id системы");
        const std::string md = r.str("mode", "enable"), ac = r.str("accept", "normal");
        if (md == "enable") pc.mode = 0; else if (md == "monitor") pc.mode = 1; else if (md == "disable") pc.mode = 2; else if (md == "mobile") pc.mode = 3; else r.error("mode: enable, monitor, mobile или disable");
        pc.manualWeight = static_cast<int>(clampd(r.num("weight", pc.manualWeight), 1, 10));
        if (ac == "narrow") pc.accept = 0; else if (ac == "normal") pc.accept = 1; else if (ac == "wide") pc.accept = 2; else r.error("accept: narrow, normal или wide");
        pc.autoRef = r.boolean("autoRef", false);
        r.finish(); e.posRef[id] = pc;
      }
      e.mruTimeoutS = o.num("mruTimeoutS", e.mruTimeoutS); e.mruDisagreeDeg = o.num("mruDisagreeDeg", e.mruDisagreeDeg); e.mruDisagreeHeaveM = o.num("mruDisagreeHeaveM", e.mruDisagreeHeaveM);
      o.finish();
    }
    // --- имитатор
    { auto o = R.obj("sim");
      cfg.simEnabled = o.boolean("enabled", true); cfg.simSpeed = o.num("speed", 1.0); cfg.seed = static_cast<unsigned>(o.integer("seed", 11));
      cfg.initialHeadingDeg = o.num("initialHeadingDeg", 0);
      auto e = o.obj("environment");
      cfg.env.windSpeed = e.num("windSpeed", 0); cfg.env.windFromDeg = e.num("windFromDeg", 0);
      cfg.env.currentSpeed = e.num("currentSpeed", 0); cfg.env.currentToDeg = e.num("currentToDeg", 0);
      cfg.env.hs = e.num("hs", 0); cfg.env.tp = e.num("tp", 8); cfg.env.waveFromDeg = e.num("waveFromDeg", 0);
      cfg.env.turbulence = clampd(e.num("turbulence", 1.0), 0, 2);   // порывы, переменное течение, медленный дрейф; 0 — ровная среда
      e.finish();
      auto s = o.obj("sensors");
      cfg.simSensors.laser = s.boolean("laser", true); cfg.simSensors.wire = s.boolean("wire", true);
      cfg.simSensors.mrus = s.integer("mrus", 3); cfg.simSensors.gyros = s.integer("gyros", 3); cfg.simSensors.anemometers = s.integer("anemometers", 3);
      s.finish();
      o.finish();
      if (cfg.simSpeed <= 0) rep.errors.push_back("sim.speed должен быть больше нуля");
    }
    // --- входы
    for (auto o : R.objs("inputs")) readInput(o, cfg.inputs);
    if (root.find("extlink")) { auto o = R.obj("extlink"); readExtLink(o, cfg.extlink); }
    if (root.find("limits")) {
        auto o = R.obj("limits"); cfg.limits.on = o.boolean("on", true);
        cfg.limits.move = std::max(0.0, o.num("maxMoveM", 0)); cfg.limits.setdist = std::max(0.0, o.num("maxSetDistM", 0)); cfg.limits.hdg = std::max(0.0, o.num("maxHdgStepDeg", 0));
        { const std::string fm = o.str("forbidModes", ""); std::string t;
          for (size_t i = 0; i <= fm.size(); ++i) { if (i == fm.size() || fm[i] == ',' || fm[i] == ' ') { if (!t.empty()) cfg.limits.forbid.push_back(t); t.clear(); } else t += fm[i]; } }
        o.finish();
    }
    for (auto o : R.objs("pivotPresets")) {
        AppCfg::PivotPreset pp; pp.name = o.str("name", ""); pp.x = o.num("x", 0); pp.y = o.num("y", 0);
        if (pp.name.empty()) o.error("в pivotPresets не задано имя name");
        if (std::fabs(pp.x) > 300 || std::fabs(pp.y) > 100) o.error("pivotPresets: |x| ≤ 300, |y| ≤ 100 м");
        o.finish(); cfg.pivotPresets.push_back(pp);
    }
    for (auto o : R.objs("posts")) {   // права операторских постов
        const std::string st = o.str("station", ""), rt = o.str("rights", "control,ack,setup");
        if (st.empty()) o.error("не задано имя поста station");
        std::string why; if (!parsePostRights(rt, why)) o.error("rights: " + why);
        o.finish();
        cfg.postRights.push_back({st, rt});
    }
    { auto o = R.obj("origin");
      if (o.present()) { cfg.originSet = true; cfg.originLat = o.num("lat", 0); cfg.originLon = o.num("lon", 0); o.finish(); } }
    // --- выходы
    for (auto o : R.objs("outputs")) {
        LinkCfg l;
        l.id = o.str("id", "CTRL1");
        auto t = o.obj("transport");
        const std::string ty = t.str("type", "tcp");
        l.serial = ty == "serial";
        if (ty != "tcp" && ty != "serial") t.error("транспорт «" + ty + "» неизвестен (tcp, serial)");
        l.host = t.str("host", "127.0.0.1"); l.port = t.integer("port", 502);
        l.device = t.str("device", ""); l.baud = t.integer("baud", 9600);
        const std::string par = t.str("parity", "N"); l.parity = par.empty() ? 'N' : par[0]; l.stopBits = t.integer("stopBits", 1);
        t.finish();
        l.unitId = o.integer("unitId", 1); l.timeoutMs = o.integer("timeoutMs", 300); l.periodMs = o.num("periodMs", 100);
        l.staleTimeoutS = o.num("staleTimeoutS", 1.0); l.retryS = o.num("retryS", 2.0);
        l.heartbeatReg = o.integer("heartbeatReg", -1); l.modeReg = o.integer("modeReg", -1); l.healthReg = o.integer("healthReg", -1);
        for (auto e : o.objs("registers")) {
            RegEntry r; r.thrusterId = e.str("thruster", "");
            const std::string fld = e.str("field", "pct");
            if (fld == "pct") r.field = OutField::Pct; else if (fld == "angle") r.field = OutField::AngleDeg; else e.error("поле «" + fld + "» неизвестно (pct, angle)");
            r.address = e.integer("address", 0);
            const std::string units = e.str("units", "percent");
            if (units == "percent") r.unitPerPct = 1.0;
            else if (units == "kw") {
                double pm = 0; for (const auto& th : cfg.thrusters) if (th.id == r.thrusterId) pm = th.powerMaxKW;
                if (pm <= 0) e.error("для единиц kw у движителя должен быть задан powerMaxKW");
                r.unitPerPct = pm / 100.0;
            } else if (units == "custom") r.unitPerPct = e.num("unitPerPct", 1.0);
            else e.error("единицы «" + units + "» неизвестны (percent, kw, custom)");
            r.scale = e.num("scale", 1.0); r.offset = e.num("offset", 0.0); r.isSigned = e.boolean("signed", true);
            r.rawMin = static_cast<long>(e.num("rawMin", r.isSigned ? -32768 : 0)); r.rawMax = static_cast<long>(e.num("rawMax", r.isSigned ? 32767 : 65535));
            r.angle360 = e.boolean("angle360", true); r.safeValue = e.num("safe", 0.0);
            if (r.scale == 0) e.error("scale не может быть равен нулю");
            bool known = false; for (const auto& th : cfg.thrusters) known = known || th.id == r.thrusterId;
            if (!known) e.error("движитель «" + r.thrusterId + "» не описан в thrusters");
            e.finish();
            l.entries.push_back(r);
        }
        if (l.serial && l.device.empty()) o.error("для serial не задан device");
        if (l.entries.empty()) o.error("не заданы регистры (registers)");
        o.finish();
        cfg.links.push_back(l);
    }
    // --- программа
    { auto o = R.obj("app");
      cfg.cycleHz = o.num("cycleHz", 10); cfg.statusPeriodS = o.num("statusPeriodS", 5); cfg.logFile = o.str("logFile", "");
      cfg.startMode = o.str("startMode", "standby");
      cfg.dpClass = static_cast<int>(o.num("dpClass", 0)); if (cfg.dpClass != 0 && cfg.dpClass != 2 && cfg.dpClass != 3) o.error("dpClass: 0, 2 или 3");
      bool ok; parseMode(cfg.startMode, ok); if (!ok) o.error("режим запуска «" + cfg.startMode + "» неизвестен");
      auto sp = o.nums("setpoint"); if (sp.size() == 3) { cfg.startSetpoint = {sp[0], sp[1], sp[2]}; cfg.startSetpointGiven = true; } else if (!sp.empty()) o.error("setpoint — три числа [север, восток, курс]");
      if (o.has("track")) {
          auto t = o.obj("track");
          cfg.track.speed = t.num("speed", 1.0); cfg.track.headingAlongTrack = t.boolean("headingAlongTrack", false); cfg.track.acceptRadius = t.num("acceptRadius", 8.0);
          for (auto& p : t.numLists("waypoints")) { if (p.size() == 2) cfg.track.wp.push_back({p[0], p[1]}); else t.error("точка трека — пара [север, восток]"); }
          t.finish();
      }
      o.finish();
      if (cfg.cycleHz < 1 || cfg.cycleHz > 100) rep.errors.push_back("app.cycleHz должен быть от 1 до 100");
    }
    R.finish();
    return rep.errors.empty();
}

}  // namespace dp
