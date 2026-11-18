# Разбор снимков K-Pos (база_данных/Загрузки/Screenshots_Kongsberg, 39 фото)

Снят пост DP-OS1 Operator, K-Pos DP-21, ПО 8.2.8, учебное судно «Kongsberg Challenger II», режимы AUTO POSITION / JOYSTICK / STANDBY. Разбор — для сопоставления с нашим пультом по дорожной карте, этап 1.

## 1. Шапка состояния (всегда на экране)

- Слева: имя станции (`DP-OS1 Operator`) и системы (`K-POS`), дата-время.
- Режим: крупная зелёная плашка (`AUTO POSITION` / `JOYSTICK` / `STANDBY`) + `Main DP` — какой контроллер ведущий.
- **Два ряда тревог**: верхний — предупреждения (W, жёлтые), нижний — тревоги (A, красные); в каждом ряду последнее сообщение с временем. Раскрываются списком: `Tunnel bow 2 high force`, `Wind 2 sensor rejected`, `Wind 3 sensor rejected`, `Reduced thruster alloc capability`, `DP not under command`, `Internal system logging not running`.
- Справа колокол со **счётчиком неподтверждённых** тревог (красная цифра).
- Кнопки групп меню справа: `Positioning, Settings, Sensors, Thruster / Alarms, View, Tools, System`.

У нас: шапка и строка тревог есть. **Не хватает**: разделения W/A на два ряда, счётчика неподтверждённых на колоколе, раскрытия списка из шапки.

## 2. Главный экран — набор панелей (View)

Меню `View` раскрывает список панелей, которые оператор ставит в ячейки: Posplot, Posplot2, Capability plot, Joystick, Motion prediction, Numeric, Power, Power consumption, Ref sys main, Ref sys status, Position center, Sensor, Thruster forces, Thruster main, Thruster setp feedback, Trends, None. **Это ровно наш принцип «своё рабочее место: панели в ячейках» (этап 1, п. 3).**

Типовая раскладка главного экрана:

| Панель | Содержимое | У нас |
|---|---|---|
| Posplot | Круг с кольцами, Range/Grid стрелками, EBL (пеленг), судно, след, точка задания, ветер и «residual as current» в углах снизу | Есть (PositionView, переработан) |
| Vessel speed | SOG, Model, круговая диаграмма скорости | Частично (блок «Курс и скорость») |
| Position deviation | Круговой индикатор отклонения с сектором | Нет отдельной панели |
| Heading | Mode PRESENT, Auto control axis, ROT °/мин, DEV со шкалой; **заданный курс мелким под фактическим** | Есть |
| Gyro | Три зелёных кружка 1-2-3 (жёлтый = проблема) | Нет |
| Rotation center position | Широта/долгота до 4 знаков, Reference origin sensor (GPS-1), DP class | Частично (lat/lon выведены локально) |
| Controller Mode / Gain level | High Precision / Medium | Нет на экране (этап 1, п. 4) |
| Thruster main | Allocation mode VARIABLE, Priority HDG, Free run OFF, Resultant force/direction/moment, таблица Running/Ready/Enabled с барами kN | Частично (плитки движителей) |
| Thruster force bar | Полосы 0–100 % по каждому движителю; **жёлтеют при перегрузе** | Есть в плитках |
| Thruster force vector | Контур судна с векторами упора, Moment, Resultant force/dir | Есть на плане |
| Wind sensors | 3 датчика: стрелка + Measured vs True | Есть (датчики со значениями — локально) |
| Wind | Компас со стрелкой, 5-мин усреднение, Range 58 kn | Стрелка у обода плана |
| Pitch and roll | Точечное облако качки по датчику | Нет |
| Power consumption | Вертикальная шкала кВт + тренд | Мощность есть (busKW локально), шкалы нет |
| Тренды | Power / Wind / Residual trend, графики внизу | Нет (этап 1, п. 5) |

## 3. Capability plot (диаграмма возможностей)

