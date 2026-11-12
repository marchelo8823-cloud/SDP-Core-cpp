// Радиус удержания: настройка закона, предупреждение и аларм; медианный тест без ложных отказов и мигания
#include <cstdio>
#include <cmath>
#include <set>
#include "dp/runtime.hpp"
using namespace dp;
static int fails = 0;
#define CHECK(c, m) do { if (!(c)) { std::printf("ОШИБКА: %s\n", m); ++fails; } } while (0)

struct R { double maxDev = 0, meanDev = 0; std::set<std::string> codes; int medFlips = 0; };
static R run(const AppCfg& cfg, double radius, int median, double dur) {
    Runtime rt(cfg, [](const std::string&) {});
    rt.command("thr_take all");
    if (median == 2) rt.command("fusion median reject");
    if (radius > 0) rt.command("radius " + std::to_string(radius));
    rt.command("sim wind 11.4 60"); rt.command("sim wave 1.4 7 50"); rt.command("sim current 0.5 200");
    bool pos = false; double tp = 0, sum = 0; long n = 0; bool prev = false; R r;
    while (rt.clock() < dur) {
        if (!pos && rt.clock() > 600) { rt.command("position"); pos = true; tp = rt.clock(); }
        rt.cycle();
        bool med = false;
        const bool steady = pos && rt.clock() > tp + 150;   // переходный процесс после включения режима в расчёт тревог радиуса не берётся
        for (auto& a : rt.out().alarms) { if (steady) r.codes.insert(a.code); if (a.code.rfind("POS_MEDIAN", 0) == 0 || a.code == "POS_ALL_REJ") med = true; }
        if (med != prev) { ++r.medFlips; prev = med; }
        if (pos && rt.clock() > tp + 150) { const auto& t = rt.sim()->truth(); const double d = std::hypot(t.n - rt.out().ctl.refN, t.e - rt.out().ctl.refE); r.maxDev = std::max(r.maxDev, d); sum += d; ++n; }
    }
    r.meanDev = n ? sum / n : 0; return r;
}

int main(int argc, char** argv) {
    AppCfg cfg; json::Report rep; if (!loadConfig(argc > 1 ? argv[1] : "config/salvage73_pms.json", cfg, rep)) return 2;
    // 1. зависимость настройки от радиуса
    const ControlCfg b = cfg.control; const ControlCfg t1 = tuneForRadius(b, 1), t5 = tuneForRadius(b, 5), t20 = tuneForRadius(b, 20), t0 = tuneForRadius(b, 0);
    CHECK(t1.wnPos > t5.wnPos && t5.wnPos >= t20.wnPos, "меньше радиус — быстрее контур");
    CHECK(t1.posTolM < t5.posTolM && t5.posTolM < t20.posTolM, "меньше радиус — меньше допуск закона");
    CHECK(t1.posDeadM == b.posDeadM && t20.posDeadM > t1.posDeadM, "зона нечувствительности только при большом радиусе");
    CHECK(t0.wnPos == b.wnPos && t0.posTolM == b.posTolM && t0.biasFilterS == b.biasFilterS, "радиус 0 — базовые настройки");
    // 2. имитация: жёсткий радиус держит плотнее мягкого
    const R tight = run(cfg, 1.0, 0, 1300), soft = run(cfg, 10.0, 0, 1300);
    std::printf("радиус 1 м: среднее %.2f макс %.2f; радиус 10 м: среднее %.2f макс %.2f\n", tight.meanDev, tight.maxDev, soft.meanDev, soft.maxDev);
    CHECK(tight.maxDev < soft.maxDev && tight.meanDev < soft.meanDev, "малый радиус держит плотнее большого");
    CHECK(tight.maxDev < 1.2, "при радиусе 1 м истинное отклонение не больше ~1 м");
    CHECK(soft.maxDev < 10.0, "при радиусе 10 м судно не выходит за радиус");
    // 3. предупреждение и аларм
    const R tiny = run(cfg, 0.5, 0, 1300);
    CHECK(tiny.codes.count("RADIUS_OUT"), "аларм выхода за радиус при слишком малом радиусе");
    CHECK(soft.codes.count("RADIUS_OUT") == 0 && soft.codes.count("RADIUS_WARN") == 0, "при достаточном радиусе предупреждений нет");
    const R none = run(cfg, 0, 0, 1300);
    CHECK(none.codes.count("RADIUS_OUT") == 0 && none.codes.count("RADIUS_WARN") == 0, "без радиуса предупреждений нет");
    // 4. медианный тест: нет ложных отказов и мигания
    const R med = run(cfg, 0, 2, 1300);
    CHECK(med.medFlips <= 2, "медианный тест не мигает на штатном шуме");
    CHECK(med.codes.count("POS_ALL_REJ") == 0, "системы положения не отклоняются все");
    std::printf(fails ? "radius_test: ОШИБКИ\n" : "radius_test: ok\n"); return fails ? 1 : 0;
}
