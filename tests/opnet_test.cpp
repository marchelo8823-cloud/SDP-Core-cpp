// Проверка сети постов оператора: два поста, передача управления, потеря связи, отказ чужому, кодирование снимка.
#include <cstdio>
#include <clocale>
#include <set>

#include "dp/service.hpp"

using namespace dp;
static int fails = 0;
#define CHECK(c, msg) do { if (!(c)) { std::printf("  [ПРОВАЛ] %s\n", msg); ++fails; } else std::printf("  [ок] %s\n", msg); } while (0)
static void sleepMs(int ms) { std::this_thread::sleep_for(std::chrono::milliseconds(ms)); }

struct Post {
    std::mutex m; OpSnap snap; OpControl ctl; OpStatic info; int snaps = 0, hist = 0, samples = 0; std::vector<std::string> log; std::string err;
    std::unique_ptr<OpClient> cl;
    Post(const std::string& name, int port) {
        cl.reset(new OpClient("127.0.0.1", port, name, [this](const json::Value& v) {
            std::lock_guard<std::mutex> lk(m);
            const std::string t = js(v, "t");
            if (t == "snap") { snap = decodeSnap(v); ++snaps; }
            else if (t == "ctl") ctl = decodeCtl(v);
            else if (t == "static") info = decodeStatic(v);
            else if (t == "hist") hist = static_cast<int>(ja(v, "s").size());
            else if (t == "s") ++samples;
            else if (t == "log") log.push_back(js(v, "m"));
            else if (t == "err") err = js(v, "m");
        }));
        cl->start();
    }
    OpControl c() { std::lock_guard<std::mutex> lk(m); return ctl; }
    OpSnap s() { std::lock_guard<std::mutex> lk(m); return snap; }
    bool logHas(const std::string& sub) { std::lock_guard<std::mutex> lk(m); for (auto& l : log) if (l.find(sub) != std::string::npos) return true; return false; }
};
template <class F> static bool waitFor(F f, int ms = 4000) { for (int t = 0; t < ms; t += 20) { if (f()) return true; sleepMs(20); } return f(); }

