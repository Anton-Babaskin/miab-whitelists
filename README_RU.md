<p align="right">
  <a href="./README.md">🇬🇧 English</a> · 🇷🇺 Русский
</p>

<div align="center">

# 📬 MIAB Whitelists

### Набор инструментов для управления whitelist Postfix и Postgrey на Mail-in-a-Box

<p>
  Два дополняющих друг друга Bash-инструмента: добавлять доверенных отправителей вручную и держать диапазоны облачных провайдеров в актуальном состоянии прямо из их SPF-записей.
</p>

<p>
  <a href="https://github.com/Anton-Babaskin/miab-whitelists/actions/workflows/shellcheck.yml">
    <img alt="ShellCheck" src="https://img.shields.io/github/actions/workflow/status/Anton-Babaskin/miab-whitelists/shellcheck.yml?branch=main&style=for-the-badge&logo=githubactions&logoColor=white&label=ShellCheck">
  </a>
  <img alt="Версия" src="https://img.shields.io/badge/version-2.0-1f6feb?style=for-the-badge">
  <a href="./LICENSE">
    <img alt="Лицензия MIT" src="https://img.shields.io/github/license/Anton-Babaskin/miab-whitelists?style=for-the-badge">
  </a>
  <a href="https://github.com/Anton-Babaskin/miab-whitelists/commits/main">
    <img alt="Последний коммит" src="https://img.shields.io/github/last-commit/Anton-Babaskin/miab-whitelists?style=for-the-badge">
  </a>
</p>

<p>
  <img alt="Bash" src="https://img.shields.io/badge/Bash-4%2B-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white">
  <img alt="Mail-in-a-Box" src="https://img.shields.io/badge/Mail--in--a--Box-Compatible-1f6feb?style=for-the-badge">
  <img alt="Postfix" src="https://img.shields.io/badge/Postfix-Whitelist-336791?style=for-the-badge">
  <img alt="Postgrey" src="https://img.shields.io/badge/Postgrey-Whitelist-6f42c1?style=for-the-badge">
  <img alt="Платформа" src="https://img.shields.io/badge/Debian%20%7C%20Ubuntu-Supported-E95420?style=for-the-badge&logo=ubuntu&logoColor=white">
</p>

<p>
  <a href="https://github.com/Anton-Babaskin/miab-whitelists/stargazers">
    <img alt="Звёзды" src="https://img.shields.io/github/stars/Anton-Babaskin/miab-whitelists?style=flat-square">
  </a>
  <a href="https://github.com/Anton-Babaskin/miab-whitelists/issues">
    <img alt="Задачи" src="https://img.shields.io/github/issues/Anton-Babaskin/miab-whitelists?style=flat-square">
  </a>
  <a href="https://github.com/Anton-Babaskin/miab-whitelists/forks">
    <img alt="Форки" src="https://img.shields.io/github/forks/Anton-Babaskin/miab-whitelists?style=flat-square">
  </a>
</p>

</div>

---

## 🧰 Инструменты

