// Проверка чтения ZIP (Deflate, хранение, CRC) без Qt. Архив собран Python-библиотекой zipfile.
#include <cstdio>
#include <cstring>
#include "dp/geotiff.hpp"
#include "dp/zipread.hpp"
using namespace dp;

static int fails = 0;
#define CHECK(c, msg) do { if (!(c)) { std::printf("ОШИБКА: %s\n", msg); ++fails; } } while (0)

static bool same(const std::vector<uint8_t>& v, const std::string& s) { return v.size() == s.size() && std::memcmp(v.data(), s.data(), s.size()) == 0; }

int main(int argc, char** argv) {
    const std::string path = argc > 1 ? argv[1] : "tests/data/test.zip";
    auto bytes = geo::readFileBytes(path);
    CHECK(!bytes.empty(), "тестовый архив читается с диска");
    zip::Archive z; std::string err;
    CHECK(z.open(bytes, err), "оглавление ZIP разбирается");
    CHECK(z.entries().size() == 5, "в архиве 5 файлов");
    std::vector<uint8_t> out;
    std::string text; for (int i = 0; i < 300; ++i) text += "Строка номер " + std::to_string(i) + ": проверка распаковки\n";
    auto get = [&](const char* n) { const zip::Entry* e = z.find(n); return e && z.read(*e, out, err); };
    CHECK(get("text.txt") && same(out, text), "Deflate (динамические таблицы): текст совпадает");
    std::string bin; for (int i = 0; i < 1000; ++i) bin.push_back(char((i * 7) & 255));
    CHECK(get("stored.bin") && same(out, bin), "хранение без сжатия");
    CHECK(get("repeat.txt") && same(out, std::string(5000, 'a')), "Deflate: длинные повторы");
    CHECK(get("small.txt") && same(out, "hi"), "Deflate: короткая строка");
    CHECK(get("empty.txt") && out.empty(), "пустой файл");
    // порча данных должна обнаруживаться по контрольной сумме
    auto bad = bytes; for (size_t i = 40; i < 60 && i < bad.size(); ++i) bad[i] ^= 0x55;
    zip::Archive zb; std::string e2; bool anyBad = false;
    if (zb.open(bad, e2)) for (auto& e : zb.entries()) { std::vector<uint8_t> o; std::string e3; if (!zb.read(e, o, e3)) anyBad = true; }
    CHECK(anyBad, "повреждение данных обнаруживается");
    std::vector<uint8_t> junk(100, 3); zip::Archive zj; CHECK(!zj.open(junk, err), "не-ZIP отвергается");
    // дополнительный реальный файл (необязательный): проверяем все записи
    if (argc > 2) {
        auto kb = geo::readFileBytes(argv[2]); zip::Archive zk; std::string e4;
        bool ok = zk.open(kb, e4); int good = 0;
        for (auto& e : zk.entries()) { std::vector<uint8_t> o; std::string e5; if (zk.read(e, o, e5)) ++good; else std::printf("  %s\n", e5.c_str()); }
        std::printf("реальный архив: %d из %zu записей прочитано, CRC сошлись\n", good, zk.entries().size());
        CHECK(ok && good == int(zk.entries().size()), "реальный архив читается целиком");
    }
    std::printf(fails ? "zip_test: ПРОВАЛ (%d)\n" : "zip_test: всё в порядке\n", fails);
    return fails ? 1 : 0;
}
