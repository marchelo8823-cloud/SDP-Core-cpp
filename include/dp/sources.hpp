// Физические источники данных: какие COM/USB-порты и сетевые интерфейсы есть на этом компьютере, и проверка линии
// (открывается ли порт, идёт ли поток, сколько байт). Только чтение: в линию ничего не отправляется.
// ⚠ Список интерфейсов и портов проверен на Linux; на macOS ожидаются /dev/cu.*, на Windows — COM1…COM64 (не проверялось).
#pragma once
#include <algorithm>
#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#ifndef _WIN32
#include <arpa/inet.h>
#include <dirent.h>
#include <ifaddrs.h>
#include <net/if.h>
#endif
#include "dp/capture.hpp"
#include "dp/vesselio.hpp"

namespace dp {
namespace src {

inline std::string q(const std::string& x) { return "\"" + vio::esc(x) + "\""; }

struct PortInfo { std::string name, kind; };
struct IfInfo { std::string name, ip; bool up = false, loop = false; };

inline std::vector<PortInfo> listPorts() {
    std::vector<PortInfo> r;
#ifdef _WIN32
    for (int i = 1; i <= 64; ++i) {
        char t[16], tg[260]; std::snprintf(t, sizeof t, "COM%d", i);
        if (QueryDosDeviceA(t, tg, sizeof tg)) r.push_back({t, "COM"});
    }
#else
    if (DIR* d = ::opendir("/dev")) {
        while (dirent* e = ::readdir(d)) {
            const std::string n = e->d_name;
            auto has = [&](const char* p) { return n.rfind(p, 0) == 0; };
            std::string kind;
            if (has("cu.")) kind = n.find("usb") != std::string::npos || n.find("USB") != std::string::npos ? "USB-COM" : (n.find("Bluetooth") != std::string::npos ? "Bluetooth" : "COM");
            else if (has("ttyUSB") || has("ttyACM")) kind = "USB-COM";
            else if (has("rfcomm") || has("ttyAMA") || has("ttyO")) kind = "COM";
            else if (has("ttyS") && n.size() <= 6) kind = "COM (встроенный)";
            if (!kind.empty()) r.push_back({"/dev/" + n, kind});
        }
        ::closedir(d);
    }
#endif
    std::sort(r.begin(), r.end(), [](const PortInfo& a, const PortInfo& b) { return a.name < b.name; });
    return r;
}

inline std::vector<IfInfo> listInterfaces() {
    std::vector<IfInfo> r;
#ifndef _WIN32
    ifaddrs* ifa = nullptr;
    if (::getifaddrs(&ifa) == 0) {
        for (ifaddrs* p = ifa; p; p = p->ifa_next) {
            if (!p->ifa_addr || p->ifa_addr->sa_family != AF_INET) continue;
            char b[64]; ::inet_ntop(AF_INET, &reinterpret_cast<sockaddr_in*>(p->ifa_addr)->sin_addr, b, sizeof b);
            IfInfo i; i.name = p->ifa_name; i.ip = b; i.up = (p->ifa_flags & IFF_UP) && (p->ifa_flags & IFF_RUNNING); i.loop = (p->ifa_flags & IFF_LOOPBACK) != 0;
            r.push_back(i);
        }
        ::freeifaddrs(ifa);
    }
#endif
    return r;
}

inline std::string listJson() {
    std::string j = "{\"ports\":[";
    auto p = listPorts(); for (size_t i = 0; i < p.size(); ++i) j += std::string(i ? "," : "") + "{\"name\":" + q(p[i].name) + ",\"kind\":" + q(p[i].kind) + "}";
    j += "],\"ifs\":[";
    auto f = listInterfaces(); for (size_t i = 0; i < f.size(); ++i) j += std::string(i ? "," : "") + "{\"name\":" + q(f[i].name) + ",\"ip\":" + q(f[i].ip) + ",\"up\":" + (f[i].up ? "true" : "false") + ",\"loop\":" + (f[i].loop ? "true" : "false") + "}";
    return j + "]}";
}

// Проверка одной линии: открывает её на несколько секунд, только слушает, считает принятое.
class LineTest {
public:
    ~LineTest() { join(); }
    bool running() const { return running_; }
    bool start(const cap::EpCfg& c, double seconds, std::string& why) {
        if (running_) { why = "проверка уже идёт"; return false; }
        join();
        { std::lock_guard<std::mutex> lk(m_); res_ = Result(); res_.desc = describe(c); res_.state = "run"; res_.total = seconds; }
        running_ = true;
        th_ = std::thread([this, c, seconds] {
            cap::Endpoint ep(c); std::string peerSeen; ep.start([&](const std::string&, const std::string& peer, bool) { if (peerSeen.empty()) peerSeen = peer; });
            const auto t0 = std::chrono::steady_clock::now(); bool everUp = false;
            while (true) {
                const double el = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
                if (el >= seconds) break;
                everUp = everUp || ep.connected();
                { std::lock_guard<std::mutex> lk(m_); res_.elapsed = el; res_.opened = everUp; res_.bytes = ep.rx(); res_.err = ep.error(); res_.peer = peerSeen; }
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }
            everUp = everUp || ep.connected();
            { std::lock_guard<std::mutex> lk(m_); res_.elapsed = seconds; res_.opened = everUp; res_.bytes = ep.rx(); res_.err = ep.error(); res_.peer = peerSeen; res_.state = "done"; }
            ep.stop(); running_ = false;
        });
        return true;
    }
    std::string json() const {
        std::lock_guard<std::mutex> lk(m_);
        if (res_.state.empty()) return "null";
        char b[64];
        std::string verdict;
        if (res_.state == "done") verdict = !res_.opened ? "линия не открылась" + (res_.err.empty() ? std::string() : ": " + res_.err) : (res_.bytes > 0 ? "поток идёт" : "линия открыта, но данных нет");
        std::snprintf(b, sizeof b, "%.1f", res_.elapsed);
        return "{\"desc\":" + q(res_.desc) + ",\"state\":" + q(res_.state) + ",\"t\":" + b + ",\"total\":" + std::to_string(static_cast<int>(res_.total)) + ",\"opened\":" + (res_.opened ? "true" : "false")
            + ",\"bytes\":" + std::to_string(res_.bytes) + ",\"peer\":" + q(res_.peer) + ",\"err\":" + q(res_.err) + ",\"verdict\":" + q(verdict) + "}";
    }
    static std::string describe(const cap::EpCfg& c) {
        if (c.type == "udp") return "UDP " + c.bind + ":" + std::to_string(c.port) + (c.group.empty() ? "" : " группа " + c.group);
        if (c.type == "tcpc") return "TCP-клиент " + c.host + ":" + std::to_string(c.port);
        if (c.type == "tcps") return "TCP-сервер " + c.bind + ":" + std::to_string(c.port);
        return "COM " + c.device + " " + std::to_string(c.baud) + " бод";
    }
private:
    void join() { if (th_.joinable()) th_.join(); }
    struct Result { std::string desc, state, err, peer; double elapsed = 0, total = 0; bool opened = false; long long bytes = 0; } res_;
    mutable std::mutex m_;
    std::atomic<bool> running_{false};
    std::thread th_;
};

}  // namespace src
}  // namespace dp
