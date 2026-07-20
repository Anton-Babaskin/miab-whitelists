#!/usr/bin/env bash
# refresh_cloud_senders.sh
# Тянет актуальные ip4/ip6 диапазоны крупных почтовых провайдеров из их SPF-записей
# (рекурсивно разворачивая include: и redirect=) и генерит готовую секцию для whitelist.
#
# Зачем: SPF — источник правды самого провайдера, он его обновляет сам.
# Вместо ручной поддержки сотен IP — раз в квартал прогоняешь скрипт и получаешь
# свежий список. Отдельные IP гниют, SPF всегда актуален.
#
# Режимы:
#   ./refresh_cloud_senders.sh                       # полный список -> cloud_senders.generated.txt
#   ./refresh_cloud_senders.sh -o ranges.txt         # свой путь вывода
#   ./refresh_cloud_senders.sh -d whitelist.txt      # diff: показать только НОВЫЕ диапазоны
#   ./refresh_cloud_senders.sh -d whitelist.txt -o new.txt
#   ./refresh_cloud_senders.sh -d whitelist.txt --apply   # diff + сразу применить новые
#
# НЕ используем set -e — ломается на grep с exit code 1.
set -uo pipefail

VERSION="1.3"

# Exit codes: 0 ok, 1 error (включая «ни одного диапазона не собрано»),
#             3 partial (часть DNS-запросов упала; --apply в этом случае отказывается)

# ============================================================================
# CONFIG — провайдеры, чьи SPF разворачиваем. Добавляй своих по аналогии.
# ============================================================================
PROVIDERS=(
  "spf.protection.outlook.com"   # Microsoft 365 / Exchange Online
  "_spf.google.com"              # Google Workspace
  "amazonses.com"                # Amazon SES
  "sendgrid.net"                 # SendGrid
  "mailgun.org"                  # Mailgun (включает spf1/spf2.mailgun.org)
  "_netblocks.mimecast.com"      # Mimecast (если используют партнёры)
)

MAX_DEPTH=10                                  # защита от зацикливания include

# ============================================================================
# Цвета — только для TTY (в пайпе/логе чисто)
# ============================================================================
if [ -t 1 ]; then
  C_G=$(tput setaf 2); C_Y=$(tput setaf 3); C_C=$(tput setaf 6)
  C_R=$(tput setaf 1); C_B=$(tput bold);    C_RST=$(tput sgr0)
else
  C_G=""; C_Y=""; C_C=""; C_R=""; C_B=""; C_RST=""
fi
msg() { printf '%b\n' "$*"; }
die() { printf '%bERROR:%b %s\n' "$C_R" "$C_RST" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
refresh_cloud_senders.sh v$VERSION

Разворачивает SPF-записи крупных почтовых провайдеров в список ip4/ip6 CIDR.

Usage:
  refresh_cloud_senders.sh [-o OUTPUT] [-d EXISTING] [-h]

Options:
  -o OUTPUT    Файл вывода (по умолчанию: cloud_senders.generated.txt)
  -d EXISTING  Diff-режим: сравнить с существующим whitelist и вывести
               ТОЛЬКО новые диапазоны (которых там ещё нет).
  --apply      Сразу применить результат через add_whitelists.sh -f
               (требует root; в diff-режиме применяются только новые диапазоны)
  -h           Эта справка
  --version    Версия

Примеры:
  refresh_cloud_senders.sh
  refresh_cloud_senders.sh -d whitelist.txt          # что нового у провайдеров
  refresh_cloud_senders.sh -d whitelist.txt -o new.txt
  sudo refresh_cloud_senders.sh -d whitelist.txt --apply
EOF
  exit "${1:-1}"
}

# ============================================================================
# Аргументы
# ============================================================================
APPLY=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --version) printf 'refresh_cloud_senders.sh v%s\n' "$VERSION"; exit 0 ;;
    --help)    usage 0 ;;
    --apply)   APPLY=1 ;;
    *)         ARGS+=( "$a" ) ;;
  esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}

OUTPUT_FILE="cloud_senders.generated.txt"
DIFF_FILE=""
while getopts ":o:d:h" opt; do
  case "$opt" in
    o) OUTPUT_FILE="$OPTARG" ;;
    d) DIFF_FILE="$OPTARG" ;;
    h) usage 0 ;;
    *) usage 1 ;;
  esac
done

# ============================================================================
# Зависимости
# ============================================================================
command -v dig >/dev/null 2>&1 || die "Нужен 'dig' (apt install dnsutils / yum install bind-utils)."
[ -n "$DIFF_FILE" ] && [ ! -f "$DIFF_FILE" ] && die "Diff-файл не найден: $DIFF_FILE"

