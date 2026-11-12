// Рабочая программа СДП (консольная): ядро + приём датчиков + вывод на контроллер.
// Режимы: с имитатором судна (sim.enabled = true) или с реальными входами (inputs) без имитатора.
#include <atomic>
#include <clocale>
#include <csignal>
#include <cstdio>
#include <iostream>

#include "dp/runtime.hpp"

using namespace dp;

static std::atomic<bool> g_stop{false};
static void onSignal(int) { g_stop = true; }

int main(int argc, char** argv) {
    std::setlocale(LC_ALL, "C");
    std::string path; double duration = -1, speedOverride = -1; bool checkOnly = false, quiet = false;
    const char* usage = "Использование: sdp_run <настройки.json> [--check] [--duration с] [--speed множитель] [--quiet]\n";
    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        if (a == "--duration" && i + 1 < argc) duration = std::atof(argv[++i]);
        else if (a == "--speed" && i + 1 < argc) speedOverride = std::atof(argv[++i]);
        else if (a == "--check") checkOnly = true;
        else if (a == "--quiet") quiet = true;
        else if (a == "--help" || a == "-h") { std::printf("%s%s", usage, Runtime::helpText()); return 0; }
        else if (path.empty()) path = a;
        else { std::printf("Неизвестный параметр: %s\n", a.c_str()); return 2; }
    }
    if (path.empty()) { std::printf("%s", usage); return 2; }

    AppCfg cfg; json::Report rep;
    const bool ok = loadConfig(path, cfg, rep);
    for (auto& w : rep.warnings) std::printf("Предупреждение: %s\n", w.c_str());
    for (auto& e : rep.errors) std::printf("ОШИБКА: %s\n", e.c_str());
    if (!ok) return 2;
    if (!cfg.simEnabled && cfg.inputs.empty()) { std::printf("ОШИБКА: не включён имитатор и не заданы входы датчиков (inputs)\n"); return 2; }
    if (cfg.simEnabled && !cfg.inputs.empty()) std::printf("Предупреждение: в режиме имитации входы inputs не используются.\n");
    if (speedOverride > 0) cfg.simSpeed = speedOverride;
    std::printf("Настройки приняты: судно «%s», движителей %zu, закон управления: %s, %s.\n", cfg.vessel.name.c_str(), cfg.thrusters.size(),
                cfg.control.law == LawType::Pid ? "ПИД" : cfg.control.law == LawType::Lqr ? "LQR" : "MPC",
                cfg.simEnabled ? "режим имитации" : "реальные входы");
    if (checkOnly) return 0;

    std::signal(SIGINT, onSignal);
    const bool simulated = cfg.simEnabled;
    const double speed = cfg.simSpeed, statusPeriod = cfg.statusPeriodS;
    Runtime rt(cfg, [](const std::string& s) { std::printf("%s\n", s.c_str()); });
    const double dt = rt.dt();

    std::mutex qm; std::deque<std::string> queue;
    std::thread([&] {
        std::string line;
        while (std::getline(std::cin, line)) { std::lock_guard<std::mutex> lk(qm); queue.push_back(line); }
    }).detach();

    std::printf("Работа начата. Введите help для списка команд, Ctrl+C — выход.\n");
    double nextStatus = 0;
    auto next = std::chrono::steady_clock::now();
    while (!g_stop && !rt.quitRequested()) {
        next += std::chrono::microseconds(static_cast<long long>(1e6 * dt / (simulated ? speed : 1.0)));
        { std::deque<std::string> q; { std::lock_guard<std::mutex> lk(qm); q.swap(queue); } for (auto& l : q) rt.command(l); }
        rt.cycle();
        if (rt.takeStatusRequest()) nextStatus = 0;
        const EngineOutput& o = rt.out();
        if (!quiet && rt.clock() >= nextStatus) {
            nextStatus = rt.clock() + statusPeriod;
            std::string al; for (auto& a : o.alarms) al += (al.empty() ? "" : ", ") + a.code;
            std::string ln;
            for (auto& s : rt.linkStatus()) ln += " " + s.id + (s.connected ? ":связь" : ":НЕТ СВЯЗИ") + (s.stale ? "(команды устарели)" : "");
            std::printf("[t=%6.0f с] %s | положение N=%.1f E=%.1f курс=%.1f° | ошибка %.2f м, %.2f° | ветер %.1f м/с | загрузка %.0f %% | тревоги: %s |%s\n",
                        rt.clock(), modeName(rt.engine().mode()), o.est.n, o.est.e, rad2deg(o.est.psi), o.ctl.errDist, o.ctl.errHdgDeg, o.est.windSpeed, 100 * o.alloc.utilization,
                        al.empty() ? "нет" : al.c_str(), ln.empty() ? " выход не настроен" : ln.c_str());
        }
        if (duration > 0 && rt.clock() >= duration) break;
        std::this_thread::sleep_until(next);
        if (std::chrono::steady_clock::now() > next + std::chrono::seconds(1)) next = std::chrono::steady_clock::now();   // не копим отставание
    }
    rt.stop();
    std::printf("Остановлено на %.0f с.\n", rt.clock());
    const RunStats st = rt.stats();
    if (st.seconds > 0) std::printf("ИТОГ после переходного процесса (%.0f с): ошибка положения среднеквадратичная %.2f м, наибольшая %.2f м; по курсу %.2f° и %.2f°.\n",
                                    st.seconds, st.rmsPos, st.maxPos, st.rmsHdg, st.maxHdg);
    // Поток чтения stdin заблокирован в getline: при открытом канале (ctest, запуск из другой программы) обычный выход зависал.
    std::fflush(stdout);
    std::_Exit(0);
}
