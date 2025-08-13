#!/usr/bin/env bash
set -Eeuo pipefail

# -------------------- CONFIG --------------------
POSTFIX_FILE="/etc/postfix/client_whitelist"            # hash/lmdb map: "value OK"
POSTGREY_FILE="/etc/postgrey/whitelist_clients.local"   # plain list: "domain.tld"
BACKUP_TSTAMP="$(date +%F_%H%M%S)"
# ------------------------------------------------

usage() {
  cat <<EOF
Usage:
  $0 [-n] <domain-or-ip>
  $0 [-n] -f <file_with_entries>

Options:
  -f FILE   Файл со списком (по одной записи в строке, пустые/комментарии # игнорируются)
  -n        Тестовый запуск (ничего не меняет)
  -h        Помощь

Примеры:
  $0 example.com
  $0 203.0.113.7
  $0 -f whitelists.txt
EOF
  exit 1
}

DRY=0
LIST_FILE=""
while getopts ":f:nh" opt; do
  case "$opt" in
    f) LIST_FILE="$OPTARG" ;;
    n) DRY=1 ;;
    h) usage ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))

SINGLE_TARGET="${1:-}"

if [[ -z "$SINGLE_TARGET" && -z "$LIST_FILE" ]]; then
  usage
fi

# -------------------- HELPERS --------------------
msg(){ echo -e "$*"; }
die(){ echo -e "❌ $*" >&2; exit 1; }

require_root(){
  if [[ $EUID -ne 0 ]]; then
    die "Нужно запускать от root (sudo)."
  fi
}

ensure_file(){
  local path="$1"
  local dir
  dir="$(dirname "$path")"
  if [[ ! -d "$dir" ]]; then
    msg "📁 Создаю директорию: $dir"
    [[ $DRY -eq 0 ]] && mkdir -p "$dir"
  fi
  if [[ ! -f "$path" ]]; then
    msg "📝 Создаю файл: $path"
    [[ $DRY -eq 0 ]] && touch "$path"
    [[ $DRY -eq 0 ]] && chmod 0644 "$path"
  fi
}

backup_if_exists(){
  local path="$1"
  if [[ -f "$path" ]]; then
    msg "🗂️  Бэкап: ${path}.bak_${BACKUP_TSTAMP}"
    [[ $DRY -eq 0 ]] && cp -a "$path" "${path}.bak_${BACKUP_TSTAMP}"
  else
    msg "ℹ️  Файл $path отсутствует — бэкап не нужен."
  fi
}

is_domain(){
  local s="$1"
  [[ "$s" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]
}

is_ipv4(){
  local s="$1"
  [[ "$s" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

is_cidr(){
  local s="$1"
  [[ "$s" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]
}

already_in_file(){
  local needle="$1" file="$2"
  grep -qE "^${needle//./\\.}([[:space:]]|$)" "$file"
}

add_postfix(){
  local v="$1"
  if already_in_file "$v" "$POSTFIX_FILE"; then
    msg "ℹ️  Уже есть в Postfix: $v"
    return 1
  fi
  msg "➕ Добавляю в Postfix: $v OK"
  [[ $DRY -eq 0 ]] && echo "$v OK" >> "$POSTFIX_FILE"
  return 0
}

add_postgrey(){
  local v="$1"
  if already_in_file "$v" "$POSTGREY_FILE"; then
    msg "ℹ️  Уже есть в Postgrey: $v"
    return 1
  fi
  msg "➕ Добавляю в Postgrey: $v"
  [[ $DRY -eq 0 ]] && echo "$v" >> "$POSTGREY_FILE"
  return 0
}
# -------------------------------------------------

require_root
msg "🔧 Dry-run: $DRY"

# Готовим файлы (создаём при отсутствии)
ensure_file "$POSTFIX_FILE"
ensure_file "$POSTGREY_FILE"

# Бэкапы
backup_if_exists "$POSTFIX_FILE"
backup_if_exists "$POSTGREY_FILE"

CHANGED_POSTFIX=0
CHANGED_POSTGREY=0
ERRORS=0

process_entry(){
  local raw="$1"
  local entry
  entry="$(echo "$raw" | tr '[:upper:]' '[:lower:]' | xargs)"  # trim + lower

  # игнорируем мусор
  [[ -z "$entry" ]] && return 0
  [[ "$entry" =~ ^# ]] && return 0

  if is_cidr "$entry"; then
    # ВАЖНО: CIDR в hash/texthash не работает. Предупреждаем.
    msg "⚠️  CIDR '$entry' не поддерживается в hash-карте Postfix."
    msg "   Добавь такую сеть в CIDR-таблицу и подключи её в main.cf, например:"
    msg "   check_client_access cidr:/etc/postfix/client_whitelist.cidr"
    msg "   (скрипт этот CIDR пропустит)"
    return 0
  elif is_ipv4 "$entry"; then
    add_postfix "$entry" && CHANGED_POSTFIX=1 || true
    # IP в Postgrey не нужен
  elif is_domain "$entry"; then
    add_postfix "$entry" && CHANGED_POSTFIX=1 || true
    add_postgrey "$entry" && CHANGED_POSTGREY=1 || true
  else
    msg "❌ Некорректная запись: $entry"
    ERRORS=$((ERRORS+1))
    return 1
  fi
}

if [[ -n "$LIST_FILE" ]]; then
  [[ -f "$LIST_FILE" ]] || die "Файл не найден: $LIST_FILE"
  msg "📚 Обрабатываю список: $LIST_FILE"
  while IFS= read -r line || [[ -n "$line" ]]; do
    process_entry "$line" || true
  done < "$LIST_FILE"
else
  process_entry "$SINGLE_TARGET" || true
fi

# Применяем изменения
if [[ $DRY -eq 0 ]]; then
  if [[ $CHANGED_POSTFIX -eq 1 ]]; then
    msg "🧰 postmap $POSTFIX_FILE"
    postmap "$POSTFIX_FILE"
  fi
  if [[ $CHANGED_POSTFIX -eq 1 ]]; then
    msg "🔄 Перезапуск postfix"
    systemctl restart postfix
  fi
  if [[ $CHANGED_POSTGREY -eq 1 ]]; then
    msg "🔄 Перезапуск postgrey"
    systemctl restart postgrey || systemctl restart postgrey.service || true
  fi
  msg "✅ Готово. Изменения: Postfix=${CHANGED_POSTFIX}, Postgrey=${CHANGED_POSTGREY}. Ошибок: ${ERRORS}"
else
  msg "🔎 Dry-run завершён. Ничего не изменено. Предполагаемые изменения: Postfix=${CHANGED_POSTFIX}, Postgrey=${CHANGED_POSTGREY}. Ошибок: ${ERRORS}"
fi

# Подсказка на всякий:
grep -q "client_whitelist" /etc/postfix/main.cf || msg "⚠️  Внимание: в /etc/postfix/main.cf не видно подключения client_whitelist. Убедись, что в smtpd_client_restrictions есть:
    check_client_access hash:${POSTFIX_FILE}"