# --apply: находим add_whitelists.sh заранее, чтобы не падать после генерации
ADD_SCRIPT=""
if [ "$APPLY" -eq 1 ]; then
  [ "$(id -u)" -eq 0 ] || die "--apply требует root (запусти через sudo)."
  if command -v add_whitelists.sh >/dev/null 2>&1; then
    ADD_SCRIPT="$(command -v add_whitelists.sh)"
  elif [ -x "$(dirname "$0")/add_whitelists.sh" ]; then
    ADD_SCRIPT="$(dirname "$0")/add_whitelists.sh"
  else
    die "--apply: add_whitelists.sh не найден ни в PATH, ни рядом со скриптом."
  fi
fi

# ============================================================================
# Состояние
# ============================================================================
declare -A SEEN_DOMAINS=()
RESULT_IP4=()
RESULT_IP6=()
DNS_FAILS=0

expand_spf() {
  local domain="$1" depth="$2"

  if [ "$depth" -gt "$MAX_DEPTH" ]; then
    msg "   ${C_Y}⚠ depth limit на $domain — пропуск${C_RST}" >&2
    return 0
  fi
  if [ -n "${SEEN_DOMAINS[$domain]:-}" ]; then
    return 0
  fi
  SEEN_DOMAINS[$domain]=1

  # v1.3: различаем сетевой сбой DNS (dig rc != 0: timeout/SERVFAIL/нет связи)
  # и пустой ответ (NXDOMAIN / нет TXT). Сбой считается в DNS_FAILS: при
  # частичных данных скрипт вернёт 3, а --apply откажется применять.
  local raw txt
  if ! raw="$(dig +short txt "$domain" 2>/dev/null)"; then
    DNS_FAILS=$((DNS_FAILS+1))
    msg "   ${C_R}✗ DNS-сбой на $domain (timeout/SERVFAIL)${C_RST}" >&2
    return 0
  fi
  txt="$(printf '%s' "$raw" | tr -d '"' | tr '\n' ' ')"
  if [ -z "${txt// /}" ]; then
    msg "   ${C_Y}⚠ нет TXT/SPF у $domain${C_RST}" >&2
    return 0
  fi
  case "$txt" in
    *v=spf1*) : ;;
    *) return 0 ;;
  esac

  local token
  # SPF tokens are intentionally word-split on whitespace.
  # shellcheck disable=SC2086
  for token in $txt; do
    case "$token" in
      ip4:*)      RESULT_IP4+=( "${token#ip4:}" ) ;;
      ip6:*)      RESULT_IP6+=( "${token#ip6:}" ) ;;
      include:*)  expand_spf "${token#include:}"  $((depth + 1)) ;;
      redirect=*) expand_spf "${token#redirect=}" $((depth + 1)) ;;
      *)          : ;;
    esac
  done
}

# ============================================================================
# MAIN
# ============================================================================
msg "${C_B}🔄 refresh_cloud_senders.sh v${VERSION}${C_RST} — разворачиваю SPF провайдеров..."
[ -n "$DIFF_FILE" ] && msg "   ${C_C}diff-режим против:${C_RST} $DIFF_FILE"
msg ""

