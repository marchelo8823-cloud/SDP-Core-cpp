# Книги сопряжения СДП с пультами управления движителями (ПУ): пустой шаблон, примеры для «Бахтемира» и «Бейсуга»
# и книги с намеренными ошибками для теста pu_test.
# Запуск: python3 tools/make_pu_books.py [папка данных] [папка испорченных книг]   (нужен пакет openpyxl).
# Ядру этот скрипт не нужен: он только делает файлы.
#
# Адреса в ПЛК ПУ взяты из проектов TIA Portal V13 SP1 (S7-1200, прошивка V3.0) шести ПУ: Бахтемир ПУ1–3, Бейсуг ПУ1–3.
# Адреса сигналов сопряжения с СДП во всех шести проектах одинаковые.
# ⚠ Раскладка по узлам, модулям и каналам ET 200SP — предложение, а не данные со схем. Калибровки, знак упора и связь
#   с движителями книги судна не заданы: их нужно снять на судне. Поэтому в примерах управление от СДП выключено.
import os, sys
from openpyxl import Workbook, load_workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

F = Font(name="Arial", size=10); FB = Font(name="Arial", size=10, bold=True); FH = Font(name="Arial", size=10, bold=True, color="FFFFFF")
HEAD = PatternFill("solid", fgColor="1F4E79"); REQ = PatternFill("solid", fgColor="FFF2CC"); OPT = PatternFill("solid", fgColor="E2EFDA")
THIN = Side(style="thin", color="999999"); BOX = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
WRAP = Alignment(wrap_text=True, vertical="top")

# Сигналы сопряжения: подпись (как в include/dp/pu.hpp), адрес в ПЛК ПУ, вид канала СДП
SIGNALS = [
    ("Запрос управления от СДП", "%I5.2", "DQ"),
    ("Задание шага от СДП", "%IW110", "AQ"),
    ("Управление от СДП разрешено", "%Q3.3", "DI"),
    ("Фактический шаг", "%QW100", "AI"),
    ("Отказ системы управления ПУ", "%Q0.0", "DI"),
    ("Готовность ПУ", "%Q4.2", "DI"),
    ("Режим СДП/джойстик", "%Q4.6", "DI"),
    ("Отказ ограничения нагрузки", "%Q0.1", "DI"),
    ("Обобщённая АПС ПУ", "%Q3.6", "DI"),
    ("Нагрузка приводного двигателя", "%QW106", "AI"),
    ("Приводной двигатель работает", "%Q2.1", "DI"),
    ("Нулевой шаг", "%Q2.4", "DI"),
]
# Места модулей в каждом узле ET 200SP (предложение): 1 — DQ, 2 — AQ, 3 — DI, 4 — AI
SLOT = {"DQ": 1, "AQ": 2, "DI": 3, "AI": 4}
PER_PU = {"DQ": 1, "AQ": 1, "DI": 8, "AI": 2}     # каналов каждого вида на один ПУ

UCOLS = [("ПУ", True, 12, "Обозначение ПУ, без повторов"),
         ("Судно", True, 14, "Одна книга — одно судно"),
         ("Название", True, 30, "Как называть ПУ в сообщениях"),
         ("Движитель", False, 12, "Обозначение туннельного движителя с листа «Движители» книги судна; при включённом управлении обязательно"),
         ("Управление от СДП", False, 12, "да | нет; пусто — нет (только наблюдение)"),
         ("Положительный упор", False, 16, "на правый борт | на левый борт; при включённом управлении обязательно")]
