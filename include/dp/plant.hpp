// Электростанция судна (PMS) для имитации: генераторы, две шины, секционный выключатель, служебная нагрузка.
// Считает доступную мощность, нагрузку, резерв и проверяет наихудший отказ (потеря генератора или шины).
// Только имитация: у реального судна эти данные должны приходить от PMS. Не сертифицировано.
#pragma once
#include <string>
#include <vector>

#include "dp/thrust.hpp"

namespace dp {

struct WorstCaseResult {
    bool ok = true;               // удержание после наихудшего отказа возможно
    double ratio = 0;             // нужная доля возможностей оставшихся движителей (больше 1 — не хватает)
    std::string what;             // что отказывает в наихудшем случае
};

// Анализ последствий отказа (K-Pos, DP Online Consequence Analysis): по каждому «наихудшему единичному отказу» проверяется, хватит ли
// упора и мощности оставшихся движителей на текущую потребность. fails — отказы, после которых удержание невозможно.
struct ConseqFail { std::string what; bool power = false; double ratio = 0; };   // power: false — не хватает упора, true — не хватает мощности
struct ConseqResult { bool ran = false; std::vector<ConseqFail> fails; double worstRatio = 0; std::string worstWhat; };

struct PlantState {
    bool enabled = false;
    double availableKW = 0;       // располагаемая мощность работающих генераторов на живых шинах
    double loadKW = 0;            // суммарная нагрузка (движители + служебные)
    double reserveKW = 0, reservePct = 0;
    double busAvailKW[2] = {0, 0}, busLoadKW[2] = {0, 0};
    bool busFailed[2] = {false, false};
    bool tieClosed = true;
    double engineAvailKW = 1e9;   // значение для ядра: availableKW, приведённое к сумме максимумов движителей
    std::vector<double> genLoadPct;
};

class Plant {
public:
    Plant() = default;
    explicit Plant(PlantCfg c) : cfg_(std::move(c)) { reset(); }
    const PlantCfg& cfg() const { return cfg_; }
    bool enabled() const { return cfg_.enabled && !cfg_.gens.empty(); }

    void reset() {
        online_.assign(cfg_.gens.size(), true);
        for (size_t i = 0; i < cfg_.gens.size(); ++i) online_[i] = cfg_.gens[i].online;
        busFailed_[0] = busFailed_[1] = false; tie_ = cfg_.tieClosed;
    }
    bool setGen(const std::string& id, bool on) {
        for (size_t i = 0; i < cfg_.gens.size(); ++i) if (cfg_.gens[i].id == id) { online_[i] = on; return true; }
        return false;
    }
    bool setBus(int b, bool failed) { if (b < 0 || b > 1) return false; busFailed_[b] = failed; return true; }
    void setTie(bool closed) { tie_ = closed; }
    bool genOnline(size_t i) const { return i < online_.size() && online_[i]; }
    bool busFailed(int b) const { return b >= 0 && b <= 1 && busFailed_[b]; }
    bool tieClosed() const { return tie_; }
    // Шина обесточена: отказала или (при разомкнутом секционном) на ней не осталось работающих генераторов.
    bool busDead(int b) const {
        if (b < 0 || b > 1) return false;
        if (busFailed_[b]) return true;
        if (tie_) { double all = 0; for (int k = 0; k < 2; ++k) all += genKW(k); return all <= 0.0; }
        return genKW(b) <= 0.0;
    }
    // Движитель потерян, если его шина отказала.
    bool thrusterLost(const ThrusterCfg& t) const { return t.bus >= 0 && t.bus <= 1 && busDead(t.bus); }

