// Движок СДП: оценка состояния → регулятор → распределение тяги → команды на движители.
#pragma once
#include "dp/forecast.hpp"
#include "dp/control.hpp"

namespace dp {

// Приоритеты сообщений как в K-Pos: 0 — аварийное (Emergency), 1 — тревога (Alarm), 2 — предупреждение (Warning), 3 — информация.
// Если приоритет не задан (-1), он берётся из critical: критичное — тревога, остальное — предупреждение.
struct Alarm {
    std::string code;     // краткий код
    std::string text;     // сообщение оператору
    bool critical = false;
    int prio = -1;
    int level() const { return prio >= 0 ? prio : (critical ? 1 : 2); }
};

struct EngineOutput {
    std::vector<ThrusterCmd> cmds;
    ControlOutput ctl;
    AllocResult alloc;
    EstimatorState est;
    Capability cap;
    Wrench thrustFb;      // фактическая сумма сил движителей
    Wrench windModel;     // сила ветра по модели
    Wrench waveModel;     // средняя дрейфовая сила волн по оценке МИО (с учётом доли ffGain)
    double powerScale = 1;
    double powerKW = 0;       // оценка потребляемой мощности движителей по обратной связи по упору, кВт
    FcOut fc;                 // прогноз внешних сил (если включён)
    std::vector<Alarm> alarms;
    std::vector<std::string> infos;     // информационные сообщения шага (для журнала событий)
};

class DpEngine {
public:
    DpEngine(const VesselCfg& v, std::vector<ThrusterCfg> th, ControlCfg cc = {}, EstimatorCfg ec = {})
        : vcfg_(v), est_(v, ec), ctl_(v, cc), alloc_(std::move(th)) {
        for (const auto& t : alloc_.thrusters()) {
            ThrusterCmd c; c.id = t.id; c.angleDeg = t.type == ThrusterType::Azimuth ? 0.0 : rad2deg(thrusterBaseAngle(t));
            last_.push_back(c);
        }
    }

    Controller& controller() { return ctl_; }
    const Estimator& estimator() const { return est_; }
    Estimator& estimatorMut() { return est_; }
    const Allocator& allocator() const { return alloc_; }
    void setHoldRadius(double r) { holdR_ = r > 0 ? r : 0; }
    double holdRadius() const { return holdR_; }
    Forecaster& forecast() { return fc_; }
    const Forecaster& forecast() const { return fc_; }
    // Предел курса, ° (0 — выключен): предупреждение при 80 %, аларм при выходе за предел. Только когда курс удерживается.
    void setHdgLimit(double d) { hdgLim_ = d > 0 ? d : 0; }
    double hdgLimit() const { return hdgLim_; }
    void setThrusterEnabled(size_t i, bool on) { alloc_.setEnabled(i, on); }
    void setThrusterPreload(size_t i, double prefDeg, double pct) { alloc_.setPreload(i, prefDeg, pct); }
    void setMode(DpMode m) { ctl_.setMode(m, est_.state()); }
    DpMode mode() const { return ctl_.mode(); }

