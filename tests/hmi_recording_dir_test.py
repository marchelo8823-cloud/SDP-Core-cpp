#!/usr/bin/env python3
"""Папка записи пульта: пользовательский каталог, ошибочный путь и исчезновение каталога."""
import argparse
import csv
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


def state(output):
    match = re.search(
        r"запись: папка=(.*?); файл=(.*?); резерв=(\d); активна=(\d); предупреждение=(.*)",
        output,
    )
    if not match:
        raise AssertionError(f"Нет итогового состояния записи\n{output}")
    return {
        "dir": match.group(1),
        "file": match.group(2),
        "fallback": match.group(3) == "1",
        "active": match.group(4) == "1",
        "warning": match.group(5),
        "output": output,
    }


def environment(home):
    home.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update({
        "HOME": str(home),
        "XDG_DATA_HOME": str(home / "data"),
        "XDG_CONFIG_HOME": str(home / "config"),
        "QT_QPA_PLATFORM": "offscreen",
        "QT_QUICK_BACKEND": "software",
        # На macOS QStandardPaths не следует за HOME: внутреннюю папку задаём явно внутри build.
        "SDP_INTERNAL_RECORDING_DIR": str(home / "internal"),
    })
    return env


def arguments(args, directory, expected, shot):
    return [
        str(args.hmi),
        "--recording-dir", str(directory),
        "--ship", str(args.source / "data" / "Данные_судна_пример.xlsx"),
        "--sim", str(args.source / "tests" / "scenarios" / "имитатор_быстро.xlsx"),
        "--run", "20", "--cmd", "thr_take all", "--cmd", "position", "--run", "30",
        "--tab", "8", "--size", "1366x768",
        "--expect-recording", expected, "--screenshot", str(shot),
    ]


def check_csv(args, path, require_holding=True):
    path = Path(path)
    if not path.is_file():
        raise AssertionError(f"Не создан журнал: {path}")
    with path.open(encoding="utf-8", newline="") as stream:
        rows = list(csv.reader(stream))
    if len(rows) < 2 or not rows[0] or rows[0][0] != "t_s":
        raise AssertionError(f"Журнал пуст или имеет неверный заголовок: {path}")
    if require_holding and not any(len(row) > 1 and row[1] == "УДЕРЖАНИЕ" for row in rows[1:]):
        raise AssertionError(f"В журнале нет продолжающегося удержания: {path}")
    report = subprocess.run(
        [sys.executable, str(args.source / "tools" / "sdp_report.py"), str(path)],
        text=True, capture_output=True, timeout=30,
    )
    if report.returncode != 0:
        raise AssertionError(f"tools/sdp_report.py не принял {path}\n{report.stdout}\n{report.stderr}")
    print(f"CSV проверен: {path} ({len(rows) - 1} строк данных)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--hmi", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    args = parser.parse_args()
    args.hmi = args.hmi.resolve()
    args.source = args.source.resolve()
    args.build = args.build.resolve()
    root = args.build / "hmi_recording_dir"
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True)

    # 1. Запись непосредственно в существующий пользовательский каталог.
    custom = root / "custom"
    custom.mkdir()
    custom_shot = root / "custom.png"
    result = subprocess.run(
        arguments(args, custom, "custom", custom_shot),
        cwd=args.source, env=environment(root / "home_custom"),
        text=True, capture_output=True, timeout=40,
    )
    if result.returncode != 0:
        raise AssertionError(f"Пользовательская папка: код {result.returncode}\n{result.stdout}\n{result.stderr}")
    custom_state = state(result.stdout)
    if Path(custom_state["dir"]) != custom or custom_state["fallback"] or not custom_state["active"]:
        raise AssertionError(f"Неверное состояние пользовательской папки: {custom_state}")
    custom_csv = custom / custom_state["file"]
    check_csv(args, custom_csv)
    if not custom_shot.is_file():
        raise AssertionError("Нет снимка пользовательской папки")

    # 2. Несуществующий путь: предупреждение и новый журнал во внутренней папке.
    missing = root / "missing" / "not-mounted"
    invalid_shot = root / "fallback_invalid.png"
    invalid = subprocess.run(
        arguments(args, missing, "fallback", invalid_shot),
        cwd=args.source, env=environment(root / "home_invalid"),
        text=True, capture_output=True, timeout=40,
    )
    if invalid.returncode != 0:
        raise AssertionError(f"Недоступный путь: код {invalid.returncode}\n{invalid.stdout}\n{invalid.stderr}")
    invalid_state = state(invalid.stdout)
    if not invalid_state["fallback"] or not invalid_state["active"] or not invalid_state["warning"]:
        raise AssertionError(f"Нет резервного режима после ошибки пути: {invalid_state}")
    check_csv(args, Path(invalid_state["dir"]) / invalid_state["file"])

    # 3. Каталог исчезает после создания CSV: открытый старый поток не должен помешать резервной записи.
    removable = root / "removable"
    removable.mkdir()
    removed_shot = root / "fallback_removed.png"
    process = subprocess.Popen(
        arguments(args, removable, "fallback", removed_shot),
        cwd=args.source, env=environment(root / "home_removed"),
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    deadline = time.monotonic() + 20
    initial_csv = None
    while time.monotonic() < deadline:
        candidates = list(removable.glob("*.csv"))
        if candidates and candidates[0].stat().st_size > 200:
            initial_csv = candidates[0]
            break
        if process.poll() is not None:
            break
        time.sleep(0.02)
    if initial_csv is None:
        output = process.communicate(timeout=5)[0]
        raise AssertionError(f"Не создан исходный CSV перед удалением каталога\n{output}")
    shutil.rmtree(removable)
    output = process.communicate(timeout=40)[0]
    if process.returncode != 0:
        raise AssertionError(f"Исчезновение каталога: код {process.returncode}\n{output}")
    removed_state = state(output)
    if not removed_state["fallback"] or not removed_state["active"] or not removed_state["warning"]:
        raise AssertionError(f"Нет предупреждения и резервной записи после удаления: {removed_state}")
    if Path(removed_state["dir"]) == removable:
        raise AssertionError("Пульт продолжает считать удалённый каталог активным")
    fallback_csv = Path(removed_state["dir"]) / removed_state["file"]
    check_csv(args, fallback_csv)
    if not removed_shot.is_file():
        raise AssertionError("Нет снимка резервного режима")
    print("Проверены пользовательская папка, ошибочный путь и исчезновение каталога во время записи.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ОШИБКА: {exc}", file=sys.stderr)
        sys.exit(1)