    // thrFrac — доля упора каждого движителя по модулю (0..1), в порядке списка th.
    PlantState compute(const std::vector<ThrusterCfg>& th, const std::vector<double>& thrFrac) const {
        PlantState s; s.enabled = enabled(); s.tieClosed = tie_;
        if (!s.enabled) return s;
        s.busFailed[0] = busFailed_[0]; s.busFailed[1] = busFailed_[1];
        for (size_t i = 0; i < cfg_.gens.size(); ++i) {
            const int b = cfg_.gens[i].bus < 1 ? 0 : 1;
            if (online_[i] && !busFailed_[b]) s.busAvailKW[b] += cfg_.gens[i].ratedKW;
        }
        bool dead[2] = {busDead(0), busDead(1)};
        for (int b = 0; b < 2; ++b) if (!dead[b]) s.busLoadKW[b] += cfg_.serviceKW[b];
        double needAll = 0, needLive[2] = {0, 0};
        for (size_t i = 0; i < th.size(); ++i) {
            const auto& t = th[i]; if (!t.enabled) continue;
            needAll += t.powerMaxKW;
            const double p = thrusterPowerKW(t, i < thrFrac.size() ? thrFrac[i] : 0.0);
            if (t.bus >= 0 && t.bus <= 1) { if (!dead[t.bus]) { s.busLoadKW[t.bus] += p; needLive[t.bus] += t.powerMaxKW; } }
            else for (int b = 0; b < 2; ++b) if (!dead[b]) { s.busLoadKW[b] += 0.5 * p; needLive[b] += 0.5 * t.powerMaxKW; }
        }
        s.availableKW = s.busAvailKW[0] + s.busAvailKW[1];
        s.loadKW = s.busLoadKW[0] + s.busLoadKW[1];
        s.reserveKW = s.availableKW - s.loadKW;
        s.reservePct = s.availableKW > 1e-9 ? 100.0 * s.reserveKW / s.availableKW : (s.loadKW > 0 ? -100.0 : 0.0);
        // нагрузка генераторов: пропорционально номиналу в пределах объединённой (секция замкнута) или отдельной шины
        s.genLoadPct.assign(cfg_.gens.size(), 0.0);
        for (size_t i = 0; i < cfg_.gens.size(); ++i) {
            const int b = cfg_.gens[i].bus < 1 ? 0 : 1;
            if (!online_[i] || busFailed_[b] || cfg_.gens[i].ratedKW <= 0) continue;
            const double av = tie_ ? s.availableKW : s.busAvailKW[b], ld = tie_ ? s.loadKW : s.busLoadKW[b];
            s.genLoadPct[i] = av > 1e-9 ? 100.0 * ld / av : 0.0;
        }
        // для ядра: доля мощности относительно суммы максимумов движителей (живых шин)
        double ratio = 1.0;
        auto r = [&](double av, double nd) { return nd > 1e-9 ? av / nd : 1e9; };
        const double svc0 = dead[0] ? 0 : cfg_.serviceKW[0], svc1 = dead[1] ? 0 : cfg_.serviceKW[1];   // служебная нагрузка берётся из мощности раньше движителей
        if (tie_) ratio = r(std::max(0.0, s.availableKW - svc0 - svc1), needLive[0] + needLive[1]);
        else ratio = std::min(dead[0] ? 1e9 : r(std::max(0.0, s.busAvailKW[0] - svc0), needLive[0]), dead[1] ? 1e9 : r(std::max(0.0, s.busAvailKW[1] - svc1), needLive[1]));
        s.engineAvailKW = needAll > 0 ? std::min(ratio, 1e6) * needAll : 1e9;
        return s;
    }

