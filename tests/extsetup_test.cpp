// v0.23: настройка связи с внешней ДП из окна оператора (ext setup / ext clear), хранение в extlink.json, чтение при запуске.
#include <cstdio>
#include <filesystem>
#include <fstream>
#include "dp/config.hpp"
#include "dp/runtime.hpp"
#include "dp/rights.hpp"

using namespace dp;
static int fails = 0;
static std::string lastSay;
#define CHECK(c, msg) do { const bool ok_ = (c); std::printf("%s %s\n", ok_ ? "  ok " : "FAIL ", msg); if (!ok_) ++fails; } while (0)

int main(int argc, char** argv) {
    if (argc < 2) { std::printf("нужен файл настроек\n"); return 2; }
    AppCfg cfg; json::Report rep;
    if (!loadConfig(argv[1], cfg, rep)) { std::printf("настройки не прочитаны\n"); return 2; }
    const std::string f = "/tmp/extsetup_test_extlink.json"; std::filesystem::remove(f);
    {   // разбор и обратная запись
        ExtLinkCfg c; std::string err;
        CHECK(parseExtLink("{\"vendor\":\"praxis\",\"inputs\":[{\"id\":\"P\",\"kind\":\"gnss\",\"transport\":{\"type\":\"udp\",\"port\":5601}},{\"id\":\"H\",\"kind\":\"gyro\",\"transport\":{\"type\":\"serial\",\"device\":\"COM3\",\"baud\":9600}}],\"posAlarmM\":7}", c, err)
              && c.inputs.size() == 2 && c.inputs[1].baud == 9600 && c.posAlarmM == 7 && c.vendor == "praxis", "разбор настроек связи (UDP и COM)");
        ExtLinkCfg c2; CHECK(parseExtLink(extLinkToJson(c), c2, err) && c2.inputs.size() == 2 && c2.inputs[0].port == 5601 && c2.inputs[1].device == "COM3", "запись в JSON и чтение обратно без потерь");
        CHECK(!parseExtLink("{\"inputs\":[{\"id\":\"A\",\"kind\":\"gnss\",\"transport\":{\"type\":\"udp\"}}]}", c, err) && err.find("port") != std::string::npos, "UDP без порта отклоняется");
        CHECK(!parseExtLink("{\"inputs\":[{\"id\":\"A\",\"kind\":\"gnss\",\"transport\":{\"type\":\"udp\",\"port\":1}},{\"id\":\"A\",\"kind\":\"gyro\",\"transport\":{\"type\":\"udp\",\"port\":2}}]}", c, err), "повтор имени входа отклоняется");
        CHECK(!parseExtLink("{\"inputs\":[],\"posAlarmM\":0}", c, err), "нулевой порог отклоняется");
        CHECK(!parseExtLink("{не json", c, err), "испорченный текст отклоняется");
        CHECK(isSetupCommand("ext setup {}") && isSetupCommand("ext clear") && isChiefCommand("ext setup {}"), "ext setup и ext clear — команды настройки (нужен «Старший» или администратор)");
    }
    {   // применение в работающем ядре
        AppCfg c = cfg; c.extlink = ExtLinkCfg();
        Runtime r(c, [](const std::string& s) { lastSay = s; });
        r.setExtFile(f);
        CHECK(r.extJson().find("\"configured\":false") != std::string::npos, "связь не настроена: статус «configured:false» с настройками по умолчанию");
        r.command("ext setup {\"enabled\":true,\"vendor\":\"kongsberg\",\"inputs\":[{\"id\":\"XG\",\"kind\":\"gnss\",\"transport\":{\"type\":\"udp\",\"bind\":\"127.0.0.1\",\"port\":55311}}]}");
        CHECK(lastSay.find("применена") != std::string::npos && r.extJson().find("\"configured\":true") != std::string::npos, "настройки применены без перезапуска");
        r.cycle(); CHECK(r.extJson().find("kongsberg") != std::string::npos, "поставщик виден в состоянии");
        r.command("ext setup {\"inputs\":[{\"id\":\"B\",\"kind\":\"gnss\",\"transport\":{\"type\":\"tcp\"}}]}");
        CHECK(lastSay.find("не изменена") != std::string::npos && r.extJson().find("\"configured\":true") != std::string::npos, "ошибочная настройка не ломает рабочую");
        CHECK(std::filesystem::exists(f), "настройки записаны в файл папки данных");
    }
    {   // чтение при следующем запуске
        AppCfg c = cfg; c.extlink = ExtLinkCfg();
        Runtime r(c, [](const std::string& s) { lastSay = s; });
        r.setExtFile(f);
        CHECK(r.extJson().find("\"configured\":true") != std::string::npos && r.extJson().find("55311") != std::string::npos, "после перезапуска настройки читаются из файла");
        r.command("ext clear");
        CHECK(r.extJson().find("\"configured\":false") != std::string::npos && lastSay.find("выключена") != std::string::npos, "ext clear выключает связь");
    }
    {
        AppCfg c = cfg; c.extlink = ExtLinkCfg();
        Runtime r(c, [](const std::string&) {}); r.setExtFile(f);
        CHECK(r.extJson().find("\"configured\":false") != std::string::npos, "выключенное состояние тоже сохраняется");
    }
    std::filesystem::remove(f);
    std::printf(fails ? "ПРОВАЛОВ: %d\n" : "ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ\n", fails);
    return fails ? 1 : 0;
}
