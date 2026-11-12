// Встроенный помощник: поиск по базе знаний (документы, журналы, справка), короткие уроки по терминам ДП и разбор предложений
// изменений из ответа языковой модели. Работает без интернета; облачная модель (Claude API) подключается в окне оператора администратором.
// Помощник сам ничего не меняет: предложенные команды применяет человек кнопкой, права проверяет ядро, каждое применение пишется в журнал.
#pragma once
#include <algorithm>
#include <cctype>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

namespace dp {

struct KbChunk { std::string source, title, text; };
struct KbHit { size_t chunk = 0; double score = 0; std::string source, title, snippet; };

namespace agent_detail {
// Нижний регистр для латиницы и кириллицы в UTF-8; прочее не меняется
inline std::string lowerUtf8(const std::string& s) {
    std::string r; r.reserve(s.size());
    for (size_t i = 0; i < s.size(); ++i) {
        const unsigned char c = static_cast<unsigned char>(s[i]);
        if (c < 0x80) { r += static_cast<char>(std::tolower(c)); continue; }
        if (c == 0xD0 && i + 1 < s.size()) {
            const unsigned char d = static_cast<unsigned char>(s[i + 1]);
            if (d >= 0x90 && d <= 0x9F) { r += static_cast<char>(0xD0); r += static_cast<char>(d + 0x20); ++i; continue; }
            if (d >= 0xA0 && d <= 0xAF) { r += static_cast<char>(0xD1); r += static_cast<char>(d - 0x20); ++i; continue; }
            if (d == 0x81) { r += static_cast<char>(0xD1); r += static_cast<char>(0x91); ++i; continue; }   // Ё → ё
        }
        r += static_cast<char>(c);
    }
    return r;
}
// Слова запроса и текста: буквы и цифры (в том числе любые байты UTF-8), основа — первые 6 символов (грубая обработка окончаний)
inline std::vector<std::string> tokens(const std::string& text) {
    const std::string s = lowerUtf8(text); std::vector<std::string> out; std::string t;
    auto flush = [&]() {
        if (t.empty()) return;
        // обрезка по символам UTF-8, не по байтам
        size_t chars = 0, i = 0; while (i < t.size() && chars < 6) { unsigned char c = static_cast<unsigned char>(t[i]); i += c < 0x80 ? 1 : (c >> 5) == 6 ? 2 : (c >> 4) == 14 ? 3 : 4; ++chars; }
        const std::string w = t.substr(0, std::min(i, t.size()));
        if (chars >= 2 || std::isdigit(static_cast<unsigned char>(w[0]))) out.push_back(w);
        t.clear();
    };
    for (char ch : s) { const unsigned char c = static_cast<unsigned char>(ch); if (c >= 0x80 || std::isalnum(c) || c == '_') t += ch; else flush(); }
    flush(); return out;
}
}  // namespace agent_detail

class KnowledgeBase {
public:
    // Добавляет документ: делит на фрагменты по абзацам и заголовкам (до ~700 символов)
    void addText(const std::string& source, const std::string& text) {
        std::string title = source, cur; std::istringstream is(text); std::string line;
        auto flush = [&]() { if (cur.size() > 20) { chunks_.push_back({source, title, cur}); } cur.clear(); };
        while (std::getline(is, line)) {
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (line.rfind("#", 0) == 0) { flush(); size_t k = line.find_first_not_of("# "); title = k == std::string::npos ? source : line.substr(k); cur = title + "\n"; continue; }
            if (line.empty()) { if (cur.size() > 350) flush(); continue; }
            cur += line + "\n"; if (cur.size() > 700) flush();
        }
        flush(); dirty_ = true;
    }
    // Загружает файлы папки (txt, md, json, csv, ini, log, cfg), до 2 МБ каждый, вложенные папки тоже
    int addDir(const std::string& dir) {
        namespace fs = std::filesystem; int n = 0; std::error_code ec;
        if (!fs::exists(dir, ec)) return 0;
        for (auto it = fs::recursive_directory_iterator(dir, fs::directory_options::skip_permission_denied, ec); !ec && it != fs::recursive_directory_iterator(); it.increment(ec)) {
            if (!it->is_regular_file(ec)) continue;
            std::string ext = it->path().extension().string(); std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char c) { return std::tolower(c); });
            if (ext != ".txt" && ext != ".md" && ext != ".json" && ext != ".csv" && ext != ".ini" && ext != ".log" && ext != ".cfg") continue;
            if (it->file_size(ec) > 2u * 1024 * 1024) continue;
            std::ifstream f(it->path(), std::ios::binary); if (!f) continue;
            std::stringstream ss; ss << f.rdbuf(); addText(it->path().filename().string(), ss.str()); ++n;
        }
        return n;
    }
    size_t size() const { return chunks_.size(); }
    const std::vector<KbChunk>& chunks() const { return chunks_; }

    // Поиск по смыслу слов: TF-IDF; в заголовке слово весит больше
    std::vector<KbHit> search(const std::string& query, size_t k = 5) {
        build();
        const auto q = agent_detail::tokens(query); std::map<std::string, int> qtf; for (auto& w : q) ++qtf[w];
        std::vector<KbHit> hits;
        for (size_t i = 0; i < chunks_.size(); ++i) {
            double score = 0;
            for (auto& kv : qtf) {
                auto f = tf_[i].find(kv.first); if (f == tf_[i].end()) continue;
                auto d = df_.find(kv.first); const double idf = std::log(1.0 + static_cast<double>(chunks_.size()) / (d == df_.end() ? 1 : d->second));
                score += (1.0 + std::log(static_cast<double>(f->second))) * idf * kv.second;
            }
            if (score <= 0) continue;
            score /= std::sqrt(static_cast<double>(len_[i]) + 10.0);
            hits.push_back({i, score, chunks_[i].source, chunks_[i].title, snippet(chunks_[i].text, q)});
        }
        std::sort(hits.begin(), hits.end(), [](const KbHit& a, const KbHit& b) { return a.score > b.score; });
        if (hits.size() > k) hits.resize(k);
        return hits;
    }
    // Заголовки уроков (разделы «## …» файла glossary*.md)
    std::vector<std::string> lessons() const {
        std::vector<std::string> r; std::set<std::string> seen;
        for (auto& c : chunks_) if (c.source.rfind("glossary", 0) == 0 && seen.insert(c.title).second) r.push_back(c.title);
        return r;
    }
    std::string lesson(const std::string& title) const {
        std::string t; for (auto& c : chunks_) if (c.source.rfind("glossary", 0) == 0 && c.title == title) t += c.text + "\n";
        return t;
    }