Полярная диаграмма предельной скорости ветра по курсам + окно настроек `DP Capability and Motion Prediction Settings`: Waves (Height / Period / Dir TRUE), Average Wind (Speed / Dir), Sea Current (Speed / Dir), «automatic calculation of wave and current properties», Average heading. Внизу: Present wind / Waves / Sea current на момент анализа, Vessel HDG, EBL HDG.

У нас: диаграмма возможностей в ядре есть (`cap`), на пульт не выведена — этап 1, п. 4. **Заимствовать**: окно условий среды с ручным вводом и автоматикой.

## 4. Мощность (однолинейная схема)

Генераторы G1–G6 с кВт, секции шин A(1)/A(2)/B(1) с выключателями (зелёные = включены), движители-потребители с кВт, Available/Load/Consumption, тренд Consumption. У нас такой вкладки нет — дорожная карта, вкладка «Мощность» + этап 4 (связь с PMS).

## 5. Диалоги и справка

- **Help по тревоге** (двойной щелчок): Description / Additional information / **Possible consequences** / **Corrective actions**. Примеры: «Thruster high force» (предел ~80 % за ~15 с), «Reduced thruster alloc capability», «Wind sensor rejected». → Это в точности этап 2, п. 7 «причина — реакция — действие».
- **Sensors**: таблица датчиков с колонками Enable / Reference / Scale / Pos / Ref / Value — ручное снятие и выбор системы (этап 2, п. 2).
- **Joystick Settings**: Thrust Full/Reduced, Precision High/General/Low speed, Exponent 1.0, компенсация среды и подстройка течения по осям Surge/Sway/Yaw (этап 3, п. 1–2).
- **System**: System monitor control, Equipment, Redundant stations, Reset controller PS (с подтверждением), Stop/restart (OS software Stop/Restart, Windows Shutdown/Reboot, «Reboot both OS»), Date/time, Printer, Event printer, Access control, Change user, PS/OS configuration mode, Messages, About.
- Подсказка о пользователе: User Operator, Station DP-OS1, Product, SW Rank, Vessel Name.

## 6. Второй экран (Thruster view) — альтернативная раскладка

Слева крупный Heading (факт 325,9° крупно, заданный 326,0 мелким под ним, DEV-шкала), центр — судно с движителями во весь рост (Pitch-бары, CP/OP, RPM, углы), справа: Vessel speed (компас + SOG), Wind, Power consumption, Wind sensors, и панель **Steering**: Heading control Automatic, Gain level Medium, Counter rudder 100 %, Auto trim, Auto/Manual rudder limit 15°/40°, Wind compensation ON, Steering group PROPELLER, Steering mode Asynchronous/Auto.

## 7. Аппаратура

Фото пульта: экран + отдельная панель с джойстиком, поворотной ручкой и клавишами с подсветкой. Учесть при этапе 3 (ручной джойстик): оси экранного джойстика должны повторять логику аппаратного.

## Выводы для этапа 1 (что доделать в нашем пульте)

1. Шапка: разделить W/A в два ряда, счётчик неподтверждённых, раскрытие списка тревог из шапки.
2. Панели-вкладки: у K-Pos раскладка собирается из панелей через View — подтверждает наш п. 3 (наборы рабочих мест); список панелей выше — ориентир набора.
3. На главный экран добавить: Position deviation (круговой), статус гирокомпасов 1-2-3, Controller Mode/Gain, шкалу Power consumption, Pitch-and-roll облако.
4. Тренды (п. 5): Power / Wind / Residual — как у K-Pos, три узких графика внизу.
5. Capability plot с окном условий среды (п. 4) — макет готов у K-Pos.
6. ⚠ Тревоги: структура Help «описание — последствия — действия» у K-Pos совпадает с Mega-Guard; брать за образец при этапе 2, п. 7.
7. ⚠ Изменения раскладки и шапки — только отображение; регулятор и тревоги ядра не затрагиваются.