CCOLS = [("ПУ", True, 10, "Обозначение с листа «ПУ»"),
         ("Сигнал", True, 32, "Выбор из списка"),
         ("Адрес в ПЛК ПУ", True, 12, "Адрес из реестра data/ПУ_реестр_сигналов.csv"),
         ("Узел", True, 8, "Узел ввода-вывода СДП (набор ET 200SP); для DP-2 — два узла"),
         ("Модуль", True, 8, "Номер места модуля в узле, 1…64; в одном модуле — каналы одного вида"),
         ("Канал", True, 8, "Номер канала модуля, 0…15"),
         ("мА при −100 %", False, 10, "Только для шага: ток при полном шаге «−», 4…20 мА"),
         ("мА при 0 %", False, 10, "Только для шага: ток при нулевом шаге"),
         ("мА при +100 %", False, 10, "Только для шага: ток при полном шаге «+»; точки по возрастанию"),
         ("Полная шкала, А", False, 10, "Только для нагрузки двигателя: ток при 10 В")]

def table(ws, cols, rows, nrows):
    for i, (h, req, w, note) in enumerate(cols, 1):
        c = ws.cell(row=1, column=i, value=h); c.font = FH; c.fill = HEAD; c.border = BOX; c.alignment = WRAP
        ws.column_dimensions[get_column_letter(i)].width = w
    for k in range(nrows):
        for i, (h, req, w, note) in enumerate(cols, 1):
            v = rows[k][i - 1] if k < len(rows) and i - 1 < len(rows[k]) else None
            c = ws.cell(row=2 + k, column=i, value=v); c.fill = REQ if req else OPT; c.border = BOX; c.font = F
    r = 2 + nrows + 1
    ws.cell(row=r, column=1, value="Пояснения к столбцам (эту часть ядро не читает):").font = FB
    for h, req, w, note in cols:
        r += 1; ws.cell(row=r, column=2, value=h).font = FB; ws.cell(row=r, column=3, value="обязательно" if req else "необязательно").font = F; ws.cell(row=r, column=4, value=note).font = F
    ws.freeze_panes = "B2"

def build(path, vessel=None):
    wb = Workbook(); wu = wb.active; wu.title = "ПУ"; wc = wb.create_sheet("Каналы"); wl = wb.create_sheet("Списки")
    for i, (lbl, _, _) in enumerate(SIGNALS, 1): wl.cell(row=i, column=1, value=lbl)
    wl.sheet_state = "hidden"
    units, chans = [], []
    if vessel:
        nodes = ["ET1", "ET2", "ET1"]        # ⚠ предложение: ПУ1 и ПУ3 на первом узле, ПУ2 — на втором
        used = {}
        for n in range(1, 4):
            pid = "ПУ%d" % n; node = nodes[n - 1]
            units.append((pid, vessel, "%s, ПУ%d" % (vessel, n), None, "нет", None))
            k = used.get(node, 0); used[node] = k + 1
            cnt = {}
            for lbl, addr, kind in SIGNALS:
                ch = k * PER_PU[kind] + cnt.get(kind, 0); cnt[kind] = cnt.get(kind, 0) + 1
                chans.append((pid, lbl, addr, node, SLOT[kind], ch, None, None, None, 2000 if lbl == "Нагрузка приводного двигателя" else None))
    table(wu, UCOLS, units, 8); table(wc, CCOLS, chans, max(48, len(chans) + 6))
    dv = DataValidation(type="list", formula1="=Списки!$A$1:$A$%d" % len(SIGNALS), allow_blank=True); dv.error = "Выберите сигнал из списка"
    wc.add_data_validation(dv); dv.add("B2:B60")
    for rng, items in (("E2:E9", "да,нет"), ("F2:F9", "на правый борт,на левый борт")):
        d = DataValidation(type="list", formula1='"' + items + '"', allow_blank=True); wu.add_data_validation(d); d.add(rng)
    wb.save(path)

def find_row(ws, pu, sig):
    for r in range(2, ws.max_row + 1):
        if ws.cell(row=r, column=1).value == pu and ws.cell(row=r, column=2).value == sig: return r
    raise KeyError((pu, sig))

