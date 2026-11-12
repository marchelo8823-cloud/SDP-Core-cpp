# Справка по командам СДП

Команды оператора:
  standby                    ожидание (команды на движители не выдаются)
  position                   удержание позиции в текущей точке
  heading                    удержание курса
  track                      движение по треку из настроек
  set <север> <восток> <курс>  новая уставка (м от начала координат, градусы)
  move <dС> <dВ> [dКурс]     сместить уставку относительно текущей
  hdgconfirm <°>|off         смена курса больше порога ждёт подтверждения: hdg accept | hdg cancel
  watch on <мин>|off|reset   таймер бдительности оператора (любая команда его сбрасывает)
  sentwatch <с>|off          тревога, если принимаемая посылка датчика замолчала
  pivotreset on|off          сброс точки вращения через 5 с после выхода из режима ДП
  ext [status|tpl|active on <код>|off|send <шаблон>|inject <строка>|setup <JSON>|clear]  связь с внешней ДП (Praxis, Kongsberg); setup/clear — настройка из окна
  rate [rot <°/мин|off>|speed <уз|off>]  ограничения движения оператора: максимальная скорость поворота и перемещения (действуют на опорную точку)
  src [list|test <JSON линии> [секунд]|watch on|off]  физические источники: COM/USB-порты, сетевые интерфейсы, проверка линии (только слушает)
  cap [status|setup <JSON>|clear|start [метка]|stop|mark <текст>|report|replay last <канал> <адрес> <порт> [скорость]|replay stop|watch on|off]  запись обмена с внешней системой (UDP/TCP/COM, Modbus)
  limits [on|off|move|setdist|hdg|forbid|allow]  ограничения оператора (меняет администратор)
  pivot center|bow|stern|<имя>  точка вращения по названию (список: pivots; свои — pivotPresets в конфигурации)
  hypot fail=… bus=A|B limit=% wind=м/с from=° cur=м/с radius=м  гипотетический анализ: держит ли, дрейф, время до радиуса
  tal normal|lowbias|highbias|portahead|stbdahead  режим логики распределения тяги колонок
  autoexcl on|off            автоснятие движителя с управления при расхождении обратной связи
  holdarea <R м>|off|warn <%>|stop <%>  зона удержания (радиус, предупреждение, остановка)
  ref <ID> auto on|off|now   автоначало относительной системы по текущему решению
  fusion freeze <N>|off      тест заморозки: N одинаковых измерений подряд
  fusion variance off|warn|factor <k>  тест дисперсии (повторяемости) систем положения
  fusion weights normal|manual|auto    веса систем: обычные, ручные 1–10 (ref <ID> weight), по повторяемости
  fusion diverge off|<м>     тест расхождения: предупреждение, если две системы расходятся больше предела
  ref <ID> mode enable|monitor|mobile|disable  режим системы (mobile — не участвует в удержании)
  sensor <ID> brg off <°>    поправка нуля пеленга Fanbeam или азимута Artemis
  msg <код>|all              описание сообщения: последствия и действия (словарь сообщений)
  hdg <курс>                 новый курс
  law pid|lqr|mpc            сменить закон управления
  gain high|low              усиление контуров: высокое / низкое (High/Low gain)
  minpower on|off            минимальная мощность: малые отклонения не отрабатываются
  forecast on|off|reset|save  прогнозирование сил: накопление таблицы поправок и прогноз нагрузки; forecast apply on|off
  hdglimit <1…45°>|off       предел курса: предупреждение при 80 %, аларм при выходе
  plant ...                  электростанция (имитация): gen off|on <ID>, bus off|on A|B, tie open|close, reset
  sim ...                    имитация: wind, current, wave, off|on <ID>, thr off|on <ID>, jump, noise, gyro, mru, reset
  status                     показать состояние
  quit                       выход

