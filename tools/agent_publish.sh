#!/usr/bin/env bash
# Задание отправки (с правом записи, без Claude): проверяет, что агент менял только разрешённые файлы, отправляет ветку
# и открывает предложение изменений. tools/agent_publish.sh <префикс ветки> <разрешённые пути, регулярное выражение> <№ задачи или пусто>
set -euo pipefail
PREFIX="$1"; ALLOW="$2"; ISSUE="${3:-}"
[ -f agent-out/ветка.txt ] || { echo "Агент ничего не сдал."; exit 0; }
BR=$(head -1 agent-out/ветка.txt)
[[ "$BR" == "$PREFIX"* ]] || { echo "::error::Ветка «$BR» не начинается с «$PREFIX» — не отправляю."; exit 1; }
[[ "$BR" =~ ^[A-Za-z0-9/_.-]+$ ]] || { echo "::error::Недопустимое имя ветки — не отправляю."; exit 1; }
git fetch -q agent-out/изменения.bundle "refs/heads/$BR:refs/heads/$BR"
BASE=$(git merge-base "$BR" HEAD)
BAD=$(git -c core.quotepath=off diff --name-only "$BASE" "$BR" | grep -Ev "$ALLOW" || true)
if [ -n "$BAD" ]; then
  echo "::error::Агент изменил файлы вне разрешённых — не отправляю:"; echo "$BAD"
  [ -n "$ISSUE" ] && gh issue comment "$ISSUE" --body "⚠ Изменения агента не отправлены: затронуты файлы вне разрешённых (${PREFIX}*):
\`\`\`
$BAD
\`\`\`" || true
  exit 1
fi
git push -u origin "$BR"
TITLE=$(grep -m1 -E '^# ' agent-out/описание.md | sed 's/^# //' || true); [ -n "$TITLE" ] || TITLE="Изменения агента: $BR"
gh pr create --head "$BR" --title "$TITLE" --body-file agent-out/описание.md || echo "Предложение изменений уже есть или не создано."
