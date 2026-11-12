// Статус ДП по образцу ASOG/CAMO (Rolls-Royce DP Operations Manual, гл. 8): ЗЕЛЁНЫЙ / СИНИЙ (совет) / ЖЁЛТЫЙ (избыточность потеряна) / КРАСНЫЙ (потеря контроля или положения).
// ⚠ Правила здесь общие, по сообщениям системы. Реальные пределы и действия определяет ASOG конкретного судна и операции — этот статус их не заменяет.
#pragma once
#include <string>
#include <vector>

#include "dp/engine.hpp"

namespace dp {

enum class DpStatus { Green = 0, Blue = 1, Yellow = 2, Red = 3 };

struct AsogInput {
    std::vector<Alarm> alarms;           // действующие сообщения
    bool posValid = true, hdgValid = true, posDropout = false;
    int posUsable = 0, gyroUsable = 0;   // сколько систем положения / гирокомпасов исправны
    int dpClass = 0;                     // 0 — избыточность не требуется; 2 и 3 — требуется ≥ 2 независимых систем положения и гирокомпасов
    bool operating = true;               // ДП включена (в ручном режиме статус не оценивается)
};
struct AsogResult {
    DpStatus status = DpStatus::Green;
    std::string name, action, reasons;   // название, действие по ASOG, причины через «; »
};

inline AsogResult evaluateAsog(const AsogInput& in) {
    AsogResult r; std::vector<std::string> red, yellow, blue;
    auto has = [&](const char* code) { for (auto& a : in.alarms) if (a.code == code) return true; return false; };
    auto hasPrefix = [&](const char* p) { for (auto& a : in.alarms) if (a.code.rfind(p, 0) == 0) return true; return false; };
    if (!in.operating) { r.name = "—"; r.action = "ДП не включена"; return r; }
    if (!in.posValid || has("POS_LOST")) red.push_back("положение потеряно");
    if (in.posDropout || has("POS_DROPOUT")) red.push_back("нет измерений положения дольше допустимого");
    if (has("POS_ALL_REJ")) red.push_back("все системы положения отклонены");
    if (!in.hdgValid || has("HDG_LOST")) red.push_back("курс потерян");
    if (has("BLACKOUT")) red.push_back("потеря электропитания");
    if (has("HOLD_AREA_EXIT")) red.push_back("выход из допустимой зоны");
    if (has("RADIUS_OUT")) red.push_back("отклонение больше допустимого радиуса");
    if (has("SATURATION")) red.push_back("движители насыщены");
    if (has("POWER_SHORT")) red.push_back("не хватает мощности");
    if (in.dpClass >= 2) {          // избыточность DP-2/DP-3: не менее двух независимых систем положения и двух гирокомпасов
        if (in.posUsable < 2 && in.posValid) yellow.push_back("систем положения в работе меньше двух");
        if (in.gyroUsable < 2 && in.hdgValid) yellow.push_back("гирокомпасов в работе меньше двух");
    }
    if (has("WORST_CASE") || has("CQ_THRUST") || has("CQ_POWER")) yellow.push_back("после худшего отказа тяги/питания не хватит");
    if (has("BUS_DEAD_A") || has("BUS_DEAD_B")) yellow.push_back("шина обесточена");
    if (has("TIE_CLOSED")) yellow.push_back("шиносоединитель замкнут");
    if (hasPrefix("THR_FB_MISMATCH_")) yellow.push_back("движитель не отрабатывает команду");
    if (has("LOW_RESERVE") || has("POWER_LIMIT")) yellow.push_back("мощность ограничивает тягу");
    if (has("MRU_LOST")) yellow.push_back("нет данных МИО");
    if (has("GYRO_DISAGREE")) yellow.push_back("гирокомпасы расходятся");
    if (has("POS_MEDIAN")) yellow.push_back("система положения отброшена медианным тестом");
    for (auto& a : in.alarms) {     // всё остальное, что действует, — совет (СИНИЙ)
        const std::string& c = a.code;
        const bool known = c == "POS_LOST" || c == "POS_DROPOUT" || c == "POS_ALL_REJ" || c == "HDG_LOST" || c == "BLACKOUT" || c == "HOLD_AREA_EXIT" || c == "RADIUS_OUT" || c == "SATURATION" || c == "POWER_SHORT"
            || c == "WORST_CASE" || c == "CQ_THRUST" || c == "CQ_POWER" || c == "BUS_DEAD_A" || c == "BUS_DEAD_B" || c == "TIE_CLOSED" || c.rfind("THR_FB_MISMATCH_", 0) == 0 || c == "LOW_RESERVE" || c == "POWER_LIMIT"
            || c == "MRU_LOST" || c == "GYRO_DISAGREE" || c == "POS_MEDIAN";
        if (!known && a.level() <= 2) blue.push_back(a.code);
    }
    auto join = [](const std::vector<std::string>& v) { std::string s; for (size_t i = 0; i < v.size(); ++i) s += (i ? "; " : "") + v[i]; return s; };
    if (!red.empty())         { r.status = DpStatus::Red;    r.name = "КРАСНЫЙ — авария";            r.action = "ПРЕКРАТИТЬ ОПЕРАЦИЮ (потеря контроля или положения)"; r.reasons = join(red); }
    else if (!yellow.empty()) { r.status = DpStatus::Yellow; r.name = "ЖЁЛТЫЙ — избыточность потеряна"; r.action = "ГОТОВИТЬСЯ ПРЕКРАТИТЬ ОПЕРАЦИЮ";                     r.reasons = join(yellow); }
    else if (!blue.empty())   { r.status = DpStatus::Blue;   r.name = "СИНИЙ — совет";                r.action = "ОЦЕНИТЬ РИСК, операция может продолжаться";          r.reasons = "активных предупреждений: " + std::to_string(blue.size()); }
    else                      { r.status = DpStatus::Green;  r.name = "ЗЕЛЁНЫЙ — норма";              r.action = "ПРОДОЛЖАТЬ ОПЕРАЦИЮ";                                r.reasons = ""; }
    return r;
}

}  // namespace dp
