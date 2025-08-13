#!/bin/bash

# Скрипт для добавления доменов и IP в Postfix и Postgrey whitelist
# Использование: ./add_whitelists.sh whitelist.txt

# Цвета
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

# Проверка аргумента
if [ -z "$1" ]; then
    echo -e "❌ ${RED}Укажите файл с доменами и IP. Пример: ./add_whitelists.sh whitelist.txt${RESET}"
    exit 1
fi

LIST_FILE="$1"
DRY_RUN=0

echo -e "🛠 ${CYAN}Dry-run:${RESET} $DRY_RUN"

# Пути к файлам
PF_FILE="/etc/postfix/client_whitelist"
PG_FILE="/etc/postgrey/whitelist_clients.local"

# Создаём файлы, если нет
echo -e "📄 ${YELLOW}Creating file:${RESET} $PF_FILE"
touch "$PF_FILE"

echo -e "📄 ${YELLOW}Creating file:${RESET} $PG_FILE"
touch "$PG_FILE"

# Резервные копии
PF_BACKUP="${PF_FILE}.bak_$(date +%F_%H%M%S)"
PG_BACKUP="${PG_FILE}.bak_$(date +%F_%H%M%S)"

cp "$PF_FILE" "$PF_BACKUP"
echo -e "📦 ${CYAN}Backup:${RESET} $PF_BACKUP"

cp "$PG_FILE" "$PG_BACKUP"
echo -e "📦 ${CYAN}Backup:${RESET} $PG_BACKUP"

# Добавляем в Postfix
grep -vE '^\s*#|^\s*$' "$LIST_FILE" | while read -r entry; do
    echo "$entry    OK" >> "$PF_FILE"
done
echo -e "➕ ${GREEN}Adding to Postfix:${RESET} $LIST_FILE OK"

# Добавляем в Postgrey (только домены, без IP)
grep -vE '^\s*#|^\s*$' "$LIST_FILE" | grep -vE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' >> "$PG_FILE"
echo -e "➕ ${GREEN}Adding to Postgrey:${RESET} $LIST_FILE"

# Перегенерация и рестарт сервисов
postmap "$PF_FILE"
echo -e "🔄 ${YELLOW}Restarting Postfix${RESET}"
systemctl restart postfix

echo -e "🔄 ${YELLOW}Restarting Postgrey${RESET}"
systemctl restart postgrey

# Итог
POSTFIX_COUNT=$(grep -vE '^\s*#|^\s*$' "$LIST_FILE" | wc -l)
POSTGREY_COUNT=$(grep -vE '^\s*#|^\s*$' "$LIST_FILE" | grep -vE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | wc -l)

echo -e "✅ ${GREEN}Done.${RESET} Changes: Postfix=${CYAN}$POSTFIX_COUNT${RESET}, Postgrey=${CYAN}$POSTGREY_COUNT${RESET}, Errors=${CYAN}0${RESET}"

echo -e "\n📊 ${YELLOW}Всего добавлено в белый список ($POSTFIX_COUNT записей):${RESET}"

# Красивый цветной вывод — IP одним цветом, домены другим
grep -vE '^\s*#|^\s*$' "$LIST_FILE" | while read -r entry; do
    if [[ "$entry" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "   🌐 ${CYAN}$entry${RESET}"   # IP — голубой
    else
        echo -e "   🏷  ${GREEN}$entry${RESET}" # Домен — зелёный
    fi
done
