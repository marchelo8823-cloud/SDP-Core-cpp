// v0.17: потеря опорных систем (счисление), журнал тревог, анализ последствий отказа, пониженный вес GNSS. Только имитация.
#include <cstdio>
#include "dp/service.hpp"

using namespace dp;
static int fails = 0;
#define CHECK(c, msg) do { const bool ok_ = (c); std::printf("%s %s\n", ok_ ? "  ok " : "FAIL ", msg); if (!ok_) ++fails; } while (0)

static bool hasCode(const std::vector<Alarm>& a, const char* c) { for (auto& x : a) if (x.code == c) return true; return false; }
static const AlarmRec* rec(const Runtime& r, const char* c) { for (auto& x : r.alarmMgr().records()) if (x.code == c) return &x; return nullptr; }

int main(int argc, char** argv) {
    AppCfg cfg; json::Report rep;
    if (!loadConfig(argc > 1 ? argv[1] : "config/demo.json", cfg, rep)) { std::printf("не удалось прочитать настройки\n"); return 2; }
    cfg.logFile.clear(); cfg.startMode = "position";
    Runtime r(cfg, [](const std::string&) {});
    r.command("sim wind 5 270");
    while (r.clock() < 60) r.cycle();
    CHECK(!r.out().est.refLost && !hasCode(r.out().alarms, "POS_ALL_REJ"), "при исправных системах потери опорных систем нет");

    // анализ последствий: класс 2
    r.command("class 2");
    while (r.clock() < 75) r.cycle();
    CHECK(r.dpClass() == 2 && r.conseqRunning(), "команда class 2 включает анализ последствий в авто-позиции");
    bool seen = false; for (auto& e : r.alarmMgr().events()) if (e.text.find("Анализ последствий отказа запущен") != std::string::npos) seen = true;
    CHECK(seen, "запуск анализа записан в журнал событий");
    CHECK(r.conseq().ran, "первый расчёт выполнен");
    r.command("class 0"); r.cycle();
    CHECK(!r.conseqRunning(), "class 0 останавливает анализ");

    // потеря всех позиционных опор
    std::vector<std::string> pos; for (auto& c : r.hub().channels(r.hubNow())) if (c.id.rfind("GNSS", 0) == 0 || c.id == "LASER" || c.id == "WIRE") pos.push_back(c.id);
    for (auto& id : pos) r.command("sim off " + id);
    const double t0 = r.clock(); bool allRej = false, dropout = false; double tDrop = 0;
    while (r.clock() < t0 + 40) {
        r.cycle();
        if (hasCode(r.out().alarms, "POS_ALL_REJ")) allRej = true;
        if (!dropout && hasCode(r.out().alarms, "POS_DROPOUT")) { dropout = true; tDrop = r.clock() - t0; }
    }
    CHECK(allRej, "«Все опорные системы отклонены» выдано сразу после потери");
    CHECK(dropout && tDrop > 15 && tDrop < 30, "«Потеря положения» выдаётся примерно через 20 с");
    CHECK(rec(r, "POS_DROPOUT") != nullptr && !rec(r, "POS_DROPOUT")->acked, "тревога в списке и не подтверждена");
    CHECK(r.alarmMgr().audible(), "звук включён до подтверждения");
    r.command("silence");
    CHECK(!r.alarmMgr().audible(), "silence выключает звук");
    r.command("ack");
    CHECK(rec(r, "POS_DROPOUT") != nullptr && rec(r, "POS_DROPOUT")->acked, "ack подтверждает тревоги");
    CHECK(r.out().ctl.errDist < 15, "судно удерживается моделью (не бросили, ошибка мала)");
    CHECK(r.engine().mode() == DpMode::AutoPosition, "режим авто-позиции сохранён при счислении");

    // восстановление
    for (auto& id : pos) r.command("sim on " + id);
    const double t1 = r.clock();
    while (r.clock() < t1 + 30) r.cycle();
    CHECK(!hasCode(r.out().alarms, "POS_DROPOUT") && !hasCode(r.out().alarms, "POS_ALL_REJ"), "после возврата систем тревоги снимаются");
    CHECK(rec(r, "POS_DROPOUT") == nullptr || rec(r, "POS_DROPOUT")->state == AlarmNormal, "запись переходит в «Нормально»");
    bool ev = false; for (auto& e : r.alarmMgr().events()) if (e.kind == EvNormal) ev = true;
    CHECK(ev, "возврат в норму записан в журнал событий");

    // пониженный вес GNSS: 2 GNSS + 1 другая → 0.10 / 0.10 / 0.80
    r.command("fusion gnssweight reduced");
    CHECK(std::fabs(r.engine().estimator().cfg().reducedGnssWeightRatio - 0.125) < 1e-9 && r.engine().estimator().cfg().gnssWeight == 1, "пониженный вес GNSS включён (отношение 1/8)");

    // сеть: снимок туда и обратно
    OpSnap s = CoreService::makeSnap(r, cfg);
    json::Value jv; std::string perr; json::parse(encodeSnap(s), jv, perr);
    const OpSnap d = decodeSnap(jv);
    CHECK(d.evs.size() == s.evs.size() && !d.evs.empty() && d.arecs.size() == s.arecs.size(), "журнал и список тревог проходят по сети");
    std::printf(fails ? "ПРОВАЛ: %d\n" : "Все проверки пройдены\n", fails);
    return fails ? 1 : 0;
}