    EngineOutput step(double dt, const SensorFrame& fr) {
        EngineOutput o;
        alloc_.setSpeedKn(std::hypot(est_.state().u, est_.state().v) / 0.514444);   // спад упора ПУ на ходу
        const auto& th = alloc_.thrusters();
        // --- мощность электростанции
        double need = 0;
        for (const auto& t : th) if (t.enabled) need += t.powerMaxKW;
        double ps = 1.0;
        if (fr.power.fresh) availKW_ = fr.power.availableKW;
        if (need > 0 && availKW_ < need) ps = clampd(availKW_ / need, 0.2, 1.0);
        // коэффициент по упору примерно кубический закон по мощности: упор ~ P^(2/3)
        const double thrustScale = thrustScaleForPower(th, ps);
        o.powerScale = thrustScale;

        // --- фактические углы и упоры по обратной связи
        std::vector<double> actAngle(th.size(), 0.0);
        Wrench thrust{};
        for (size_t i = 0; i < th.size(); ++i) {
            const auto& t = th[i];
            double pct = last_[i].pct, ang = last_[i].angleDeg;   // при отсутствии обратной связи — по последней команде
            for (const auto& f : fr.fb) if (f.id == t.id && f.valid) { pct = f.pct; ang = f.angleDeg; }
            actAngle[i] = ang;
            if (!t.enabled) continue;
            const double N = pct >= 0 ? pct / 100.0 * t.maxForward : pct / 100.0 * t.maxReverse;
            const double a = t.type == ThrusterType::Azimuth ? deg2rad(ang) : thrusterBaseAngle(t);
            const Wrench w = thrusterWrench(t, N, a);
            thrust.X += w.X; thrust.Y += w.Y; thrust.N += w.N;
        }
        o.thrustFb = thrust;
        for (size_t i = 0; i < th.size(); ++i) {   // потребляемая мощность по фактическому упору
            if (!th[i].enabled) continue;
            double pct = last_[i].pct; for (const auto& f : fr.fb) if (f.id == th[i].id && f.valid) pct = f.pct;
            o.powerKW += thrusterPowerKW(th[i], std::fabs(pct) / 100.0);
        }

        // --- расхождение команды и обратной связи движителя: больше порога fbDiffPct (азимут: угол больше fbDiffAngleDeg при команде выше 10 %) дольше fbDiffDelayS (по умолчанию 25 %, 30°, 30 с)
        if (!(ctl_.mode() == DpMode::Standby)) {
            auto g = [](double v) { char b[24]; std::snprintf(b, sizeof b, "%g", v); return std::string(b); };
            for (size_t i = 0; i < th.size() && i < last_.size(); ++i) {
                if (!th[i].enabled) continue;
                const ThrusterFb* f = nullptr; for (const auto& x : fr.fb) if (x.id == th[i].id && x.valid) f = &x;
                bool bad = false;
                if (f) {
                    bad = std::fabs(f->pct - last_[i].pct) > th[i].fbDiffPct;
                    if (!bad && th[i].type == ThrusterType::Azimuth && std::fabs(last_[i].pct) > 10.0)
                        bad = std::fabs(rad2deg(wrapPi(deg2rad(f->angleDeg - last_[i].angleDeg)))) > th[i].fbDiffAngleDeg;
                }
                if (mmT_.size() <= i) mmT_.resize(th.size(), 0.0);
                mmT_[i] = bad ? mmT_[i] + dt : 0.0;
                if (mmT_[i] >= th[i].fbDiffDelayS) o.alarms.push_back({"THR_FB_MISMATCH_" + th[i].id, "Движитель " + th[i].id + ": обратная связь расходится с командой (упор больше " + g(th[i].fbDiffPct) + " % или угол больше " + g(th[i].fbDiffAngleDeg) + "°) более " + g(th[i].fbDiffDelayS) + " с", false});
            }
        } else mmT_.assign(mmT_.size(), 0.0);

        // --- ветер по модели (по отфильтрованному кажущемуся ветру предыдущего шага)
        const EstimatorState& prev = est_.state();
        Wrench wind{};
        if (prev.windValid) wind = windForce(vcfg_, prev.windSpeed, prev.windFromRel);
        Wrench fcApplied{};      // поправка таблицы прогнозирования, внесённая в силу ветра (общая для оценки и закона управления)
        if (fc_.cfg().enabled && fc_.cfg().apply && prev.windValid && prev.hdgValid) { fcApplied = fc_.correction(prev.windSpeed, prev.windFromRel, lastCap_); wind.X += fcApplied.X; wind.Y += fcApplied.Y; wind.N += fcApplied.N; }
        o.windModel = wind;
        // --- дрейфовая сила волн по оценке, полученной из данных МИО (не из настроек имитатора)
        Wrench wave{}, wavePrev{};
        bool waveOn = false; double wHs = 0, wFrom = 0, wGain = 0;
        if (ctl_.cfg().waveFeedForward && prev.wave.valid && prev.wave.dirValid && prev.hdgValid && prev.wave.ffGain > 0) {
            waveOn = true; wHs = prev.wave.hs; wFrom = prev.wave.fromDeg; wGain = prev.wave.ffGain;
            wave = waveDriftForce(vcfg_, wHs, wFrom, prev.psi, prev.wave.tz);
            wave.X *= wGain; wave.Y *= wGain; wave.N *= wGain;
        }
        if (lastWaveOn_) {                       // прежняя оценка при нынешнем курсе: разница — только от уточнения оценки волн
            wavePrev = waveDriftForce(vcfg_, lastHs_, lastFrom_, prev.psi, lastTz_);
            wavePrev.X *= lastGain_; wavePrev.Y *= lastGain_; wavePrev.N *= lastGain_;
        }
        o.waveModel = wave;
        est_.absorbKnownChange(Wrench{wave.X - wavePrev.X, wave.Y - wavePrev.Y, wave.N - wavePrev.N});
        lastWaveOn_ = waveOn; lastTz_ = prev.wave.tz; lastHs_ = wHs; lastFrom_ = wFrom; lastGain_ = wGain;
        const Wrench known{wind.X + wave.X, wind.Y + wave.Y, wind.N + wave.N};     // известные внешние силы: ветер и волны

        // --- оценка
        // ветровая сила уже учтена в модели, поэтому неизвестная сила (bias) содержит только остаток
        est_.step(dt, fr.time, fr, thrust, known);
        const EstimatorState& es = est_.state();
        o.est = es;

        // --- возможности и управление
        const double effScale = thrustScale;     // допустимая доля упора определяется электростанцией
        const Capability cap = alloc_.capability(effScale);
        o.cap = cap;
        const DpMode m = ctl_.mode();
        const bool needPos = m == DpMode::AutoPosition || m == DpMode::Track || m == DpMode::FollowTarget;
        const bool needHdg = m != DpMode::Standby && m != DpMode::Manual;
        bool ok = true;
        if (needPos && !es.posValid) { ok = false; o.alarms.push_back({"POS_LOST", "Потеря положения — счисление по модели превысило допустимое время", true}); }
        if (needHdg && !es.hdgValid) { ok = false; o.alarms.push_back({"HDG_LOST", "Потеря курса — нет данных гирокомпасов, счисление курса закончилось: упор снят", true}); }
        if (needHdg && es.hdgDeadReckon) {
            const int left = static_cast<int>(std::max(0.0, est_.cfg().hdgDeadReckonS - es.hdgLostS));
            o.alarms.push_back({"HDG_DR", "Потеря курса — нет данных гирокомпасов " + std::to_string(static_cast<int>(es.hdgLostS)) + " с, курс по счислению (до снятия упора " + std::to_string(left) + " с)", true, 1});
        }
        if (es.gnssDisagree) o.alarms.push_back({"POS_DISAGREE", "Расхождение источников положения", false});
        // потеря опорных систем (K-Pos, «Position dropout»): сначала «Все системы положения отклонены», через posDropoutS — «Потеря положения»;
        // судно при этом удерживается по модели, уставка оператора не меняется. Когда измерения вернутся и судно окажется дальше
        // returnStartM от уставки, оно возвращается в неё плавно, не быстрее returnSpeedMS (ctl_.beginReturn)
        if (needPos && es.posValid && es.refLost) {
            if (es.posDropout) {
                char u[48]; std::snprintf(u, sizeof u, "%.1f", es.drDriftM);
                o.alarms.push_back({"POS_DROPOUT", "Потеря положения — нет измерений " + std::to_string(static_cast<int>(es.refLostS)) + " с, удержание по модели (счисление), вероятный уход ≈ " + u + " м (оценка)", true, 1});
                dropLatched_ = true;
            } else o.alarms.push_back({"POS_ALL_REJ", "Все системы положения отклонены или недоступны — удержание по модели", true, 1});
        }
        if (dropLatched_ && !es.refLost) {   // измерения положения вернулись после потери
            dropLatched_ = false;
            if (m == DpMode::AutoPosition) {
                const Setpoint crp = ctl_.crpFromHold(ctl_.setpoint());
                const double d = std::hypot(es.n - crp.n, es.e - crp.e);
                const ControlCfg& cc = ctl_.cfg();
                char b[200];
                if (d > cc.returnStartM) {
                    ctl_.beginReturn(es, cc.returnSpeedMS, 3.0);
                    std::snprintf(b, sizeof b, "Положение восстановлено: судно в %.1f м от заданной точки, возврат со скоростью до %.1f м/с", d, cc.returnSpeedMS > 0 ? std::min(cc.returnSpeedMS, cc.refMaxSpeed) : cc.refMaxSpeed);
                } else std::snprintf(b, sizeof b, "Положение восстановлено: судно в %.1f м от заданной точки", d);
                o.infos.push_back(b);
            } else o.infos.push_back("Положение восстановлено");
        }
        if (wasReturning_ && !ctl_.returning() && m == DpMode::AutoPosition) o.infos.push_back("Возврат в заданную точку завершён");
        wasReturning_ = ctl_.returning();
        if (m == DpMode::AutoPosition && ctl_.returning()) {
            char b[160]; std::snprintf(b, sizeof b, "Возврат в заданную точку после потери положения: осталось %.1f м", ctl_.returnLeftM());
            o.alarms.push_back({"POS_RETURN", b, false});
        }
        for (const auto& pa : es.posAlerts) o.alarms.push_back({pa.first, pa.second, false});
        if (es.softCorrecting) o.alarms.push_back({"POS_SOFT", "Плавная коррекция положения — после скачка опорной системы", false});
        if (es.gyroDisagree) o.alarms.push_back({"GYRO_DISAGREE", "Расхождение гирокомпасов", false});
        if (!fr.mru.empty() && !es.mruValid) o.alarms.push_back({"MRU_LOST", "Нет достоверных данных МИО: волны не оцениваются, наклон антенн не учитывается", false});
        if (es.mruDisagree) o.alarms.push_back({"MRU_DISAGREE", "Расхождение показаний МИО", false});
        if (ps < 0.999) o.alarms.push_back({"POWER_LIMIT", "Ограничение по мощности электростанции", false});

        ControlOutput co;
        if (ok) co = ctl_.compute(dt, es, known, cap);
        o.ctl = co;

        // --- распределение
        if (m == DpMode::Standby || m == DpMode::Manual || !ok) {
            // команды не формируем: в ручном режиме движители управляются с поста, при потере данных удерживаем нулевую тягу
            for (size_t i = 0; i < th.size(); ++i) {
                ThrusterCmd c; c.id = th[i].id; c.pct = 0; c.angleDeg = actAngle[i];
                if (m == DpMode::Standby && th[i].type == ThrusterType::Azimuth && th[i].parkDeg < 1e8) c.angleDeg = th[i].parkDeg;   // стоянка колонок
                o.cmds.push_back(c);
            }
            o.alloc.cmds = o.cmds;
        } else {
            o.alloc = alloc_.allocate(co.tau, actAngle, effScale);
            o.cmds = o.alloc.cmds;
            // Ограничение скорости изменения команд возможностями самого движителя: распределитель упоров
            // может переключать решение скачком (пара ВРК при малых усилиях), а движитель такой скачок всё равно не отработает.
            for (size_t i = 0; i < th.size() && i < o.cmds.size() && i < last_.size(); ++i) {
                if (!th[i].enabled) continue;
                const double dp = 100.0 * th[i].rateFracPerS * dt;
                // мягкая зона нечувствительности: малые изменения команды не передаются (меньше «дёрганья» упора и колонок)
                const double pd = th[i].pctDeadPct;
                const double dpct = pd > 0 ? Controller::dead(o.cmds[i].pct - last_[i].pct, pd) : o.cmds[i].pct - last_[i].pct;
                o.cmds[i].pct = last_[i].pct + clampd(dpct, -dp, dp);
                if (th[i].type == ThrusterType::Azimuth) {
                    const double da = th[i].azRateDegS * dt;
                    double err = rad2deg(wrapPi(deg2rad(o.cmds[i].angleDeg - last_[i].angleDeg)));
                    if (th[i].azDeadDeg > 0) err = Controller::dead(err, th[i].azDeadDeg);
                    o.cmds[i].angleDeg = last_[i].angleDeg + clampd(err, -da, da);
                }
            }
            for (const auto& id : o.alloc.softZone) o.alarms.push_back({"AZ_SOFT_ZONE_" + id, "Колонка " + id + " в нежелательном секторе (струя на соседнюю колонку): иначе запрос не выполнить", false});
            // Насыщение: запрос больше возможностей комплекса — тревога сразу. Если же запрос в пределах возможностей, а недодача только
            // оттого, что колонки разворачиваются (при торможении нужен разворот до 180°), — сообщение «Колонки разворачиваются»;
            // тревога — если недодача держится дольше 5 с.
            const bool overCap = std::fabs(o.ctl.tau.X) > cap.X || std::fabs(o.ctl.tau.Y) > cap.Y || std::fabs(o.ctl.tau.N) > cap.N;
            satT_ = o.alloc.saturated ? satT_ + dt : 0.0;
            const bool turnOnly = o.alloc.saturated && o.alloc.turning && !overCap;
            if (o.alloc.saturated && (!turnOnly || satT_ > 5.0)) o.alarms.push_back({"SATURATION", "Запрошенное усилие превышает возможности комплекса", false});
            else if (turnOnly) o.alarms.push_back({"AZ_TURNING", "Колонки разворачиваются: упор временно набирается не полностью", false, 3});
            // тревога высокой загрузки с гистерезисом: включается после 3 с выше 90 % допустимой, снимается после 3 с ниже 80 %;
            // пока колонки разворачиваются при запросе в пределах возможностей, время не копится (кратковременная перекладка)
            const double u = o.alloc.utilization;
            if (!highLoad_) { onT_ = u > 0.9 && !(o.alloc.turning && !overCap) ? onT_ + dt : (u > 0.9 ? onT_ : 0.0); if (onT_ >= 3.0) { highLoad_ = true; offT_ = 0; } }
            else { offT_ = u < 0.8 ? offT_ + dt : 0.0; if (offT_ >= 3.0) { highLoad_ = false; onT_ = 0; } }
        }
        if (m == DpMode::Standby || m == DpMode::Manual || !ok) { highLoad_ = false; onT_ = offT_ = 0; satT_ = 0; }
        if (highLoad_) o.alarms.push_back({"HIGH_LOAD", "Загрузка движителей выше 90 % допустимой", false});
        // --- радиус удержания: предупреждение при 80 % радиуса, аларм при выходе за радиус (с выдержкой и гистерезисом)
        if (holdR_ > 0 && ok && (m == DpMode::AutoPosition || m == DpMode::Track)) {
            const double q = o.ctl.errDist / holdR_;
            auto upd = [&](bool& on, double& tOn, double& tOff, double hi, double lo, double holdOn, double holdOff) {
                if (!on) { tOn = q >= hi ? tOn + dt : 0.0; if (tOn >= holdOn) { on = true; tOff = 0; } }
                else { tOff = q < lo ? tOff + dt : 0.0; if (tOff >= holdOff) { on = false; tOn = 0; } }
            };
            upd(rOut_, rOutOn_, rOutOff_, 1.0, 0.9, 2.0, 3.0);
            upd(rWarn_, rWarnOn_, rWarnOff_, 0.8, 0.7, 3.0, 3.0);
            char b[200];
            if (rOut_) { std::snprintf(b, sizeof b, "Судно вышло за радиус удержания: %.1f м при радиусе %.1f м", o.ctl.errDist, holdR_); Alarm a{"RADIUS_OUT", b, true}; a.prio = 1; o.alarms.push_back(a); }
            else if (rWarn_) { std::snprintf(b, sizeof b, "Приближение к границе радиуса удержания: %.1f м из %.1f м", o.ctl.errDist, holdR_); o.alarms.push_back({"RADIUS_WARN", b, false}); }
        } else { rWarn_ = rOut_ = false; rWarnOn_ = rWarnOff_ = rOutOn_ = rOutOff_ = 0; }
        // --- предел курса: предупреждение при 80 % предела, аларм при выходе (с выдержкой и гистерезисом, как у радиуса)
        if (hdgLim_ > 0 && ok && (m == DpMode::AutoHeading || m == DpMode::AutoPosition || m == DpMode::Track)) {
            const double q = std::fabs(o.ctl.errHdgDeg) / hdgLim_;
            auto upd = [&](bool& on, double& tOn, double& tOff, double hi, double lo, double holdOn, double holdOff) {
                if (!on) { tOn = q >= hi ? tOn + dt : 0.0; if (tOn >= holdOn) { on = true; tOff = 0; } }
                else { tOff = q < lo ? tOff + dt : 0.0; if (tOff >= holdOff) { on = false; tOn = 0; } }
            };
            upd(hOut_, hOutOn_, hOutOff_, 1.0, 0.9, 2.0, 3.0);
            upd(hWarn_, hWarnOn_, hWarnOff_, 0.8, 0.7, 3.0, 3.0);
            char b[200];
            if (hOut_) { std::snprintf(b, sizeof b, "Курс вышел за предел: отклонение %.1f° при пределе %.1f°", std::fabs(o.ctl.errHdgDeg), hdgLim_); Alarm a{"HDG_OUT", b, true}; a.prio = 1; o.alarms.push_back(a); }
            else if (hWarn_) { std::snprintf(b, sizeof b, "Приближение к пределу курса: %.1f° из %.1f°", std::fabs(o.ctl.errHdgDeg), hdgLim_); o.alarms.push_back({"HDG_WARN", b, false}); }
        } else { hWarn_ = hOut_ = false; hWarnOn_ = hWarnOff_ = hOutOn_ = hOutOff_ = 0; }
        // --- прогнозирование внешних сил: накопление таблицы поправок и прогноз нагрузки на 1…10 мин
        {
            FcIn fi; fi.dt = dt; const EstimatorState& e2 = o.est;
            fi.learn = ok && m == DpMode::AutoPosition && e2.posValid && e2.hdgValid && e2.windValid && !lastSat_ && std::hypot(e2.vn, e2.ve) < 0.6;
            fi.windValid = e2.windValid; fi.hdgValid = e2.hdgValid; fi.windSpeed = e2.windSpeed; fi.windRel = e2.windFromRel; fi.psi = e2.psi;
            fi.biasN = e2.biasN; fi.biasE = e2.biasE; fi.biasM = e2.biasMoment; fi.applied = fcApplied; fi.cap = cap;
            fi.waveValid = waveOn; fi.hs = wHs; fi.waveFrom = wFrom; fi.tz = e2.wave.tz; fi.waveGain = wGain;
            o.fc = fc_.step(fi, vcfg_);
            if (o.fc.warn && (m == DpMode::AutoPosition || m == DpMode::Track)) {
                char b[200]; double l5 = 0; for (size_t k = 0; k < o.fc.horizonS.size(); ++k) if (std::fabs(o.fc.horizonS[k] - fc_.cfg().warnHorizonS) < 1.0) l5 = o.fc.load[k];
                std::snprintf(b, sizeof b, "Прогноз: через %.0f мин нагрузка комплекса составит %.0f %% допустимой", fc_.cfg().warnHorizonS / 60.0, 100.0 * l5);
                o.alarms.push_back({"FORECAST_LOAD", b, false});
            }
        }
        lastCap_ = cap; lastSat_ = o.alloc.saturated;
        last_ = o.cmds;
        return o;
    }

private:
    bool highLoad_ = false, dropLatched_ = false, wasReturning_ = false; double onT_ = 0, offT_ = 0;
    Forecaster fc_; Capability lastCap_; bool lastSat_ = false; double satT_ = 0;
    double hdgLim_ = 0; bool hWarn_ = false, hOut_ = false; double hWarnOn_ = 0, hWarnOff_ = 0, hOutOn_ = 0, hOutOff_ = 0;
    std::vector<double> mmT_;
    double holdR_ = 0; bool rWarn_ = false, rOut_ = false; double rWarnOn_ = 0, rWarnOff_ = 0, rOutOn_ = 0, rOutOff_ = 0;
    VesselCfg vcfg_;
    Estimator est_;
    Controller ctl_;
    Allocator alloc_;
    std::vector<ThrusterCmd> last_;
    double availKW_ = 1e9;
    bool lastWaveOn_ = false; double lastHs_ = 0, lastFrom_ = 0, lastGain_ = 0, lastTz_ = 0;
};

}  // namespace dp
