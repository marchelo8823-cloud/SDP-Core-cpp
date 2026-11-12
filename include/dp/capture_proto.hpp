// Запись и разбор обмена (v0.24): записи, выделение сообщений, статистика по типам сообщений и полям,
// разбор Modbus TCP / RTU (карта регистров), выгрузка в CSV и pcap. Здесь нет ввода-вывода по сети: всё проверяется тестами без оборудования.
// Назначение — снять обмен чужой системы ДП так, чтобы по записи можно было восстановить протокол и заменить программную часть.
// ⚠ Разбор Modbus и статистика — эвристики для анализа записи. Сама запись (сырые байты со временем) от них не зависит и всегда полная.
#pragma once
#include <algorithm>
#include <bitset>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

namespace dp {
namespace cap {

// ---------------------------------------------------------------- запись обмена
struct Rec {
    double t = 0;          // время (с, UNIX)
    std::string ch;        // имя канала
    std::string dir;       // RX, TX, A, B, A>B, B>A, ОПРОС→, ←ОПРОС, МЕТКА
    std::string data;      // сырые байты
    std::string peer;      // откуда пришло (адрес:порт) — если известно
    bool dgram = false;    // целая датаграмма (UDP): границы сообщения известны
};

inline std::string hexOf(const std::string& s, size_t maxBytes = 0, bool spaced = true) {
    static const char* d = "0123456789ABCDEF";
    std::string r; const size_t n = maxBytes && s.size() > maxBytes ? maxBytes : s.size();
    for (size_t i = 0; i < n; ++i) { const unsigned char c = static_cast<unsigned char>(s[i]); if (spaced && i) r += ' '; r += d[c >> 4]; r += d[c & 15]; }
    if (n < s.size()) r += "…";
    return r;
}
inline bool fromHex(const std::string& h, std::string& out) {
    out.clear(); int hi = -1;
    for (char c : h) {
        int v;
        if (c >= '0' && c <= '9') v = c - '0'; else if (c >= 'A' && c <= 'F') v = c - 'A' + 10; else if (c >= 'a' && c <= 'f') v = c - 'a' + 10;
        else if (c == ' ') continue; else return false;
        if (hi < 0) hi = v; else { out += static_cast<char>(hi * 16 + v); hi = -1; }
    }
    return hi < 0;
}
// Текст для просмотра: печатные ASCII как есть, управляющие — условными знаками, остальное — «·».
inline std::string asciiOf(const std::string& s, size_t maxBytes = 0) {
    std::string r; const size_t n = maxBytes && s.size() > maxBytes ? maxBytes : s.size();
    for (size_t i = 0; i < n; ++i) {
        const unsigned char c = static_cast<unsigned char>(s[i]);
        if (c == '\r') r += "\\r"; else if (c == '\n') r += "\\n"; else if (c == '\t') r += "\\t";
        else if (c >= 32 && c < 127) r += static_cast<char>(c); else r += "·";
    }
    if (n < s.size()) r += "…";
    return r;
}
inline std::string jq(const std::string& s) {
    std::string r = "\"";
    for (char ch : s) {
        const unsigned char c = static_cast<unsigned char>(ch);
        if (c == '"' || c == '\\') { r += '\\'; r += ch; }
        else if (c == '\n') r += "\\n"; else if (c == '\r') r += "\\r"; else if (c == '\t') r += "\\t";
        else if (c < 32) { char b[8]; std::snprintf(b, sizeof b, "\\u%04x", c); r += b; }
        else r += ch;
    }
    return r + "\"";
}
inline std::string num(double v, int prec = 6) { char b[48]; std::snprintf(b, sizeof b, "%.*g", prec, v); return b; }
inline std::string isoTime(double t) {
    const time_t s = static_cast<time_t>(t); std::tm tm{};
#ifdef _WIN32
    gmtime_s(&tm, &s);
#else
    gmtime_r(&s, &tm);
#endif
    char b[96]; std::snprintf(b, sizeof b, "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec, static_cast<int>((t - std::floor(t)) * 1000));
    return b;
}

// CSV: время_unix, время_iso, канал, направление, длина, hex, текст (в кавычках).
inline std::string csvHeader() { return "t_unix,t_iso,channel,dir,len,hex,text,peer\n"; }
inline std::string csvQ(const std::string& s) { std::string r = "\""; for (char c : s) { if (c == '"') r += "\"\""; else r += c; } return r + "\""; }
inline std::string csvRow(const Rec& r) {
    char tb[32]; std::snprintf(tb, sizeof tb, "%.6f", r.t);
    return std::string(tb) + "," + isoTime(r.t) + "," + csvQ(r.ch) + "," + csvQ(r.dir) + "," + std::to_string(r.data.size()) + "," + hexOf(r.data) + "," + csvQ(r.dir == "МЕТКА" ? r.data : asciiOf(r.data)) + "," + csvQ(r.peer) + "\n";
}
// Чтение CSV, записанного csvRow (текст берём из hex — он точнее).
inline bool loadCsv(const std::string& path, std::vector<Rec>& out, std::string& err) {
    std::ifstream f(path); if (!f) { err = "файл не открыт: " + path; return false; }
    std::string line; std::getline(f, line);
    auto field = [](const std::string& s, size_t& i) {
        std::string r;
        if (i < s.size() && s[i] == '"') { ++i; while (i < s.size()) { if (s[i] == '"') { if (i + 1 < s.size() && s[i + 1] == '"') { r += '"'; i += 2; continue; } ++i; break; } r += s[i++]; } }
        else while (i < s.size() && s[i] != ',') r += s[i++];
        if (i < s.size() && s[i] == ',') ++i;
        return r;
    };
    while (std::getline(f, line)) {
        if (line.empty()) continue;
        size_t i = 0; Rec r; const std::string tu = field(line, i); field(line, i); r.ch = field(line, i); r.dir = field(line, i); field(line, i);
        const std::string hx = field(line, i); field(line, i); r.peer = field(line, i);
        r.t = std::atof(tu.c_str());
        if (!fromHex(hx, r.data)) { err = "испорченная строка: " + line.substr(0, 60); return false; }
        out.push_back(std::move(r));
    }
    return true;
}

// pcap (Wireshark): тип канала 147 (USER0). Кадр: [номер канала][код направления][байты].
inline int dirCode(const std::string& d) {
    static const char* names[] = {"RX", "TX", "A", "B", "A>B", "B>A", "ОПРОС→", "←ОПРОС", "МЕТКА"};
    for (int i = 0; i < 9; ++i) if (d == names[i]) return i;
    return 9;
}
inline std::string pcapHeader() {
    std::string o; auto u32 = [&](uint32_t v) { for (int i = 0; i < 4; ++i) o += static_cast<char>((v >> (8 * i)) & 255); };
    auto u16 = [&](uint16_t v) { o += static_cast<char>(v & 255); o += static_cast<char>(v >> 8); };
    u32(0xa1b2c3d4); u16(2); u16(4); u32(0); u32(0); u32(65535); u32(147);
    return o;
}
inline std::string pcapPacket(const Rec& r, int chIdx) {
    std::string o; auto u32 = [&](uint32_t v) { for (int i = 0; i < 4; ++i) o += static_cast<char>((v >> (8 * i)) & 255); };
    const uint32_t n = static_cast<uint32_t>(std::min<size_t>(r.data.size(), 65000)) + 2;
    const double ip = std::floor(r.t);
    u32(static_cast<uint32_t>(ip)); u32(static_cast<uint32_t>((r.t - ip) * 1e6)); u32(n); u32(n);
    o += static_cast<char>(chIdx & 255); o += static_cast<char>(dirCode(r.dir)); o.append(r.data, 0, n - 2);
    return o;
}
inline std::string pcapFile(const std::vector<Rec>& recs) {
    std::string o = pcapHeader(); std::map<std::string, int> idx;
    for (const auto& r : recs) { auto it = idx.find(r.ch); if (it == idx.end()) it = idx.emplace(r.ch, static_cast<int>(idx.size())).first; o += pcapPacket(r, it->second); }
    return o;
}

// ---------------------------------------------------------------- Modbus
inline uint16_t crc16(const uint8_t* d, size_t n) {
    uint16_t crc = 0xFFFF;
    for (size_t i = 0; i < n; ++i) { crc ^= d[i]; for (int b = 0; b < 8; ++b) crc = (crc & 1) ? static_cast<uint16_t>((crc >> 1) ^ 0xA001) : static_cast<uint16_t>(crc >> 1); }
    return crc;
}
struct MbFrame { int unit = 0, fc = 0, tid = -1; std::string pdu; bool rtu = false; };   // pdu — без кода функции
enum class MbDir { Unknown, Request, Response };

inline const char* mbFcName(int fc) {
    switch (fc & 0x7F) {
        case 1: return "чтение катушек"; case 2: return "чтение дискретных входов"; case 3: return "чтение регистров хранения"; case 4: return "чтение входных регистров";
        case 5: return "запись катушки"; case 6: return "запись регистра"; case 15: return "запись катушек"; case 16: return "запись регистров";
        case 22: return "маскированная запись"; case 23: return "чтение и запись регистров"; case 43: return "идентификация"; default: return "другая функция";
    }
}

// Выделение кадров из потока (TCP: по MBAP; RTU: по контрольной сумме CRC16).
class MbFramer {
public:
    explicit MbFramer(bool rtu) : rtu_(rtu) {}
    long crcErrors = 0, resync = 0;
    void feed(double t, const std::string& chunk, std::vector<MbFrame>& out) {
        if (rtu_ && !buf_.empty() && t - lastT_ > 0.05) { crcErrors += 1; buf_.clear(); }     // пауза больше 50 мс: хвост неполного кадра
        lastT_ = t; buf_ += chunk;
        if (rtu_) rtu(out); else tcp(out);
    }
private:
    void tcp(std::vector<MbFrame>& out) {
        for (;;) {
            if (buf_.size() < 8) return;
            const auto* b = reinterpret_cast<const uint8_t*>(buf_.data());
            const size_t len = (static_cast<size_t>(b[4]) << 8) | b[5];
            if (b[2] != 0 || b[3] != 0 || len < 2 || len > 254) { buf_.erase(0, 1); ++resync; continue; }
            if (buf_.size() < 6 + len) return;
            MbFrame f; f.tid = (b[0] << 8) | b[1]; f.unit = b[6]; f.fc = b[7]; f.pdu = buf_.substr(8, len - 2);
            out.push_back(std::move(f)); buf_.erase(0, 6 + len);
        }
    }
    void rtu(std::vector<MbFrame>& out) {
        for (;;) {
            if (buf_.size() < 4) return;
            const auto* b = reinterpret_cast<const uint8_t*>(buf_.data());
            bool found = false;
            for (size_t n = 4; n <= std::min<size_t>(buf_.size(), 256); ++n) {
                if (crc16(b, n) == 0 && b[0] <= 247) {
                    MbFrame f; f.rtu = true; f.unit = b[0]; f.fc = b[1]; f.pdu = buf_.substr(2, n - 4);
                    out.push_back(std::move(f)); buf_.erase(0, n); found = true; break;
                }
            }
            if (found) continue;
            if (buf_.size() >= 256) { buf_.erase(0, 1); ++resync; continue; }
            return;
        }
    }
    bool rtu_; std::string buf_; double lastT_ = 0;
};

struct MbReg { int unit = 0, table = 0, addr = 0; uint16_t value = 0, vmin = 0, vmax = 0; long updates = 0, changes = 0, writes = 0; double firstT = 0, lastT = 0; bool written = false; };
inline const char* mbTable(int t) { static const char* n[] = {"катушка", "дискретный вход", "входной регистр", "регистр хранения"}; return n[t & 3]; }

class MbTracker {
public:
    long frames = 0, requests = 0, responses = 0, exceptions = 0, unpaired = 0;
    std::map<int, long> fcCount;
    std::map<std::pair<int, int>, MbReg> regs;     // (unit·4+таблица, адрес)
    std::string lastNote;

    // Разобрать кадр. hint — известное направление (опрос, роль стороны), иначе по ожидающим запросам.
    void add(double t, const MbFrame& f, MbDir hint = MbDir::Unknown) {
        ++frames; ++fcCount[f.fc & 0x7F];
        const bool exc = (f.fc & 0x80) != 0;
        const std::pair<int, int> key = {f.unit, f.rtu ? -1 : f.tid};
        MbDir d = hint;
        if (d == MbDir::Unknown) {
            if (exc) d = MbDir::Response;
            else {
                auto it = pend_.find(key);
                d = (it != pend_.end() && it->second.fc == f.fc) ? MbDir::Response : MbDir::Request;
            }
        }
        if (exc) { ++exceptions; ++responses; pend_.erase(key); lastNote = "исключение " + std::to_string(f.pdu.empty() ? 0 : static_cast<uint8_t>(f.pdu[0])) + " на функцию " + std::to_string(f.fc & 0x7F); return; }
        if (d == MbDir::Request) { ++requests; request(t, f, key); }
        else { ++responses; response(t, f, key); }
    }
    std::string json(size_t maxRegs = 300) const {
        std::string j = "{\"frames\":" + std::to_string(frames) + ",\"requests\":" + std::to_string(requests) + ",\"responses\":" + std::to_string(responses) + ",\"exceptions\":" + std::to_string(exceptions) + ",\"unpaired\":" + std::to_string(unpaired) + ",\"fc\":{";
        bool first = true; for (auto& kv : fcCount) { j += std::string(first ? "" : ",") + "\"" + std::to_string(kv.first) + "\":" + std::to_string(kv.second); first = false; }
        j += "},\"regs\":[";
        size_t n = 0; first = true;
        for (auto& kv : regs) {
            if (n++ >= maxRegs) break; const MbReg& r = kv.second;
            j += std::string(first ? "" : ",") + "{\"u\":" + std::to_string(r.unit) + ",\"tb\":" + std::to_string(r.table) + ",\"a\":" + std::to_string(r.addr) + ",\"v\":" + std::to_string(r.value) + ",\"mn\":" + std::to_string(r.vmin) + ",\"mx\":" + std::to_string(r.vmax)
                + ",\"n\":" + std::to_string(r.updates) + ",\"c\":" + std::to_string(r.changes) + ",\"w\":" + std::to_string(r.writes) + ",\"t\":" + num(r.lastT, 15) + "}";
            first = false;
        }
        return j + "]}";
    }
    // Таблица регистров в CSV для выгрузки.
    std::string registersCsv() const {
        std::string s = "unit,table,address,last,min,max,updates,changes,writes,first_t,last_t\n";
        for (auto& kv : regs) { const MbReg& r = kv.second; s += std::to_string(r.unit) + "," + mbTable(r.table) + "," + std::to_string(r.addr) + "," + std::to_string(r.value) + "," + std::to_string(r.vmin) + "," + std::to_string(r.vmax) + "," + std::to_string(r.updates) + "," + std::to_string(r.changes) + "," + std::to_string(r.writes) + "," + num(r.firstT, 15) + "," + num(r.lastT, 15) + "\n"; }
        return s;
    }
private:
    struct Pend { int fc = 0, addr = 0, count = 0; };
    static int u16(const std::string& s, size_t i) { return (static_cast<uint8_t>(s[i]) << 8) | static_cast<uint8_t>(s[i + 1]); }
    void put(double t, int unit, int table, int addr, uint16_t v, bool write) {
        MbReg& r = regs[{unit * 4 + table, addr}];
        if (r.updates == 0) { r.unit = unit; r.table = table; r.addr = addr; r.value = r.vmin = r.vmax = v; r.firstT = t; }
        else { if (v != r.value) ++r.changes; r.value = v; r.vmin = std::min(r.vmin, v); r.vmax = std::max(r.vmax, v); }
        ++r.updates; r.lastT = t; if (write) { ++r.writes; r.written = true; }
    }
    void request(double t, const MbFrame& f, const std::pair<int, int>& key) {
        const std::string& p = f.pdu; Pend q; q.fc = f.fc;
        if ((f.fc >= 1 && f.fc <= 6) && p.size() >= 4) { q.addr = u16(p, 0); q.count = (f.fc <= 4) ? u16(p, 2) : 1; }
        if (f.fc == 5 && p.size() >= 4) put(t, f.unit, 0, u16(p, 0), u16(p, 2) == 0xFF00 ? 1 : 0, true);
        else if (f.fc == 6 && p.size() >= 4) put(t, f.unit, 3, u16(p, 0), static_cast<uint16_t>(u16(p, 2)), true);
        else if (f.fc == 16 && p.size() >= 5) {
            const int a = u16(p, 0), n = u16(p, 2), bc = static_cast<uint8_t>(p[4]); q.addr = a; q.count = n;
            if (p.size() >= 5 + static_cast<size_t>(bc) && bc == n * 2) for (int i = 0; i < n; ++i) put(t, f.unit, 3, a + i, static_cast<uint16_t>(u16(p, 5 + 2 * i)), true);
        } else if (f.fc == 15 && p.size() >= 5) {
            const int a = u16(p, 0), n = u16(p, 2), bc = static_cast<uint8_t>(p[4]); q.addr = a; q.count = n;
            if (p.size() >= 5 + static_cast<size_t>(bc)) for (int i = 0; i < n && i / 8 < bc; ++i) put(t, f.unit, 0, a + i, (static_cast<uint8_t>(p[5 + i / 8]) >> (i % 8)) & 1, true);
        }
        pend_[key] = q;
    }
    void response(double t, const MbFrame& f, const std::pair<int, int>& key) {
        auto it = pend_.find(key);
        if (it == pend_.end() || it->second.fc != f.fc) { ++unpaired; return; }
        const Pend q = it->second; pend_.erase(it); const std::string& p = f.pdu;
        if ((f.fc == 3 || f.fc == 4) && !p.empty()) {
            const int bc = static_cast<uint8_t>(p[0]); const int n = std::min(bc / 2, q.count);
            if (static_cast<size_t>(bc) + 1 <= p.size()) for (int i = 0; i < n; ++i) put(t, f.unit, f.fc == 3 ? 3 : 2, q.addr + i, static_cast<uint16_t>(u16(p, 1 + 2 * i)), false);
        } else if ((f.fc == 1 || f.fc == 2) && !p.empty()) {
            const int bc = static_cast<uint8_t>(p[0]);
            for (int i = 0; i < q.count && i / 8 < bc && 1 + static_cast<size_t>(i / 8) < p.size(); ++i) put(t, f.unit, f.fc == 1 ? 0 : 1, q.addr + i, (static_cast<uint8_t>(p[1 + i / 8]) >> (i % 8)) & 1, false);
        }
    }
    std::map<std::pair<int, int>, Pend> pend_;
};

// ---------------------------------------------------------------- выделение сообщений и статистика
enum class Framing { Auto, Text, Datagram, Binary, ModbusTcp, ModbusRtu };
inline Framing framingFromName(const std::string& n) {
    if (n == "text") return Framing::Text; if (n == "datagram") return Framing::Datagram; if (n == "binary") return Framing::Binary;
    if (n == "modbus-tcp") return Framing::ModbusTcp; if (n == "modbus-rtu") return Framing::ModbusRtu; return Framing::Auto;
}
inline bool looksText(const std::string& s) {
    if (s.empty()) return false; size_t ok = 0;
    for (unsigned char c : s) if ((c >= 32 && c < 127) || c == '\r' || c == '\n' || c == '\t') ++ok;
    return ok * 100 >= s.size() * 95;
}
inline std::string signatureOf(const std::string& m, bool text) {
    if (text) {
        size_t i = 0; std::string r;
        if (!m.empty() && (m[0] == '$' || m[0] == '!')) { r += m[0]; ++i; }
        size_t k = 0; while (i < m.size() && k < 14 && (std::isalnum(static_cast<unsigned char>(m[i])) || m[i] == '_')) { r += m[i]; ++i; ++k; }
        return r.empty() || r == "$" || r == "!" ? std::string("текст") : r;
    }
    return "bin " + hexOf(m.substr(0, 2)) + " /" + std::to_string(m.size()) + " Б";
}

struct FieldStat { long n = 0; std::set<std::string> vals; bool overflow = false, numeric = true; double mn = 0, mx = 0, last = 0; std::string lastText; };
struct SigStat {
    std::string sig, dir; bool text = true; long count = 0; double first = 0, last = 0, minDt = 1e18, maxDt = 0, sumDt = 0; size_t minLen = 1 << 30, maxLen = 0; std::string sample;
    std::vector<FieldStat> fields;          // текст: поля через запятую
    std::vector<std::bitset<256>> bytes;    // двоичные: значения по позициям
    std::vector<int> firstByte;
};

class Analyzer {
public:
    explicit Analyzer(Framing f = Framing::Auto) : fr_(f) {}
    long records = 0, bytes = 0;
    double firstT = 0, lastT = 0;
    std::map<std::string, SigStat> sigs;     // ключ: направление|сигнатура
    MbTracker mb; long mbCrcErrors() const { long n = 0; for (auto& kv : fram_) n += kv.second.crcErrors; return n; }
    std::string modeName() const { return mode_; }

    void add(const Rec& r, MbDir mbHint = MbDir::Unknown) {
        if (r.dir == "МЕТКА") return;
        if (records == 0) firstT = r.t;
        ++records; bytes += static_cast<long long>(r.data.size()); lastT = r.t;
        Framing f = fr_;
        if (f == Framing::Auto) { if (decided_ == Framing::Auto) { sniff_ += r.data; if (sniff_.size() >= 48 || r.data.find('\n') != std::string::npos) { decided_ = looksModbus(sniff_) ? Framing::ModbusRtu : (looksText(sniff_) ? Framing::Text : Framing::Binary); sniffDone(); } } f = decided_ == Framing::Auto ? Framing::Binary : decided_; }
        mode_ = f == Framing::Text ? "текст" : f == Framing::Binary ? "двоичный" : f == Framing::Datagram ? "датаграммы" : f == Framing::ModbusTcp ? "Modbus TCP" : f == Framing::ModbusRtu ? "Modbus RTU" : "авто";
        if (f == Framing::ModbusTcp || f == Framing::ModbusRtu) {
            std::vector<MbFrame> fs; auto fit = fram_.find(r.dir); if (fit == fram_.end()) fit = fram_.emplace(r.dir, MbFramer(f == Framing::ModbusRtu)).first; fit->second.feed(r.t, r.data, fs);
            for (auto& fr : fs) { mb.add(r.t, fr, mbHint); addMsg(r.t, r.dir, "Modbus fc" + std::to_string(fr.fc & 0x7F) + " unit " + std::to_string(fr.unit), std::string(1, static_cast<char>(fr.fc)) + fr.pdu, false); }
            return;
        }
        if (f == Framing::Binary || f == Framing::Datagram) {
            if (looksText(r.data) && (f == Framing::Datagram || false)) { splitLines(r.t, r.dir, r.data); return; }
            addMsg(r.t, r.dir, signatureOf(r.data, false), r.data, false); return;
        }
        // текстовый поток: собираем строки
        std::string& acc = lineBuf_[r.dir]; acc += r.data;
        size_t p;
        while ((p = acc.find_first_of("\r\n")) != std::string::npos) { std::string line = acc.substr(0, p); acc.erase(0, p + 1); if (!line.empty()) addMsg(r.t, r.dir, signatureOf(line, true), line, true); }
        if (r.dgram && !acc.empty()) { addMsg(r.t, r.dir, signatureOf(acc, true), acc, true); acc.clear(); }
        if (acc.size() > 4096) acc.clear();
    }

    std::string json(size_t maxSig = 60) const {
        std::string j = "{\"mode\":" + jq(mode_) + ",\"records\":" + std::to_string(records) + ",\"bytes\":" + std::to_string(bytes) + ",\"t0\":" + num(firstT, 15) + ",\"t1\":" + num(lastT, 15) + ",\"sigs\":[";
        std::vector<const SigStat*> v; for (auto& kv : sigs) v.push_back(&kv.second);
        std::sort(v.begin(), v.end(), [](const SigStat* a, const SigStat* b) { return a->count > b->count; });
        for (size_t i = 0; i < v.size() && i < maxSig; ++i) {
            const SigStat& s = *v[i]; const double span = s.last - s.first;
            j += std::string(i ? "," : "") + "{\"sig\":" + jq(s.sig) + ",\"dir\":" + jq(s.dir) + ",\"n\":" + std::to_string(s.count) + ",\"hz\":" + num(span > 0 ? (s.count - 1) / span : 0, 4)
                + ",\"dtmin\":" + num(s.count > 1 ? s.minDt : 0, 4) + ",\"dtmax\":" + num(s.maxDt, 4) + ",\"lmin\":" + std::to_string(s.minLen == (1 << 30) ? 0 : s.minLen) + ",\"lmax\":" + std::to_string(s.maxLen)
                + ",\"sample\":" + jq(s.text ? s.sample : hexOf(s.sample, 48)) + ",\"txt\":" + (s.text ? "true" : "false") + ",\"fields\":[";
            if (s.text) for (size_t k = 0; k < s.fields.size(); ++k) {
                const FieldStat& fs = s.fields[k];
                j += std::string(k ? "," : "") + "{\"i\":" + std::to_string(k) + ",\"d\":" + std::to_string(fs.vals.size()) + ",\"ov\":" + (fs.overflow ? "true" : "false")
                    + ",\"num\":" + (fs.numeric && fs.n ? "true" : "false") + ",\"mn\":" + num(fs.mn) + ",\"mx\":" + num(fs.mx) + ",\"last\":" + jq(fs.lastText) + "}";
            } else for (size_t k = 0; k < s.bytes.size() && k < 64; ++k) j += std::string(k ? "," : "") + "{\"i\":" + std::to_string(k) + ",\"d\":" + std::to_string(s.bytes[k].count()) + "}";
            j += "]}";
        }
        return j + "],\"modbus\":" + (mb.frames ? mb.json() : std::string("null")) + "}";
    }
    // Текстовый отчёт.
    std::string report(const std::string& title) const {
        std::ostringstream o; o << "Отчёт по обмену: " << title << "\nРежим разбора: " << mode_ << "\nЗаписей: " << records << ", байт: " << bytes << ", интервал: " << (lastT - firstT) << " с\n\n";
        std::vector<const SigStat*> v; for (auto& kv : sigs) v.push_back(&kv.second);
        std::sort(v.begin(), v.end(), [](const SigStat* a, const SigStat* b) { return a->count > b->count; });
        for (const SigStat* s : v) {
            const double span = s->last - s->first;
            o << "[" << s->dir << "] " << s->sig << ": " << s->count << " шт., " << (span > 0 ? (s->count - 1) / span : 0) << " Гц, длина " << s->minLen << "…" << s->maxLen << ", период " << (s->count > 1 ? s->minDt : 0) << "…" << s->maxDt << " с\n  пример: " << (s->text ? s->sample : hexOf(s->sample, 64)) << "\n";
            if (s->text) for (size_t k = 0; k < s->fields.size(); ++k) { const FieldStat& f = s->fields[k]; o << "  поле " << k << ": разных значений " << f.vals.size() << (f.overflow ? "+" : "") << (f.numeric && f.n ? ", число " + num(f.mn) + "…" + num(f.mx) : "") << (f.vals.size() == 1 ? " (постоянное: " + *f.vals.begin() + ")" : "") << "\n"; }
            else { o << "  байты (разных значений): "; for (size_t k = 0; k < s->bytes.size() && k < 64; ++k) o << (k ? " " : "") << k << ":" << s->bytes[k].count(); o << "\n"; }
        }
        if (mb.frames) { o << "\nModbus: кадров " << mb.frames << ", запросов " << mb.requests << ", ответов " << mb.responses << ", исключений " << mb.exceptions << ", без пары " << mb.unpaired << "\n"; for (auto& kv : mb.fcCount) o << "  функция " << kv.first << " (" << mbFcName(kv.first) << "): " << kv.second << "\n"; }
        return o.str();
    }
private:
    static bool looksModbus(const std::string&) { return false; }      // автоопределение Modbus по байтам ненадёжно: тип задаёт оператор
    void sniffDone() { sniff_.clear(); }
    void splitLines(double t, const std::string& dir, const std::string& d) {
        size_t s = 0;
        while (s < d.size()) { size_t e = d.find_first_of("\r\n", s); if (e == std::string::npos) e = d.size(); if (e > s) { const std::string line = d.substr(s, e - s); addMsg(t, dir, signatureOf(line, true), line, true); } s = e + 1; }
    }
    void addMsg(double t, const std::string& dir, const std::string& sig, const std::string& m, bool text) {
        SigStat& s = sigs[dir + "|" + sig];
        if (s.count == 0) { s.sig = sig; s.dir = dir; s.text = text; s.first = t; } else { const double dt = t - s.last; s.minDt = std::min(s.minDt, dt); s.maxDt = std::max(s.maxDt, dt); s.sumDt += dt; }
        ++s.count; s.last = t; s.minLen = std::min(s.minLen, m.size()); s.maxLen = std::max(s.maxLen, m.size()); s.sample = m.size() > 160 ? m.substr(0, 160) : m;
        if (sigs.size() > 400) return;
        if (text) {
            size_t k = 0, st = 0; const size_t star = m.find('*'); const std::string body = star == std::string::npos ? m : m.substr(0, star);
            while (st <= body.size() && k < 24) {
                size_t e = body.find(',', st); if (e == std::string::npos) e = body.size();
                const std::string v = body.substr(st, e - st);
                if (s.fields.size() <= k) s.fields.resize(k + 1);
                FieldStat& f = s.fields[k]; ++f.n; f.lastText = v;
                if (f.vals.size() < 20) f.vals.insert(v); else if (!f.vals.count(v)) f.overflow = true;
                char* endp = nullptr; const double x = std::strtod(v.c_str(), &endp);
                if (!v.empty() && endp && *endp == '\0') { if (f.n == 1 || !f.numeric) { if (f.n == 1) { f.mn = f.mx = x; } } else { f.mn = std::min(f.mn, x); f.mx = std::max(f.mx, x); } f.last = x; }
                else if (!v.empty()) f.numeric = false;
                ++k; st = e + 1; if (e == body.size()) break;
            }
        } else {
            if (s.bytes.size() < m.size() && s.bytes.size() < 256) s.bytes.resize(std::min<size_t>(m.size(), 256));
            for (size_t i = 0; i < m.size() && i < s.bytes.size(); ++i) s.bytes[i].set(static_cast<uint8_t>(m[i]));
        }
    }
    Framing fr_, decided_ = Framing::Auto; std::string mode_ = "авто", sniff_;
    std::map<std::string, std::string> lineBuf_;
    std::map<std::string, MbFramer> fram_;
};

}  // namespace cap
}  // namespace dp
