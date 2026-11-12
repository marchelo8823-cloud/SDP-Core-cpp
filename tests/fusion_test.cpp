// Компиляция позиции: медианная проверка, режимы систем, мягкая коррекция после скачка. Только имитация, не сертифицировано.
#include <cstdio>
#include "dp/runtime.hpp"

using namespace dp;
static int fails = 0;
#define CHECK(c, msg) do { const bool ok_ = (c); std::printf("%s %s\n", ok_ ? "  ok " : "FAIL ", msg); if (!ok_) ++fails; } while (0)

struct Res { double maxEstErr = 0, maxStep1s = 0, finalEstErr = 0; bool pred = false, median = false, soft = false; std::string st1; double maxTruth = 0; };

// scenario: 1 — GNSS1 сдвинут на 10 м (остальные верны); 2 — все три сдвинуты на 12 м (общий скачок)
static Res run(AppCfg c, int scenario) {
    c.logFile.clear(); c.startMode = "position"; c.env.turbulence = 0.5;
    for (const char* id : {"LASER", "WIRE"}) c.est.posRef[id].mode = 2;     // остаются три GNSS
    Runtime r(c, [](const std::string&) {});
    while (r.clock() < 200) r.cycle();
    if (scenario == 1) r.command("sim jump GNSS1 10 0");
    else { r.command("sim jump GNSS1 12 0"); r.command("sim jump GNSS2 12 0"); r.command("sim jump GNSS3 12 0"); }
    Res res; double t0 = r.clock(); double hn = 0, he = 0; std::vector<std::pair<double, std::pair<double, double>>> hist;
    while (r.clock() < t0 + 120) {
        r.cycle();
        double n, e, p; r.truth(n, e, p);
        const auto& es = r.out().est;
        double en = es.n - n, ee = es.e - e;
        if (scenario == 2) { en -= 12; }          // для общего скачка «истиной» считаем сдвинутую позицию
        const double err = std::hypot(en, ee); res.maxEstErr = std::max(res.maxEstErr, err);
        hist.push_back({r.clock(), {es.n, es.e}});
        while (hist.size() > 1 && hist.front().first < r.clock() - 1.0) hist.erase(hist.begin());
        res.maxStep1s = std::max(res.maxStep1s, std::hypot(es.n - hist.front().second.first, es.e - hist.front().second.second));
        for (auto& a : r.out().alarms) { if (a.code == "POS_PRED") res.pred = true; if (a.code == "POS_MEDIAN") res.median = true; if (a.code == "POS_SOFT") res.soft = true; }
        res.maxTruth = std::max(res.maxTruth, std::hypot(n - r.out().ctl.refN, e - r.out().ctl.refE));
        (void)hn; (void)he;
    }
    double n, e, p; r.truth(n, e, p);
    res.finalEstErr = std::hypot(r.out().est.n - n - (scenario == 2 ? 12 : 0), r.out().est.e - e);
    for (auto& s : r.out().est.sensors) if (s.id == "P:GNSS1") res.st1 = s.state;
    return res;
}

int main(int argc, char** argv) {
    AppCfg cfg; json::Report rep;
    if (!loadConfig(argc > 1 ? argv[1] : "config/demo.json", cfg, rep)) { std::printf("не удалось прочитать настройки\n"); return 2; }
    // 1. один из трёх сдвинут на 10 м
    const Res a = run(cfg, 1);
    AppCfg m = cfg; m.est.medianMode = 2;
    const Res b = run(m, 1);
    std::printf("скачок одной системы: прежнее — ошибка оценки макс %.1f м, итог %.1f м; с медианной проверкой — макс %.1f м, итог %.1f м, состояние GNSS1: %s\n", a.maxEstErr, a.finalEstErr, b.maxEstErr, b.finalEstErr, b.st1.c_str());
    CHECK(b.finalEstErr < 1.5 && b.maxEstErr < 3.0, "медианная проверка (отклонять): сдвинутая система не тянет оценку, ошибка < 3 м");
    CHECK(b.st1 == "MEDIAN" && b.median, "система показана как «отклонена по медиане», выдана тревога POS_MEDIAN");
    CHECK(a.pred, "по предсказанию скачок отмечается тревогой POS_PRED (прежний режим)");
    // 2. режимы систем: наблюдение и выключение
    AppCfg mon = cfg; mon.est.posRef["GNSS1"].mode = 1;
    const Res c = run(mon, 1);
    std::printf("GNSS1 в режиме наблюдения: ошибка оценки макс %.1f м, состояние %s\n", c.maxEstErr, c.st1.c_str());
    CHECK(c.maxEstErr < 3.0, "система в режиме «наблюдение» не влияет на решение");
    AppCfg off = cfg; off.est.posRef["GNSS1"].mode = 2;
    const Res d = run(off, 1);
    CHECK(d.maxEstErr < 3.0 && d.st1 == "OFF", "выключенная система не влияет на решение и показана как OFF");
    // 3. общий скачок всех систем: мягкая коррекция
    const Res e1 = run(cfg, 2);
    AppCfg sc = cfg; sc.est.softRateMS = 0.3;
    const Res e2 = run(sc, 2);
    std::printf("общий скачок 12 м: прежнее — наибольший сдвиг оценки за 1 с %.1f м; мягкая коррекция — %.2f м (тревога POS_SOFT: %s)\n", e1.maxStep1s, e2.maxStep1s, e2.soft ? "да" : "нет");
    CHECK(e1.maxStep1s > 3.0, "без мягкой коррекции оценка перескакивает");
    CHECK(e2.maxStep1s < 1.0 && e2.soft, "с мягкой коррекцией оценка сдвигается не быстрее ~0,3 м/с, выдана тревога POS_SOFT");
    std::printf(fails ? "ПРОВАЛ: %d\n" : "Все проверки пройдены\n", fails);
    return fails ? 1 : 0;
}