private:
    // Фрагмент около первого найденного слова запроса (по основе слова)
    static std::string snippet(const std::string& t, const std::vector<std::string>& q) {
        if (t.size() <= 420) return t;
        const std::string low = agent_detail::lowerUtf8(t); size_t pos = std::string::npos;
        for (auto& w : q) { const size_t p = low.find(w); if (p != std::string::npos && (pos == std::string::npos || p < pos)) pos = p; }
        size_t a = 0; if (pos != std::string::npos && pos > 150) { a = pos - 150; while (a > 0 && (static_cast<unsigned char>(t[a]) & 0xC0) == 0x80) --a; const size_t nl = t.rfind('\n', a); if (nl != std::string::npos && a - nl < 120) a = nl + 1; }
        std::string s = t.substr(a, 420); while (!s.empty() && (static_cast<unsigned char>(s.back()) & 0xC0) == 0x80) s.pop_back();
        return (a ? "…" : "") + s + (a + 420 < t.size() ? "…" : "");
    }
    void build() {
        if (!dirty_) return;
        tf_.assign(chunks_.size(), {}); len_.assign(chunks_.size(), 0); df_.clear();
        for (size_t i = 0; i < chunks_.size(); ++i) {
            for (auto& w : agent_detail::tokens(chunks_[i].text)) { ++tf_[i][w]; ++len_[i]; }
            for (auto& w : agent_detail::tokens(chunks_[i].title)) { tf_[i][w] += 2; }
            for (auto& kv : tf_[i]) ++df_[kv.first];
        }
        dirty_ = false;
    }
    std::vector<KbChunk> chunks_;
    std::vector<std::map<std::string, int>> tf_; std::vector<size_t> len_; std::map<std::string, int> df_;
    bool dirty_ = true;
};

// Системное сообщение для языковой модели: роль, ограничения, формат предложений
inline std::string agentSystemPrompt(const std::string& shipStatus) {
    return "Ты помощник оператора системы динамического позиционирования (СДП). Отвечай по-русски, кратко и по делу. "
           "Опирайся только на приведённые фрагменты базы знаний и состояние системы; если данных нет — так и скажи, не придумывай значения. "
           "Ты ничего не меняешь сам. Если предлагаешь изменение, перечисли консольные команды системы блоком ```commands (по одной в строке), "
           "после блока объясни, зачем каждая. Разрешены только команды настройки и управления из справки (help); никогда не предлагай quit, ext active, смену пароля. "
           "Любое изменение применит человек после проверки.\nСостояние системы:\n" + shipStatus;
}
inline std::string agentUserPrompt(const std::string& question, const std::vector<KbHit>& hits) {
    std::string s = "Вопрос оператора: " + question + "\n\nФрагменты базы знаний:\n";
    for (size_t i = 0; i < hits.size(); ++i) s += "[" + std::to_string(i + 1) + "] (" + hits[i].source + " — " + hits[i].title + ")\n" + hits[i].snippet + "\n";
    return s;
}

// Предложения изменений из ответа: строки блока ```commands … ``` (или ```cmd). Запрещённые команды отбрасываются и перечисляются в rejected.
inline std::vector<std::string> parseProposals(const std::string& reply, std::vector<std::string>* rejected = nullptr) {
    std::vector<std::string> out; std::istringstream is(reply); std::string line; bool in = false;
    static const std::set<std::string> deny = {"quit", "exit", "ext", "kbadd", "chpw", "login", "logout"};
    while (std::getline(is, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        std::string t = line; t.erase(0, t.find_first_not_of(" \t"));
        if (t.rfind("```", 0) == 0) { if (in) in = false; else { const std::string tag = t.substr(3); in = (tag == "commands" || tag == "cmd" || tag == "команды"); } continue; }
        if (!in || t.empty() || t[0] == '#') continue;
        if (t.rfind("> ", 0) == 0 || t.rfind("$ ", 0) == 0) t = t.substr(2);
        std::istringstream ls(t); std::string c; ls >> c;
        if (deny.count(c)) { if (rejected) rejected->push_back(t); continue; }
        out.push_back(t);
    }
    return out;
}

}  // namespace dp
