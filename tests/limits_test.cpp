// Предел курса (HDG_WARN/HDG_OUT) и расхождение команды с обратной связью движителя (THR_FB_MISMATCH_*)
#include <cstdio>
#include <cmath>
#include <set>
#include "dp/runtime.hpp"
using namespace dp;
static int fails = 0;
#define CHECK(c, m) do { if (!(c)) { std::printf("ОШИБКА: %s\n", m); ++fails; } } while (0)

static std::set<std::string> runHdg(const AppCfg& cfg, double limit, double turn, double dur) {
    Runtime rt(cfg, [](const std::string&) {});
    rt.command("thr_take all");
    if (limit > 0) rt.command("hdglimit " + std::to_string(limit));
    std::set<std::string> codes; bool turned = false;
    while (rt.clock() < dur) {
        if (rt.clock() > 200 && !turned) { rt.command("heading"); turned = true; rt.command("hdg " + std::to_string(rt.out().ctl.refPsiDeg + turn)); }
        rt.cycle();
        if (turned) for (auto& a : rt.out().alarms) codes.insert(a.code);
    }
    return codes;
}

int main(int argc, char** argv) {
    AppCfg cfg; json::Report rep; if (!loadConfig(argc > 1 ? argv[1] : "config/salvage73_pms.json", cfg, rep)) return 2;
    // 1. предел курса: большая смена курса при малом пределе даёт предупреждение и аларм, без предела — ничего
    const auto tight = runHdg(cfg, 3.0, 30.0, 500), none = runHdg(cfg, 0, 30.0, 500), wide = runHdg(cfg, 45.0, 30.0, 500);
    std::printf("предел 3°: HDG_WARN=%d HDG_OUT=%d; без предела: %d; предел 45°: %d\n", (int)tight.count("HDG_WARN"), (int)tight.count("HDG_OUT"), (int)(none.count("HDG_WARN") + none.count("HDG_OUT")), (int)(wide.count("HDG_WARN") + wide.count("HDG_OUT")));
    CHECK(tight.count("HDG_OUT") == 1, "малый предел при смене курса на 30° даёт аларм HDG_OUT");
    CHECK(none.count("HDG_WARN") + none.count("HDG_OUT") == 0, "без предела тревог курса нет");
    CHECK(wide.count("HDG_OUT") == 0, "предел 45° не нарушен");
    // 2. обратная связь: расхождение больше 25 % держится 30 с — тревога; раньше 30 с и при совпадении — нет
    DpEngine eng(cfg.vessel, cfg.thrusters, cfg.control);
    eng.setMode(DpMode::Manual);
    SensorFrame fr; ThrusterFb f; f.id = cfg.thrusters[0].id; f.valid = true; f.pct = 40; f.angleDeg = 0; fr.fb.push_back(f);
    bool early = false, late = false; double t = 0; const std::string code = "THR_FB_MISMATCH_" + f.id;
    for (; t < 45; t += 0.5) { fr.time = t; auto o = eng.step(0.5, fr); bool has = false; for (auto& a : o.alarms) if (a.code == code) has = true; if (t < 29 && has) early = true; if (t > 31 && has) late = true; }
    CHECK(!early, "тревога расхождения не раньше 30 с");
    CHECK(late, "тревога расхождения после 30 с");
    fr.fb[0].pct = 0; bool still = false;
    for (int i = 0; i < 4; ++i) { auto o = eng.step(0.5, fr); for (auto& a : o.alarms) if (a.code == code) still = true; }
    CHECK(!still, "тревога расхождения снимается при совпадении");
    // 3. штатная работа без расхождений (ложные тревоги недопустимы)
    {
        Runtime rt(cfg, [](const std::string&) {}); rt.command("thr_take all"); rt.command("sim wind 11.4 60"); rt.command("sim wave 1.4 7 50");
        bool pos = false; std::set<std::string> c;
        while (rt.clock() < 900) { if (!pos && rt.clock() > 300) { rt.command("position"); pos = true; } rt.cycle(); for (auto& a : rt.out().alarms) if (a.code.rfind("THR_FB_MISMATCH", 0) == 0) c.insert(a.code); }
        CHECK(c.empty(), "в штатной работе тревоги расхождения нет");
    }
    std::printf(fails ? "ПРОВАЛ\n" : "limits_test: OK\n"); return fails ? 1 : 0;
}
