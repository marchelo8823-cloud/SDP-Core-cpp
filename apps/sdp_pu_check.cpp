// Проверка книги сопряжения СДП с пультами управления движителями (ПУ).
// sdp_pu_check <книга ПУ> [--registry <реестр.csv>] [--ship <книга судна>]
// По умолчанию реестр — data/ПУ_реестр_сигналов.csv. С книгой судна проверяется связь ПУ с движителями.
// Код выхода: 0 — книга принята, 1 — есть ошибки, 2 — неверный вызов.
#include <cstdio>
#include <string>

#include "dp/pu.hpp"

using namespace dp;

static void print(const char* head, const std::vector<std::string>& v) {
    if (v.empty()) return;
    std::printf("%s:\n", head);
    for (auto& s : v) std::printf("  %s\n", s.c_str());
}

int main(int argc, char** argv) {
    std::string book, registry = "data/ПУ_реестр_сигналов.csv", ship;
    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        if (a == "--registry" && i + 1 < argc) registry = argv[++i];
        else if (a == "--ship" && i + 1 < argc) ship = argv[++i];
        else if (!a.empty() && a[0] != '-' && book.empty()) book = a;
        else { std::fprintf(stderr, "вызов: sdp_pu_check <книга ПУ> [--registry <реестр.csv>] [--ship <книга судна>]\n"); return 2; }
    }
    if (book.empty()) { std::fprintf(stderr, "вызов: sdp_pu_check <книга ПУ> [--registry <реестр.csv>] [--ship <книга судна>]\n"); return 2; }

    pu::Registry reg; BookReport rr;
    if (!pu::loadRegistry(registry, reg, rr)) { print("Ошибки реестра", rr.errors); return 1; }
    std::printf("Реестр: %zu сигналов ПЛК ПУ\n", reg.signals.size());

    std::vector<ThrusterCfg> thrusters;
    if (!ship.empty()) {
        AppCfg ac; BookReport sr;
        if (!loadShipBook(ship, ac, sr)) { print("Ошибки книги судна", sr.errors); return 1; }
        thrusters = ac.thrusters;
        std::printf("Книга судна: %zu движителей\n", thrusters.size());
    }

    pu::Config cfg; BookReport rep;
    const bool ok = pu::loadBook(book, reg, thrusters, cfg, rep);
    for (auto& u : cfg.units) {
        std::printf("%s — %s: каналов %zu, управление от СДП %s%s%s\n", u.id.c_str(), u.title.c_str(), u.channels.size(),
                    u.controlEnabled ? "включено" : "выключено (наблюдение)",
                    u.thruster.empty() ? "" : ", движитель ", u.thruster.c_str());
    }
    print("Ошибки", rep.errors);
    print("Предупреждения", rep.warnings);
    std::printf("%s\n", ok ? "Книга принята." : "Книга не принята.");
    return ok ? 0 : 1;
}
