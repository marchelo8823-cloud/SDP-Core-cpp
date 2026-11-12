// Связь с работающей системой ДП другого изготовителя (Praxis, Kongsberg и др.).
// Режимы: ПАССИВНЫЙ (по умолчанию) — только приём данных чужой системы по сети или последовательному порту и сравнение с нашим решением;
// АКТИВНЫЙ — включается вручную, администратором (команда ext active on <код>), и позволяет отправлять в чужую систему строки по шаблонам из настроек
// (ext send <шаблон>). Без шаблонов из документации изготовителя отправлять нечего — по умолчанию их нет. Каждая отправка пишется в журнал.
// ⚠ Форматы собственных посылок Praxis и Kongsberg здесь не зашиты: стандартные NMEA разбираются (GGA, RMC, HDT и др.), остальное — через поля fields в настройках.
#pragma once
#include <algorithm>
#include <cmath>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "dp/config.hpp"
#include "dp/hub.hpp"
#include "dp/io.hpp"

namespace dp {

struct ExtSignal {                   // один сигнал внешней системы (из таблицы fields)
    std::string name, group, unit, ch, cmp;
    bool has = false; double value = 0, ageS = 1e9;
    bool haveOurs = false; double ours = 0, delta = 0;   // наша величина для сверки (заполняет runtime)
};

struct ExtStatus {
    bool enabled = false, active = false, linked = false;
    std::string vendor;
    double ageS = 1e9;                   // с последнего принятого сообщения
    bool havePos = false, haveHdg = false;
    double n = 0, e = 0, psiDeg = 0;     // положение и курс по данным чужой системы (в нашей локальной системе)
    double dPosM = 0, dHdgDeg = 0;       // расхождение с нашим решением
    long long lines = 0, sent = 0;
    std::map<std::string, double> fields;
    std::vector<ExtSignal> sig;
    std::vector<std::string> raw;        // последние принятые и отправленные строки (новые в конце)
    std::string note;
};

class ExtLink {
public:
    explicit ExtLink(ExtLinkCfg c) : cfg_(std::move(c)) {
        for (auto& in : cfg_.inputs) { ChannelCfg ch = in.ch; hub_.addChannel(ch); if (first_.empty()) first_ = ch.id; }
    }
    ~ExtLink() { stop(); }
    const ExtLinkCfg& cfg() const { return cfg_; }

    void start() {
        for (auto& in : cfg_.inputs) {
            std::unique_ptr<Channel> ch;
            if (in.transport == "udp") ch = std::make_unique<UdpChannel>(in.port, in.bind);
            else if (in.transport == "tcp") ch = std::make_unique<TcpChannel>(in.host, in.port);
            else ch = std::make_unique<SerialChannel>(in.device, in.baud);
            const std::string id = in.ch.id;
            ch->start([this, id](const std::string& line) { onLine(id, line, monotonicSeconds()); });
            chans_.push_back(std::move(ch));
        }
    }
    void stop() { for (auto& c : chans_) c->stop(); chans_.clear(); }

    // Приём одной строки (из сети или вручную для проверки и обучения).
    void onLine(const std::string& id, const std::string& line, double now) {
        { std::lock_guard<std::mutex> lk(m_);
          ++lines_; lastRx_ = now; pushRaw("<< " + line);
          for (const auto& f : cfg_.fields) {
              if (!f.ch.empty() && f.ch != id) continue;
              if (line.compare(0, f.prefix.size(), f.prefix) != 0) continue;
              std::vector<std::string> p; std::string t;
              for (char ch : line) { if (ch == ',' || ch == '*') { p.push_back(t); t.clear(); } else t += ch; }
              p.push_back(t);
              if (f.index >= 0 && static_cast<size_t>(f.index) < p.size()) { try { fields_[f.name] = std::stod(p[f.index]) * f.scale; fieldT_[f.name] = now; } catch (...) {} }
          } }
        hub_.ingest(id, line, now);
    }
    // Строка вручную (проверка, обучение): «ИД|строка» — в канал с этим именем, без префикса — в первый вход
    void inject(const std::string& line, double now) {
        const size_t bar = line.find('|');
        if (bar != std::string::npos && bar > 0 && bar < 24) onLine(line.substr(0, bar), line.substr(bar + 1), now);
        else onLine(first_.empty() ? std::string("EXT") : first_, line, now);
    }

