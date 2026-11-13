// Книга Excel с данными судна: чтение, обязательные поля, перевод единиц, проверка значений.
// Аргументы: <шаблон судна> <пример судна> <папка с испорченными книгами> <шаблон имитатора> <пример имитатора>
#include <cstdio>
#include <cmath>
#include "dp/shipbook.hpp"
using namespace dp;
static int fails = 0;
#define CHECK(c, m) do { const bool ok_ = (c); std::printf("%s %s\n", ok_ ? "  ok " : "FAIL ", m); if (!ok_) ++fails; } while (0)
static bool has(const std::vector<std::string>& v, const std::string& part) { for (auto& s : v) if (s.find(part) != std::string::npos) return true; return false; }

int main(int argc, char** argv) {
    if (argc < 6) { std::printf("нужны пять аргументов\n"); return 2; }
    const std::string bad = argv[3];
    std::printf("-- пустой шаблон не принимается --\n");
    { AppCfg c; BookReport r; const bool ok = loadShipBook(argv[1], c, r);
      CHECK(!ok, "пустой шаблон отклонён");
      CHECK(has(r.errors, "«Осадка»: не заполнено") && has(r.errors, "«Водоизмещение»: не заполнено"), "названы незаполненные поля корпуса");
      CHECK(has(r.errors, "не описан ни один движитель"), "названо отсутствие движителей");
      CHECK(!has(r.errors, "Источник данных") && !has(r.errors, "Работа"), "листа «Работа» и выбора источника в книге судна больше нет"); }
    std::printf("-- заполненный пример --\n");
    { AppCfg c; BookReport r; const bool ok = loadShipBook(argv[2], c, r);
      for (auto& e : r.errors) std::printf("     %s\n", e.c_str());
      CHECK(ok, "пример принят");
      CHECK(c.vessel.name == "Демонстрационное судно", "название прочитано (кириллица)");
      CHECK(std::fabs(c.vessel.mass - 2.2e6) < 1, "водоизмещение 2200 т переведено в кг");
      CHECK(c.thrusters.size() == 4 && c.thrusters[0].id == "AZ1" && c.thrusters[0].type == ThrusterType::Azimuth, "четыре движителя, первый поворотный");
      CHECK(std::fabs(c.thrusters[0].maxForward - 180000) < 1 && std::fabs(c.thrusters[0].maxReverse - 150000) < 1, "упор 180 и 150 кН переведён в ньютоны");
      CHECK(std::fabs(c.thrusters[2].x - 22) < 1e-9 && c.thrusters[2].type == ThrusterType::Tunnel, "место и тип носового подруливающего");
      CHECK(!c.simEnabled && c.inputs.empty(), "книга судна не включает имитатор; без «Подключения» входов нет");
      CHECK(c.simSensors.gnss.size() == 2 && c.simSensors.gyros == 3 && c.simSensors.anemometers == 2 && c.simSensors.mrus == 2 && c.simSensors.laser && !c.simSensors.wire, "состав датчиков имитатора взят с листа «Датчики»");
      CHECK(std::fabs(c.simSensors.gnss[1].offset.x + 18) < 1e-9 && std::fabs(c.simSensors.gnss[1].sigma - 0.6) < 1e-9, "место и погрешность второго приёмника");
      CHECK(c.originSet && std::fabs(c.originLat - 60.0) < 1e-9 && std::fabs(c.originLon - 29.5) < 1e-9, "район работ");
      CHECK(has(r.defaults, "«Темп упора, %/с»: не задано, принято 25 %/с"), "сообщено о значении по умолчанию");
      CHECK(!r.estimates.empty(), "выданы оценки по введённым данным"); }
    std::printf("-- испорченные книги --\n");
    { AppCfg c; BookReport r; const bool ok = loadShipBook(bad + "/нет_упора.xlsx", c, r);
      CHECK(!ok && has(r.errors, "(BOW1), «Упор вперёд, кН»: не заполнено"), "пустой упор: названы лист, строка и столбец"); }
    { AppCfg c; BookReport r; const bool ok = loadShipBook(bad + "/не_число.xlsx", c, r);
      CHECK(!ok && has(r.errors, "«Осадка»: «четыре» — не число"), "текст вместо числа отклонён"); }
    { AppCfg c; BookReport r; const bool ok = loadShipBook(bad + "/запятая.xlsx", c, r);
      CHECK(ok && std::fabs(c.vessel.draft - 4.5) < 1e-9, "десятичная запятая «4,5» принята"); }
    { AppCfg c; BookReport r; const bool ok = loadShipBook(bad + "/плохой_тип.xlsx", c, r);
      CHECK(!ok && has(r.errors, "«Тип»: укажите"), "неизвестный тип движителя отклонён"); }
    { AppCfg c; BookReport r; const bool ok = loadShipBook(bad + "/вне_корпуса.xlsx", c, r);
      CHECK(ok && has(r.warnings, "вне габаритов корпуса"), "движитель вне корпуса: предупреждение"); }
    { AppCfg c; BookReport r; const bool ok = loadShipBook(bad + "/датчики_часть.xlsx", c, r);
      CHECK(ok && c.inputs.size() == 1 && has(r.warnings, "не заполнено «Подключение» у GNSS2"), "подключён один датчик: вход один, об остальных предупреждение"); }
    { AppCfg c; BookReport r; const bool ok = loadShipBook(bad + "/датчики_плохое_подключение.xlsx", c, r);
      CHECK(!ok && has(r.errors, "«Подключение»: укажите udp, tcp или serial"), "неизвестный вид подключения отклонён"); }
    { AppCfg c; BookReport r; const bool ok = loadShipBook(bad + "/датчики_порт.xlsx", c, r);
      CHECK(ok && !c.simEnabled && c.inputs.size() == 10 && c.inputs[0].transport == "udp" && c.inputs[0].port == 10001, "работа от датчиков: входы с листа «Датчики»"); }
    { AppCfg c; BookReport r; const bool ok = loadShipBook(bad + "/секторы.xlsx", c, r);
      CHECK(ok && c.thrusters[0].forbidden.size() == 2 && std::fabs(c.thrusters[0].forbidden[1].fromDeg - 60) < 1e-9 && std::fabs(c.thrusters[0].rateFracPerS - 0.15) < 1e-9, "запретные сектора и темп 15 %/с прочитаны"); }
    { AppCfg c; BookReport r; const bool ok = loadShipBook(bad + "/выдача.xlsx", c, r);
      for (auto& e : r.errors) std::printf("     %s\n", e.c_str());
      CHECK(ok && c.links.size() == 1 && c.links[0].entries.size() == 2 && c.links[0].port == 1502, "лист «Выдача»: линия Modbus и два регистра"); }
    { AppCfg c; BookReport r; const bool ok = loadShipBook(bad + "/не_книга.xlsx", c, r);
      CHECK(!ok && has(r.errors, "не является книгой Excel"), "посторонний файл отклонён понятным сообщением"); }
    std::printf("-- книга имитатора --\n");
    { SimBook s; BookReport r; const bool ok = loadSimBook(argv[4], s, r);
      CHECK(!ok && has(r.errors, "«Ветер, м/с»: не заполнено"), "пустой шаблон имитатора отклонён"); }
    { SimBook s; BookReport r; const bool ok = loadSimBook(argv[5], s, r);
      CHECK(ok && std::fabs(s.env.windSpeed - 10) < 1e-9 && std::fabs(s.env.currentToDeg - 200) < 1e-9 && std::fabs(s.headingDeg - 10) < 1e-9 && s.speed == 1.0, "пример имитатора прочитан"); }
    { SimBook s; BookReport r; const bool ok = loadSimBook(argv[2], s, r);
      CHECK(!ok && has(r.errors, "похоже, это книга судна"), "книга судна вместо книги имитатора распознана"); }
    std::printf(fails ? "ОШИБОК: %d\n" : "ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ\n", fails);
    return fails ? 1 : 0;
}