    // Наихудший отказ: теряем каждый работающий генератор и каждую шину по очереди; смотрим, хватает ли возможностей оставшихся
    // движителей на текущую потребность tau. Возможности — прямоугольная оценка, как в остальном ядре.
    WorstCaseResult worstCase(const std::vector<ThrusterCfg>& th, const Wrench& tau) const {
        WorstCaseResult w;
        if (!enabled()) return w;
        struct Case { std::string name; int gen; int bus; };
        std::vector<Case> cs;
        for (size_t i = 0; i < cfg_.gens.size(); ++i) if (online_[i]) cs.push_back({"генератора " + cfg_.gens[i].id, static_cast<int>(i), -1});
        for (int b = 0; b < 2; ++b) if (!busFailed_[b]) cs.push_back({std::string("шины ") + (b ? "B" : "A"), -1, b});
        for (const auto& c : cs) {
            std::vector<ThrusterCfg> t2 = th;
            bool bf[2] = {busFailed_[0], busFailed_[1]}; if (c.bus >= 0) bf[c.bus] = true;
            double av[2] = {0, 0};
            for (size_t i = 0; i < cfg_.gens.size(); ++i) {
                const int b = cfg_.gens[i].bus < 1 ? 0 : 1;
                if (online_[i] && !bf[b] && static_cast<int>(i) != c.gen) av[b] += cfg_.gens[i].ratedKW;
            }
            if (!tie_) { for (int b = 0; b < 2; ++b) if (av[b] <= 0.0) bf[b] = true; }
            else if (av[0] + av[1] <= 0.0) { bf[0] = bf[1] = true; }
            double nd[2] = {0, 0}, ndAll = 0;
            for (auto& t : t2) {
                if (!t.enabled) continue;
                if (t.bus >= 0 && t.bus <= 1 && bf[t.bus]) { t.enabled = false; continue; }
                if (t.bus >= 0 && t.bus <= 1) nd[t.bus] += t.powerMaxKW; else { nd[0] += 0.5 * t.powerMaxKW; nd[1] += 0.5 * t.powerMaxKW; }
                ndAll += t.powerMaxKW;
            }
            double ps = 1.0;
            if (ndAll > 0) {
                const double svc0 = bf[0] ? 0 : cfg_.serviceKW[0], svc1 = bf[1] ? 0 : cfg_.serviceKW[1];
                if (tie_) ps = std::max(0.0, (av[0] + av[1] - svc0 - svc1)) / (nd[0] + nd[1]);
                else ps = std::min(nd[0] > 1e-9 ? std::max(0.0, av[0] - svc0) / nd[0] : 1e9, nd[1] > 1e-9 ? std::max(0.0, av[1] - svc1) / nd[1] : 1e9);
                ps = clampd(ps, 0.0, 1.0);
            }
            const double sc = ps <= 0 ? 0.0 : thrustScaleForPower(t2, std::max(ps, 0.2));
            const Capability cap = Allocator(t2).capability(sc);
            auto need = [](double req, double c) { return std::fabs(req) < 1.0 ? 0.0 : (c > 1e-6 ? std::fabs(req) / c : 1e9); };
            const double ratio = std::max({need(tau.X, cap.X), need(tau.Y, cap.Y), need(tau.N, cap.N)});
            if (ratio > w.ratio) { w.ratio = ratio; w.what = c.name; }
        }
        w.ok = w.ratio <= 1.0;
        return w;
    }

