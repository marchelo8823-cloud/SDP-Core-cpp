// Рабочий цикл ядра: запуск без данных, загрузка судна, ожидание датчиков, имитатор отдельной командой, удержание и отказы.
// Аргументы: <книга судна> <книга имитатора> <испорченная книга судна>
#include <cstdio>
#include <cmath>
#include <set>
#include "dp/core.hpp"
using namespace dp;
static int fails = 0;
#define CHECK(c, m) do { const bool ok_ = (c); std::printf("%s %s\n", ok_ ? "  ok " : "FAIL ", m); if (!ok_) ++fails; } while (0)

struct Hold { double maxPos = 0, maxHdg = 0; };
// истинное отклонение судна от опорной точки на отрезке времени [a, b] (по имитатору, а не по оценке)
static Hold hold(Core& c, double a, double b) {
    Hold h;
    while (c.clock() < b) {
        c.cycle();
        if (c.clock() < a) continue;
        const auto& s = c.sim()->truth(); const auto& o = c.out();
        h.maxPos = std::max(h.maxPos, std::hypot(s.n - o.ctl.refN, s.e - o.ctl.refE));
        h.maxHdg = std::max(h.maxHdg, std::fabs(rad2deg(wrapPi(s.psi - deg2rad(o.ctl.refPsiDeg)))));
    }
    return h;
}
static bool said(const std::vector<std::string>& v, const std::string& p) { for (auto& s : v) if (s.find(p) != std::string::npos) return true; return false; }

