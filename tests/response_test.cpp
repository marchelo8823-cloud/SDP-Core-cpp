// Отклик на отклонения и предсказание: сравнение «обычные настройки» и «разнонаправленный упор ВРК + зоны нечувствительности + предсказание».
// Только имитация, не сертифицировано.
#include <cstdio>
#include "dp/runtime.hpp"

using namespace dp;
static int fails = 0;
#define CHECK(c, msg) do { const bool ok_ = (c); std::printf("%s %s\n", ok_ ? "  ok " : "FAIL ", msg); if (!ok_) ++fails; } while (0)

struct Res { double rms = 0, maxPos = 0, azTravel = 0, pctTravel = 0, tunTravel = 0, angP = 0, angS = 0, spread = 0; bool ok = true; };

static Res run(AppCfg c, double windMS, double dur, bool tuned) {
    c.logFile.clear(); c.startMode = "position";
    if (!tuned) {                                   // «обычные» — всё новое выключено, даже если включено в файле
        c.control.posDeadM = c.control.hdgDeadDeg = 0; c.control.predict.enabled = false;
        for (auto& t : c.thrusters) { t.prefDeg = 1e9; t.preloadPct = 0; t.azDeadDeg = 0; t.pctDeadPct = 0; }
    }
    if (tuned) {
        c.control.posDeadM = 0.4; c.control.hdgDeadDeg = 0.4;
        c.control.predict.enabled = true; c.control.predict.meanS = 40; c.control.predict.horizonS = 15;
        for (auto& t : c.thrusters) {
            if (t.type == ThrusterType::Azimuth) { t.prefDeg = t.id == "VRK_P" ? 90 : 270; t.preloadPct = 10; t.azDeadDeg = 2.0; t.pctDeadPct = 1.0; }
            else t.pctDeadPct = 1.0;
        }
    }
    if (windMS <= 0.0) { c.env.currentSpeed = 0; c.env.hs = 0; }   // штиль: без ветра, течения и волн
    c.env.windSpeed = windMS; c.env.windFromDeg = 60; c.env.turbulence = 1.5;
    Runtime r(c, [](const std::string&) {});
    Res res; std::vector<double> lastAng(c.thrusters.size(), 1e9), lastPct(c.thrusters.size(), 1e9);
    double sum2 = 0; long n = 0; auto& st = r.sim()->thrusters();
    double sPx = 0, sPy = 0, sSx = 0, sSy = 0; long na = 0;
    while (r.clock() < dur) {
        r.cycle();
        if (r.clock() < 300) continue;               // выход на режим
        const double e = r.out().ctl.errDist; sum2 += e * e; ++n; res.maxPos = std::max(res.maxPos, e);
        for (size_t i = 0; i < c.thrusters.size(); ++i) {
            const double a = st[i].angleDeg(), p = st[i].pct();
            if (c.thrusters[i].type == ThrusterType::Azimuth && lastAng[i] < 1e8) res.azTravel += std::fabs(rad2deg(wrapPi(deg2rad(a - lastAng[i]))));
            if (lastPct[i] < 1e8) { res.pctTravel += std::fabs(p - lastPct[i]); if (c.thrusters[i].type != ThrusterType::Azimuth) res.tunTravel += std::fabs(p - lastPct[i]); }
            lastAng[i] = a; lastPct[i] = p;
            if (c.thrusters[i].id == "VRK_P") { sPx += std::cos(deg2rad(a)); sPy += std::sin(deg2rad(a)); }
            if (c.thrusters[i].id == "VRK_S") { sSx += std::cos(deg2rad(a)); sSy += std::sin(deg2rad(a)); }
        }
        ++na;
    }
    res.rms = n ? std::sqrt(sum2 / n) : 1e9; res.ok = r.out().est.posValid;
    res.angP = std::fmod(rad2deg(std::atan2(sPy, sPx)) + 720.0, 360.0); res.angS = std::fmod(rad2deg(std::atan2(sSy, sSx)) + 720.0, 360.0);
    return res;
}

static void predictorTest() {
    PredictCfg pc; pc.enabled = true; pc.meanS = 40; pc.trendS = 120; pc.horizonS = 15; pc.trendLimitFrac = 0.3; pc.trendFloor = 0;
    Predictor p; double peak = 0, y = 0;
    for (int i = 0; i < 600; ++i) p.step(0.1, 100.0, pc);                 // установившийся ветер 100
    for (int i = 0; i < 100; ++i) { y = p.step(0.1, 160.0, pc); peak = std::max(peak, y); }   // порыв +60 на 10 с
    CHECK(peak < 115.0, "порыв на 10 с (+60 %) даёт на выходе предсказателя не более +15 % (мгновенно бы прошло +60 %)");
    Predictor q; for (int i = 0; i < 600; ++i) q.step(0.1, 100.0, pc);
    double yy = 0; for (int i = 0; i < 3000; ++i) yy = q.step(0.1, 150.0, pc);     // устойчивый рост ветра на 300 с
    CHECK(yy > 140.0 && yy < 160.0, "устойчивое изменение ветра предсказатель отрабатывает (за 300 с выходит на новое значение)");
    Predictor off; PredictCfg po; CHECK(off.step(0.1, 42.0, po) == 42.0, "выключенный предсказатель передаёт значение без изменений");
}

int main(int argc, char** argv) {
    predictorTest();
    AppCfg cfg; json::Report rep;
    if (!loadConfig(argc > 1 ? argv[1] : "config/salvage73_pms.json", cfg, rep)) { std::printf("не удалось прочитать настройки\n"); return 2; }
    const double dur = 1500;
    const Res a = run(cfg, 10, dur, false), b = run(cfg, 10, dur, true);
    std::printf("обычные:   СКО %.2f м, макс %.2f м, ход колонок %.0f°, ход упоров %.0f %%, из них НПУ %.0f %%, средние углы %.0f/%.0f\n", a.rms, a.maxPos, a.azTravel, a.pctTravel, a.tunTravel, a.angP, a.angS);
    std::printf("настроено: СКО %.2f м, макс %.2f м, ход колонок %.0f°, ход упоров %.0f %%, из них НПУ %.0f %%, средние углы %.0f/%.0f\n", b.rms, b.maxPos, b.azTravel, b.pctTravel, b.tunTravel, b.angP, b.angS);
    CHECK(a.ok && b.ok, "положение достоверно в обоих прогонах");
    CHECK(b.rms < 3.0 && b.maxPos < 8.0, "с новыми настройками позиция удерживается (СКО < 3 м, максимум < 8 м)");
    CHECK(b.azTravel < 0.6 * a.azTravel, "колонки поворачиваются заметно меньше (ход углов упал минимум на 40 %)");
    CHECK(b.tunTravel < 0.8 * a.tunTravel, "упор НПУ меняется меньше");
    const Res calmA = run(cfg, 0.0, 700, false), calmB = run(cfg, 0.0, 700, true);
    std::printf("штиль: обычные — углы %.0f/%.0f, настроено — %.0f/%.0f\n", calmA.angP, calmA.angS, calmB.angP, calmB.angS);
    CHECK(std::fabs(calmB.angP - 90) < 20 && std::fabs(calmB.angS - 270) < 20, "при малой нагрузке колонки стоят струёй наружу: по силе на судно левая около 90°, правая около 270° (разнонаправленный упор)");
    CHECK(!(b.angP > 241 && b.angP < 299) && !(b.angS > 61 && b.angS < 119), "при ветре струи колонок не стоят в запретных секторах");
    std::printf(fails ? "ПРОВАЛ: %d\n" : "Все проверки пройдены\n", fails);
    return fails ? 1 : 0;
}