    // Текущее состояние и сравнение с нашим решением (N, E — наше положение, psiDeg — курс). frame — наша система координат (для общего начала).
    ExtStatus status(double now, double ownN, double ownE, double ownPsiDeg, const LocalFrame& frame) {
        if (frame.valid() && !originSet_) { hub_.setOrigin(frame.lat0(), frame.lon0()); originSet_ = true; }
        const SensorFrame fr = hub_.buildFrame(now);
        std::lock_guard<std::mutex> lk(m_);
        for (const auto& p : fr.pos) if (p.fresh) { n_ = p.n - p.offset.x; e_ = p.e - p.offset.y; havePos_ = true; }
        for (const auto& h : fr.hdg) if (h.fresh) { psi_ = h.psi * 180.0 / M_PI; haveHdg_ = true; }
        ExtStatus s; s.enabled = true; s.active = active_; s.vendor = cfg_.vendor; s.lines = lines_; s.sent = sent_;
        s.ageS = lines_ > 0 ? now - lastRx_ : 1e9; s.linked = s.ageS <= cfg_.lostS;
        s.havePos = havePos_; s.haveHdg = haveHdg_; s.n = n_; s.e = e_; s.psiDeg = psi_; s.fields = fields_;
        if (havePos_) s.dPosM = std::hypot(n_ - ownN, e_ - ownE);
        if (haveHdg_) { double d = std::fmod(psi_ - ownPsiDeg, 360.0); if (d > 180) d -= 360; if (d < -180) d += 360; s.dHdgDeg = d; }
        for (const auto& f : cfg_.fields) {
            ExtSignal g; g.name = f.name; g.group = f.group; g.unit = f.unit; g.ch = f.ch; g.cmp = f.cmp;
            auto it = fields_.find(f.name); if (it != fields_.end()) { g.has = true; g.value = it->second; g.ageS = now - fieldT_[f.name]; }
            s.sig.push_back(g);
        }
        // потеря связи при активном режиме: отправка выключается сама, включить заново можно только вручную
        if (active_ && lines_ > 0 && !s.linked) { active_ = false; s.active = false; s.note = "связь потеряна — активный режим выключен автоматически"; }
        s.raw.assign(raw_.begin(), raw_.end());
        return s;
    }

    // Активный режим: вручную, с кодом подтверждения «ДА-<vendor>».
    bool setActive(bool on, const std::string& code, std::string& why) {
        std::lock_guard<std::mutex> lk(m_);
        if (!on) { active_ = false; return true; }
        if (cfg_.txPort <= 0 || cfg_.templates.empty()) { why = "для отправки нет настроек tx и шаблонов (templates): добавьте их по документации изготовителя"; return false; }
        if (code != "ДА-" + cfg_.vendor && code != "YES-" + cfg_.vendor) { why = "для включения введите код подтверждения: ext active on ДА-" + cfg_.vendor; return false; }
        active_ = true; return true;
    }
    bool active() const { std::lock_guard<std::mutex> lk(m_); return active_; }

