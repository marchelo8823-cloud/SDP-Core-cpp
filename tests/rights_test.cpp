// Права постов: наблюдатель не принимает управление; пост без права «настройка» не меняет настройки; квитирование по праву ack.
#include <cstdio>
#include <clocale>
#include "dp/service.hpp"

using namespace dp;
static int fails = 0;
#define CHECK(c, msg) do { if (!(c)) { std::printf("  [ПРОВАЛ] %s\n", msg); ++fails; } else std::printf("  [ок] %s\n", msg); } while (0)
static void sleepMs(int ms) { std::this_thread::sleep_for(std::chrono::milliseconds(ms)); }
struct Post {
    std::mutex m; OpControl ctl; OpSnap snap; std::vector<std::string> log; std::unique_ptr<OpClient> cl;
    Post(const std::string& name, int port) {
        cl.reset(new OpClient("127.0.0.1", port, name, [this](const json::Value& v) {
            std::lock_guard<std::mutex> lk(m); const std::string t = js(v, "t");
            if (t == "ctl") ctl = decodeCtl(v); else if (t == "snap") snap = decodeSnap(v); else if (t == "log") log.push_back(js(v, "m"));
        }));
        cl->start();
    }
    OpControl c() { std::lock_guard<std::mutex> lk(m); return ctl; }
    bool logHas(const std::string& s) { std::lock_guard<std::mutex> lk(m); for (auto& l : log) if (l.find(s) != std::string::npos) return true; return false; }
};
template <class F> static bool waitFor(F f, int ms = 4000) { for (int t = 0; t < ms; t += 20) { if (f()) return true; sleepMs(20); } return f(); }

int main(int argc, char** argv) {
    std::setlocale(LC_ALL, "C");
    PostRights r; std::string why;
    CHECK(parsePostRights("control,ack,setup", why, &r) && r.control && r.ack && r.setup, "все права разбираются");
    CHECK(parsePostRights("view", why, &r) && !r.control && !r.ack && !r.setup, "view — без прав");
    CHECK(parsePostRights("ack", why, &r) && r.ack && !r.control, "только ack");
    CHECK(!parsePostRights("fly", why) && !why.empty(), "неизвестное право отклоняется");
    CHECK(!parsePostRights("setup", why), "setup без control отклоняется");
    CHECK(isSetupCommand("sensor GNSS1 accept GGA") && isSetupCommand("calib start") && !isSetupCommand("move 5 0") && !isSetupCommand("pivot 10 0"), "классификация команд");

    AppCfg cfg; json::Report rep;
    if (!loadConfig(argc > 1 ? argv[1] : "config/demo.json", cfg, rep)) { std::printf("не удалось прочитать настройки\n"); return 2; }
    cfg.simSpeed = 20; cfg.postRights = {{"OBS", "view"}, {"OP2", "control,ack"}};
    const int port = 5392;
    CoreService svc(cfg, port, "sdp_test_data_rights");
    std::string err; CHECK(svc.start(err), "ядро запущено");
    Post OBS("OBS", port);
    CHECK(waitFor([&] { return OBS.c().stations.size() == 1; }), "наблюдатель подключился");
    sleepMs(200);
    CHECK(OBS.c().holder.empty(), "наблюдатель не получает управление при подключении");
    OBS.cl->take(false); OBS.cl->take(true);
    CHECK(waitFor([&] { return OBS.logHas("нет права принимать управление"); }) && OBS.c().holder.empty(), "наблюдатель не может взять управление, даже принудительно");
    Post OP2("OP2", port);
    CHECK(waitFor([&] { return OP2.c().holder == "OP2"; }), "пост с правом control получает управление");
    OP2.cl->command("sensor GNSS1 accept GGA");
    CHECK(waitFor([&] { return OP2.logHas("нет права «настройка»"); }), "пост без права setup: команда настройки отклонена");
    Post OP3("OP3", port);
    CHECK(waitFor([&] { return OP3.c().stations.size() == 3; }), "пост без записи в настройках имеет все права");
    OP3.cl->take(true);
    CHECK(waitFor([&] { return OP3.c().holder == "OP3"; }), "пост с полными правами принимает управление принудительно");
    OP3.cl->command("sensor GNSS1 accept GGA");
    sleepMs(300);
    CHECK(!OP3.logHas("нет права"), "пост с правом setup настраивает");
    OBS.cl->command("silence");
    sleepMs(300);
    CHECK(OBS.logHas("нет управления"), "наблюдатель без права ack не может квитировать");
    svc.stop();
    std::printf(fails ? "ПРОВАЛ: %d\n" : "Все проверки пройдены\n", fails);
    return fails ? 1 : 0;
}
