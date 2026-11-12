// Электростанция (PMS): располагаемая мощность, резерв, отказы генераторов и шин, наихудший отказ, сетевой снимок.
#include <cstdio>
#include "dp/opnet.hpp"
#include "dp/runtime.hpp"

using namespace dp;
static int fails = 0;
#define CHECK(c, msg) do { const bool ok_ = (c); std::printf("%s %s\n", ok_ ? "  ok " : "FAIL ", msg); if (!ok_) ++fails; } while (0)

static bool hasAlarm(const EngineOutput& o, const char* code) { for (auto& a : o.alarms) if (a.code == code) return true; return false; }

static void parkTest(const AppCfg& cfg) {
    {
        AppCfg c2 = cfg; c2.startMode = "standby"; c2.logFile.clear();
        Runtime r2(c2, [](const std::string&) {});
        while (r2.clock() < 25) r2.cycle();
        double aP = -1, aS = -1; auto& st = r2.sim()->thrusters();
        for (size_t i = 0; i < c2.thrusters.size(); ++i) { if (c2.thrusters[i].id == "VRK_P") aP = st[i].angleDeg(); if (c2.thrusters[i].id == "VRK_S") aS = st[i].angleDeg(); }
        aP = std::fmod(aP + 720.0, 360.0); aS = std::fmod(aS + 720.0, 360.0);
        CHECK(std::fabs(aP - 90) < 1.0 && std::fabs(aS - 270) < 1.0, "в ожидании колонки стоят струёй наружу: левая 90°, правая 270° (по силе на судно; по струе — 270° и 90°)");
        r2.command("sim wind 12 60"); r2.command("thr_take all"); r2.command("position");
        int inP = 0, inS = 0, nS = 0;                      // углы колонок не задерживаются в запретных секторах (проход допустим)
        for (int i = 0; i < 1500; ++i) {
            r2.cycle();
            for (size_t k = 0; k < c2.thrusters.size(); ++k) {
                if (c2.thrusters[k].id == "VRK_P") { double a = std::fmod(st[k].angleDeg() + 720.0, 360.0); if (a > 241 && a < 299) ++inP; }
                if (c2.thrusters[k].id == "VRK_S") { double a = std::fmod(st[k].angleDeg() + 720.0, 360.0); if (a > 61 && a < 119) ++inS; }
            }
            ++nS;
        }
        CHECK(inP < 0.02 * nS && inS < 0.02 * nS, "струя левой колонки не стоит в секторе 60–120°, правой — в 240–300° (проход допустим, не более 2 % времени)");
        CHECK(r2.out().est.posValid && r2.stats().maxPos < 5.0, "с такими секторами судно держит позицию (ветер 12 м/с)");
    }
}

