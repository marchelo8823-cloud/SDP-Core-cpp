// Судовое время (решение владельца 17.11.2026). Внутри — всегда UTC; на экране — судовое время = UTC + пояс судна.
// Источник UTC: GNSS (ZDA, RMC) по умолчанию; часы компьютера — запасной, если времени GNSS нет (или по выбору оператора).
// Сверка: время GNSS сравнивается с часами компьютера (TIME_PC_DIFF), само с собой (скачок, замёрзшее время, увод — TIME_JUMP)
// и приёмники между собой (TIME_RX_DIFF). Показ — от одного основного приёмника, другой берётся, только если основной замолчал.
// Пояс: при первом известном положении — по долготе (морской пояс, 15° на час); дальше при переходе в другой пояс — только
// предупреждение TIME_ZONE, переводит оператор (zone accept), как на судне — по распоряжению. До положения — пояс компьютера.
// В имитации — часы компьютера (время имитатора ускоряется и показывается отдельно).
// Только время и пояс: регулятор, распределитель упоров и оценку состояния не затрагивает.
#pragma once
#include <chrono>
#include <cmath>
#include <cstdio>
#include <ctime>
#include <cstdlib>
#include <map>
#include <string>
#include <vector>

namespace dp {

// Дни от 1970-01-01 по гражданской дате (алгоритм Х. Хиннанта), без часовых поясов.
inline long long daysFromCivil(int y, int m, int d) {
    y -= m <= 2;
    const long long era = (y >= 0 ? y : y - 399) / 400;
    const unsigned yoe = static_cast<unsigned>(y - era * 400);
    const unsigned doy = (153u * static_cast<unsigned>(m + (m > 2 ? -3 : 9)) + 2u) / 5u + static_cast<unsigned>(d) - 1u;
    const unsigned doe = yoe * 365u + yoe / 4u - yoe / 100u + doy;
    return era * 146097 + static_cast<long long>(doe) - 719468;
}

// «hhmmss[.ss]» и дата → секунды UTC от 1970 года; false — поля пусты или вне диапазона.
inline bool nmeaUtc(const std::string& hms, int day, int month, int year, double& utc) {
    if (hms.size() < 6 || day < 1 || month < 1 || month > 12 || year < 1980 || year > 2200) return false;
    if (day > daysFromCivil(month == 12 ? year + 1 : year, month == 12 ? 1 : month + 1, 1) - daysFromCivil(year, month, 1)) return false;   // 31.02 и т. п.
    for (int i = 0; i < 6; ++i) if (hms[i] < '0' || hms[i] > '9') return false;
    const int hh = (hms[0] - '0') * 10 + (hms[1] - '0'), mm = (hms[2] - '0') * 10 + (hms[3] - '0');
    const double ss = std::atof(hms.c_str() + 4);
    if (hh > 23 || mm > 59 || ss < 0 || ss >= 61) return false;
    utc = static_cast<double>(daysFromCivil(year, month, day)) * 86400.0 + hh * 3600.0 + mm * 60.0 + ss;
    return true;
}

inline double pcUtcNow() { return std::chrono::duration<double>(std::chrono::system_clock::now().time_since_epoch()).count(); }

// Пояс компьютера, минуты к UTC (+180 — Москва).
inline int pcZoneMin() {
    const std::time_t t = std::time(nullptr);
    std::tm lt{}, gt{};
#if defined(_WIN32)
    localtime_s(&lt, &t); gmtime_s(&gt, &t);
#else
    localtime_r(&t, &lt); gmtime_r(&t, &gt);
#endif
    gt.tm_isdst = lt.tm_isdst;
    return static_cast<int>(std::lround(std::difftime(std::mktime(&lt), std::mktime(&gt)) / 60.0));
}

inline std::string zoneText(int min) {
    char b[24]; const int a = std::abs(min);
    if (a % 60) std::snprintf(b, sizeof b, "UTC%c%d:%02d", min < 0 ? '-' : '+', a / 60, a % 60);
    else std::snprintf(b, sizeof b, "UTC%c%d", min < 0 ? '-' : '+', a / 60);
    return b;
}
inline std::string hmsText(double utc, int zoneMin) {
    long long s = static_cast<long long>(std::floor(utc + zoneMin * 60.0)); s %= 86400; if (s < 0) s += 86400;
    char b[16]; std::snprintf(b, sizeof b, "%02lld:%02lld:%02lld", s / 3600, (s / 60) % 60, s % 60); return b;
}
inline std::string dateText(double utc, int zoneMin) {   // ДД.ММ.ГГГГ (гражданский календарь из дней)
    long long z = static_cast<long long>(std::floor((utc + zoneMin * 60.0) / 86400.0)) + 719468;
    const long long era = (z >= 0 ? z : z - 146096) / 146097; const unsigned doe = static_cast<unsigned>(z - era * 146097);
    const unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; const long long y = static_cast<long long>(yoe) + era * 400;
    const unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100), mp = (5 * doy + 2) / 153, d = doy - (153 * mp + 2) / 5 + 1, m = mp < 10 ? mp + 3 : mp - 9;
    char b[40]; std::snprintf(b, sizeof b, "%02u.%02u.%04lld", d, m, y + (m <= 2)); return b;
}

