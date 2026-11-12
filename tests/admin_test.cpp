// Проверка этапа «Параметры судна»: SHA-256/HMAC/PBKDF2 по стандартным векторам, профиль судна (чтение, запись,
// проверки, расчёты), служба администратора (пароль, блокировка, сеансы, журнал, сохранение) и доступ по сети.
#include <clocale>
#include <cstdio>
#include <filesystem>

#include "dp/service.hpp"

using namespace dp;
static int fails = 0;
#define CHECK(c, msg) do { if (!(c)) { std::printf("  [ПРОВАЛ] %s\n", msg); ++fails; } else std::printf("  [ок] %s\n", msg); } while (0)
static void sleepMs(int ms) { std::this_thread::sleep_for(std::chrono::milliseconds(ms)); }
template <class F> static bool waitFor(F f, int ms = 4000) { for (int t = 0; t < ms; t += 20) { if (f()) return true; sleepMs(20); } return f(); }

static json::Value parseOrDie(const std::string& s) { json::Value v; std::string e; if (!json::parse(s, v, e)) { std::printf("JSON: %s\n  %s\n", e.c_str(), s.c_str()); std::exit(3); } return v; }
static std::string req(const std::string& op, const std::string& extra = "", int id = 1) { return "{\"t\":\"adm\",\"id\":" + std::to_string(id) + ",\"op\":\"" + op + "\"" + (extra.empty() ? "" : "," + extra) + "}"; }
static bool okOf(const std::string& reply) { json::Value v = parseOrDie(reply); return jb(v, "ok"); }
static std::string errOf(const std::string& reply) { return js(parseOrDie(reply), "err"); }
static std::string call(AdminService& a, const std::string& sid, const std::string& op, const std::string& extra = "") { return a.handle(sid, parseOrDie(req(op, extra))); }

static VesselProfile demoProfile(const std::string& cfgPath) {
    AppCfg cfg; json::Report rep; loadConfig(cfgPath, cfg, rep);
    VesselProfile p; p.vessel = cfg.vessel; p.thrusters = cfg.thrusters; return p;
}

// ---- пост, принимающий ответы adm
struct Post {
    std::mutex m; std::map<long long, json::Value> adm; OpStatic info; OpSnap snap; std::vector<std::string> log; long long nextId = 100;
    std::unique_ptr<OpClient> cl;
    Post(const std::string& name, int port) {
        cl.reset(new OpClient("127.0.0.1", port, name, [this](const json::Value& v) {
            std::lock_guard<std::mutex> lk(m); const std::string t = js(v, "t");
            if (t == "adm") adm[static_cast<long long>(jn(v, "id"))] = v;
            else if (t == "static") info = decodeStatic(v);
            else if (t == "snap") snap = decodeSnap(v);
            else if (t == "log") log.push_back(js(v, "m"));
        }));
        cl->start();
    }
    // Запрос и ожидание ответа с тем же id
    json::Value ask(const std::string& op, const std::string& extra = "") {
        const long long id = nextId++;
        cl->sendRaw(req(op, extra, static_cast<int>(id)));
        json::Value out;
        if (waitFor([&] { std::lock_guard<std::mutex> lk(m); return adm.count(id) > 0; }, 6000)) { std::lock_guard<std::mutex> lk(m); out = adm[id]; }
        return out;
    }
    bool logHas(const std::string& s) { std::lock_guard<std::mutex> lk(m); for (auto& l : log) if (l.find(s) != std::string::npos) return true; return false; }
    OpSnap s() { std::lock_guard<std::mutex> lk(m); return snap; }
    OpStatic i() { std::lock_guard<std::mutex> lk(m); return info; }
};