| Инструмент | Что делает | Нужен root |
| ---------- | ---------- | :--------: |
| [`add_whitelists.sh`](#-add_whitelistssh) | Добавляет домены, IPv4-адреса и IPv4 CIDR-подсети в whitelist Postfix и Postgrey — по одной записи или массово из файла. Идемпотентно, с бэкапами и dry-run. | Да |
| [`refresh_cloud_senders.sh`](#%EF%B8%8F-refresh_cloud_senderssh) | Автоматически генерирует актуальные диапазоны облачных провайдеров, рекурсивно разворачивая их SPF-записи в ip4/ip6 CIDR. Работает в паре с `add_whitelists.sh`. | Нет |

Типовой конвейер:

```bash
# 1. Найти новые диапазоны провайдеров, которых ещё нет в whitelist
./refresh_cloud_senders.sh -d whitelist.txt -o new.txt

# 2. Просмотреть их
less new.txt

# 3. Применить (записи IPv4 направляются в Postgrey; см. примечания ниже)
sudo ./add_whitelists.sh -f new.txt
```

---

# 🧩 `add_whitelists.sh`

Безопасно добавляет доверенных отправителей в whitelist-файлы Postfix и Postgrey, используемые на серверах Mail-in-a-Box.

```bash
sudo ./add_whitelists.sh example.com
```

Скрипт автоматически:

* определяет, является ли запись доменом, IPv4-адресом или IPv4 CIDR-подсетью;
* направляет её в соответствующий whitelist;
* пропускает существующие записи;
* создаёт резервные копии с таймстампом;
* удаляет резервные копии старше 30 дней;
* перестраивает карту Postfix только при необходимости;
* перезапускает только изменённые сервисы;
* записывает действия в журнал, если журналирование доступно.

Для нескольких записей:

```bash
sudo ./add_whitelists.sh -f examples/whitelist.example.txt
```

Для предварительного просмотра без изменения сервера:

```bash
sudo ./add_whitelists.sh -n -f examples/whitelist.example.txt
```

### ✨ Возможности

| Возможность                     | Описание                                                                           |
| ------------------------------- | ---------------------------------------------------------------------------------- |
| 🎯 Автоматическая маршрутизация | Домены, IPv4-адреса и CIDR-подсети отправляются в нужный whitelist                 |
| 📄 Одиночный и файловый режимы  | Можно обработать одну запись или загрузить сотни записей из файла                  |
| ♻️ Идемпотентность              | Существующие записи определяются и пропускаются                                    |
| 🔍 Режим dry-run                | Показывает запланированные изменения без модификации файлов и перезапуска сервисов |
| 💾 Резервные копии              | Перед обработкой создаются копии обоих whitelist-файлов                            |
| 🧹 Ротация копий                | Бэкапы старше 30 дней удаляются автоматически                                      |
| ⚡ Условное обновление сервисов  | `postmap` и перезапуски выполняются только при реальных изменениях                 |
| 🧾 Журналирование               | Операции записываются в `/var/log/add_whitelists.log`, когда это возможно          |
| 🎨 Удобный вывод                | В интерактивном терминале автоматически используется цветной вывод                 |
| 🛡️ Проверка root               | Скрипт не изменяет системные файлы без административных прав                       |

### 🧭 Маршрутизация записей

Два whitelist-файла выполняют разные задачи, поэтому записи маршрутизируются автоматически.

| Тип записи         | Пример            |       Postfix       |       Postgrey      |
| ------------------ | ----------------- | :-----------------: | :-----------------: |
| Домен или hostname | `example.com`     |  ✅ `example.com OK` |   ✅ `example.com`   |
| IPv4-адрес         | `203.0.113.10`    | ✅ `203.0.113.10 OK` |   ✅ `203.0.113.10`  |
| IPv4 CIDR-подсеть  | `198.51.100.0/24` |          ❌          | ✅ `198.51.100.0/24` |

> [!NOTE]
> `hash:`-карты Postfix не поддерживают CIDR-подсети. Поэтому CIDR-записи добавляются только в Postgrey.

> [!IMPORTANT]
> `add_whitelists.sh` валидирует только IPv4. Поддерживаются домены, IPv4-адреса и IPv4 CIDR; IPv6 не поддерживается. IPv6-диапазоны помечаются как некорректные записи (см. примечание в разделе `refresh_cloud_senders.sh`).

#### Управляемые файлы

| Сервис   | Файл                                    |
| -------- | --------------------------------------- |
| Postfix  | `/etc/postfix/client_whitelist`         |
| Postgrey | `/etc/postgrey/whitelist_clients.local` |

### 🚀 Быстрый старт

#### Вариант 1: запуск из репозитория

```bash
git clone https://github.com/Anton-Babaskin/miab-whitelists.git
cd miab-whitelists

chmod +x add_whitelists.sh
sudo ./add_whitelists.sh example.com
```

#### Вариант 2: глобальная установка

```bash
git clone https://github.com/Anton-Babaskin/miab-whitelists.git
cd miab-whitelists

sudo install -m 0755 add_whitelists.sh /usr/local/bin/add_whitelists.sh
```

После этого команду можно запускать из любой директории:

```bash
sudo add_whitelists.sh example.com
```

### 🛠 Использование

```bash
sudo add_whitelists.sh example.com                       # добавить домен
sudo add_whitelists.sh mail.example.net                  # добавить почтовый hostname
sudo add_whitelists.sh 203.0.113.10                      # добавить IPv4-адрес
sudo add_whitelists.sh 198.51.100.0/24                   # добавить IPv4 CIDR-подсеть
sudo add_whitelists.sh -f examples/whitelist.example.txt # импортировать файл
sudo add_whitelists.sh -n example.com                    # проверить одну запись
sudo add_whitelists.sh -n -f examples/whitelist.example.txt  # проверить весь файл
add_whitelists.sh -h                                     # показать справку
add_whitelists.sh --help                                 # показать справку
add_whitelists.sh --version                              # показать версию скрипта
```

### 🎛 Справочник CLI

```text
Использование:
  add_whitelists.sh [-n] ENTRY
  add_whitelists.sh [-n] -f FILE

Параметры:
  -f FILE      Прочитать записи из файла
  -n           Dry-run: показать результат без применения изменений
  -h           Показать справку
  --help       Показать справку
  --version    Показать версию скрипта
```

> [!IMPORTANT]
> Режим dry-run также требует root-прав, поскольку скрипт проверяет доступ к системному окружению до начала обработки.

### 📄 Формат входного файла

Используйте одну запись на строку:

```text
# Домены
example.com
mail.example.net

# IPv4-адреса
203.0.113.10

# IPv4 CIDR-подсети
198.51.100.0/24
```

Обработчик:

* игнорирует пустые строки;
* игнорирует строки, начинающиеся с `#`;
* удаляет пробелы по краям;
* преобразует записи в нижний регистр;
* сообщает о неподдерживаемых или некорректных записях;
* пропускает уже существующие записи.

> [!NOTE]
> Текущая версия поддерживает домены, IPv4-адреса и IPv4 CIDR-подсети. IPv6 пока не поддерживается.

### 🔄 Что происходит при запуске

```text
Входные данные
  │
  ▼
Нормализация и проверка
  │
  ▼
Определение типа записи
  │
  ├── Домен ────────► Postfix + Postgrey
  ├── IPv4 ─────────► Postfix + Postgrey
  └── IPv4 CIDR ────► только Postgrey
  │
  ▼
Пропуск существующих записей
  │
  ▼
Применение только реальных изменений
  │
  ├── Изменён Postfix ─► postmap + перезапуск Postfix
  └── Изменён Postgrey ─► перезапуск Postgrey
```

Во время каждого запуска скрипт:

1. проверяет наличие root-прав;
2. подготавливает журнал, когда это возможно;
3. создаёт отсутствующие директории и whitelist-файлы;
4. подготавливает резервные копии с таймстампом;
5. удаляет бэкапы старше 30 дней;
6. обрабатывает и маршрутизирует каждую запись;
7. пропускает дубликаты;
8. перестраивает hash-карту Postfix только при его изменении;
9. перезапускает только затронутый сервис;
10. выводит счётчики и список добавленных записей.

### 💾 Резервные копии и восстановление

Резервные копии имеют следующий формат:

```text
/etc/postfix/client_whitelist.bak_YYYY-MM-DD_HHMMSS
/etc/postgrey/whitelist_clients.local.bak_YYYY-MM-DD_HHMMSS
```

Бэкапы старше 30 дней удаляются автоматически.

#### Просмотр доступных копий

```bash
ls -lah /etc/postfix/client_whitelist.bak_*
ls -lah /etc/postgrey/whitelist_clients.local.bak_*
```

#### Восстановление Postfix

```bash
sudo cp \
  /etc/postfix/client_whitelist.bak_YYYY-MM-DD_HHMMSS \
  /etc/postfix/client_whitelist

sudo postmap /etc/postfix/client_whitelist
sudo systemctl restart postfix
```

#### Восстановление Postgrey

```bash
sudo cp \
  /etc/postgrey/whitelist_clients.local.bak_YYYY-MM-DD_HHMMSS \
  /etc/postgrey/whitelist_clients.local

sudo systemctl restart postgrey
```

Замените `YYYY-MM-DD_HHMMSS` на таймстамп восстанавливаемой резервной копии.

### 🧾 Журналирование

Если файл журнала удаётся подготовить, операции записываются в:

```text
/var/log/add_whitelists.log
```

Пример просмотра:

```bash
sudo tail -f /var/log/add_whitelists.log
```

В журнал записываются запуск и завершение скрипта, пользователь, добавленные записи, дубликаты, некорректные записи, перезапуски сервисов и итоговые счётчики. Журналирование работает по принципу best-effort — ошибка подготовки файла журнала не останавливает обработку whitelist.

### 🛡️ Предупреждение о безопасности

> [!WARNING]
> Whitelist может позволить выбранным отправителям обходить greylisting или другие ограничения почтового сервера.

Добавляйте только записи, которые вы контролируете или независимо проверили. Перед применением большого списка:

```bash
sudo add_whitelists.sh -n -f whitelist.txt
```

Рекомендации:

* проверяйте каждый домен, IP-адрес и диапазон;
* храните корпоративные данные whitelist в приватном репозитории;
* не публикуйте конфигурацию рабочей почтовой инфраструктуры;
* используйте минимально необходимую CIDR-подсеть;
* проверяйте `/var/log/add_whitelists.log`;
* периодически проводите аудит обоих whitelist-файлов;
* проверяйте резервные копии перед удалением старых записей.

Этот репозиторий намеренно не содержит рабочего корпоративного whitelist.

### 🛟 Решение проблем

| Симптом | Решение |
| ------- | ------- |
| `ERROR: Run as root or with sudo` | Запустите через `sudo`. |
| `File not found: ...` | Проверьте путь через `ls -lah`, затем передайте абсолютный путь в `-f`. |
| Запись не была добавлена | Скорее всего, она уже существует — `grep -F "example.com" /etc/postfix/client_whitelist`. Также проверьте журнал. |
| CIDR отсутствует в Postfix | Это ожидаемо — `hash:`-карты Postfix не поддерживают CIDR, поэтому CIDR идёт только в Postgrey. |
| Изменения Postfix не применились | `sudo postmap /etc/postfix/client_whitelist && sudo systemctl restart postfix`. |

Проверка скрипта перед запуском:

```bash
bash -n add_whitelists.sh
shellcheck add_whitelists.sh
```

---

# ☁️ `refresh_cloud_senders.sh`

Держит диапазоны облачных провайдеров актуальными, читая их прямо из SPF-записи каждого провайдера.

### Зачем

SPF-запись провайдера — это **его собственный источник правды**: он обновляет её при любых изменениях своей отправляющей инфраструктуры. Ручная поддержка сотен отдельных IP быстро устаревает; SPF-запись — нет. Запускайте инструмент периодически и всегда получайте текущие диапазоны провайдера.

`refresh_cloud_senders.sh` рекурсивно разворачивает SPF-запись каждого провайдера (следуя за `include:` и `redirect=`, с лимитом глубины и защитой от зацикливания), собирает все диапазоны `ip4:` и `ip6:`, дедуплицирует их и записывает готовый список. Он только читает DNS и пишет файл — **root не требуется**, и он напрямую не трогает почтовый сервер.

### Зависимость

Требуется `dig`:

```bash
sudo apt install dnsutils      # Debian / Ubuntu
sudo yum install bind-utils    # RHEL / CentOS / Fedora
```

### Использование

```text
Использование:
  refresh_cloud_senders.sh [-o OUTPUT] [-d EXISTING] [-h]

Параметры:
  -o OUTPUT    Файл вывода (по умолчанию: cloud_senders.generated.txt)
  -d EXISTING  Diff-режим: сравнить с существующим whitelist и вывести
               ТОЛЬКО новые диапазоны (которых там ещё нет).
  -h           Показать справку
  --version    Показать версию скрипта
```

```bash
./refresh_cloud_senders.sh                          # полный список -> cloud_senders.generated.txt
./refresh_cloud_senders.sh -o ranges.txt            # свой путь вывода
./refresh_cloud_senders.sh -d whitelist.txt         # только новые для вашего whitelist диапазоны
./refresh_cloud_senders.sh -d whitelist.txt -o new.txt
./refresh_cloud_senders.sh --version
```

Сгенерированный файл аннотирован и разбит на секции IPv4 и IPv6, с заголовком, фиксирующим дату, режим и источники-провайдеры.

### Типовой workflow

```bash
# 1. Вычислить, что нового относительно текущего whitelist
./refresh_cloud_senders.sh -d whitelist.txt -o new.txt

# 2. Просмотреть перед применением
less new.txt

# 3. Применить парным инструментом
sudo ./add_whitelists.sh -f new.txt
```

> [!IMPORTANT]
> `refresh_cloud_senders.sh` выдаёт диапазоны и IPv4, и IPv6, но `add_whitelists.sh` валидирует только IPv4. Когда вы подаёте сгенерированный файл в `add_whitelists.sh`, IPv4 CIDR-диапазоны направляются в Postgrey, а любые IPv6-диапазоны помечаются как некорректные записи и пропускаются. Секция IPv6 включена для справки и ручного использования в Postgrey.

### Провайдеры по умолчанию

Массив `PROVIDERS` в начале скрипта определяет, какие SPF-записи разворачиваются. По умолчанию:

| Провайдер | SPF-домен |
| --------- | --------- |
| Microsoft 365 / Exchange Online | `spf.protection.outlook.com` |
| Google Workspace | `_spf.google.com` |
| Amazon SES | `amazonses.com` |
| SendGrid | `sendgrid.net` |
| Mailgun | `mailgun.org` |
| Mimecast | `_netblocks.mimecast.com` |

Чтобы отслеживать ещё одного провайдера, добавьте его SPF-домен в массив:

```bash
PROVIDERS=(
  "spf.protection.outlook.com"
  "_spf.google.com"
  # ...
  "spf.example-provider.com"   # ваш дополнительный провайдер
)
```

### Поддержание актуальности

Диапазоны провайдеров меняются изредка, а не постоянно. Обычно достаточно квартального аудита:

```cron
# Запуск 1-го числа каждого квартала с отправкой diff на ревью (без авто-применения)
0 6 1 1,4,7,10 * /usr/local/bin/refresh_cloud_senders.sh -d /etc/postfix/client_whitelist -o /tmp/cloud_new.txt
```

Просматривайте diff и применяйте его осознанно через `add_whitelists.sh` — не стоит вслепую авто-применять диапазоны провайдеров к почтовым фильтрам.

---

## 📦 Структура репозитория

```text
miab-whitelists/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yml
│   │   ├── feature_request.yml
│   │   └── config.yml
│   ├── workflows/
│   │   └── shellcheck.yml
│   └── PULL_REQUEST_TEMPLATE.md
├── examples/
│   └── whitelist.example.txt
├── add_whitelists.sh
├── refresh_cloud_senders.sh
├── CHANGELOG.md
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── LICENSE
├── README.md
├── README_RU.md
└── SECURITY.md
```

---

## 📋 Требования

| Инструмент | Требования |
| ---------- | ---------- |
| `add_whitelists.sh` | Bash, Debian/Ubuntu, Postfix, Postgrey, `postmap`, `systemctl`, root/`sudo` |
| `refresh_cloud_senders.sh` | Bash, `dig` (dnsutils / bind-utils) — root не требуется |

Проект предназначен для серверов Mail-in-a-Box, но `add_whitelists.sh` также работает с совместимыми установками Postfix/Postgrey, использующими такие же пути whitelist-файлов.

> [!CAUTION]
> Перед использованием скриптов вне Mail-in-a-Box обязательно проверьте пути файлов и конфигурацию почтового сервера.

---

## 🔗 Связанные репозитории

| Репозиторий                                                                                  | Назначение                                            |
| -------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| [`miab-whitelists`](https://github.com/Anton-Babaskin/miab-whitelists)                       | Универсальный обработчик whitelist                    |
| [`mass-domain-miab-whitelist`](https://github.com/Anton-Babaskin/mass-domain-miab-whitelist) | Массовый импортёр готового whitelist                  |
| [`miab-whitelist-installer`](https://github.com/Anton-Babaskin/miab-whitelist-installer)     | Автоматический установщик полного набора инструментов |

---

## 🤝 Участие в разработке

Предложения и Pull Request приветствуются. Перед открытием Pull Request выполните:

```bash
bash -n add_whitelists.sh && shellcheck add_whitelists.sh
bash -n refresh_cloud_senders.sh && shellcheck refresh_cloud_senders.sh
```

Ознакомьтесь с файлами:

* [CONTRIBUTING.md](./CONTRIBUTING.md)
* [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)
* [SECURITY.md](./SECURITY.md)

Никогда не добавляйте в задачи или Pull Request реальные корпоративные whitelist-данные, токены, почтовые журналы или сведения о приватной инфраструктуре.

---

## 📜 История изменений

История выпусков и важные изменения находятся в [CHANGELOG.md](./CHANGELOG.md).

---

## ⚖️ Лицензия

Проект распространяется по [лицензии MIT](./LICENSE).

Copyright © 2025-2026 Anton Babaskin.

---

## ℹ️ Отказ от ответственности

Это независимый общественный проект, который не связан с проектом Mail-in-a-Box и официально им не поддерживается.

Перед применением записей на рабочем сервере всегда запускайте dry-run и проверяйте конфигурацию почтовой системы.