struct TimeMsg { std::string code, text; int prio; };   // prio: 2 — предупреждение, 3 — сообщение

class ShipTime {
public:
    enum Source { Gnss = 0, Pc = 1 };
    double gnssFreshS = 5.0;     // время GNSS считается свежим столько секунд после приёма
    double maxDiffS = 2.0;       // допустимое расхождение GNSS и часов компьютера, с
    double jumpS = 2.0;          // скачок времени GNSS больше этого — предупреждение
    double jumpHoldS = 60.0;     // предупреждение о скачке держится столько секунд
    double zoneHystDeg = 0.25;   // гистерезис границы пояса по долготе, °

    // Время UTC от приёмника ch: utc — секунды от 1970, at — часы приёма (те же, что у update: монотонные или время имитатора).
    // Скачок ищется у каждого приёмника отдельно (два приёмника с разным временем — не скачок) по смещению utc − at
    // относительно его опорного: так ловится и скачок, и замёрзшее время, и увод. Одиночный выброс (пачка строк из буфера)
    // не считается — нужны два приёма подряд вне допуска.
    void feedGnss(double utc, double at, const std::string& ch = "") {
        if (!std::isfinite(utc) || !std::isfinite(at)) return;
        Rx& r = rx_[ch]; const double off = utc - at;
        if (!r.has) { r.ref = off; r.bad = 0; }
        else if (at - r.at > 30.0) {   // после перерыва пачки быть не может — одного приёма вне допуска достаточно
            if (std::fabs(off - r.ref) > jumpS) { jumpUntil_ = at + jumpHoldS; jumpBy_ = off - r.ref; jumpCh_ = ch; }
            r.ref = off; r.bad = 0;
        }
        else if (std::fabs(off - r.ref) > jumpS) {
            if (++r.bad >= 2) { jumpUntil_ = at + jumpHoldS; jumpBy_ = off - r.ref; jumpCh_ = ch; r.ref = off; r.bad = 0; }
        } else { r.ref += 0.05 * (off - r.ref); r.bad = 0; }   // медленно следует за дрожанием приёма
        r.at = at; r.utc = utc; r.has = true;
        // показ — от одного (основного) приёмника: первый, от которого пришло время; другой — только если основной замолчал
        auto it = rx_.find(primary_);
        if (it == rx_.end() || at - it->second.at > gnssFreshS) primary_ = ch;
        const Rx& p = rx_[primary_]; gUtc_ = p.utc; gAt_ = p.at; hasG_ = true;
    }

    // now — те же часы, что в feedGnss; pcUtc — часы компьютера (UTC); lonValid/lonDeg — долгота судна; sim — работает имитатор.
    void update(double now, double pcUtc, bool lonValid, double lonDeg, bool sim, std::vector<TimeMsg>& out, std::vector<std::string>& infos) {
        now_ = now; sim_ = sim;
        const bool fresh = hasG_ && now - gAt_ <= gnssFreshS;
        usingGnss_ = !sim && src_ == Gnss && fresh;
        utc_ = usingGnss_ ? gUtc_ + (now - gAt_) : pcUtc;
        if (!sim && src_ == Gnss && !fresh && !fallbackSaid_) { infos.push_back("Время: нет данных GNSS (ZDA, RMC) — судовое время по часам компьютера"); fallbackSaid_ = true; }
        if (fresh) fallbackSaid_ = false;
        if (!sim && fresh) {
            pcDiff_ = gUtc_ + (now - gAt_) - pcUtc;
            if (std::fabs(pcDiff_) > maxDiffS) {
                char b[256]; std::snprintf(b, sizeof b, "Часы компьютера расходятся с GNSS на %.0f с — судовое время %s", pcDiff_, usingGnss_ ? "по GNSS" : "по компьютеру (выбрано оператором)");
                out.push_back({"TIME_PC_DIFF", b, 2});
            }
        } else pcDiff_ = 0;
        if (!sim && now < jumpUntil_) {
            char b[256]; std::snprintf(b, sizeof b, "Скачок или задержка времени GNSS%s%s на %.0f с — сбой приёмника, задержка передачи или подмена сигнала; проверьте приёмник", jumpCh_.empty() ? "" : " ", jumpCh_.c_str(), jumpBy_);
            out.push_back({"TIME_JUMP", b, 2});
        }
        // приёмники между собой: расхождение больше maxDiffS — одно предупреждение, показ остаётся от основного
        if (!sim && fresh) {
            const double pu = gUtc_ + (now - gAt_); double worst = 0; std::string who;
            for (const auto& kv : rx_) {
                if (kv.first == primary_ || !kv.second.has || now - kv.second.at > gnssFreshS) continue;
                const double d = kv.second.utc + (now - kv.second.at) - pu;
                if (std::fabs(d) > std::fabs(worst)) { worst = d; who = kv.first; }
            }
            if (std::fabs(worst) > maxDiffS) {
                char b[256]; std::snprintf(b, sizeof b, "Время приёмников GNSS расходится: %s на %.0f с от %s — судовое время по %s", who.c_str(), worst, primary_.c_str(), primary_.c_str());
                out.push_back({"TIME_RX_DIFF", b, 2});
            }
        }
        // пояс по долготе
        if (lonValid && std::isfinite(lonDeg)) {
            const int sug = suggestFrom(lonDeg);
            if (!zoneSet_) { zone_ = sug; zoneSet_ = true; ackSug_ = sug; char b[160]; std::snprintf(b, sizeof b, "Судовое время: %s (по долготе %.1f°)", zoneText(zone_).c_str(), lonDeg); infos.push_back(b); }
            sug_ = sug; sugValid_ = true;
        }
        if (!zoneSet_) zone_ = pcZoneMin();
        if (zoneSet_ && sugValid_ && sug_ != zone_ && sug_ != ackSug_) {
            const std::string t = "Судно в поясе " + zoneText(sug_) + ", судовое время " + zoneText(zone_) + " — перевести: «Настройки» → «Перевести» (zone accept)";
            out.push_back({"TIME_ZONE", t, 2});
        }
    }

