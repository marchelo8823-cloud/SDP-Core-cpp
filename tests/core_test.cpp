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

    std::printf("-- потеря всех систем положения --\n");
    for (auto& id : c.simIds()) if (id.rfind("GNSS", 0) == 0 || id == "LASER") c.command("sim off " + id);
    const double tl = c.clock(); bool drop = false;
    while (c.clock() < tl + 60) { c.cycle(); for (auto& a : c.out().alarms) drop = drop || a.code == "POS_DROPOUT"; }
    CHECK(drop && c.mode() == DpMode::AutoPosition, "без положения: тревога POS_DROPOUT, удержание по счислению, режим не снят");
    c.command("sim reset");
    h = hold(c, c.clock() + 120, c.clock() + 300);
    CHECK(h.maxPos < 3.0, "положение вернулось: удержание снова в пределах 3 м");
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
