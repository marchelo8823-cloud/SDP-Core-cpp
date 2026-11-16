// Судовое время (решение владельца 17.11.2026): UTC из ZDA и RMC, источник GNSS с запасным — компьютер, сверка с часами
// компьютера, скачок времени GNSS, пояс по долготе при первом положении, при переходе в другой пояс — только предупреждение,
// перевод — командой оператора. Плюс: хаб разбирает ZDA и RMC, ядро отвечает на time и zone.
// Аргументы: <книга судна> <книга имитатора>
#include <cstdio>
#include <cmath>
#include "dp/core.hpp"
using namespace dp;
static int fails = 0;
#define CHECK(c, m) do { const bool ok_ = (c); std::printf("%s %s\n", ok_ ? "  ok " : "FAIL ", m); if (!ok_) ++fails; } while (0)
static bool has(const std::vector<TimeMsg>& v, const char* code) { for (auto& m : v) if (m.code == code) return true; return false; }

int main(int argc, char** argv) {
    std::printf("-- разбор времени --\n");
    double u = 0;
    CHECK(nmeaUtc("123456.50", 17, 11, 2026, u) && std::fabs(u - (daysFromCivil(2026, 11, 17) * 86400.0 + 12 * 3600 + 34 * 60 + 56.5)) < 1e-6, "ZDA 12:34:56.5 17.11.2026");
    CHECK(daysFromCivil(1970, 1, 1) == 0 && daysFromCivil(2000, 3, 1) == 11017, "дни от 1970 года");
    CHECK(!nmeaUtc("", 17, 11, 2026, u) && !nmeaUtc("256000", 17, 11, 2026, u) && !nmeaUtc("120000", 0, 11, 2026, u), "пустое и неверное время отклоняется");
    CHECK(hmsText(u, 180) == "15:34:56" && dateText(u, 180) == "17.11.2026" && zoneText(180) == "UTC+3" && zoneText(-210) == "UTC-3:30", "показ: часы, дата, пояс");

    std::printf("-- источник и сверка --\n");
    {
        ShipTime st; std::vector<TimeMsg> m; std::vector<std::string> inf;
        const double pc = u;
        st.update(0, pc, false, 0, false, m, inf);
        CHECK(!st.usingGnss() && st.utc() == pc && inf.size() == 1, "нет GNSS — часы компьютера, одно сообщение");
        st.feedGnss(u, 1.0); m.clear(); inf.clear();
        st.update(1.5, pc + 1.5, false, 0, false, m, inf);
        CHECK(st.usingGnss() && std::fabs(st.utc() - (u + 0.5)) < 1e-6 && m.empty(), "есть GNSS — судовое время по GNSS, расхождения нет");
        m.clear(); st.update(2.0, pc + 2.0 + 5.0, false, 0, false, m, inf);
        CHECK(has(m, "TIME_PC_DIFF"), "часы компьютера ушли на 5 с — TIME_PC_DIFF");
        st.feedGnss(u + 2.0 + 30.0, 2.0); m.clear(); st.update(2.1, u + 32.1, false, 0, false, m, inf);
        CHECK(has(m, "TIME_JUMP"), "время GNSS прыгнуло на 30 с — TIME_JUMP");
        m.clear(); st.update(20.0, pc + 20, false, 0, false, m, inf);
        CHECK(!st.usingGnss(), "GNSS устарело — запасной источник: компьютер");
        st.setSource(ShipTime::Pc); st.feedGnss(u + 100, 30.0); m.clear(); st.update(30.1, pc + 50, false, 0, false, m, inf);
        CHECK(!st.usingGnss() && std::fabs(st.utc() - (pc + 50)) < 1e-6, "выбран компьютер — GNSS не используется");
        CHECK(has(m, "TIME_PC_DIFF"), "но расхождение с GNSS всё равно показывается");
        ShipTime s2; m.clear(); s2.feedGnss(u, 1.0); s2.update(1.0, u + 99, false, 0, true, m, inf);
        CHECK(!s2.usingGnss() && m.empty(), "в имитации — часы компьютера, без предупреждений");
    }

    std::printf("-- пояс --\n");
    {
        ShipTime st; std::vector<TimeMsg> m; std::vector<std::string> inf;
        st.update(0, u, true, 30.3, false, m, inf);
        CHECK(st.zoneMin() == 120 && m.empty() && !inf.empty(), "первое положение 30,3° В — пояс UTC+2 без вопросов");
        m.clear(); st.update(1, u, true, 37.6, false, m, inf);
        CHECK(st.zoneMin() == 120 && !has(m, "TIME_ZONE"), "37,6° — ещё UTC+2 (граница 37,5° с гистерезисом)");
        m.clear(); st.update(2, u, true, 38.0, false, m, inf);
        CHECK(st.zoneMin() == 120 && has(m, "TIME_ZONE") && st.zonePending() && st.suggestMin() == 180, "38,0° — предупреждение «судно в UTC+3», пояс сам не меняется");
        st.accept(); m.clear(); st.update(3, u, true, 38.0, false, m, inf);
        CHECK(st.zoneMin() == 180 && !has(m, "TIME_ZONE"), "zone accept — переведено на UTC+3, предупреждение снято");
        st.setZone(240); m.clear(); st.update(4, u, true, 38.0, false, m, inf);
        CHECK(st.zoneMin() == 240 && !has(m, "TIME_ZONE"), "пояс задан вручную — пока судно в том же поясе, не напоминает");
        m.clear(); st.update(5, u, true, -70.0, false, m, inf);
        CHECK(has(m, "TIME_ZONE") && st.suggestMin() == -300, "другая долгота (70° З) — снова предупреждение, UTC-5");
    }

    std::printf("-- хаб и ядро --\n");
    {
        SensorHub h; ChannelCfg ch; ch.id = "G"; ch.kind = ChannelKind::Gnss; h.addChannel(ch); h.setOrigin(60, 30);
        double ut = 0, at = 0;
        h.ingest("G", nmea::make("GPZDA,123456.00,17,11,2026,00,00"), 5.0);
        CHECK(h.latestUtc(ut, at) && std::fabs(ut - (daysFromCivil(2026, 11, 17) * 86400.0 + 45296)) < 1e-6 && at == 5.0, "ZDA принят по умолчанию, время UTC");
        h.ingest("G", nmea::make("GPRMC,123500.00,A,6000.0000,N,03000.0000,E,0.1,10.0,171126,,"), 9.0);
        CHECK(h.latestUtc(ut, at) && at == 9.0 && std::fabs(ut - (daysFromCivil(2026, 11, 17) * 86400.0 + 45300)) < 1e-6, "RMC: время и дата ддммгг");
        double la, lo; CHECK(h.toGeo(0, 0, la, lo) && std::fabs(lo - 30) < 1e-9, "долгота по местной системе координат");
    }
    if (argc >= 3) {
        std::vector<std::string> log;
        Core c({}, [&](const std::string& s) { log.push_back(s); });
        c.command(std::string("ship load ") + argv[1]); c.command(std::string("sim start ") + argv[2]);
        for (int i = 0; i < 50; ++i) c.cycle();
        c.command("time");
        bool st = false; for (auto& s : log) if (s.find("Судовое время") != std::string::npos && s.find("компьютер") != std::string::npos) st = true;
        CHECK(st, "имитация: time — судовое время по часам компьютера");
        log.clear(); c.command("zone +5:30");
        CHECK(c.shipTime().zoneMin() == 330 && !log.empty() && log.back().find("UTC+5:30") != std::string::npos, "zone +5:30 — пояс задан");
        log.clear(); c.command("zone 99"); CHECK(!log.empty() && log.back().find("Формат") != std::string::npos, "неверный пояс отклонён");
    }
    std::printf(fails ? "ПРОВАЛЕНО: %d\n" : "ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ\n", fails);
    return fails ? 1 : 0;
}
