// Проверка чтения карт BSB/KAP: синтетическая карта с известным рисунком и (необязательно) реальный файл.
#include <cstdio>
#include "dp/bsb.hpp"
#include "dp/geotiff.hpp"
using namespace dp;

static int fails = 0;
#define CHECK(c, msg) do { if (!(c)) { std::printf("ОШИБКА: %s\n", msg); ++fails; } } while (0)
static bool near(double a, double b, double t) { return std::fabs(a - b) <= t; }

static int expected(int x, int y) {          // тот же рисунок, что в генераторе теста
    if (y < 8) return 1;
    if (y < 16) return ((x / 3) % 2 == 0) ? 2 : 3;
    if (y < 24) return x < 40 ? 4 : 1;
    return (x + y) % 4 + 1;
}

int main(int argc, char** argv) {
    auto bytes = geo::readFileBytes(argc > 1 ? argv[1] : "tests/data/test.kap");
    CHECK(!bytes.empty(), "тестовый файл читается");
    bsb::Chart c = bsb::parse(bytes);
    CHECK(c.ok, c.err.c_str());
    CHECK(c.width == 64 && c.height == 48 && c.depth == 4, "размер и глубина цвета");
    CHECK(c.name == "TestChart" && c.projection == "MERCATOR" && c.datum == "WGS84", "название, проекция, датум");
    CHECK(c.refs.size() == 4, "четыре опорные точки");
    CHECK(c.hasColor[1] && c.pal[1][0] == 255 && c.pal[3][2] == 255 && c.pal[4][1] == 20, "палитра");
    bool same = c.pix.size() == 64u * 48u;
    for (int y = 0; same && y < 48; ++y) for (int x = 0; x < 64; ++x) if (c.pix[size_t(y) * 64 + x] != expected(x, y)) { same = false; std::printf("  первое расхождение x=%d y=%d\n", x, y); break; }
    CHECK(same, "пиксели совпадают с рисунком (серии с продолжением и без)");
    CHECK(near(c.fitErrPx, 0, 0.05), "опорные точки согласуются с проекцией");
    // привязка: долгота левого края 10°, правого 11°; север 55°
    CHECK(near((0 - c.bx) / c.ax, 10.0, 1e-9) && near((64 - c.bx) / c.ax, 11.0, 1e-9), "привязка по долготе");
    CHECK(near(c.ay * bsb::detail::mercY(55.0) + c.by, 0, 1e-6), "привязка по широте: верхний край на 55° с.ш.");
    // отказы
    std::vector<uint8_t> junk(200, 7); CHECK(!bsb::parse(junk).ok, "не-KAP отвергается");
    auto cut = bytes; cut.resize(cut.size() - 40); CHECK(!bsb::parse(cut).ok, "обрезанный файл отвергается");
    std::string t(bytes.begin(), bytes.end()); const size_t pos = t.find("PR=MERCATOR"); auto other = bytes;
    if (pos != std::string::npos) { std::string rep = "PR=POLYCONIC"; other.insert(other.begin() + long(pos), rep.begin(), rep.end()); other.erase(other.begin() + long(pos + rep.size()), other.begin() + long(pos + rep.size() + 11)); }
    CHECK(!bsb::parse(other).ok, "незнакомая проекция отвергается с сообщением");
    // реальная карта (необязательно)
    if (argc > 2) {
        auto rb = geo::readFileBytes(argv[2]); bsb::Chart r = bsb::parse(rb);
        std::printf("реальная карта: %s\n", r.ok ? "прочитана" : r.err.c_str());
        CHECK(r.ok && r.width == 8192 && r.height == 3072 && r.rowsRead == 3072, "реальная карта: размер и все строки");
        if (r.ok) {
            std::printf("  палитра: %d цветов, проекция %s, датум %s, невязка привязки %.4f px\n", int(std::count(r.hasColor, r.hasColor + 256, true)), r.projection.c_str(), r.datum.c_str(), r.fitErrPx);
            CHECK(near((0 - r.bx) / r.ax, 19.3359375, 1e-6) && near((8192 - r.bx) / r.ax, 30.5859375, 1e-6), "реальная карта: долготы краёв");
            CHECK(near(r.fitErrPx, 0, 0.01), "реальная карта: опорные точки точно согласуются");
        }
    }
    std::printf(fails ? "bsb_test: ПРОВАЛ (%d)\n" : "bsb_test: всё в порядке\n", fails);
    return fails ? 1 : 0;
}