int main(int argc, char** argv) {
    std::setlocale(LC_ALL, "C");
    const std::string cfgPath = argc > 1 ? argv[1] : "config/demo.json";
    AppCfg cfg; json::Report rep;
    if (!loadConfig(cfgPath, cfg, rep)) { std::printf("не удалось прочитать %s\n", cfgPath.c_str()); return 2; }
    cfg.simSpeed = 20;
    const int port = 5391;

    std::printf("1. Кодирование снимка туда и обратно\n");
    {
        OpSnap a; a.t = 12.5; a.n = 123.456; a.e = -7.25; a.psiDeg = 270.5; a.modeText = "Удержание позиции"; a.lawText = "ПИД"; a.posValid = true; a.lat0 = 59.9; a.lon0 = 30.3; a.frameValid = true;
        a.vn = 0.12; a.ve = -0.34; a.waveHs = 2.4; a.waveTz = 7.5; a.waveTp = 8.1; a.waveFromDeg = 215; a.waveConf = 0.9; a.waveSeconds = 300; a.waveValid = true; a.waveDirValid = true;
        a.rollDeg = 1.5; a.pitchDeg = -0.7; a.heaveM = 0.9; a.mruCount = 3; a.mruValid = true; a.mruDisagree = true; a.highGain = true; a.minPower = true; a.simOn = true; a.simWindSpeed = 17; a.simHs = 3.5; a.simFailed = "GNSS1 MRU1"; a.simThrFailed = "VRK_P"; a.simMods = "GNSS1 сдвиг +15.0/-10.0 м; "; a.posValid = true; a.hdgValid = false;
        SensorStatus ss; ss.id = "P:GNSS1"; ss.valid = true; ss.ageS = 0.2; a.sensors.push_back(ss);
        LinkStatus lk; lk.id = "ctrl"; lk.connected = true; a.links.push_back(lk);
        ThrusterView t; t.id = "AZ1"; t.type = ThrusterType::Azimuth; t.pct = 33.3; t.angleDeg = 45; t.x = -25.5; t.y = 4.25; t.fixedAngleDeg = 90; a.th.push_back(t);
        Alarm al; al.code = "HIGH_LOAD"; al.text = "Загрузка выше 90 %"; al.critical = true; a.alarms.push_back(al);
        json::Value v; std::string e; const bool pr = json::parse(encodeSnap(a), v, e);
        CHECK(pr, "снимок разбирается как JSON");
        const OpSnap b = decodeSnap(v);
        CHECK(std::fabs(b.n - 123.456) < 1e-6 && std::fabs(b.e + 7.25) < 1e-9 && std::fabs(b.lat0 - 59.9) < 1e-9, "числа сохраняются");
        CHECK(std::fabs(b.vn - 0.12) < 1e-9 && std::fabs(b.ve + 0.34) < 1e-9, "скорость над грунтом сохраняется");
        CHECK(b.waveValid && b.waveDirValid && std::fabs(b.waveHs - 2.4) < 1e-9 && std::fabs(b.waveTz - 7.5) < 1e-9 && std::fabs(b.waveFromDeg - 215) < 1e-9 && std::fabs(b.waveConf - 0.9) < 1e-9, "оценка волнения сохраняется");
        CHECK(b.highGain && b.minPower, "усиление и минимальная мощность доходят до поста");
        CHECK(b.simOn && std::fabs(b.simWindSpeed - 17) < 1e-9 && std::fabs(b.simHs - 3.5) < 1e-9 && b.simFailed == "GNSS1 MRU1" && b.simThrFailed == "VRK_P" && b.simMods == a.simMods, "состояние имитатора доходит до поста");
        CHECK(std::fabs(b.rollDeg - 1.5) < 1e-9 && std::fabs(b.pitchDeg + 0.7) < 1e-9 && std::fabs(b.heaveM - 0.9) < 1e-9 && b.mruCount == 3 && b.mruValid && b.mruDisagree && !b.hdgValid, "показания МИО сохраняются, признак курса не затёрт");
        CHECK(b.sensors.size() == 1 && b.sensors[0].id == "P:GNSS1" && b.links.size() == 1 && b.links[0].connected, "датчики и каналы сохраняются");
        {   // в одном объекте JSON не должно быть повторяющихся ключей (разбор берёт первый и молча теряет второй)
            std::function<bool(const json::Value&)> uniq = [&](const json::Value& x) {
                std::set<std::string> seen;
                for (auto& kv : x.o) { if (!seen.insert(kv.first).second) return false; if (!uniq(kv.second)) return false; }
                for (auto& e2 : x.a) if (!uniq(e2)) return false;
                return true;
            };
            CHECK(uniq(v), "в снимке нет повторяющихся ключей");
        }
        CHECK(b.modeText == a.modeText && b.th.size() == 1 && b.th[0].id == "AZ1" && b.alarms.size() == 1 && b.alarms[0].critical, "текст, движители и тревоги сохраняются");
        CHECK(std::fabs(b.th[0].x + 25.5) < 1e-9 && std::fabs(b.th[0].y - 4.25) < 1e-9 && b.th[0].fixedAngleDeg == 90, "положение движителей на судне сохраняется");
    }

    std::printf("2. Ядро с двумя постами\n");
    CoreService svc(cfg, port, "sdp_test_data");
    std::string err;
    CHECK(svc.start(err), "ядро запущено, порт открыт");
    Post A("A", port);
    CHECK(waitFor([&] { return A.s().t > 1; }), "пост A получает состояние");
    CHECK(waitFor([&] { return A.c().holder == "A"; }), "первый пост получил управление");
    Post B("B", port);
    CHECK(waitFor([&] { return B.s().t > 1 && B.c().stations.size() == 2; }), "пост B подключился и видит оба поста");
    { std::lock_guard<std::mutex> lk(B.m); CHECK(B.info.ship == cfg.vessel.name && B.hist > 0, "пост B получил описание судна и историю графиков"); }
    CHECK(B.c().holder == "A", "у поста B управления нет");

    std::printf("3. Команды только от поста с управлением\n");
    CHECK(waitFor([&] { return A.s().mode >= 2; }, 20000), "режим удержания включился");
    sleepMs(300);
    const double n0 = A.s().spN;
    B.cl->command("move 25 0");
    CHECK(waitFor([&] { return B.logHas("нет управления"); }), "команда с поста B отклонена с пояснением");
    sleepMs(300);
    CHECK(std::fabs(A.s().spN - n0) < 0.5, "уставка не изменилась");
    A.cl->command("move 25 0");
    CHECK(waitFor([&] { return std::fabs(B.s().spN - (n0 + 25)) < 0.5; }), "команда поста A выполнена, оба поста видят новую уставку");
    A.cl->command("quit");
    sleepMs(300);
    CHECK(!svc.quitRequested(), "команда quit по сети не останавливает ядро");

    std::printf("4. Передача управления\n");
    B.cl->take(false);
    CHECK(waitFor([&] { return A.c().requester == "B" && A.c().holder == "A"; }), "запрос поста B виден посту A, управление пока у A");
    A.cl->give();
    CHECK(waitFor([&] { return B.c().holder == "B" && B.c().requester.empty(); }), "пост A передал управление посту B");
    B.cl->command("move -25 0");
    CHECK(waitFor([&] { return std::fabs(A.s().spN - n0) < 0.5; }), "теперь команды принимаются от поста B");
    A.cl->take(true);
    CHECK(waitFor([&] { return A.c().holder == "A"; }), "принудительный приём управления работает");

    std::printf("5. Одинаковое имя поста\n");
    {
        Post A2("A", port);
        CHECK(waitFor([&] { std::lock_guard<std::mutex> lk(A2.m); return !A2.err.empty(); }), "второй пост «A» отвергнут");
    }

    std::printf("6. Потеря связи с постом\n");
    const double t0 = svc.snapshot().t;
    A.cl->stop();
    CHECK(waitFor([&] { return B.c().holder.empty(); }, 8000), "после потери поста A управление свободно");
    CHECK(waitFor([&] { return svc.snapshot().t > t0 + 1; }, 8000), "ядро продолжает работать");
    B.cl->take(false);
    CHECK(waitFor([&] { return B.c().holder == "B"; }), "пост B принимает свободное управление");
    sleepMs(200);
    B.cl->stop();
    sleepMs(300);
    const double t1 = svc.snapshot().t; sleepMs(800);
    CHECK(svc.snapshot().t > t1, "без постов ядро по-прежнему работает");
    svc.stop();
    if (fails) { std::printf("ПРОВАЛОВ: %d\n", fails); return 1; }
    std::printf("ИТОГ: всё в порядке\n");
    return 0;
}
