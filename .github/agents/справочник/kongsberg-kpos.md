# Kongsberg K-Pos

Метки — см. `README.md`.

## Что это
- Семейство СДП Kongsberg Maritime: K-Pos DP (одиночная, двойная, тройная — для классов DP1/DP2/DP3). Обозначения DP-11/12, DP-21/22, DP-31/32 ⚠ (первая цифра — класс, вторая — число контроллеров/постов; проверить по документации).
- Предшественники: SDP ⚠, cPos — снят с продажи, поддерживается ✔ (kongsberg.com, cPos-DP).
- Состав ✔ (брошюра K-Pos): посты оператора (DP Operator Stations), контроллер (DP Controller), джойстики, в том числе наружные; управление движителями — K-Thrust.

## Режимы
- ✔ Auto Heading: Present Heading, Change Heading, Minimum Power Heading.
- ✔ Joystick — трёхосевая рукоятка.
- ✔ Green Control Follow Target — часть GreenDP.
- ⚠ Auto Position, Auto Track, Follow Target / Follow Sub, ROV Follow, Weather Vane, Auto Area/Radius — по учебным материалам; проверить по руководству.

## Что привычно оператору K-Pos (для агента 7, профиль `kongsberg`) — ⚠ всё по памяти
- Экраны: положение (Position plot), движители (Thrusters), опорные системы (Position reference / Heading reference), датчики (Sensors), тревоги (Alarm list), тренды.
- Consequence Analysis — постоянная, с тревогой «не удержимся при худшем отказе».
- Capability plot онлайн; отдельно — StatCap ✔ (программа расчёта возможностей, kongsberg.com).
- GreenDP — режим экономии топлива с подвижными границами удержания ✔ (название), ⚠ (как работает).
- Передача управления между постами — запрос и подтверждение.

## Источники
- K-Pos, брошюра: https://pdf.nauticexpo.com/pdf/kongsberg-maritime/k-pos-dynamic-positioning-optimizing-complex-vessel-operations/31233-89788.html
- cPos: https://kongsberg.com/maritime/products/positioning-and-manoeuvring/dynamic-positioning/cPos-DP
- StatCap: https://www.kongsberg.com/maritime/products/positioning-and-manoeuvring/dynamic-positioning/statcap-web
- Сертификат типа DNV на систему управления ДП: https://www.kongsberg.com/globalassets/maritime/documents/certificates/product/dynamic-positioning-control-system/det-norske-veritas-dnv/taa000004c-revision7.pdf
