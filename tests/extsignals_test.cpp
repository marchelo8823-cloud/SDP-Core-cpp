// v0.25: сигналы пропульсивного комплекса во внешней связи (группы, сверка, пределы отправки, автоотключение) и источники данных (порты, интерфейсы, проверка линии).
#include <cstdio>
#include <chrono>
#include <thread>
#include "dp/config.hpp"
#include "dp/extlink.hpp"
#include "dp/runtime.hpp"
#include "dp/rights.hpp"
#include "dp/sources.hpp"

using namespace dp;
static int fails = 0;
#define CHECK(c, msg) do { const bool ok_ = (c); std::printf("%s %s\n", ok_ ? "  ok " : "FAIL ", msg); if (!ok_) ++fails; } while (0)

int main(int argc, char** argv) {
    if (argc < 2) return 2;
    AppCfg cfg; json::Report rep; if (!loadConfig(argv[1], cfg, rep)) { std::printf("настройки не прочитаны\n"); return 2; }
    const std::string js = R"({"vendor":"praxis","lostS":1,"inputs":[{"id":"P","kind":"gnss","transport":{"type":"udp","bind":"127.0.0.1","port":55411}}],
        "fields":[{"name":"AZ1_rpm","prefix":"$PRPM","index":2,"group":"feedback","unit":"об/мин","ch":"P"},
                  {"name":"AZ1_ang","prefix":"$PAZ","index":2,"group":"feedback","unit":"°","cmp":"AZ1.angle"},
                  {"name":"BUS_A_kW","prefix":"$PPWR","index":1,"group":"power","unit":"кВт"},
                  {"name":"AZ1_cmd","prefix":"$PCMD","index":2,"group":"command"}],
        "templates":[{"name":"thr","text":"$PTHR,{pct}","minIntervalS":0.3,"limits":[{"name":"pct","min":-50,"max":50}]}],
        "tx":{"type":"udp","host":"127.0.0.1","port":55412}})";
    ExtLinkCfg c; std::string err;
    CHECK(parseExtLink(js, c, err), "разбор таблицы сигналов с группами, пределами и интервалом");
    CHECK(c.fields.size() == 4 && c.fields[0].group == "feedback" && c.fields[0].unit == "об/мин" && c.fields[1].cmp == "AZ1.angle" && c.templates[0].limits.size() == 1, "группа, единицы, вход, сверка и предел прочитаны");
    ExtLinkCfg c2; CHECK(parseExtLink(extLinkToJson(c), c2, err) && c2.fields[1].cmp == "AZ1.angle" && c2.templates[0].limits[0].hi == 50 && c2.templates[0].minIntervalS == 0.3, "запись в JSON и чтение обратно без потерь");
    CHECK(!parseExtLink(R"({"inputs":[],"fields":[{"name":"x","prefix":"$P","group":"что-то"}]})", c2, err), "неизвестная группа отклоняется");

    ExtLink x(c);
    double t = monotonicSeconds();
    x.onLine("P", "$PRPM,AZ1,148.5*00", t); x.onLine("P", "$PAZ,AZ1,92.0*00", t); x.onLine("P", "$PPWR,1250.0*00", t); x.onLine("Q", "$PRPM,AZ1,5*00", t);
    LocalFrame fr;
    ExtStatus s = x.status(t + 0.1, 0, 0, 0, fr);
    CHECK(s.sig.size() == 4, "в состоянии все сигналы таблицы");
    CHECK(s.sig[0].has && std::fabs(s.sig[0].value - 148.5) < 1e-9 && s.sig[0].group == "feedback", "обратная связь движителя принята");
    CHECK(s.sig[2].has && s.sig[2].value == 1250.0 && s.sig[2].group == "power", "сигнал энергосистемы принят");
    CHECK(!s.sig[3].has, "сигнал, которого не было, помечен как «нет данных»");
    x.onLine("Q", "$PRPM,AZ1,5*00", t); s = x.status(t + 0.1, 0, 0, 0, fr);
    CHECK(std::fabs(s.sig[0].value - 148.5) < 1e-9, "строка из другого входа не попадает в сигнал с фильтром входа");

    // отправка: пределы, интервал, автоотключение при потере связи
    std::string why, out;
    CHECK(x.setActive(true, "ДА-praxis", why), "активный режим включается вручную с кодом");
    CHECK(!x.send("thr", {{"pct", "80"}}, out, why) && why.find("вне допустимого") != std::string::npos, "значение вне предела не отправляется");
    CHECK(!x.send("thr", {}, out, why) && why.find("pct") != std::string::npos, "без обязательного параметра не отправляется");
    CHECK(!x.send("thr", {{"pct", "abc"}}, out, why), "не число не отправляется");
    CHECK(x.send("thr", {{"pct", "30"}}, out, why) && out == "$PTHR,30", "значение в пределах отправляется");
    CHECK(!x.send("thr", {{"pct", "31"}}, out, why) && why.find("слишком часто") != std::string::npos, "слишком частая отправка отклоняется");
    std::this_thread::sleep_for(std::chrono::milliseconds(350));
    CHECK(x.send("thr", {{"pct", "-20"}}, out, why), "после паузы отправка снова разрешена");
    s = x.status(t + 5.0, 0, 0, 0, fr);
    CHECK(!s.active && !x.active() && !s.note.empty(), "потеря связи выключает активный режим сама");

    // сверка с нашими величинами и интерфейс команд
    {
        AppCfg a = cfg; a.extlink = c; a.extlink.enabled = true;
        std::string say;
        Runtime r(a, [&](const std::string& m) { say = m; });
        r.cycle();
        r.command("ext inject P|$PAZ,AZ1,10.0*00"); r.cycle();
        const std::string j = r.extJson();
        CHECK(j.find("\"sig\":[") != std::string::npos && j.find("\"name\":\"AZ1_ang\"") != std::string::npos && j.find("\"group\":\"feedback\"") != std::string::npos, "в состоянии окна есть таблица сигналов с группами");
        CHECK(j.find("\"cmp\":\"AZ1.angle\"") != std::string::npos, "в состоянии окна есть правило сверки");
        CHECK(isSetupCommand("src test {}") && !isSetupCommand("src list") && !isSetupCommand("src watch on"), "проверка линии — команда настройки, список и просмотр открыты");
        r.command("src watch on"); r.command("src list");
        const std::string cj = r.capJson();
        CHECK(cj.find("\"src\":{\"list\":{\"ports\":[") != std::string::npos && cj.find("\"ifs\":[") != std::string::npos, "список портов и интерфейсов в состоянии при включённом просмотре");
        r.command("src watch off");
        CHECK(r.capJson().find("\"src\"") == std::string::npos, "без просмотра список не передаётся");
    }
    // источники данных
    {
        const auto ifs = src::listInterfaces(); bool lo = false; for (auto& i : ifs) if (i.loop && i.ip == "127.0.0.1") lo = true;
#ifdef _WIN32
        lo = true;
#endif
        CHECK(lo, "сетевые интерфейсы: виден 127.0.0.1");
        json::Value v; std::string e; CHECK(json::parse(src::listJson(), v, e), "список источников — корректный JSON");
        cap::EpCfg ep; ep.type = "udp"; ep.bind = "127.0.0.1"; ep.port = 55413;
        src::LineTest lt; std::string why2; CHECK(lt.start(ep, 1.5, why2), "проверка линии запущена");
        std::this_thread::sleep_for(std::chrono::milliseconds(400));
        { SockT s2 = ::socket(AF_INET, SOCK_DGRAM, 0); sockaddr_in a{}; a.sin_family = AF_INET; a.sin_port = htons(55413); ::inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
          for (int i = 0; i < 5; ++i) ::sendto(s2, "hello\r\n", 7, 0, reinterpret_cast<sockaddr*>(&a), sizeof a); sockClose(s2); }
        std::this_thread::sleep_for(std::chrono::milliseconds(1500));
        const std::string tj = lt.json();
        CHECK(tj.find("\"state\":\"done\"") != std::string::npos && tj.find("поток идёт") != std::string::npos && tj.find("\"bytes\":35") != std::string::npos, "проверка линии: поток идёт, 35 байт");
        cap::EpCfg ep2; ep2.type = "serial"; ep2.device = "/dev/нет_такого_порта"; ep2.baud = 9600;
        src::LineTest l2; l2.start(ep2, 1.0, why2); std::this_thread::sleep_for(std::chrono::milliseconds(1400));
        CHECK(l2.json().find("линия не открылась") != std::string::npos, "несуществующий порт: «линия не открылась»");
        cap::EpCfg ep3; ep3.type = "udp"; ep3.bind = "127.0.0.1"; ep3.port = 55414;
        src::LineTest l3; l3.start(ep3, 1.0, why2); std::this_thread::sleep_for(std::chrono::milliseconds(1400));
        CHECK(l3.json().find("данных нет") != std::string::npos, "линия открыта, но данных нет");
    }
    std::printf("%s\n", fails ? "ЕСТЬ ОШИБКИ" : "все проверки пройдены");
    return fails ? 1 : 0;
}