def bad_books(src, out):
    os.makedirs(out, exist_ok=True)
    def make(name, fn):
        wb = load_workbook(src); fn(wb); wb.save(os.path.join(out, name))
    def control(wb, calib=True, thr="BOW1", sign="на правый борт"):
        u = wb["ПУ"]; u.cell(row=2, column=4, value=thr); u.cell(row=2, column=5, value="да"); u.cell(row=2, column=6, value=sign)
        if calib:
            c = wb["Каналы"]
            for s in ("Задание шага от СДП", "Фактический шаг"):
                r = find_row(c, "ПУ1", s)
                for i, v in enumerate((4, 12, 20)): c.cell(row=r, column=7 + i, value=v)
    make("пу_управление.xlsx", lambda wb: control(wb))
    make("пу_управление_без_калибровки.xlsx", lambda wb: control(wb, calib=False))
    make("пу_управление_без_знака.xlsx", lambda wb: control(wb, sign=None))
    make("пу_поворотный.xlsx", lambda wb: control(wb, thr="AZ1"))
    make("пу_нет_движителя.xlsx", lambda wb: control(wb, thr="BOW9"))
    def nofeedback(wb):
        control(wb); c = wb["Каналы"]; c.delete_rows(find_row(c, "ПУ1", "Фактический шаг"))
    make("пу_управление_без_шага.xlsx", nofeedback)
    def dupchan(wb):
        c = wb["Каналы"]; r = find_row(c, "ПУ2", "Готовность ПУ"); c.cell(row=r, column=4, value="ET1"); c.cell(row=r, column=6, value=2)
    make("пу_повтор_канала.xlsx", dupchan)
    def mixmod(wb):
        c = wb["Каналы"]; r = find_row(c, "ПУ1", "Нулевой шаг"); c.cell(row=r, column=5, value=1); c.cell(row=r, column=6, value=9)
    make("пу_смешанный_модуль.xlsx", mixmod)
    def addr(wb):
        c = wb["Каналы"]; c.cell(row=find_row(c, "ПУ1", "Задание шага от СДП"), column=3, value="%IW199")
        c.cell(row=find_row(c, "ПУ1", "Управление от СДП разрешено"), column=3, value="%I5.2")
    make("пу_адрес.xlsx", addr)
    def calib(wb, vals):
        c = wb["Каналы"]; r = find_row(c, "ПУ1", "Фактический шаг")
        for i, v in enumerate(vals): c.cell(row=r, column=7 + i, value=v)
    make("пу_калибровка_убывает.xlsx", lambda wb: calib(wb, (20, 12, 4)))
    make("пу_калибровка_вне.xlsx", lambda wb: calib(wb, (2, 12, 20)))
    make("пу_калибровка_неполная.xlsx", lambda wb: calib(wb, (4, 12)))
    make("пу_неизвестный_сигнал.xlsx", lambda wb: wb["Каналы"].cell(row=2, column=2, value="Задание курса"))
    make("пу_повтор_пу.xlsx", lambda wb: wb["ПУ"].cell(row=3, column=1, value="ПУ1"))
    make("пу_два_судна.xlsx", lambda wb: wb["ПУ"].cell(row=3, column=2, value="Бейсуг"))
    def onenode(wb):          # остаются ПУ1 и ПУ3, оба на узле ET1
        c = wb["Каналы"]
        for r in range(c.max_row, 1, -1):
            if c.cell(row=r, column=1).value == "ПУ2": c.delete_rows(r)
        wb["ПУ"].delete_rows(3)
    make("пу_один_узел.xlsx", onenode)

data = sys.argv[1] if len(sys.argv) > 1 else "data"
books = sys.argv[2] if len(sys.argv) > 2 else "tests/books"
build(os.path.join(data, "Сопряжение_ПУ_шаблон.xlsx"))
build(os.path.join(data, "Сопряжение_ПУ_Бахтемир_пример.xlsx"), "Бахтемир")
build(os.path.join(data, "Сопряжение_ПУ_Бейсуг_пример.xlsx"), "Бейсуг")
bad_books(os.path.join(data, "Сопряжение_ПУ_Бахтемир_пример.xlsx"), books)
print("готово:", data, books)
