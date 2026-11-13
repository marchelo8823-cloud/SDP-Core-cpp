#!/usr/bin/env python3
"""Скачивает вложения из текста задачи в папку вход/ (для агента 1 в GitHub Actions).

Текст задачи берётся из переменной окружения ISSUE_BODY. Скачиваются только ссылки вида
https://github.com/user-attachments/... и https://github.com/<владелец>/<репозиторий>/files/..., не больше 10 файлов по 50 МБ.
Токен (переменная GH_TOKEN) передаётся только на github.com.
"""
import os, re, sys, urllib.request, urllib.parse

body = os.environ.get("ISSUE_BODY", "")
repo = os.environ.get("GITHUB_REPOSITORY", "")
token = os.environ.get("GH_TOKEN", "")
pat = re.compile(r"https://github\.com/(?:user-attachments/(?:assets|files)/[\w\-./%]+|" + re.escape(repo) + r"/files/[\w\-./%]+)")
urls = list(dict.fromkeys(pat.findall(body)))[:10]
os.makedirs("вход", exist_ok=True)
got = []
for i, u in enumerate(urls, 1):
    name = os.path.basename(urllib.parse.urlparse(u).path) or f"файл_{i}"
    name = re.sub(r"[^\w.\-]", "_", name)[:100]
    req = urllib.request.Request(u, headers={"Authorization": f"token {token}"} if token else {})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            host = urllib.parse.urlparse(r.geturl()).hostname or ""
            data = r.read(50_000_001)
        if len(data) > 50_000_000:
            print(f"⚠ {u}: больше 50 МБ, пропущен"); continue
        with open(os.path.join("вход", name), "wb") as fh:
            fh.write(data)
        got.append(name); print(f"скачан: вход/{name} ({len(data)} байт, с {host})")
    except Exception as e:
        print(f"⚠ {u}: не скачан ({e.__class__.__name__})")
with open(os.path.join("вход", "СПИСОК.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(got) + ("\n" if got else "Вложений не скачано.\n"))