int main(int argc, char** argv) {
    std::setlocale(LC_ALL, "C");
    const std::string cfgPath = argc > 1 ? argv[1] : "config/demo.json";
    const std::string tmp = (std::filesystem::temp_directory_path() / "sdp_admin_test").string();
    std::filesystem::remove_all(tmp);

    std::printf("1. SHA-256, HMAC, PBKDF2\n");
    {
        using namespace sha;
        CHECK(toHex(sha256("abc")) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256(\"abc\")");
        CHECK(toHex(sha256("")) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "SHA-256(пустая строка)");
        CHECK(toHex(sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", "SHA-256, сообщение на два блока");
        { Sha256 h; std::string a(1000, 'a'); for (int i = 0; i < 1000; ++i) h.update(a); CHECK(toHex(h.finish()) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0", "SHA-256, миллион символов «a» по частям"); }
        const std::string d = "what do ya want for nothing?"; const std::string k = "Jefe";
        CHECK(toHex(hmac(std::vector<uint8_t>(k.begin(), k.end()), reinterpret_cast<const uint8_t*>(d.data()), d.size())) == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", "HMAC-SHA256, вектор RFC 4231 №2");
        const std::vector<uint8_t> salt = {'s', 'a', 'l', 't'};
        CHECK(toHex(pbkdf2("password", salt, 1)) == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b", "PBKDF2-HMAC-SHA256, 1 итерация");
        CHECK(toHex(pbkdf2("password", salt, 2)) == "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43", "PBKDF2-HMAC-SHA256, 2 итерации");
        CHECK(toHex(pbkdf2("password", salt, 4096)) == "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a", "PBKDF2-HMAC-SHA256, 4096 итераций");
        CHECK(pbkdf2("password", salt, 1, 64).size() == 64, "длина ключа больше одного блока");
        const auto t0 = std::chrono::steady_clock::now(); pbkdf2("x", salt, 150000);
        std::printf("  (150000 итераций: %.0f мс на этом компьютере)\n", std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count());
    }

    std::printf("2. Профиль судна\n");
    VesselProfile base = demoProfile(cfgPath);
    {
        const std::string txt = writeProfile(base);
        VesselProfile q; json::Report rep;
        CHECK(parseProfileText(txt, q, rep), "записанный профиль читается обратно");
        CHECK(diffProfiles(base, q).empty(), "после записи и чтения различий нет");
        CHECK(q.thrusters.size() == 4 && q.vessel.name == base.vessel.name, "движители и название сохранены");
        CHECK(!hasErrors(validateProfile(base)), "профиль демонстрационного судна проходит проверку");
        for (auto& i : validateProfile(base)) std::printf("    замечание: %s — %s\n", i.field.c_str(), i.text.c_str());
        VesselProfile bad = base; bad.vessel.length = -3; bad.thrusters[1].id = bad.thrusters[0].id; bad.thrusters[2].maxForward = 0;
        const auto is = validateProfile(bad); int errs = 0; for (auto& i : is) errs += i.error;
        CHECK(errs >= 3, "отрицательная длина, повтор id и нулевой упор — ошибки");
        VesselProfile cb = base; cb.vessel.mass = 40e6;
        bool cbErr = false; for (auto& i : validateProfile(cb)) if (i.error && i.field == "vessel.mass") cbErr = true;
        CHECK(cbErr, "масса не согласована с размерами и осадкой — ошибка");
        VesselProfile w = base; w.vessel.mass = 0.95 * 1025 * 60 * 14 * 4; w.thrusters[0].x = 60;
        int warns = 0; for (auto& i : validateProfile(w)) warns += !i.error;
        CHECK(warns >= 1 && !hasErrors(validateProfile(w)), "необычные, но возможные значения дают предупреждения, а не ошибки");
        VesselProfile ty = base; json::Report r2;
        CHECK(!parseProfileText("{\"vessel\":{\"length\":\"много\"}}", ty, r2), "число в кавычках отвергается при разборе");
        VesselProfile uk; json::Report r3; parseProfileText("{\"vessl\":{}}", uk, r3);
        CHECK(!r3.warnings.empty(), "опечатка в названии раздела замечена");
    }
    {   // расчёты по осадке
        VesselProfile p = base;
        p.loading.draftFwd = 3.6; p.loading.draftAft = 4.6; p.loading.massFromDraft = true; p.loading.blockCoef = 0.6;
        p.loading.refDraft = 4.0; p.loading.deckLateral = 25; p.loading.deckFrontal = 6; p.loading.yawGyrationFrac = 0.25;
        const VesselCfg v = effectiveVessel(p);
        CHECK(std::fabs(v.draft - 4.1) < 1e-9, "средняя осадка = (нос + корма) / 2");
        CHECK(std::fabs(v.mass - 1025 * 0.6 * 60 * 14 * 4.1) < 1.0, "масса по осадке: ρ·Cb·L·B·T");
        CHECK(std::fabs(v.lateralArea - (base.vessel.lateralArea - 0.1 * 60 + 25)) < 1e-6, "боковая парусность: поправка на осадку и палубный груз");
        CHECK(std::fabs(v.frontalArea - (base.vessel.frontalArea - 0.1 * 14 + 6)) < 1e-6, "носовая парусность: поправка на осадку и палубный груз");
        CHECK(std::fabs(v.Izz - v.mass * 15.0 * 15.0) < 1.0, "Izz по радиусу инерции 0,25 L");
        // чем больше осадка, тем меньше парусность
        VesselProfile deep = p; deep.loading.draftFwd = deep.loading.draftAft = 5.0;
        CHECK(effectiveVessel(deep).lateralArea < v.lateralArea, "при большей осадке парусность меньше");
        CHECK(effectiveVessel(base).lateralArea == base.vessel.lateralArea && effectiveVessel(base).mass == base.vessel.mass, "без условий загрузки параметры не меняются");
        const auto est = estimateProfile(p); bool wind = false; for (auto& e : est) if (e.label.find("Предельный ветер") != std::string::npos) wind = true;
        CHECK(est.size() >= 8 && wind, "оценки (масса, парусность, предельный ветер) сформированы");
        VesselProfile half = base; half.loading.draftFwd = 3;
        bool pairErr = false; for (auto& i : validateProfile(half)) if (i.error && i.field == "loading.draftFwd") pairErr = true;
        CHECK(pairErr, "осадка задана только носом — ошибка");
    }

    std::printf("3. Служба администратора\n");
    {
        double now = 1000;
        AdminService a(tmp + "/a", 1000, [&] { return now; });
        a.setCurrent(base);
        json::Value st = parseOrDie(call(a, "post#1", "status"));
        CHECK(!jb(st, "pwSet") && !jb(st, "admin"), "пароль не задан, администратор не вошёл");
        CHECK(!okOf(call(a, "post#1", "setup", "\"pw\":\"Ghbrjkbcn-77\"")), "задать пароль по сети нельзя");
        CHECK(!okOf(call(a, "local", "setup", "\"pw\":\"123\"")), "короткий пароль отвергнут");
        CHECK(!okOf(call(a, "local", "setup", "\"pw\":\"password\"")), "очень простой пароль отвергнут");
        CHECK(okOf(call(a, "local", "setup", "\"pw\":\"Kompas-2026\"")), "первый пароль задан на компьютере ядра");
        CHECK(!okOf(call(a, "local", "setup", "\"pw\":\"Drugoy-2026\"")), "повторно «первый» пароль задать нельзя");
        {   std::ifstream f(tmp + "/a/admin.json"); std::stringstream ss; ss << f.rdbuf();
            CHECK(ss.str().find("Kompas") == std::string::npos && ss.str().find("PBKDF2") != std::string::npos, "пароль в файле не хранится открытым текстом"); }
        CHECK(!okOf(call(a, "post#1", "get")) && errOf(call(a, "post#1", "get")).find("вход") != std::string::npos, "без входа профиль не выдаётся");
        CHECK(!okOf(call(a, "post#1", "set", "\"profile\":" + writeProfile(base))), "без входа профиль записать нельзя");
        CHECK(!okOf(call(a, "post#1", "login", "\"pw\":\"neverno-1\"")), "неверный пароль отвергнут");
        CHECK(!okOf(call(a, "post#1", "login", "\"pw\":\"neverno-2\"")), "вторая неудача");
        CHECK(!okOf(call(a, "post#1", "login", "\"pw\":\"neverno-3\"")), "третья неудача");
        json::Value lk = parseOrDie(call(a, "post#1", "login", "\"pw\":\"Kompas-2026\""));
        CHECK(!jb(lk, "ok") && jn(lk, "lockSec") > 20, "после трёх неудач вход заблокирован, даже верный пароль не принимается");
        CHECK(!okOf(call(a, "post#2", "login", "\"pw\":\"Kompas-2026\"")), "блокировка действует и для другого подключения");
        now += 40;
        CHECK(okOf(call(a, "post#1", "login", "\"pw\":\"Kompas-2026\"")), "после паузы верный пароль принимается");
        CHECK(okOf(call(a, "post#1", "get")), "администратор получает профиль");
        CHECK(!okOf(call(a, "post#2", "get")), "другое подключение доступа не получило");
        // запись
        VesselProfile ch = base; ch.vessel.name = "Новое имя"; ch.loading.condition = "В балласте"; ch.loading.draftFwd = 3.5; ch.loading.draftAft = 4.5;
        CHECK(okOf(call(a, "post#1", "check", "\"profile\":" + writeProfile(ch))), "проверка без записи проходит");
        CHECK(!a.hasPending(), "проверка ничего не записывает");
        VesselProfile bad = ch; bad.vessel.beam = 0;
        std::string rb = call(a, "post#1", "set", "\"profile\":" + writeProfile(bad));
        CHECK(!okOf(rb) && rb.find("\"issues\"") != std::string::npos, "профиль с ошибкой не записывается, замечания возвращаются");
        CHECK(!std::filesystem::exists(tmp + "/a/vessel_profile.json"), "файл профиля после отказа не создан");
        CHECK(okOf(call(a, "post#1", "set", "\"profile\":" + writeProfile(ch))) && a.hasPending(), "верный профиль записан и ждёт применения");
        CHECK(std::filesystem::exists(tmp + "/a/vessel_profile.json"), "файл профиля создан");
        auto pend = a.takePending();
        CHECK(pend && pend->vessel.name == "Новое имя" && !a.hasPending(), "ядро может забрать профиль для применения");
        json::Value same = parseOrDie(call(a, "post#1", "set", "\"profile\":" + writeProfile(ch)));
        CHECK(jb(same, "ok") && jn(same, "changed", -1) == 0 && !a.hasPending(), "повторная запись без изменений ничего не ставит в очередь");
        // журнал
        std::string aud = call(a, "post#1", "audit");
        CHECK(aud.find("vessel.name") != std::string::npos && aud.find("Новое имя") != std::string::npos && aud.find("loading.draftFwd") != std::string::npos, "в журнале есть перечень изменённых полей");
        CHECK(aud.find("неверный пароль") != std::string::npos && aud.find("вход администратора") != std::string::npos, "в журнале есть неудачные и успешные входы");
        CHECK(aud.find("Kompas") == std::string::npos && aud.find("neverno") == std::string::npos, "пароли в журнал не попадают");
        // смена пароля
        CHECK(!okOf(call(a, "post#1", "chpw", "\"old\":\"nepravilno\",\"new\":\"Novyj-Parol-9\"")), "смена пароля с неверным старым отклонена");
        CHECK(!okOf(call(a, "post#1", "chpw", "\"old\":\"Kompas-2026\",\"new\":\"abc\"")), "слабый новый пароль отклонён");
        CHECK(okOf(call(a, "post#1", "chpw", "\"old\":\"Kompas-2026\",\"new\":\"Novyj-Parol-9\"")), "пароль изменён");
        // сеанс и простой
        now += 601;
        CHECK(!okOf(call(a, "post#1", "get")), "через 10 минут без действий сеанс закрыт");
        CHECK(!okOf(call(a, "post#1", "login", "\"pw\":\"Kompas-2026\"")), "старый пароль больше не подходит");
        CHECK(okOf(call(a, "post#1", "login", "\"pw\":\"Novyj-Parol-9\"")), "новый пароль подходит");
        a.closeSession("post#1");
        CHECK(!okOf(call(a, "post#1", "get")), "после закрытия подключения сеанс закрыт");
        // перезапуск
        AdminService b(tmp + "/a", 1000, [&] { return now; });
        CHECK(b.passwordSet() && okOf(call(b, "x#1", "login", "\"pw\":\"Novyj-Parol-9\"")), "после перезапуска пароль сохранился");
        std::string note; auto sp = b.loadStoredProfile(note);
        CHECK(sp && sp->vessel.name == "Новое имя", "после перезапуска профиль читается с диска");
        // повреждённые файлы
        { std::ofstream f(tmp + "/a/vessel_profile.json", std::ios::trunc); f << "{ это не json"; }
        std::string note2; CHECK(!b.loadStoredProfile(note2).has_value() && !note2.empty(), "повреждённый файл профиля не применяется и объясняется");
        { std::ofstream f(tmp + "/a/admin.json", std::ios::trunc); f << "мусор"; }
        AdminService c(tmp + "/a", 1000, [&] { return now; });
        CHECK(!c.passwordSet(), "повреждённый файл пароля — пароль считается не заданным (задаётся заново на компьютере ядра)");
    }

    std::printf("4. Доступ по сети и применение к модели\n");
    {
        AppCfg cfg; json::Report rep; loadConfig(cfgPath, cfg, rep); cfg.simSpeed = 20; cfg.logFile.clear();
        const int port = 5391;
        std::filesystem::remove_all(tmp + "/n");
        CoreService svc(cfg, port, tmp + "/n", 1000);
        std::string err; CHECK(svc.start(err), "ядро запущено");
        Post A("A", port), B("B", port);
        CHECK(waitFor([&] { return A.s().t > 1 && B.s().t > 1; }), "оба поста получают состояние");
        CHECK(!jb(A.ask("status"), "pwSet"), "пост видит, что пароль не задан");
        CHECK(!jb(A.ask("setup", "\"pw\":\"Kompas-2026\""), "ok"), "пароль по сети задать нельзя");
        CHECK(jb(parseOrDie(svc.adminLocal(req("setup", "\"pw\":\"Kompas-2026\""))), "ok"), "пароль задан в окне ядра (локально)");
        CHECK(jb(A.ask("status"), "pwSet") && !jb(A.ask("status"), "admin"), "после этого пост A всё ещё не администратор");
        CHECK(!jb(A.ask("get"), "ok"), "пост A без входа профиль не получает");
        CHECK(!jb(B.ask("login", "\"pw\":\"ne-tot-parol\""), "ok"), "пост B: неверный пароль отвергнут");
        CHECK(jb(B.ask("login", "\"pw\":\"Kompas-2026\""), "ok"), "пост B вошёл с верным паролем");
        json::Value g = B.ask("get");
        CHECK(jb(g, "ok") && g.find("profile") != nullptr, "пост B получил профиль");
        CHECK(!jb(A.ask("get"), "ok"), "вход поста B не открывает доступ посту A");
        VesselProfile p; json::Report r2; parseProfile(*g.find("profile"), p, r2);
        CHECK(p.thrusters.size() == 4 && p.vessel.name == cfg.vessel.name, "профиль соответствует текущему описанию судна");

        // применяется только в режиме ожидания
        CHECK(waitFor([&] { return A.s().mode >= 2; }, 30000), "ядро вышло в режим удержания");
        VesselProfile q = p; q.vessel.name = "Судно после правки"; q.loading.draftFwd = q.loading.draftAft = 3.0; q.loading.massFromDraft = true;
        q.thrusters.pop_back();
        CHECK(jb(B.ask("set", "\"profile\":" + writeProfile(q)), "ok"), "профиль записан");
        CHECK(waitFor([&] { return B.logHas("не применён"); }, 5000), "в режиме удержания профиль не применяется, оператору сообщено");
        CHECK(A.i().ship == cfg.vessel.name, "до применения судно прежнее");
        svc.command("standby");
        CHECK(waitFor([&] { return B.logHas("Профиль судна применён"); }, 8000), "в режиме ожидания профиль применён");
        CHECK(waitFor([&] { return A.i().ship == "Судно после правки"; }), "посты получили новое описание судна");
        CHECK(waitFor([&] { return A.s().th.size() == 3; }), "число движителей в состоянии изменилось: 4 → 3");
        svc.command("position");
        CHECK(waitFor([&] { return A.s().mode >= 2; }, 30000), "режим удержания включается и с новым профилем");
        sleepMs(6000);
        CHECK(waitFor([&] { return A.s().errDist < 3.0; }, 40000), "судно удерживает позицию с новыми параметрами");
        // выход и потеря связи
        CHECK(jb(B.ask("logout"), "ok") && !jb(B.ask("get"), "ok"), "после выхода доступ закрыт");
        CHECK(jb(B.ask("login", "\"pw\":\"Kompas-2026\""), "ok"), "вход снова");
        B.cl->stop();
        Post B2("B", port);
        CHECK(waitFor([&] { return B2.s().t > 0; }), "пост B переподключился");
        CHECK(!jb(B2.ask("get"), "ok"), "после переподключения права администратора не сохраняются");
        svc.stop();
        // перезапуск ядра берёт профиль с диска
        CoreService svc2(cfg, port + 1, tmp + "/n", 1000);
        CHECK(svc2.start(err), "ядро перезапущено");
        CHECK(svc2.cfg().vessel.name == "Судно после правки" && svc2.cfg().thrusters.size() == 3, "после перезапуска применён профиль с диска");
        CHECK(std::fabs(svc2.cfg().vessel.draft - 3.0) < 1e-9, "в модель попала осадка из профиля");
        svc2.stop();
    }
    std::filesystem::remove_all(tmp);
    if (fails) { std::printf("ПРОВАЛОВ: %d\n", fails); return 1; }
    std::printf("ИТОГ: всё в порядке\n");
    return 0;
}