    // Анализ последствий: отказ каждого работающего движителя; при включённой электростанции ещё и отказ каждого генератора и каждой шины
    // (шина — «распределительный щит»; помещение моделируется потерей всех движителей и генераторов шины). Упор и мощность проверяются раздельно.
    ConseqResult consequences(const std::vector<ThrusterCfg>& th, const Wrench& tau) const {
        ConseqResult res; res.ran = true;
        auto need = [](double req, double c) { return std::fabs(req) < 1.0 ? 0.0 : (c > 1e-6 ? std::fabs(req) / c : 1e9); };
        auto ratioOf = [&](const std::vector<ThrusterCfg>& t, double scale) {
            const Capability cap = Allocator(t).capability(scale);
            return std::max({need(tau.X, cap.X), need(tau.Y, cap.Y), need(tau.N, cap.N)});
        };
        auto add = [&](const std::string& what, double thrustRatio, double powerRatio) {
            const double r = std::max(thrustRatio, powerRatio);
            if (r > res.worstRatio) { res.worstRatio = r; res.worstWhat = what; }
            if (thrustRatio > 1.0) res.fails.push_back({what, false, thrustRatio});
            else if (powerRatio > 1.0) res.fails.push_back({what, true, powerRatio});
        };
        for (size_t i = 0; i < th.size(); ++i) {
            if (!th[i].enabled) continue;
            std::vector<ThrusterCfg> t2 = th; t2[i].enabled = false;
            add("движителя " + th[i].id, ratioOf(t2, 1.0), 0.0);
        }
        if (enabled()) {
            struct Case { std::string name; int gen; int bus; };
            std::vector<Case> cs;
            for (size_t i = 0; i < cfg_.gens.size(); ++i) if (online_[i]) cs.push_back({"генератора " + cfg_.gens[i].id, static_cast<int>(i), -1});
            for (int b = 0; b < 2; ++b) if (!busFailed_[b]) cs.push_back({std::string("шины ") + (b ? "B" : "A"), -1, b});
            for (const auto& c : cs) {
                std::vector<ThrusterCfg> t2 = th;
                bool bf[2] = {busFailed_[0], busFailed_[1]}; if (c.bus >= 0) bf[c.bus] = true;
                double av[2] = {0, 0};
                for (size_t i = 0; i < cfg_.gens.size(); ++i) {
                    const int b = cfg_.gens[i].bus < 1 ? 0 : 1;
                    if (online_[i] && !bf[b] && static_cast<int>(i) != c.gen) av[b] += cfg_.gens[i].ratedKW;
                }
                if (!tie_) { for (int b = 0; b < 2; ++b) if (av[b] <= 0.0) bf[b] = true; }
                else if (av[0] + av[1] <= 0.0) { bf[0] = bf[1] = true; }
                double nd[2] = {0, 0}, ndAll = 0;
                for (auto& t : t2) {
                    if (!t.enabled) continue;
                    if (t.bus >= 0 && t.bus <= 1 && bf[t.bus]) { t.enabled = false; continue; }
                    if (t.bus >= 0 && t.bus <= 1) nd[t.bus] += t.powerMaxKW; else { nd[0] += 0.5 * t.powerMaxKW; nd[1] += 0.5 * t.powerMaxKW; }
                    ndAll += t.powerMaxKW;
                }
                double ps = 1.0;
                if (ndAll > 0) {
                    const double svc0 = bf[0] ? 0 : cfg_.serviceKW[0], svc1 = bf[1] ? 0 : cfg_.serviceKW[1];
                    if (tie_) ps = std::max(0.0, (av[0] + av[1] - svc0 - svc1)) / (nd[0] + nd[1]);
                    else ps = std::min(nd[0] > 1e-9 ? std::max(0.0, av[0] - svc0) / nd[0] : 1e9, nd[1] > 1e-9 ? std::max(0.0, av[1] - svc1) / nd[1] : 1e9);
                    ps = clampd(ps, 0.0, 1.0);
                }
                const double thrustR = ratioOf(t2, 1.0);                                   // только потеря движителей, мощности достаточно
                const double sc = ps <= 0 ? 0.0 : thrustScaleForPower(t2, std::max(ps, 0.2));
                const double powerR = ratioOf(t2, sc);                                     // с учётом нехватки мощности
                add(c.name, thrustR, powerR);
            }
        }
        return res;
    }

private:
    double genKW(int b) const {
        double a = 0;
        for (size_t i = 0; i < cfg_.gens.size(); ++i) if (online_[i] && (cfg_.gens[i].bus < 1 ? 0 : 1) == b && !busFailed_[b]) a += cfg_.gens[i].ratedKW;
        return a;
    }
    PlantCfg cfg_;
    std::vector<bool> online_;
    bool busFailed_[2] = {false, false};
    bool tie_ = true;
};

}  // namespace dp