    // Отправка строки по шаблону (только в активном режиме). vars — подстановки {имя}.
    bool send(const std::string& tplName, const std::map<std::string, std::string>& vars, std::string& out, std::string& why) {
        std::string text;
        { std::lock_guard<std::mutex> lk(m_);
          if (!active_) { why = "активный режим выключен (ext active on <код>)"; return false; }
          const ExtTemplate* tp = nullptr; for (auto& t : cfg_.templates) if (t.name == tplName) tp = &t;
          if (!tp) { why = "нет шаблона «" + tplName + "»"; return false; }
          text = tp->text; }
        { std::lock_guard<std::mutex> lk(m_);
          const ExtTemplate* tp = nullptr; for (auto& t : cfg_.templates) if (t.name == tplName) tp = &t;
          for (const auto& l : tp->limits) {
              auto it = vars.find(l.var);
              if (it == vars.end()) { why = "для шаблона нужен параметр " + l.var + "=<число> (задан предел)"; return false; }
              double v; try { size_t k = 0; v = std::stod(it->second, &k); if (k != it->second.size()) throw 1; } catch (...) { why = "параметр " + l.var + " — не число"; return false; }
              if (v < l.lo || v > l.hi) { char b[160]; std::snprintf(b, sizeof b, "%s=%g вне допустимого диапазона %g…%g", l.var.c_str(), v, l.lo, l.hi); why = b; return false; }
          }
          const double now = monotonicSeconds(); auto lt = lastTx_.find(tplName);
          if (lt != lastTx_.end() && now - lt->second < tp->minIntervalS) { why = "слишком часто: между отправками шаблона «" + tplName + "» не менее " + std::to_string(tp->minIntervalS).substr(0, 4) + " с"; return false; }
          lastTx_[tplName] = now; }
        for (const auto& kv : vars) { const std::string key = "{" + kv.first + "}"; size_t p; while ((p = text.find(key)) != std::string::npos) text.replace(p, key.size(), kv.second); }
        if (text.find('{') != std::string::npos && text.find('}') != std::string::npos) { why = "в шаблоне остались неподставленные поля: " + text; return false; }
        if (!transmit(text + "\r\n", why)) return false;
        { std::lock_guard<std::mutex> lk(m_); ++sent_; pushRaw(">> " + text); }
        out = text; return true;
    }

private:
    void pushRaw(const std::string& s) { raw_.push_back(s); while (raw_.size() > 60) raw_.pop_front(); }
    bool transmit(const std::string& data, std::string& why) {
        netInit();
        const bool tcp = cfg_.txTransport == "tcp";
        addrinfo hints{}, *res = nullptr; hints.ai_family = AF_INET; hints.ai_socktype = tcp ? SOCK_STREAM : SOCK_DGRAM;
        if (::getaddrinfo(cfg_.txHost.c_str(), std::to_string(cfg_.txPort).c_str(), &hints, &res) != 0 || !res) { why = "адрес не найден: " + cfg_.txHost; return false; }
        SockT s = ::socket(res->ai_family, res->ai_socktype, res->ai_protocol);
        if (s == BAD_SOCK) { ::freeaddrinfo(res); why = "не удалось создать сокет"; return false; }
        bool ok = true;
        if (tcp && ::connect(s, res->ai_addr, static_cast<int>(res->ai_addrlen)) != 0) { why = "нет соединения с " + cfg_.txHost; ok = false; }
        if (ok) {
            const int r = tcp ? static_cast<int>(::send(s, data.data(), static_cast<int>(data.size()), 0))
                              : static_cast<int>(::sendto(s, data.data(), static_cast<int>(data.size()), 0, res->ai_addr, static_cast<int>(res->ai_addrlen)));
            if (r < 0) { why = "отправка не удалась"; ok = false; }
        }
        ::freeaddrinfo(res); sockClose(s); return ok;
    }

    ExtLinkCfg cfg_;
    SensorHub hub_;
    std::vector<std::unique_ptr<Channel>> chans_;
    mutable std::mutex m_;
    std::deque<std::string> raw_;
    std::map<std::string, double> fields_, fieldT_, lastTx_;
    std::string first_;
    double lastRx_ = 0, n_ = 0, e_ = 0, psi_ = 0;
    long long lines_ = 0, sent_ = 0;
    bool havePos_ = false, haveHdg_ = false, active_ = false, originSet_ = false;
};

}  // namespace dp
