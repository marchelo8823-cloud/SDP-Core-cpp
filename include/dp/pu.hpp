// Сопряжение СДП с пультами управления движителями (ПУ) на контроллерах Siemens S7-1200.
// Этап 1: реестр сигналов ПЛК ПУ и книга сопряжения с проверками. Обмена с оборудованием здесь нет.
//
// Реестр — data/ПУ_реестр_сигналов.csv (разделитель «;», UTF-8): адрес в ПЛК ПУ, тип, название в проекте
// (кит.), название в базовом проекте JM5-2 (англ.), назначение (рус.), связь с СДП, отличия по судам и ПУ.
//
// Книга сопряжения (Excel), листы:
//   «ПУ»     — таблица с первой ячейкой «ПУ»: Судно, Название, Движитель, Управление от СДП, Положительный упор;
//   «Каналы» — таблица с первой ячейкой «ПУ»: Сигнал, Адрес в ПЛК ПУ, Узел, Модуль, Канал,
//              мА при −100 %, мА при 0 %, мА при +100 %, Полная шкала, А.
// Управление от СДП по умолчанию выключено. Пока оно выключено, СДП только наблюдает, и недостающие каналы
// дают предупреждение. Включённое управление требует всех каналов управления, калибровки, знака упора и
// связи с туннельным движителем книги судна. Заглушек нет: пустое обязательное поле — ошибка.
#pragma once
#include <cctype>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#include "dp/shipbook.hpp"

