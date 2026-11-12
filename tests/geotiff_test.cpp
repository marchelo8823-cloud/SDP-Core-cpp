// Проверка проекций и разбора привязки GeoTIFF (без Qt).
#include <cstdio>
#include <cstring>
#include "dp/geotiff.hpp"
using namespace dp::geo;

static int fails = 0;
#define CHECK(c, msg) do { if (!(c)) { std::printf("ОШИБКА: %s\n", msg); ++fails; } } while (0)
static bool near(double a, double b, double tol) { return std::fabs(a - b) <= tol; }

// собираем минимальный TIFF (little-endian) только с тегами, без пикселей
struct Tag { uint16_t tag, type; uint32_t cnt; std::vector<uint8_t> data; };
static void put16(std::vector<uint8_t>& v, uint16_t x) { v.push_back(x & 255); v.push_back(x >> 8); }
static void put32(std::vector<uint8_t>& v, uint32_t x) { for (int i = 0; i < 4; ++i) v.push_back((x >> (8 * i)) & 255); }
static Tag shortTag(uint16_t tag, std::vector<uint16_t> vals) { Tag t{tag, 3, uint32_t(vals.size()), {}}; for (auto x : vals) put16(t.data, x); return t; }
static Tag longTag(uint16_t tag, uint32_t x) { Tag t{tag, 4, 1, {}}; put32(t.data, x); return t; }
static Tag dblTag(uint16_t tag, std::vector<double> vals) { Tag t{tag, 12, uint32_t(vals.size()), {}}; for (double x : vals) { uint64_t u; std::memcpy(&u, &x, 8); for (int i = 0; i < 8; ++i) t.data.push_back((u >> (8 * i)) & 255); } return t; }

static std::vector<uint8_t> makeTiff(std::vector<Tag> tags) {
    std::sort(tags.begin(), tags.end(), [](const Tag& a, const Tag& b) { return a.tag < b.tag; });
    std::vector<uint8_t> v = {'I', 'I', 42, 0}; put32(v, 8);
    put16(v, uint16_t(tags.size()));
    size_t extra = 8 + 2 + 12 * tags.size() + 4;
    std::vector<uint8_t> blob;
    for (auto& t : tags) {
        put16(v, t.tag); put16(v, t.type); put32(v, t.cnt);
        if (t.data.size() <= 4) { auto d = t.data; d.resize(4); v.insert(v.end(), d.begin(), d.end()); }
        else { put32(v, uint32_t(extra + blob.size())); blob.insert(blob.end(), t.data.begin(), t.data.end()); }
    }
    put32(v, 0);
    v.insert(v.end(), blob.begin(), blob.end());
    return v;
}

int main() {
    // 1. UTM: экватор на осевом меридиане зоны 31 -> (500000, 0)
    Proj u31; CHECK(projFromEpsg(32631, u31), "EPSG:32631");
    double x, y; forward(u31, 0.0, 3.0, x, y);
    CHECK(near(x, 500000, 0.01) && near(y, 0, 0.01), "UTM: экватор на осевом меридиане");
    // Эйфелева башня: 48.8584 N, 2.2945 E -> зона 31N: E=448252 (известное значение), N≈5411955 (сверено независимым расчётом по дуге меридиана)
    forward(u31, 48.8584, 2.2945, x, y);
    CHECK(near(x, 448252, 3) && near(y, 5411955, 3), "UTM: Эйфелева башня");
    // зона 37 (Москва 55.7558, 37.6173): E~413 тыс., N~6179 тыс. — сверяем круговым преобразованием и грубо
    Proj u37; projFromEpsg(32637, u37); forward(u37, 55.7558, 37.6173, x, y);
    CHECK(near(x, 413000, 3000) && near(y, 6179000, 6000), "UTM: Москва грубо");
    double la, lo; inverse(u37, x, y, la, lo);
    CHECK(near(la, 55.7558, 1e-8) && near(lo, 37.6173, 1e-8), "UTM: круговое преобразование");
    // юг
    Proj s56; projFromEpsg(32756, s56); forward(s56, -33.8568, 151.2153, x, y);   // Сидней
    CHECK(near(x, 334000, 3000) && near(y, 6252000, 5000), "UTM юг: Сидней грубо");
    inverse(s56, x, y, la, lo); CHECK(near(la, -33.8568, 1e-8) && near(lo, 151.2153, 1e-8), "UTM юг: круг");
    // 2. Web Mercator
    Proj wm; projFromEpsg(3857, wm); forward(wm, 0, 180, x, y);
    CHECK(near(x, 20037508.34, 0.01) && near(y, 0, 1e-6), "Mercator: край мира");
    forward(wm, 60, 30, x, y); inverse(wm, x, y, la, lo); CHECK(near(la, 60, 1e-9) && near(lo, 30, 1e-9), "Mercator: круг");
    CHECK(!projFromEpsg(2154, wm), "неизвестная проекция должна отвергаться");

    // 3. разбор GeoTIFF: UTM-37, пиксель 2 м, левый верхний угол (413000, 6179000), «область»
    auto t1 = makeTiff({longTag(256, 1000), longTag(257, 500), shortTag(258, {8}), shortTag(259, {1}), shortTag(262, {2}), shortTag(277, {3}),
                        dblTag(33550, {2, 2, 0}), dblTag(33922, {0, 0, 0, 413000, 6179000, 0}),
                        shortTag(34735, {1, 1, 0, 3, 1024, 0, 1, 1, 1025, 0, 1, 1, 3072, 0, 1, 32637})});
    TiffInfo i1 = parseTiff(t1);
    CHECK(i1.ok && i1.width == 1000 && i1.height == 500, "TIFF: размеры");
    CHECK(i1.georef && i1.epsg == 32637 && !i1.geographic, "TIFF: EPSG 32637");
    CHECK(near(i1.a, 2, 1e-9) && near(i1.e, -2, 1e-9) && near(i1.c, 413000, 1e-6) && near(i1.f, 6179000, 1e-6), "TIFF: аффинное преобразование");
    // «точка»: сдвиг на полпикселя
    auto t2 = makeTiff({longTag(256, 10), longTag(257, 10), dblTag(33550, {1, 1, 0}), dblTag(33922, {0, 0, 0, 100, 200, 0}),
                        shortTag(34735, {1, 1, 0, 2, 1024, 0, 1, 1, 1025, 0, 1, 2})});
    TiffInfo i2 = parseTiff(t2);
    CHECK(i2.georef && near(i2.c, 99.5, 1e-9) && near(i2.f, 200.5, 1e-9), "TIFF: PixelIsPoint");
    // географическая
    auto t3 = makeTiff({longTag(256, 360), longTag(257, 180), dblTag(33550, {1, 1, 0}), dblTag(33922, {0, 0, 0, -180, 90, 0}),
                        shortTag(34735, {1, 1, 0, 3, 1024, 0, 1, 2, 1025, 0, 1, 1, 2048, 0, 1, 4326})});
    TiffInfo i3 = parseTiff(t3);
    CHECK(i3.georef && i3.geographic && i3.epsg == 4326, "TIFF: градусы WGS84");
    // без привязки и не TIFF
    auto t4 = makeTiff({longTag(256, 10), longTag(257, 10)});
    CHECK(parseTiff(t4).ok && !parseTiff(t4).georef, "TIFF без привязки");
    std::vector<uint8_t> junk(64, 7); CHECK(!parseTiff(junk).ok, "мусор не TIFF");
    std::printf(fails ? "geotiff_test: ПРОВАЛ (%d)\n" : "geotiff_test: всё в порядке\n", fails);
    return fails ? 1 : 0;
}
