// Сопряжение с ПУ: реестр сигналов ПЛК, книга сопряжения, проверки.
// Аргументы: <реестр.csv> <шаблон> <пример Бахтемир> <пример Бейсуг> <книга судна> <папка с испорченными книгами>
#include <cmath>
#include <cstdio>
#include <sstream>

#include "dp/pu.hpp"
using namespace dp;
static int fails = 0;
#define CHECK(c, m) do { const bool ok_ = (c); std::printf("%s %s\n", ok_ ? "  ok " : "FAIL ", m); if (!ok_) ++fails; } while (0)
static bool has(const std::vector<std::string>& v, const std::string& part) { for (auto& s : v) if (s.find(part) != std::string::npos) return true; return false; }
static void dump(const BookReport& r) { for (auto& e : r.errors) std::printf("     ошибка: %s\n", e.c_str()); }

int main(int argc, char** argv) {
    if (argc < 7) { std::printf("нужны шесть аргументов\n"); return 2; }
    const std::string bad = argv[6];

    std::printf("-- реестр сигналов --\n");
    pu::Registry reg;
    { BookReport r; const bool ok = pu::loadRegistry(argv[1], reg, r); dump(r);
      CHECK(ok, "реестр прочитан без ошибок");
      CHECK(reg.signals.size() == 146, "146 сигналов");
      int di = 0, dq = 0, ai = 0, aq = 0;
      for (auto& s : reg.signals) { di += s.type == pu::PlcType::DI; dq += s.type == pu::PlcType::DO; ai += s.type == pu::PlcType::AI; aq += s.type == pu::PlcType::AO; }
      CHECK(di == 62 && dq == 66 && ai == 10 && aq == 8, "62 DI, 66 DO, 10 AI, 8 AO");
      const pu::PlcSignal* s = reg.find("%I5.2");
      CHECK(s && s->nameCn == "DP控制请求" && s->nameEn == "DP_control_request" && s->nameRu == "Запрос управления от СДП" && s->dpRelated, "%I5.2: названия на трёх языках, связь с СДП");
      s = reg.find("%IW64");
      CHECK(s && s->differences.find("Бейсуг: %IW100;") != std::string::npos, "отличия по судам с «;» внутри кавычек сохранены");
      s = reg.find("%IW106");
      CHECK(s && s->differences.find("%IW114") != std::string::npos, "отличие ПУ1 Бахтемир (обратная связь на %IW114) сохранено"); }
    { pu::Registry r2; BookReport r;
      std::istringstream in("заголовок\n%I0.0;DO;a;b;c;;\n%X1;DI;a;b;c;;\n%I0.1;DI;a;b;c;;\n%I0.1;DI;a;b;c;;\n%I0.2;DI;a;b;;;\n%I0.3;DI;a\n");
      pu::parseRegistry(in, r2, r);
      CHECK(has(r.errors, "строка 2: тип DO не соответствует адресу %I0.0"), "тип, не подходящий к адресу, — ошибка");
      CHECK(has(r.errors, "строка 3: «%X1» — не адрес ПЛК"), "неверный адрес — ошибка");
      CHECK(has(r.errors, "строка 5: адрес %I0.1 повторяется"), "повтор адреса — ошибка");
      CHECK(has(r.errors, "строка 6 (%I0.2): не заполнено назначение"), "пустое назначение — ошибка");
      CHECK(has(r.errors, "строка 7: ожидается 7 полей"), "неполная строка — ошибка"); }

    AppCfg ship; { BookReport r; CHECK(loadShipBook(argv[5], ship, r), "книга судна для проверки связи прочитана"); }
    const std::vector<ThrusterCfg> none;

    std::printf("-- шаблон и примеры --\n");
    { pu::Config c; BookReport r; const bool ok = pu::loadBook(argv[2], reg, none, c, r);
      CHECK(!ok && has(r.errors, "не описан ни один ПУ"), "пустой шаблон не принят"); }
    for (int b : {3, 4}) {
        pu::Config c; BookReport r; const bool ok = pu::loadBook(argv[b], reg, ship.thrusters, c, r); dump(r);
        CHECK(ok, b == 3 ? "пример «Бахтемир» принят" : "пример «Бейсуг» принят");
        CHECK(c.units.size() == 3 && c.units[0].channels.size() == 12, "три ПУ по 12 каналов");
        bool off = true; for (auto& u : c.units) off = off && !u.controlEnabled;
        CHECK(off, "управление от СДП по умолчанию выключено у всех ПУ");
        CHECK(has(r.warnings, "не задана калибровка") && has(r.warnings, "не связан с движителем"), "предупреждения: нет калибровки и связи с движителем");
        const pu::Channel* fb = c.units[1].find(pu::Sig::PitchFeedback);
        CHECK(fb && fb->plcAddress == "%QW100" && fb->node == "ET2" && fb->module == 4 && fb->channel == 0, "канал «Фактический шаг» ПУ2");
        const pu::Channel* ml = c.units[0].find(pu::Sig::MotorLoad);
        CHECK(ml && std::fabs(ml->fullScaleA - 2000) < 1e-9, "полная шкала нагрузки 2000 А");
    }

    std::printf("-- управление включено --\n");
    { pu::Config c; BookReport r; const bool ok = pu::loadBook(bad + "/пу_управление.xlsx", reg, ship.thrusters, c, r); dump(r);
      CHECK(ok && c.units[0].controlEnabled && c.units[0].thruster == "BOW1" && c.units[0].positiveStarboard == 1, "полный ПУ1: связь с BOW1, знак упора");
      const pu::Channel* sp = c.units[0].find(pu::Sig::PitchSetpoint);
      CHECK(sp && sp->scale.set && std::fabs(pu::pitchToMa(sp->scale, 0) - 12) < 1e-9 && std::fabs(pu::pitchToMa(sp->scale, -100) - 4) < 1e-9 && std::fabs(pu::pitchToMa(sp->scale, 150) - 20) < 1e-9,
            "задание: 0 % → 12 мА, −100 % → 4 мА, больше +100 % ограничено 20 мА");
      CHECK(sp && std::fabs(pu::maToPitch(sp->scale, 16) - 50) < 1e-9, "обратный перевод: 16 мА → +50 %"); }
    { pu::Config c; BookReport r; pu::loadBook(bad + "/пу_управление.xlsx", reg, none, c, r);
      CHECK(has(r.errors, "нужна книга судна для проверки связи"), "включённое управление без книги судна не принимается"); }
    struct Case { const char* file; const char* part; const char* what; };
    const Case cases[] = {
        {"пу_управление_без_калибровки.xlsx", "ПУ ПУ1: управление от СДП включено, но не задана калибровка", "управление без калибровки — ошибка"},
        {"пу_управление_без_знака.xlsx", "(ПУ1), «Положительный упор»: при включённом управлении нужно указать знак упора", "управление без знака упора — ошибка"},
        {"пу_управление_без_шага.xlsx", "нет каналов «Фактический шаг»", "управление без обратной связи по шагу — ошибка"},
        {"пу_поворотный.xlsx", "движитель должен быть туннельным", "связь с поворотной колонкой — ошибка"},
        {"пу_нет_движителя.xlsx", "движителя «BOW9» нет на листе «Движители»", "несуществующий движитель — ошибка"},
        {"пу_повтор_канала.xlsx", "канал ET1/3/2 уже занят (ПУ1 «Готовность ПУ»)", "один канал у двух сигналов — ошибка"},
        {"пу_смешанный_модуль.xlsx", "модуль ET1/1 уже используется как дискретный выход", "в модуле каналы разного вида — ошибка"},
        {"пу_адрес.xlsx", "адреса %IW199 нет в реестре", "адрес не из реестра — ошибка"},
        {"пу_адрес.xlsx", "%I5.2 — DI ПЛК, для «Управление от СДП разрешено» нужен DO", "адрес не того типа — ошибка"},
        {"пу_калибровка_убывает.xlsx", "ток должен возрастать", "калибровка по убыванию — ошибка"},
        {"пу_калибровка_вне.xlsx", "калибровка вне 4–20 мА", "калибровка вне 4–20 мА — ошибка"},
        {"пу_калибровка_неполная.xlsx", "калибровка задаётся тремя точками", "неполная калибровка — ошибка"},
        {"пу_неизвестный_сигнал.xlsx", "«Задание курса» — неизвестный сигнал", "неизвестный сигнал — ошибка"},
        {"пу_повтор_пу.xlsx", "обозначение ПУ повторяется", "повтор обозначения ПУ — ошибка"},
        {"пу_два_судна.xlsx", "в одной книге ПУ разных судов", "ПУ разных судов в одной книге — ошибка"},
    };
    std::printf("-- испорченные книги --\n");
    for (auto& k : cases) {
        pu::Config c; BookReport r; const bool ok = pu::loadBook(bad + "/" + k.file, reg, ship.thrusters, c, r);
        CHECK(!ok && has(r.errors, k.part), k.what);
        if (ok || !has(r.errors, k.part)) dump(r);
    }
    { pu::Config c; BookReport r; const bool ok = pu::loadBook(bad + "/пу_один_узел.xlsx", reg, ship.thrusters, c, r); dump(r);
      CHECK(ok && has(r.warnings, "все каналы на одном узле «ET1» — для DP-2 нужны два набора"), "один узел ввода-вывода: предупреждение для DP-2"); }

    std::printf(fails ? "ОШИБОК: %d\n" : "все проверки пройдены\n", fails);
    return fails ? 1 : 0;
}