int main(int argc, char** argv) {
    if (argc < 4) { std::printf("нужны три аргумента\n"); return 2; }
    const std::string ship = argv[1], simb = argv[2], bad = argv[3];
    std::vector<std::string> log;
    Core c({}, [&](const std::string& s) { log.push_back(s); });

    std::printf("-- запуск без данных --\n");
    for (int i = 0; i < 30; ++i) c.cycle();
    CHECK(c.state() == CoreState::NoShip && !c.hasShip(), "ядро работает и ждёт судно");
    c.command("position");
    CHECK(said(log, "Судно не загружено"), "без судна режимы не включаются, ядро это объясняет");
    c.command("sim start " + simb);
    CHECK(!c.simRunning() && said(log, "сначала загрузите судно"), "имитатор без судна не запускается");

    std::printf("-- загрузка судна --\n");
    CHECK(!c.loadShip(bad) && !c.hasShip(), "книга с ошибками не принимается");
    c.command("ship load " + ship);
    CHECK(c.hasShip() && c.state() == CoreState::WaitSensors, "судно загружено");
    for (int i = 0; i < 30; ++i) c.cycle();
    CHECK(c.state() == CoreState::WaitSensors, "после загрузки ядро ждёт датчики (у примера нет подключений)");
    CHECK(said(log, "Работа возможна только в имитаторе"), "ядро сообщает, что датчики судна не подключены");
    c.command("thr_take all"); c.command("position");
    CHECK(c.mode() == DpMode::Standby && said(log, "ждёт датчики"), "без датчиков режим позиции не включается");
    CHECK(!c.loadShip(bad) && c.hasShip() && c.ship()->vessel.name == "Демонстрационное судно", "ошибочная книга не заменяет загруженное судно");

    std::printf("-- имитатор отдельной командой --\n");
    c.command("sim start " + ship);
    CHECK(!c.simRunning() && said(log, "похоже, это книга судна"), "книга судна вместо книги имитатора отклонена");
    c.command("sim start " + simb);
    CHECK(c.simRunning(), "имитатор запущен");
    while (c.clock() < 20) c.cycle();
    CHECK(c.state() == CoreState::Ready, "от имитатора пошли данные: ГОТОВ");
    c.command("position");
    CHECK(c.mode() == DpMode::Standby, "после запуска имитатора движители заново не взяты — режим не включается");
    c.command("thr_take all"); c.command("position");
    CHECK(c.mode() == DpMode::AutoPosition && c.state() == CoreState::Active, "thr_take all и position: УДЕРЖАНИЕ");
    c.command("ship load " + ship);
    CHECK(said(log, "сначала режим ожидания") && c.simRunning(), "во время удержания судно не перезагружается");
    c.command("sim stop");
    CHECK(c.simRunning(), "во время удержания имитатор не останавливается");

    std::printf("-- удержание: ветер 10 м/с, течение 0,5 м/с, волна 1,5 м --\n");
    Hold h = hold(c, 300, 900);
    std::printf("   отклонение до %.2f м, курс до %.2f°\n", h.maxPos, h.maxHdg);
    CHECK(h.maxPos < 3.0 && h.maxHdg < 3.0, "судно удерживается: меньше 3 м и 3°");

    std::printf("-- сдвиг точки на 20 м к северу и курс +30° --\n");
    const double n0 = c.out().ctl.refN, h0 = c.out().ctl.refPsiDeg;
    c.command("move 20 0 30");
    h = hold(c, c.clock() + 400, c.clock() + 700);
    const auto& tr = c.sim()->truth();
    std::printf("   смещение %.1f м, поворот %.1f°\n", tr.n - n0, rad2deg(wrapPi(tr.psi - deg2rad(h0))));
    CHECK(std::fabs((tr.n - n0) - 20.0) < 3.0 && std::fabs(rad2deg(wrapPi(tr.psi - deg2rad(h0))) - 30.0) < 3.0, "судно перешло на 20 м и повернуло на 30°");

    std::printf("-- отказ носового подруливающего --\n");
    c.command("sim thr off BOW1");
    h = hold(c, c.clock() + 200, c.clock() + 600);
    std::printf("   отклонение до %.2f м\n", h.maxPos);
    CHECK(h.maxPos < 5.0, "позиция удерживается (меньше 5 м)");
    c.command("sim thr on BOW1");
    c.command("thr_take BOW1");   // после отказа движитель берётся в управление заново

    std::printf("-- потеря всех систем положения --\n");
    const double sp0n = c.out().ctl.refN, sp0e = c.out().ctl.refE;
    for (auto& id : c.simIds()) if (id.rfind("GNSS", 0) == 0 || id == "LASER") c.command("sim off " + id);
    const double tl = c.clock(); bool drop = false;
    while (c.clock() < tl + 60) { c.cycle(); for (auto& a : c.out().alarms) drop = drop || a.code == "POS_DROPOUT"; }
    CHECK(drop && c.mode() == DpMode::AutoPosition, "без положения: тревога POS_DROPOUT, удержание по счислению, режим не снят");
    CHECK(std::fabs(c.out().ctl.refN - sp0n) < 0.01 && std::fabs(c.out().ctl.refE - sp0e) < 0.01, "при потере положения уставка оператора не переносится");
    bool unc = false; for (auto& a : c.out().alarms) if (a.code == "POS_DROPOUT") unc = a.text.find("погрешность положения") != std::string::npos;
    CHECK(unc, "в тревоге POS_DROPOUT показана погрешность положения по счислению");
    // долгая потеря: судно уходит; после возврата измерений — плавный возврат в заданную точку, без насыщения движителей
    while (c.clock() < tl + 300) c.cycle();
    log.clear();
    c.command("sim reset");
    const double tRet = c.clock(); double vmax = 0, load = 0; bool ret = false;
    while (c.clock() < tRet + 250) {
        c.cycle(); const auto& s = c.sim()->truth();
        bool r = false; for (auto& a : c.out().alarms) r = r || a.code == "POS_RETURN";
        ret = ret || r;
        if (r) { const auto& o = c.out(); load = std::max({load, std::fabs(o.ctl.tau.X) / std::max(1.0, o.cap.X), std::fabs(o.ctl.tau.Y) / std::max(1.0, o.cap.Y)}); }
        if (r && c.clock() > tRet + 30) vmax = std::max(vmax, std::hypot(s.u, s.v));
    }
    std::printf("   скорость судна при возврате (после первых 30 с) до %.2f м/с, усилие до %.0f %% возможностей\n", vmax, 100 * load);
    CHECK(said(log, "Положение восстановлено") && ret, "после возврата измерений: сообщение и тревога POS_RETURN");
    CHECK(vmax < 0.3, "возврат в точку не быстрее 0,2 м/с (с запасом на волну и порывы — меньше 0,3)");
    CHECK(load < 0.8, "возврат не полным упором: усилие меньше 80 % возможностей");
    CHECK(said(log, "Возврат в заданную точку завершён"), "возврат завершён");
    h = hold(c, c.clock() + 10, c.clock() + 150);
    CHECK(h.maxPos < 3.0, "положение вернулось: удержание снова в пределах 3 м");

    std::printf("-- потеря курса --\n");
    for (auto& id : c.simIds()) if (id.rfind("GYRO", 0) == 0) c.command("sim off " + id);
    const double th0 = c.clock(); bool hdr = false, hlost = false; double thrMin = 1e9, tLost = -1;
    while (c.clock() < th0 + 40) {
        c.cycle();
        double sum = 0; for (auto& k : c.out().cmds) sum += std::fabs(k.pct);
        bool l = false; for (auto& a : c.out().alarms) { hdr = hdr || a.code == "HDG_DR"; l = l || a.code == "HDG_LOST"; }
        if (l && tLost < 0) tLost = c.clock() - th0;
        hlost = hlost || l;
        if (c.clock() > th0 + 3 && c.clock() < th0 + 30) thrMin = std::min(thrMin, sum);
    }
    std::printf("   курс снят через %.0f с\n", tLost);
    CHECK(hdr && thrMin > 1.0, "без гирокомпасов: тревога HDG_DR, упор не снимается");
    CHECK(hlost && tLost > 30 && tLost < 35, "через 30 с счисления курса: HDG_LOST и нулевой упор");
    c.command("sim reset");
    h = hold(c, c.clock() + 120, c.clock() + 200);
    CHECK(h.maxPos < 3.0 && h.maxHdg < 3.0, "курс вернулся: удержание снова в пределах 3 м и 3°");
    std::printf("-- повторная потеря положения во время возврата --\n");
    auto offPos = [&]() { for (auto& id : c.simIds()) if (id.rfind("GNSS", 0) == 0 || id == "LASER") c.command("sim off " + id); };
    auto has = [&](const char* code) { for (auto& a : c.out().alarms) if (a.code == code) return true; return false; };
    offPos();
    { const double t1 = c.clock(); while (c.clock() < t1 + 300) c.cycle(); }
    c.command("sim reset");
    { const double t1 = c.clock(); while (c.clock() < t1 + 15) c.cycle(); }
    CHECK(has("POS_RETURN"), "идёт возврат в точку");
    offPos();
    { const double t1 = c.clock(); bool d = false; while (c.clock() < t1 + 60) { c.cycle(); d = d || has("POS_DROPOUT"); }
      CHECK(d && c.mode() == DpMode::AutoPosition, "во время возврата снова потеря: POS_DROPOUT, режим не снят"); }
    log.clear();
    c.command("sim reset");
    { const double t1 = c.clock(); double load = 0;
      while (c.clock() < t1 + 300) { c.cycle(); const auto& o = c.out(); if (has("POS_RETURN")) load = std::max({load, std::fabs(o.ctl.tau.X) / std::max(1.0, o.cap.X), std::fabs(o.ctl.tau.Y) / std::max(1.0, o.cap.Y)}); }
      std::printf("   усилие при повторном возврате до %.0f %% возможностей\n", 100 * load);
      CHECK(load < 0.8 && said(log, "Возврат в заданную точку завершён"), "после повторной потери возврат снова плавный и завершается"); }
    h = hold(c, c.clock() + 10, c.clock() + 120);
    CHECK(h.maxPos < 3.0, "удержание снова в пределах 3 м");

    std::printf("-- одновременная потеря положения и курса --\n");
    offPos();
    for (auto& id : c.simIds()) if (id.rfind("GYRO", 0) == 0) c.command("sim off " + id);
    { const double t1 = c.clock(); bool dr = false, lost = false, drop = false;
      while (c.clock() < t1 + 45) { c.cycle(); dr = dr || has("HDG_DR"); lost = lost || has("HDG_LOST"); drop = drop || has("POS_DROPOUT"); }
      CHECK(dr && lost && drop, "тревоги HDG_DR, затем HDG_LOST, и POS_DROPOUT");
      CHECK(c.mode() == DpMode::AutoPosition, "режим не снят сам"); }
    c.command("sim reset");
    h = hold(c, c.clock() + 200, c.clock() + 300);
    std::printf("   после возврата датчиков: до %.2f м, %.2f°\n", h.maxPos, h.maxHdg);
    CHECK(h.maxPos < 3.0 && h.maxHdg < 3.0, "после возврата всех датчиков удержание в пределах 3 м и 3°");

    c.command("standby");
    for (int i = 0; i < 10; ++i) c.cycle();
    CHECK(c.state() == CoreState::Ready, "в ожидании с данными: ГОТОВ");

    std::printf("-- остановка имитатора --\n");
    c.command("sim stop");
    for (int i = 0; i < 30; ++i) c.cycle();
    CHECK(!c.simRunning() && c.state() == CoreState::WaitSensors, "после остановки имитатора ядро ждёт датчики судна");
    c.command("неизвестно");
    CHECK(!log.empty() && log.back().find("Неизвестная команда") != std::string::npos, "неизвестная команда отклоняется сообщением");

    std::printf(fails ? "ОШИБОК: %d\n" : "ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ\n", fails);
    return fails ? 1 : 0;
}