namespace dp {
namespace pu {

// ---------------------------------------------------------------- реестр сигналов ПЛК ПУ

enum class PlcType { DI, DO, AI, AO };   // DI/AI — входы ПЛК ПУ, DO/AO — его выходы

struct PlcSignal {
    std::string address;    // «%I5.2», «%QW100»
    PlcType type = PlcType::DI;
    std::string nameCn, nameEn, nameRu;
    bool dpRelated = false;
    std::string differences;
};

struct Registry {
    std::vector<PlcSignal> signals;
    const PlcSignal* find(const std::string& addr) const { for (auto& s : signals) if (s.address == addr) return &s; return nullptr; }
};

inline const char* typeName(PlcType t) { switch (t) { case PlcType::DI: return "DI"; case PlcType::DO: return "DO"; case PlcType::AI: return "AI"; default: return "AO"; } }

namespace detail {
// строка CSV с разделителем «;» и кавычками по RFC 4180 (поле в кавычках может содержать «;»)
inline bool splitCsv(const std::string& line, std::vector<std::string>& out) {
    out.clear(); std::string f; bool q = false;
    for (size_t i = 0; i < line.size(); ++i) {
        const char c = line[i];
        if (q) {
            if (c == '"') { if (i + 1 < line.size() && line[i + 1] == '"') { f += '"'; ++i; } else q = false; }
            else f += c;
        } else if (c == '"' && f.empty()) q = true;
        else if (c == ';') { out.push_back(f); f.clear(); }
        else if (c != '\r') f += c;
    }
    out.push_back(f);
    return !q;
}
// тип по адресу: %I0.0 → DI, %Q0.0 → DO, %IW64 → AI, %QW100 → AO; иначе false
inline bool typeOfAddress(const std::string& a, PlcType& t) {
    if (a.size() < 3 || a[0] != '%') return false;
    const char area = a[1]; if (area != 'I' && area != 'Q') return false;
    size_t i = 2; const bool word = a[2] == 'W'; if (word) ++i;
    const size_t digits0 = i; while (i < a.size() && std::isdigit(static_cast<unsigned char>(a[i]))) ++i;
    if (i == digits0) return false;
    if (word) { if (i != a.size()) return false; t = area == 'I' ? PlcType::AI : PlcType::AO; return true; }
    if (i + 2 != a.size() || a[i] != '.' || a[i + 1] < '0' || a[i + 1] > '7') return false;
    t = area == 'I' ? PlcType::DI : PlcType::DO; return true;
}
}  // namespace detail

inline bool parseRegistry(std::istream& in, Registry& reg, BookReport& rep) {
    std::string line; std::vector<std::string> f; int n = 0; std::set<std::string> seen;
    while (std::getline(in, line)) {
        ++n;
        if (n == 1) { if (line.size() >= 3 && line.compare(0, 3, "\xEF\xBB\xBF") == 0) line.erase(0, 3); continue; }   // заголовок
        if (line.empty() || line == "\r") continue;
        const std::string where = "реестр сигналов, строка " + std::to_string(n);
        if (!detail::splitCsv(line, f)) { rep.errors.push_back(where + ": незакрытая кавычка"); continue; }
        if (f.size() != 7) { rep.errors.push_back(where + ": ожидается 7 полей, найдено " + std::to_string(f.size())); continue; }
        PlcSignal s; s.address = f[0];
        PlcType byAddr;
        if (!detail::typeOfAddress(s.address, byAddr)) { rep.errors.push_back(where + ": «" + s.address + "» — не адрес ПЛК (%I0.0, %Q0.0, %IW64, %QW100)"); continue; }
        if (f[1] == "DI") s.type = PlcType::DI; else if (f[1] == "DO") s.type = PlcType::DO;
        else if (f[1] == "AI") s.type = PlcType::AI; else if (f[1] == "AO") s.type = PlcType::AO;
        else { rep.errors.push_back(where + ": тип «" + f[1] + "» — нужен DI, DO, AI или AO"); continue; }
        if (s.type != byAddr) rep.errors.push_back(where + ": тип " + f[1] + " не соответствует адресу " + s.address);
        if (!seen.insert(s.address).second) rep.errors.push_back(where + ": адрес " + s.address + " повторяется");
        s.nameCn = f[2]; s.nameEn = f[3]; s.nameRu = f[4]; s.dpRelated = f[5] == "да"; s.differences = f[6];
        if (s.nameRu.empty()) rep.errors.push_back(where + " (" + s.address + "): не заполнено назначение");
        reg.signals.push_back(s);
    }
    if (reg.signals.empty()) rep.errors.push_back("реестр сигналов пуст");
    return rep.ok();
}

inline bool loadRegistry(const std::string& path, Registry& reg, BookReport& rep) {
    std::ifstream in(path, std::ios::binary);
    if (!in) { rep.errors.push_back("не открывается реестр сигналов: " + path); return false; }
    return parseRegistry(in, reg, rep);
}

// ---------------------------------------------------------------- сигналы сопряжения СДП ↔ ПУ

enum class Sig {
    DpRequest, PitchSetpoint,                                     // СДП → ПУ
    DpAllowed, PitchFeedback, ControlFailure, Ready,              // ПУ → СДП, нужны для управления
    DpJoyMode, LoadCtrlFailure, CommonAlarm, MotorLoad, MotorRunning, ZeroPitch   // ПУ → СДП, дополнительные
};
enum class Chan { DQ, AQ, DI, AI };   // вид канала на стороне СДП (модуль ввода-вывода)

struct SigInfo { Sig sig; const char* label; PlcType plc; Chan chan; bool forControl; };

inline const std::vector<SigInfo>& signalTable() {
    static const std::vector<SigInfo> t = {
        {Sig::DpRequest,       "Запрос управления от СДП",        PlcType::DI, Chan::DQ, true},
        {Sig::PitchSetpoint,   "Задание шага от СДП",             PlcType::AI, Chan::AQ, true},
        {Sig::DpAllowed,       "Управление от СДП разрешено",     PlcType::DO, Chan::DI, true},
        {Sig::PitchFeedback,   "Фактический шаг",                 PlcType::AO, Chan::AI, true},
        {Sig::ControlFailure,  "Отказ системы управления ПУ",     PlcType::DO, Chan::DI, true},
        {Sig::Ready,           "Готовность ПУ",                   PlcType::DO, Chan::DI, true},
        {Sig::DpJoyMode,       "Режим СДП/джойстик",              PlcType::DO, Chan::DI, false},
        {Sig::LoadCtrlFailure, "Отказ ограничения нагрузки",      PlcType::DO, Chan::DI, false},
        {Sig::CommonAlarm,     "Обобщённая АПС ПУ",               PlcType::DO, Chan::DI, false},
        {Sig::MotorLoad,       "Нагрузка приводного двигателя",   PlcType::AO, Chan::AI, false},
        {Sig::MotorRunning,    "Приводной двигатель работает",    PlcType::DO, Chan::DI, false},
        {Sig::ZeroPitch,       "Нулевой шаг",                     PlcType::DO, Chan::DI, false},
    };
    return t;
}
inline const SigInfo* signalByLabel(const std::string& l) { for (auto& s : signalTable()) if (l == s.label) return &s; return nullptr; }
inline const SigInfo& info(Sig s) { for (auto& i : signalTable()) if (i.sig == s) return i; return signalTable()[0]; }
inline const char* chanName(Chan c) { switch (c) { case Chan::DQ: return "дискретный выход"; case Chan::AQ: return "аналоговый выход"; case Chan::DI: return "дискретный вход"; default: return "аналоговый вход"; } }

// калибровка аналогового канала шага: ток при −100 %, 0 и +100 % шага (4–20 мА, по возрастанию)
struct Scale { bool set = false; double maMinus = 0, maZero = 0, maPlus = 0; };

struct Channel {
    Sig sig = Sig::DpRequest;
    std::string plcAddress;   // адрес в ПЛК ПУ
    std::string node;         // узел ввода-вывода СДП (набор ET 200SP), например «ET1»
    int module = 0, channel = 0;
    Scale scale;              // для шага
    double fullScaleA = 0;    // для нагрузки двигателя: ток при 10 В
    int row = 0;
};

struct Unit {
    std::string id, vessel, title, thruster;
    bool controlEnabled = false;                 // по умолчанию — только наблюдение
    int positiveStarboard = 0;                   // +1: положительный упор на правый борт, −1: на левый, 0: не задано
    std::vector<Channel> channels;
    const Channel* find(Sig s) const { for (auto& c : channels) if (c.sig == s) return &c; return nullptr; }
};

struct Config { std::vector<Unit> units; const Unit* find(const std::string& id) const { for (auto& u : units) if (u.id == id) return &u; return nullptr; } };

// Перевод шага в ток по калибровке (кусочно-линейно, с ограничением ±100 %). Для проверок и будущего вывода.
inline double pitchToMa(const Scale& s, double pct) {
    pct = pct < -100 ? -100 : (pct > 100 ? 100 : pct);
    return pct >= 0 ? s.maZero + (s.maPlus - s.maZero) * pct / 100.0 : s.maZero + (s.maZero - s.maMinus) * pct / 100.0;
}
inline double maToPitch(const Scale& s, double ma) {
    return ma >= s.maZero ? 100.0 * (ma - s.maZero) / (s.maPlus - s.maZero) : 100.0 * (ma - s.maZero) / (s.maZero - s.maMinus);
}

// Чтение и проверка книги. registry — реестр ПЛК ПУ; thrusters — движители книги судна (пусто — связь не проверяется).
inline bool readBook(const xlsx::Book& book, const Registry& registry, const std::vector<ThrusterCfg>& thrusters, Config& cfg, BookReport& rep) {
    using shipbook::Table;
    for (const char* n : {"ПУ", "Каналы"}) if (!book.find(n)) rep.errors.push_back(std::string("в книге нет листа «") + n + "»");
    if (!rep.ok()) return false;

    // ---- лист «ПУ»
    Table U(book, "ПУ", "ПУ", rep);
    if (!U.present) { rep.errors.push_back("лист «ПУ»: нет таблицы с первой ячейкой «ПУ»"); return false; }
    for (const char* h : {"Судно", "Название", "Движитель", "Управление от СДП", "Положительный упор"})
        if (U.col(h) < 0) rep.errors.push_back(std::string("лист «ПУ»: нет столбца «") + h + "» (не меняйте заголовки)");
    if (!rep.ok()) return false;
    if (U.rows.empty()) rep.errors.push_back("лист «ПУ»: не описан ни один ПУ");
    for (size_t r = 0; r < U.rows.size(); ++r) {
        Unit u; u.id = U.rows[r][0];
        if (cfg.find(u.id)) { rep.errors.push_back(U.where(r, "ПУ") + ": обозначение ПУ повторяется"); continue; }
        u.vessel = U.cell(r, "Судно"); u.title = U.cell(r, "Название"); u.thruster = U.cell(r, "Движитель");
        if (u.vessel.empty()) rep.errors.push_back(U.where(r, "Судно") + ": не заполнено");
        if (u.title.empty()) rep.errors.push_back(U.where(r, "Название") + ": не заполнено");
        bool bad; u.controlEnabled = shipbook::yes(U.cell(r, "Управление от СДП"), false, bad);
        if (bad) rep.errors.push_back(U.where(r, "Управление от СДП") + ": «да» или «нет»");
        const std::string sign = U.cell(r, "Положительный упор");
        if (sign == "на правый борт") u.positiveStarboard = 1; else if (sign == "на левый борт") u.positiveStarboard = -1;
        else if (!sign.empty()) rep.errors.push_back(U.where(r, "Положительный упор") + ": «на правый борт» или «на левый борт»");
        if (!u.thruster.empty() && !thrusters.empty()) {
            const ThrusterCfg* t = nullptr; for (auto& x : thrusters) if (x.id == u.thruster) t = &x;
            if (!t) rep.errors.push_back(U.where(r, "Движитель") + ": движителя «" + u.thruster + "» нет на листе «Движители» книги судна");
            else if (t->type != ThrusterType::Tunnel) rep.errors.push_back(U.where(r, "Движитель") + ": ПУ управляет только шагом — движитель должен быть туннельным");
        }
        if (u.controlEnabled) {
            if (u.thruster.empty()) rep.errors.push_back(U.where(r, "Движитель") + ": при включённом управлении нужно указать движитель книги судна");
            else if (thrusters.empty()) rep.errors.push_back(U.where(r, "Движитель") + ": при включённом управлении нужна книга судна для проверки связи");
            if (u.positiveStarboard == 0) rep.errors.push_back(U.where(r, "Положительный упор") + ": при включённом управлении нужно указать знак упора");
        } else if (u.thruster.empty()) rep.warnings.push_back(U.where(r, "Движитель") + ": ПУ не связан с движителем книги судна");
        cfg.units.push_back(u);
    }
    {   // книга — одно судно: у каждого судна своя СДП
        std::set<std::string> vs; for (auto& u : cfg.units) if (!u.vessel.empty()) vs.insert(u.vessel);
        if (vs.size() > 1) { std::string s; for (auto& v : vs) s += (s.empty() ? "«" : ", «") + v + "»"; rep.errors.push_back("лист «ПУ»: в одной книге ПУ разных судов (" + s + ") — заведите книгу на каждое судно"); }
    }
    {   // один движитель — один ПУ
        std::map<std::string, std::string> by;
        for (auto& u : cfg.units) if (!u.thruster.empty()) {
            auto it = by.find(u.thruster);
            if (it != by.end()) rep.errors.push_back("лист «ПУ»: движитель «" + u.thruster + "» указан у " + it->second + " и " + u.id);
            else by[u.thruster] = u.id;
        }
    }

    // ---- лист «Каналы»
    Table C(book, "Каналы", "ПУ", rep);
    if (!C.present) { rep.errors.push_back("лист «Каналы»: нет таблицы с первой ячейкой «ПУ»"); return false; }
    for (const char* h : {"Сигнал", "Адрес в ПЛК ПУ", "Узел", "Модуль", "Канал", "мА при −100 %", "мА при 0 %", "мА при +100 %", "Полная шкала, А"})
        if (C.col(h) < 0) rep.errors.push_back(std::string("лист «Каналы»: нет столбца «") + h + "» (не меняйте заголовки)");
    if (!rep.ok()) return false;
    std::map<std::string, std::string> phys;          // «узел/модуль/канал» → кто занял
    std::map<std::string, Chan> moduleKind;           // «узел/модуль» → вид каналов
    std::set<std::string> nodes;
    for (size_t r = 0; r < C.rows.size(); ++r) {
        const std::string uid = C.rows[r][0];
        Unit* u = nullptr; for (auto& x : cfg.units) if (x.id == uid) u = &x;
        if (!u) { rep.errors.push_back(C.where(r, "ПУ") + ": такого ПУ нет на листе «ПУ»"); continue; }
        Channel ch; ch.row = C.rowNo[r];
        const std::string lbl = C.cell(r, "Сигнал");
        const SigInfo* si = signalByLabel(lbl);
        if (!si) { rep.errors.push_back(C.where(r, "Сигнал") + ": «" + lbl + "» — неизвестный сигнал (выберите из списка)"); continue; }
        ch.sig = si->sig;
        if (u->find(ch.sig)) { rep.errors.push_back(C.where(r, "Сигнал") + ": сигнал «" + lbl + "» у " + uid + " уже описан"); continue; }
        // адрес в ПЛК ПУ: есть в реестре и подходит по типу
        ch.plcAddress = C.cell(r, "Адрес в ПЛК ПУ");
        if (ch.plcAddress.empty()) rep.errors.push_back(C.where(r, "Адрес в ПЛК ПУ") + ": не заполнено");
        else {
            const PlcSignal* ps = registry.find(ch.plcAddress);
            if (!ps) rep.errors.push_back(C.where(r, "Адрес в ПЛК ПУ") + ": адреса " + ch.plcAddress + " нет в реестре сигналов ПУ");
            else if (ps->type != si->plc) rep.errors.push_back(C.where(r, "Адрес в ПЛК ПУ") + ": " + ch.plcAddress + " — " + typeName(ps->type) + " ПЛК, для «" + lbl + "» нужен " + typeName(si->plc));
        }
        // канал СДП
        ch.node = C.cell(r, "Узел");
        double m = 0, k = 0; const bool hm = C.need(r, "Модуль", m), hk = C.need(r, "Канал", k);
        if (ch.node.empty()) rep.errors.push_back(C.where(r, "Узел") + ": не заполнено");
        if (hm && (m < 1 || m > 64 || m != static_cast<int>(m))) rep.errors.push_back(C.where(r, "Модуль") + ": номер места модуля — целое от 1 до 64");
        if (hk && (k < 0 || k > 15 || k != static_cast<int>(k))) rep.errors.push_back(C.where(r, "Канал") + ": номер канала — целое от 0 до 15");
        ch.module = static_cast<int>(m); ch.channel = static_cast<int>(k);
        if (!ch.node.empty() && hm && hk) {
            nodes.insert(ch.node);
            const std::string mk = ch.node + "/" + std::to_string(ch.module), pk = mk + "/" + std::to_string(ch.channel);
            auto pi = phys.find(pk);
            if (pi != phys.end()) rep.errors.push_back(C.where(r, "Канал") + ": канал " + pk + " уже занят (" + pi->second + ")");
            else phys[pk] = uid + " «" + lbl + "»";
            auto mi = moduleKind.find(mk);
            if (mi != moduleKind.end() && mi->second != si->chan)
                rep.errors.push_back(C.where(r, "Модуль") + ": модуль " + mk + " уже используется как " + chanName(mi->second) + ", а «" + lbl + "» — " + chanName(si->chan));
            else moduleKind[mk] = si->chan;
        }
        // калибровка
        const bool pitch = ch.sig == Sig::PitchSetpoint || ch.sig == Sig::PitchFeedback;
        std::string a = C.cell(r, "мА при −100 %"), b = C.cell(r, "мА при 0 %"), c = C.cell(r, "мА при +100 %");
        if (pitch) {
            const int filled = !a.empty() + !b.empty() + !c.empty();
            if (filled == 3) {
                bool okn = true;
                okn = C.need(r, "мА при −100 %", ch.scale.maMinus) && okn; okn = C.need(r, "мА при 0 %", ch.scale.maZero) && okn; okn = C.need(r, "мА при +100 %", ch.scale.maPlus) && okn;
                if (okn) {
                    bool range = true;
                    for (double v : {ch.scale.maMinus, ch.scale.maZero, ch.scale.maPlus}) range = range && v >= 4.0 && v <= 20.0;
                    if (!range) rep.errors.push_back(C.where(r, "мА при 0 %") + ": калибровка вне 4–20 мА");
                    else if (!(ch.scale.maMinus < ch.scale.maZero && ch.scale.maZero < ch.scale.maPlus)) rep.errors.push_back(C.where(r, "мА при 0 %") + ": ток должен возрастать от −100 % к +100 %");
                    else ch.scale.set = true;
                }
            } else if (filled > 0) rep.errors.push_back(C.where(r, "мА при 0 %") + ": калибровка задаётся тремя точками (−100 %, 0, +100 %)");
        } else if (!a.empty() || !b.empty() || !c.empty()) rep.errors.push_back(C.where(r, "мА при 0 %") + ": калибровка в мА задаётся только для шага");
        const std::string fs = C.cell(r, "Полная шкала, А");
        if (ch.sig == Sig::MotorLoad) {
            if (C.need(r, "Полная шкала, А", ch.fullScaleA) && ch.fullScaleA <= 0) rep.errors.push_back(C.where(r, "Полная шкала, А") + ": должна быть больше нуля");
        } else if (!fs.empty()) rep.errors.push_back(C.where(r, "Полная шкала, А") + ": задаётся только для нагрузки двигателя");
        u->channels.push_back(ch);
    }

    // ---- полнота по каждому ПУ
    for (auto& u : cfg.units) {
        std::string missing;
        for (auto& s : signalTable()) if (s.forControl && !u.find(s.sig)) missing += std::string(missing.empty() ? "" : ", ") + "«" + s.label + "»";
        std::string uncal;
        for (Sig s : {Sig::PitchSetpoint, Sig::PitchFeedback}) { const Channel* c = u.find(s); if (c && !c->scale.set) uncal += std::string(uncal.empty() ? "" : ", ") + "«" + info(s).label + "»"; }
        if (u.controlEnabled) {
            if (!missing.empty()) rep.errors.push_back("ПУ " + u.id + ": управление от СДП включено, но нет каналов " + missing);
            if (!uncal.empty()) rep.errors.push_back("ПУ " + u.id + ": управление от СДП включено, но не задана калибровка " + uncal);
        } else {
            if (!missing.empty()) rep.warnings.push_back("ПУ " + u.id + ": нет каналов " + missing + " — управление от СДП включить нельзя");
            if (!uncal.empty()) rep.warnings.push_back("ПУ " + u.id + ": не задана калибровка " + uncal + " — управление от СДП включить нельзя");
        }
    }
    if (!cfg.units.empty() && nodes.size() == 1) rep.warnings.push_back("лист «Каналы»: все каналы на одном узле «" + *nodes.begin() + "» — для DP-2 нужны два набора ввода-вывода");
    return rep.ok();
}

inline bool loadBook(const std::string& path, const Registry& registry, const std::vector<ThrusterCfg>& thrusters, Config& cfg, BookReport& rep) {
    xlsx::Book book; std::string err;
    if (!xlsx::readFile(path, book, err)) { rep.errors.push_back(err); return false; }
    return readBook(book, registry, thrusters, cfg, rep);
}

}  // namespace pu
}  // namespace dp