int main(int argc, char** argv) {
    const std::string cfgPath = argc > 1 ? argv[1] : "config/navis90_pms.json";
    AppCfg cfg; json::Report rep;
    if (!loadConfig(cfgPath, cfg, rep)) { std::printf("не удалось прочитать %s\n", cfgPath.c_str()); return 2; }
    CHECK(cfg.plant.enabled && cfg.plant.gens.size() == 4, "электростанция читается из настроек (4 генератора)");
    if (argc > 2 && std::string(argv[2]) == "park") { parkTest(cfg); std::printf(fails ? "ПРОВАЛ: %d\n" : "Все проверки пройдены\n", fails); return fails ? 1 : 0; }

    // 1. расчёт модели
    Plant pl(cfg.plant);
    std::vector<double> frac(cfg.thrusters.size(), 0.5);
    PlantState s = pl.compute(cfg.thrusters, frac);
    CHECK(std::fabs(s.availableKW - 11200) < 1e-6, "располагаемая мощность = сумма генераторов (11 200 кВт)");
    const double expLoad = 600 + (1500 * 2 + 3500 * 2) * std::pow(0.5, 1.5);
    CHECK(std::fabs(s.loadKW - expLoad) < 1.0, "нагрузка = служебные + движители по P ~ T^1,5");
    CHECK(std::fabs(s.reserveKW - (s.availableKW - s.loadKW)) < 1e-6 && s.reservePct > 0, "резерв считается");
    pl.setGen("DG1", false);
    CHECK(std::fabs(pl.compute(cfg.thrusters, frac).availableKW - 8400) < 1e-6, "генератор DG1 отключён — мощность 8 400 кВт");
    pl.reset(); pl.setBus(0, true);
    s = pl.compute(cfg.thrusters, frac);
    CHECK(std::fabs(s.availableKW - 5600) < 1e-6 && pl.thrusterLost(cfg.thrusters[0]) && !pl.thrusterLost(cfg.thrusters[1]), "отказ шины A: остаётся 5 600 кВт, движители шины A потеряны");
    CHECK(s.engineAvailKW > 0, "для ядра выдаётся доступная мощность");

    // 2. наихудший отказ
    pl.reset();
    auto w0 = pl.worstCase(cfg.thrusters, {20000, 0, 0});
    CHECK(w0.ok, "малая потребность: после любого отказа удержание возможно");
    auto w1 = pl.worstCase(cfg.thrusters, {1.0e6, 1.0e6, 1.0e7});
    CHECK(!w1.ok && w1.ratio > 1 && !w1.what.empty(), "огромная потребность: наихудший отказ не проходит");
    pl.setGen("DG1", false); pl.setGen("DG2", false);
    auto w2 = pl.worstCase(cfg.thrusters, {300000, 100000, 3.0e6});
    pl.reset();
    auto w3 = pl.worstCase(cfg.thrusters, {300000, 100000, 3.0e6});
    CHECK(w2.ratio >= w3.ratio, "при уже отключённых генераторах запас по отказу не больше");

    // 3. ядро в имитации
    cfg.simSpeed = 1; cfg.logFile.clear();
    Runtime rt(cfg, [](const std::string&) {});
    rt.command("sim wind 12 60"); rt.command("sim wave 1 7 60");
    while (rt.clock() < 20) rt.cycle();
    rt.command("thr_take all"); rt.command("position");
    while (rt.clock() < 200) rt.cycle();
    CHECK(rt.plantState().availableKW > 11000, "в работе: располагаемая мощность 11 200 кВт");
    CHECK(rt.plantState().reservePct > 15 && !hasAlarm(rt.out(), "LOW_RESERVE"), "при слабой нагрузке резерв достаточный, тревоги нет");
    rt.command("plant gen off DG1"); rt.command("plant gen off DG2"); rt.command("plant gen off DG3");
    for (int i = 0; i < 100; ++i) rt.cycle();
    CHECK(std::fabs(rt.plantState().availableKW - 2800) < 1e-6, "команда plant gen off работает");
    CHECK(rt.plantState().reservePct < 15 ? hasAlarm(rt.out(), "LOW_RESERVE") : !hasAlarm(rt.out(), "LOW_RESERVE"), "тревога низкого резерва согласована с порогом");
    rt.command("plant gen off DG4");
    for (int i = 0; i < 50; ++i) rt.cycle();
    CHECK(hasAlarm(rt.out(), "BLACKOUT"), "потеря всех генераторов: тревога потери электропитания");
    rt.command("plant reset"); rt.command("plant gen off DG1"); rt.command("plant gen off DG2"); rt.command("plant gen off DG3");
    rt.command("sim wind 30 60");
    for (int i = 0; i < 600; ++i) rt.cycle();
    CHECK(hasAlarm(rt.out(), "POWER_LIMIT") && hasAlarm(rt.out(), "WORST_CASE"), "один генератор при сильном ветре: ограничение по мощности и тревога наихудшего отказа");
    rt.command("sim wind 12 60");
    rt.command("plant reset");
    for (int i = 0; i < 100; ++i) rt.cycle();
    CHECK(std::fabs(rt.plantState().availableKW - 11200) < 1e-6, "plant reset возвращает генераторы");
    CHECK(!rt.plantState().tieClosed && !rt.plant().tieClosed(), "в режиме ДП секционный выключатель разомкнут автоматически");
    {   // нагрузка делится по шинам: у каждой шины свои движители, при симметричной схеме нагрузки близки
        const PlantState& ps = rt.plantState();
        CHECK(std::fabs(ps.busLoadKW[0] - ps.busLoadKW[1]) < 0.35 * (ps.busLoadKW[0] + ps.busLoadKW[1]) + 1.0, "в режиме ДП нагрузка шин A и B близка (делится пополам)");
        CHECK(std::fabs(ps.busAvailKW[0] - ps.busAvailKW[1]) < 1e-6, "мощности шин равны");
    }
    rt.command("plant gen off DG1"); rt.command("plant gen off DG2");
    for (int i = 0; i < 50; ++i) rt.cycle();
    { bool l = false; for (auto& id : rt.sim()->failedThrusters()) l = l || id == "NPU1" || id == "VRK_P"; (void)l;
      bool lostA = false; for (auto& id : rt.sim()->failedThrusters()) lostA = lostA || id == cfg.thrusters[0].id || id == cfg.thrusters[2].id;
      CHECK(lostA, "шина A без генераторов при разомкнутом секционном обесточена, её движители потеряны"); }
    rt.command("plant reset");
    for (int i = 0; i < 50; ++i) rt.cycle();
    rt.command("plant bus off A");
    for (int i = 0; i < 50; ++i) rt.cycle();
    bool lost = false; if (rt.sim()) for (auto& id : rt.sim()->failedThrusters()) lost = lost || id == cfg.thrusters[0].id || id == cfg.thrusters[2].id;
    CHECK(lost, "отказ шины A выводит из строя её движители в имитаторе");
    rt.command("plant reset");

    // 4. сетевой снимок
    OpSnap sn; {
        sn.plantOn = true; sn.plAvail = 8400; sn.plLoad = 3100; sn.plRes = 5300; sn.plResPct = 63; sn.plWc = "генератора DG1"; sn.plWcOk = false; sn.plWcRatio = 1.3; sn.plTie = false;
        sn.plBusFail[1] = true; sn.plBusAvail[0] = 5600; sn.plBusLoad[0] = 2000; sn.plGens.push_back({"DG1", 2800, 55, true, 0}); sn.plGens.push_back({"DG2", 2800, 0, false, 1});
    }
    json::Value v; std::string err;
    CHECK(json::parse(encodeSnap(sn), v, err), "снимок с электростанцией — корректный JSON");
    OpSnap d = decodeSnap(v);
    CHECK(d.plantOn && d.plGens.size() == 2 && d.plGens[0].id == "DG1" && !d.plGens[1].online && d.plBusFail[1] && !d.plTie && !d.plWcOk && d.plWc == "генератора DG1" && std::fabs(d.plAvail - 8400) < 1e-6, "снимок передаёт электростанцию без потерь");
    std::printf(fails ? "ПРОВАЛ: %d\n" : "Все проверки пройдены\n", fails);
    return fails ? 1 : 0;
}
