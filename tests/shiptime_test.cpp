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
    { double u2; CHECK(!nmeaUtc("120000", 31, 2, 2026, u2) && !nmeaUtc("120000", 31, 4, 2026, u2) && nmeaUtc("120000", 29, 2, 2028, u2), "31.02 и 31.04 отклоняются, 29.02.2028 — нет"); }
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
        st.feedGnss(u + 1.0 + 30.0, 2.0); m.clear(); st.update(2.05, u + 31.05, false, 0, false, m, inf);
        CHECK(!has(m, "TIME_JUMP"), "одиночный выброс времени GNSS — ещё не скачок");
        st.feedGnss(u + 1.1 + 30.0, 2.1); m.clear(); st.update(2.15, u + 31.15, false, 0, false, m, inf);
        CHECK(has(m, "TIME_JUMP"), "время GNSS прыгнуло на 30 с (два приёма подряд) — TIME_JUMP");
        m.clear(); st.update(20.0, pc + 20, false, 0, false, m, inf);
        CHECK(!st.usingGnss(), "GNSS устарело — запасной источник: компьютер");
        st.setSource(ShipTime::Pc); st.feedGnss(u + 100, 30.0); m.clear(); st.update(30.1, pc + 50, false, 0, false, m, inf);
        CHECK(!st.usingGnss() && std::fabs(st.utc() - (pc + 50)) < 1e-6, "выбран компьютер — GNSS не используется");
        CHECK(has(m, "TIME_PC_DIFF"), "но расхождение с GNSS всё равно показывается");
        ShipTime s2; m.clear(); s2.feedGnss(u, 1.0); s2.update(1.0, u + 99, false, 0, true, m, inf);
        CHECK(!s2.usingGnss() && m.empty(), "в имитации — часы компьютера, без предупреждений");
    }
    {
        std::vector<TimeMsg> m; std::vector<std::string> inf; bool j = false;
        ShipTime a;   // два приёмника, время различается на 3 с, — не скачок
        for (int i = 0; i < 10; ++i) { a.feedGnss(u + i, i, "G1"); a.feedGnss(u + i + 3.0, i + 0.5, "G2"); m.clear(); a.update(i + 0.6, u + i + 0.6, false, 0, false, m, inf); j = j || has(m, "TIME_JUMP"); }
        CHECK(!j, "два приёмника с разным временем — TIME_JUMP нет");
        ShipTime a2; int flipsPc = 0, back = 0; bool wasPc = false, rxd = false; double prev = 0;
        for (int i = 0; i < 40; ++i) {
            const double t0 = i * 0.5; if (i % 2 == 0) a2.feedGnss(u + t0, t0, "G1"); else a2.feedGnss(u + t0 + 3.0, t0, "G2");
            m.clear(); a2.update(t0 + 0.1, u + t0 + 0.1, false, 0, false, m, inf);
            const bool pc = has(m, "TIME_PC_DIFF"); if (i > 0 && pc != wasPc) ++flipsPc; wasPc = pc; rxd = rxd || has(m, "TIME_RX_DIFF");
            if (i > 0 && a2.utc() < prev) ++back; prev = a2.utc();
        }
        CHECK(flipsPc == 0 && back == 0 && rxd, "два приёмника на 3 с врозь: показ по основному без скачков, одно TIME_RX_DIFF");
        ShipTime g; for (int i = 0; i < 5; ++i) g.feedGnss(u + i, i, "G"); g.feedGnss(u + 40 + 3600, 40, "G"); m.clear(); g.update(40.1, u + 40.1, false, 0, false, m, inf);
        CHECK(has(m, "TIME_JUMP"), "перерыв больше 30 с и возврат со скачком на 1 ч — TIME_JUMP");
        ShipTime b; j = false;   // пачка строк из буфера: 4 строки за 1 с с задержкой до 1,5 с, дальше ровно
        for (int i = 0; i < 5; ++i) b.feedGnss(u + i, i, "G");
        for (int k2 = 1; k2 <= 4; ++k2) { b.feedGnss(u + 4 + k2 * 0.5, 6.0 + 0.25 * k2, "G"); m.clear(); b.update(6.0 + 0.25 * k2, u + 6, false, 0, false, m, inf); j = j || has(m, "TIME_JUMP"); }
        for (int i = 8; i < 12; ++i) { b.feedGnss(u + i, i, "G"); m.clear(); b.update(i + 0.1, u + i + 0.1, false, 0, false, m, inf); j = j || has(m, "TIME_JUMP"); }
        CHECK(!j, "пачка строк из буфера с задержкой до 1,5 с — TIME_JUMP нет");
        ShipTime c; j = false;   // замёрзшее время: приёмник шлёт одно и то же
        for (int i = 0; i < 5; ++i) c.feedGnss(u + i, i, "G");
        for (int i = 5; i < 15; ++i) { c.feedGnss(u + 4, i, "G"); m.clear(); c.update(i + 0.1, u + i + 0.1, false, 0, false, m, inf); j = j || has(m, "TIME_JUMP"); }
        CHECK(j, "замёрзшее время GNSS — TIME_JUMP");
        ShipTime d; j = false;   // плавный увод 0,5 с за секунду
        for (int i = 0; i < 20; ++i) { d.feedGnss(u + i * 1.5, i, "G"); m.clear(); d.update(i + 0.1, u + i + 0.1, false, 0, false, m, inf); j = j || has(m, "TIME_JUMP"); }
        CHECK(j, "увод времени GNSS — TIME_JUMP");
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
        m.clear(); st.update(6, u, true, INFINITY, false, m, inf); st.update(7, u, true, NAN, false, m, inf);
        CHECK(st.suggestMin() == -300, "нечисловая долгота отбрасывается (без зависания)");
        ShipTime e; int flips = 0; bool was = false;
        e.update(0, u, true, 179.9, false, m, inf);
        for (int i = 1; i <= 10; ++i) { m.clear(); e.update(i, u, true, i % 2 ? -179.9 : 179.9, false, m, inf); const bool z = has(m, "TIME_ZONE"); if (z != was) ++flips; was = z; }
        CHECK(flips == 0, "у 180° пояс не дребезжит");
    }

    std::printf("-- хаб и ядро --\n");
    {
        SensorHub h; ChannelCfg ch; ch.id = "G"; ch.kind = ChannelKind::Gnss; h.addChannel(ch); h.setOrigin(60, 30);
        double ut = 0, at = 0;
        h.ingest("G", nmea::make("GPZDA,123456.00,17,11,2026,00,00"), 5.0);
        auto last = [&](double& ut_, double& at_) { auto v = h.gnssUtc(); if (v.empty()) return false; ut_ = v[0].utc; at_ = v[0].at; return true; };
        CHECK(last(ut, at) && std::fabs(ut - (daysFromCivil(2026, 11, 17) * 86400.0 + 45296)) < 1e-6 && at == 5.0, "ZDA принят по умолчанию, время UTC");
        h.ingest("G", nmea::make("GPRMC,123500.00,A,6000.0000,N,03000.0000,E,0.1,10.0,171126,,"), 9.0);
        CHECK(last(ut, at) && at == 9.0 && std::fabs(ut - (daysFromCivil(2026, 11, 17) * 86400.0 + 45300)) < 1e-6, "RMC: время и дата ддммгг");
        h.ingest("G", nmea::make("GPRMC,123600.00,A,6000.0000,N,03000.0000,E,0.1,10.0,1a1126,,"), 12.0);
        CHECK(last(ut, at) && at == 9.0, "RMC с датой не из цифр — время не берётся");
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
        log.clear(); c.command("zone --3"); bool f1 = !log.empty() && log.back().find("Формат") != std::string::npos;
        log.clear(); c.command("zone 5abc"); CHECK(f1 && !log.empty() && log.back().find("Формат") != std::string::npos && c.shipTime().zoneMin() == 330, "«zone --3» и «zone 5abc» отклонены");
    }
    std::printf(fails ? "ПРОВАЛЕНО: %d\n" : "ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ\n", fails);
    return fails ? 1 : 0;
}