    // Команды оператора.
    std::string setSource(Source s) { src_ = s; fallbackSaid_ = false; return s == Gnss ? "Источник времени: GNSS (если нет — часы компьютера)." : "Источник времени: часы компьютера."; }
    std::string accept() {
        if (!sugValid_) return "Пояс по положению ещё не известен.";
        const int was = zone_; zone_ = sug_; zoneSet_ = true; ackSug_ = sug_;
        return "Судовое время переведено: " + zoneText(was) + " → " + zoneText(zone_) + ".";
    }
    std::string setZone(int min) {
        if (min < -12 * 60 || min > 14 * 60) return "Пояс: от UTC-12 до UTC+14.";
        const int was = zone_; zone_ = min; zoneSet_ = true; ackSug_ = sugValid_ ? sug_ : min;
        return "Судовое время задано вручную: " + zoneText(was) + " → " + zoneText(zone_) + ".";
    }
    std::string setZonePc() { return setZone(pcZoneMin()); }

    double utc() const { return utc_; }
    int zoneMin() const { return zone_; }
    bool usingGnss() const { return usingGnss_; }
    Source source() const { return src_; }
    bool gnssFresh() const { return hasG_ && now_ - gAt_ <= gnssFreshS; }
    double pcDiff() const { return pcDiff_; }
    bool suggestValid() const { return sugValid_; }
    int suggestMin() const { return sug_; }
    bool zonePending() const { return zoneSet_ && sugValid_ && sug_ != zone_ && sug_ != ackSug_; }
    std::string clock() const { return hmsText(utc_, zone_); }
    std::string sourceText() const { return usingGnss_ ? "GNSS" : sim_ ? "компьютер (имитация)" : src_ == Pc ? "компьютер" : "компьютер (нет GNSS)"; }
    std::string status() const {
        char b[240]; std::snprintf(b, sizeof b, "Судовое время %s %s (%s), UTC %s; источник: %s%s", dateText(utc_, zone_).c_str(), clock().c_str(), zoneText(zone_).c_str(),
                                   hmsText(utc_, 0).c_str(), sourceText().c_str(), sugValid_ ? (", пояс по долготе " + zoneText(sug_)).c_str() : "");
        return b;
    }

private:
    Source src_ = Gnss;
    bool sim_ = false, hasG_ = false, usingGnss_ = false, zoneSet_ = false, sugValid_ = false, fallbackSaid_ = false;
    double gUtc_ = 0, gAt_ = -1e9, utc_ = 0, now_ = 0, pcDiff_ = 0, jumpUntil_ = -1e9, jumpBy_ = 0;
    struct Rx { bool has = false; double at = -1e9, utc = 0, ref = 0; int bad = 0; };
    std::map<std::string, Rx> rx_; std::string jumpCh_, primary_;
    int zone_ = pcZoneMin(), sug_ = 0, ackSug_ = 0;

    int suggestFrom(double lon) const {   // морской пояс: целые часы по 15° долготы, с гистерезисом у границы
        lon = std::remainder(lon, 360.0);   // −180…180 без цикла (вызывающий отбрасывает нечисловую долготу)
        if (sugValid_) {
            const double centre = sug_ / 60.0 * 15.0;
            if (std::fabs(std::remainder(lon - centre, 360.0)) <= 7.5 + zoneHystDeg) return sug_;   // и через ±180°
        }
        int h = static_cast<int>(std::lround(lon / 15.0)); if (h > 12) h = 12; if (h < -12) h = -12;
        return h * 60;
    }
};

}  // namespace dp
