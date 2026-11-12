// Служба ядра СДП без окна. Посты оператора (sdp_hmi --connect адрес:порт --station A) подключаются по сети.
// Если все посты отключились, судно продолжает удерживать уставку.
#include <clocale>
#include <csignal>
#include <cstdio>
#include <iostream>
#ifndef _WIN32
#include <termios.h>
#include <unistd.h>
#else
#include <windows.h>
#endif

#include "dp/service.hpp"

using namespace dp;

static std::atomic<bool> g_stop{false};
static void onSignal(int) { g_stop = true; }

// Ввод пароля без отображения символов (терминал). Если ввод не с терминала (например, из канала), читается обычная строка.
static std::string readSecret(const char* prompt) {
    std::printf("%s", prompt); std::fflush(stdout);
    std::string r;
#ifndef _WIN32
    termios oldt{}; const bool tty = isatty(0) && tcgetattr(0, &oldt) == 0;
    if (tty) { termios t = oldt; t.c_lflag &= ~static_cast<tcflag_t>(ECHO); tcsetattr(0, TCSANOW, &t); }
    std::getline(std::cin, r);
    if (tty) { tcsetattr(0, TCSANOW, &oldt); std::printf("\n"); }
#else
    HANDLE h = GetStdHandle(STD_INPUT_HANDLE); DWORD mode = 0; const bool tty = GetConsoleMode(h, &mode) != 0;
    if (tty) SetConsoleMode(h, mode & ~static_cast<DWORD>(ENABLE_ECHO_INPUT));
    std::getline(std::cin, r);
    if (tty) { SetConsoleMode(h, mode); std::printf("\n"); }
#endif
    while (!r.empty() && (r.back() == '\r' || r.back() == '\n')) r.pop_back();
    return r;
}

int main(int argc, char** argv) {
    std::setlocale(LC_ALL, "C");
    std::string path; int port = 5300; double duration = -1, speedOverride = -1; bool quiet = false;
    std::string dataDir = "sdp_data"; bool setPw = false;
    const char* usage = "Использование: sdp_core <настройки.json> [--port 5300] [--speed множитель] [--duration с] [--quiet] [--data-dir папка] [--set-admin-password]\n"
                        "  --data-dir            папка данных администратора (пароль, профиль судна, журнал), по умолчанию sdp_data\n"
                        "  --set-admin-password  задать или сменить пароль администратора на этом компьютере и выйти\n";
    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        if (a == "--port" && i + 1 < argc) port = std::atoi(argv[++i]);
        else if (a == "--speed" && i + 1 < argc) speedOverride = std::atof(argv[++i]);
        else if (a == "--duration" && i + 1 < argc) duration = std::atof(argv[++i]);
        else if (a == "--quiet") quiet = true;
        else if (a == "--data-dir" && i + 1 < argc) dataDir = argv[++i];
        else if (a == "--set-admin-password") setPw = true;
        else if (a == "--help" || a == "-h") { std::printf("%s%s", usage, Runtime::helpText()); return 0; }
        else if (path.empty()) path = a;
        else { std::printf("Неизвестный параметр: %s\n", a.c_str()); return 2; }
    }
    if (setPw) {   // пароль задаётся только на компьютере ядра; действующий пароль для замены не нужен (доступ к компьютеру — это и есть право сменить)
        AdminService a(dataDir);
        const std::string p1 = readSecret("Новый пароль администратора: "), p2 = readSecret("Повторите пароль: ");
        if (p1 != p2) { std::printf("ОШИБКА: пароли не совпадают\n"); return 2; }
        { const std::string why = AdminService::checkNewPassword(p1); if (!why.empty()) { std::printf("ОШИБКА: %s. Прежний пароль не изменён.\n", why.c_str()); return 2; } }
        if (a.passwordSet()) {
            std::printf("Пароль уже задан. Замена пароля с компьютера ядра записывается в журнал. ");
            std::error_code ec; std::filesystem::remove(dataDir + "/admin.json", ec);
            if (ec) { std::printf("ОШИБКА: не удалось заменить файл пароля\n"); return 2; }
            a.audit("консоль", "файл пароля удалён для замены с компьютера ядра");
        }
        AdminService b(dataDir);
        const std::string rq = "{\"op\":\"setup\",\"pw\":\"" + vio::esc(p1) + "\"}";
        json::Value v; std::string e; json::parse(rq, v, e);
        const std::string rep = b.handle("local-console", v);
        json::Value r; json::parse(rep, r, e);
        const json::Value* ok = r.find("ok"); const json::Value* er = r.find("err");
        if (ok && ok->b) { std::printf("Пароль администратора задан. Папка данных: %s\n", dataDir.c_str()); return 0; }
        std::printf("ОШИБКА: %s\n", er ? er->s.c_str() : "?"); return 2;
    }
    if (path.empty()) { std::printf("%s", usage); return 2; }
    AppCfg cfg; json::Report rep;
    const bool ok = loadConfig(path, cfg, rep);
    for (auto& w : rep.warnings) std::printf("Предупреждение: %s\n", w.c_str());
    for (auto& e : rep.errors) std::printf("ОШИБКА: %s\n", e.c_str());
    if (!ok) return 2;
    if (!cfg.simEnabled && cfg.inputs.empty()) { std::printf("ОШИБКА: не включён имитатор и не заданы входы датчиков (inputs)\n"); return 2; }
    if (speedOverride > 0) cfg.simSpeed = speedOverride;
    const double statusPeriod = cfg.statusPeriodS;

    std::signal(SIGINT, onSignal);
    CoreService svc(cfg, port, dataDir);
    std::string err;
    if (!svc.start(err)) { std::printf("ОШИБКА: %s\n", err.c_str()); return 2; }
    std::printf("Ядро запущено: судно «%s», %s. Посты подключаются к порту %d. Ctrl+C — выход.\n", cfg.vessel.name.c_str(), cfg.simEnabled ? "режим имитации" : "реальные входы", port);

    std::mutex qm; std::deque<std::string> inq;
    std::thread([&] { std::string line; while (std::getline(std::cin, line)) { std::lock_guard<std::mutex> lk(qm); inq.push_back(line); } }).detach();

    double nextStatus = 0;
    while (!g_stop && !svc.quitRequested()) {
        { std::deque<std::string> q; { std::lock_guard<std::mutex> lk(qm); q.swap(inq); } for (auto& l : q) svc.command(l); }
        for (auto& m : svc.takeLog()) std::printf("%s\n", m.c_str());
        const OpSnap s = svc.snapshot();
        if (!quiet && s.t >= nextStatus && s.t > 0) {
            nextStatus = s.t + statusPeriod;
            const OpControl c = svc.server() ? svc.server()->control() : OpControl();
            std::string st; for (auto& x : c.stations) st += (st.empty() ? "" : ",") + x;
            std::printf("[t=%6.0f с] %s | N=%.1f E=%.1f курс=%.1f° | ошибка %.2f м, %.2f° | загрузка %.0f %% | тревог: %zu | посты: %s, управление: %s\n",
                        s.t, s.modeText.c_str(), s.n, s.e, s.psiDeg, s.errDist, s.errHdg, 100 * s.util, s.alarms.size(), st.empty() ? "нет" : st.c_str(), c.holder.empty() ? "нет" : c.holder.c_str());
        }
        if (duration > 0 && s.t >= duration) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    svc.stop();
    std::printf("Остановлено.\n");
    std::fflush(stdout);
    std::_Exit(0);     // поток чтения stdin заблокирован в getline: обычный выход зависает при открытом канале
}