for p in "${PROVIDERS[@]}"; do
  msg "🌐 ${C_C}$p${C_RST}"
  b4=${#RESULT_IP4[@]}; b6=${#RESULT_IP6[@]}
  expand_spf "$p" 0
  msg "   ${C_G}+$(( ${#RESULT_IP4[@]} - b4 )) ip4, +$(( ${#RESULT_IP6[@]} - b6 )) ip6${C_RST}"
done

# v1.3: пустой массив у printf даёт пустую строку -> mapfile получал 1 фиктивный
# элемент и счётчики показывали ip4=1 при полном DNS-сбое. Теперь guard.
UNIQ_IP4=(); UNIQ_IP6=()
if [ "${#RESULT_IP4[@]}" -gt 0 ]; then
  mapfile -t UNIQ_IP4 < <(printf '%s\n' "${RESULT_IP4[@]}" | sort -u -V 2>/dev/null || printf '%s\n' "${RESULT_IP4[@]}" | sort -u)
fi
if [ "${#RESULT_IP6[@]}" -gt 0 ]; then
  mapfile -t UNIQ_IP6 < <(printf '%s\n' "${RESULT_IP6[@]}" | sort -u)
fi

# v1.3: не перезаписываем выходной файл, если не собрано ни одного диапазона
# (массовый DNS-сбой не должен уничтожать прошлый результат).
if [ "$(( ${#UNIQ_IP4[@]} + ${#UNIQ_IP6[@]} ))" -eq 0 ]; then
  die "Не собрано ни одного диапазона (DNS-сбоев: $DNS_FAILS). Файл $OUTPUT_FILE не перезаписан."
fi

NEW_IP4=(); NEW_IP6=()
if [ -n "$DIFF_FILE" ]; then
  declare -A KNOWN=()
  # v1.3: сравниваем по ПЕРВОМУ полю строки — cidr-карта Postfix хранит
  # "192.0.2.0/24 OK", раньше diff считал такие диапазоны новыми каждый раз.
  while read -r key _rest; do
    [ -z "$key" ] && continue
    case "$key" in \#*) continue ;; esac
    KNOWN["$key"]=1
  done < "$DIFF_FILE"

  for ip in "${UNIQ_IP4[@]}"; do [ -z "${KNOWN[$ip]:-}" ] && NEW_IP4+=( "$ip" ); done
  for ip in "${UNIQ_IP6[@]}"; do [ -z "${KNOWN[$ip]:-}" ] && NEW_IP6+=( "$ip" ); done
fi

if [ -n "$DIFF_FILE" ]; then
  # ${arr[@]+...} guards against unbound empty arrays under set -u (intentional).
  # shellcheck disable=SC2206
  OUT_IP4=( ${NEW_IP4[@]+"${NEW_IP4[@]}"} ); OUT_IP6=( ${NEW_IP6[@]+"${NEW_IP6[@]}"} )
  HEADER_NOTE="diff vs $DIFF_FILE — только новые диапазоны"
else
  # shellcheck disable=SC2206
  OUT_IP4=( ${UNIQ_IP4[@]+"${UNIQ_IP4[@]}"} ); OUT_IP6=( ${UNIQ_IP6[@]+"${UNIQ_IP6[@]}"} )
  HEADER_NOTE="полный список из SPF"
fi

{
  echo "# ==== AUTO-GENERATED by refresh_cloud_senders.sh v$VERSION ===="
  echo "# Date: $(date '+%F %T')"
  echo "# Mode: $HEADER_NOTE"
  echo "# Source SPF: ${PROVIDERS[*]}"
  echo "# Не редактировать руками — перегенерируется скриптом."
  if [ "${#OUT_IP4[@]}" -gt 0 ]; then
    echo "#"
    echo "# ---- IPv4 (ip4) ----"
    printf '%s\n' "${OUT_IP4[@]}"
  fi
  if [ "${#OUT_IP6[@]}" -gt 0 ]; then
    echo "#"
    echo "# ---- IPv6 (ip6) — Postgrey ок, Postfix hash их не матчит ----"
    printf '%s\n' "${OUT_IP6[@]}"
  fi
} > "$OUTPUT_FILE"

msg ""
# v1.3: при частичных DNS-данных --apply отказывается — иначе после diff
# устаревший «частичный» список выглядел бы как куча новых диапазонов.
if [ "$DNS_FAILS" -gt 0 ]; then
  msg "${C_Y}⚠ Частичный результат: DNS-сбоев ${DNS_FAILS}. Проверь сеть/резолвер и перезапусти.${C_RST}"
  if [ "$APPLY" -eq 1 ]; then
    die "--apply отменён: применять частичные данные небезопасно (exit 3 без --apply)."
  fi
fi

if [ -n "$DIFF_FILE" ]; then
  total_new=$(( ${#NEW_IP4[@]} + ${#NEW_IP6[@]} ))
  if [ "$total_new" -eq 0 ]; then
    msg "${C_G}✅ Всё актуально.${C_RST} Новых диапазонов у провайдеров нет."
  else
    msg "${C_Y}🆕 Новых диапазонов: ${total_new}${C_RST} (ip4=${#NEW_IP4[@]}, ip6=${#NEW_IP6[@]}) → ${C_B}$OUTPUT_FILE${C_RST}"
    # shellcheck disable=SC2086
    for ip in ${NEW_IP4[@]+"${NEW_IP4[@]}"} ${NEW_IP6[@]+"${NEW_IP6[@]}"}; do msg "   ${C_G}+ $ip${C_RST}"; done
    msg ""
    if [ "$APPLY" -eq 1 ]; then
      msg "🚀 ${C_B}--apply:${C_RST} применяю новые диапазоны через add_whitelists.sh"
      "$ADD_SCRIPT" -f "$OUTPUT_FILE" || die "--apply: add_whitelists.sh завершился с ошибкой."
    else
      msg "   Применить новые:  ${C_Y}sudo add_whitelists.sh -f $OUTPUT_FILE${C_RST}"
    fi
  fi
else
  msg "${C_G}✅ Готово.${C_RST} ip4=${C_C}${#UNIQ_IP4[@]}${C_RST}, ip6=${C_C}${#UNIQ_IP6[@]}${C_RST} → ${C_B}$OUTPUT_FILE${C_RST}"
  if [ "$APPLY" -eq 1 ]; then
    msg "🚀 ${C_B}--apply:${C_RST} применяю полный список через add_whitelists.sh"
    "$ADD_SCRIPT" -f "$OUTPUT_FILE" || die "--apply: add_whitelists.sh завершился с ошибкой."
  else
    msg "   Просмотри:  ${C_Y}less $OUTPUT_FILE${C_RST}"
    msg "   Применить:  ${C_Y}sudo add_whitelists.sh -f $OUTPUT_FILE${C_RST}"
  fi
fi

[ "$DNS_FAILS" -gt 0 ] && exit 3
exit 0
