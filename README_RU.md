<p align="right">
  <a href="./README.md">🇬🇧 English</a> · 🇷🇺 Русский
</p>

<div align="center">

# 📬 MIAB Whitelists

### Безопасное и идемпотентное управление whitelist Postfix и Postgrey для Mail-in-a-Box

<p>
  Добавление доверенных доменов, IPv4-адресов и CIDR-подсетей одной командой или из подготовленного файла.
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

## ⚡ В двух словах

`add_whitelists.sh` безопасно добавляет доверенных отправителей в whitelist-файлы Postfix и Postgrey, используемые на серверах Mail-in-a-Box.

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

---

## ✨ Возможности

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

---

## 🧭 Маршрутизация записей

Два whitelist-файла выполняют разные задачи, поэтому записи маршрутизируются автоматически.

| Тип записи         | Пример            |       Postfix       |       Postgrey      |
| ------------------ | ----------------- | :-----------------: | :-----------------: |
| Домен или hostname | `example.com`     |  ✅ `example.com OK` |   ✅ `example.com`   |
| IPv4-адрес         | `203.0.113.10`    | ✅ `203.0.113.10 OK` |   ✅ `203.0.113.10`  |
| IPv4 CIDR-подсеть  | `198.51.100.0/24` |          ❌          | ✅ `198.51.100.0/24` |

> [!NOTE]
> `hash:`-карты Postfix не поддерживают CIDR-подсети. Поэтому CIDR-записи добавляются только в Postgrey.

### Управляемые файлы

| Сервис   | Файл                                    |
| -------- | --------------------------------------- |
| Postfix  | `/etc/postfix/client_whitelist`         |
| Postgrey | `/etc/postgrey/whitelist_clients.local` |

---

## 🚀 Быстрый старт

### Вариант 1: запуск из репозитория

```bash
git clone https://github.com/Anton-Babaskin/miab-whitelists.git
cd miab-whitelists

chmod +x add_whitelists.sh
sudo ./add_whitelists.sh example.com
```

### Вариант 2: глобальная установка

```bash
git clone https://github.com/Anton-Babaskin/miab-whitelists.git
cd miab-whitelists

sudo install -m 0755 add_whitelists.sh /usr/local/bin/add_whitelists.sh
```

После этого команду можно запускать из любой директории:

```bash
sudo add_whitelists.sh example.com
```

### Установка полного набора инструментов

Для установки этого инструмента вместе с массовым импортёром готового whitelist используйте:

[`miab-whitelist-installer`](https://github.com/Anton-Babaskin/miab-whitelist-installer)

---

## 🛠 Использование

### Добавить домен

```bash
sudo add_whitelists.sh example.com
```

### Добавить почтовый hostname

```bash
sudo add_whitelists.sh mail.example.net
```

### Добавить IPv4-адрес

```bash
sudo add_whitelists.sh 203.0.113.10
```

### Добавить IPv4 CIDR-подсеть

```bash
sudo add_whitelists.sh 198.51.100.0/24
```

### Импортировать файл

```bash
sudo add_whitelists.sh -f examples/whitelist.example.txt
```

### Предварительно проверить одну запись

```bash
sudo add_whitelists.sh -n example.com
```

### Предварительно проверить весь файл

```bash
sudo add_whitelists.sh -n -f examples/whitelist.example.txt
```

### Показать справку

```bash
add_whitelists.sh -h
```

или:

```bash
add_whitelists.sh --help
```

### Показать версию скрипта

```bash
add_whitelists.sh --version
```

---

## 🎛 Справочник CLI

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

---

## 📄 Формат входного файла

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

---

## 🔄 Что происходит при запуске

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

---

## 💾 Резервные копии и восстановление

Резервные копии имеют следующий формат:

```text
/etc/postfix/client_whitelist.bak_YYYY-MM-DD_HHMMSS
/etc/postgrey/whitelist_clients.local.bak_YYYY-MM-DD_HHMMSS
```

Бэкапы старше 30 дней удаляются автоматически.

### Просмотр доступных копий

```bash
ls -lah /etc/postfix/client_whitelist.bak_*
ls -lah /etc/postgrey/whitelist_clients.local.bak_*
```

### Восстановление Postfix

```bash
sudo cp \
  /etc/postfix/client_whitelist.bak_YYYY-MM-DD_HHMMSS \
  /etc/postfix/client_whitelist

sudo postmap /etc/postfix/client_whitelist
sudo systemctl restart postfix
```

### Восстановление Postgrey

```bash
sudo cp \
  /etc/postgrey/whitelist_clients.local.bak_YYYY-MM-DD_HHMMSS \
  /etc/postgrey/whitelist_clients.local

sudo systemctl restart postgrey
```

Замените `YYYY-MM-DD_HHMMSS` на таймстамп восстанавливаемой резервной копии.

---

## 🧾 Журналирование

Если файл журнала удаётся подготовить, операции записываются в:

```text
/var/log/add_whitelists.log
```

Пример просмотра:

```bash
sudo tail -f /var/log/add_whitelists.log
```

В журнал записываются:

* запуск и завершение скрипта;
* пользователь, запустивший команду;
* добавленные домены, IP-адреса и CIDR-подсети;
* пропущенные дубликаты;
* некорректные записи;
* перезапуски сервисов;
* итоговые счётчики.

Журналирование работает по принципу best-effort. Ошибка подготовки файла журнала не останавливает обработку whitelist.

---

## 🛡️ Предупреждение о безопасности

> [!WARNING]
> Whitelist может позволить выбранным отправителям обходить greylisting или другие ограничения почтового сервера.

Добавляйте только записи, которые вы контролируете или независимо проверили.

Перед применением большого списка:

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

* Bash;
* Debian или Ubuntu;
* Postfix;
* Postgrey;
* `postmap`;
* `systemctl`;
* root-права или `sudo`.

Проект предназначен для серверов Mail-in-a-Box, но также может работать с совместимыми установками Postfix/Postgrey, использующими такие же пути whitelist-файлов.

> [!CAUTION]
> Перед использованием вне Mail-in-a-Box обязательно проверьте пути файлов и конфигурацию почтового сервера.

---

## 🛟 Решение проблем

### `ERROR: Run as root or with sudo`

Используйте:

```bash
sudo add_whitelists.sh example.com
```

### `File not found`

Проверьте путь:

```bash
ls -lah /path/to/whitelist.txt
```

Затем укажите абсолютный путь:

```bash
sudo add_whitelists.sh -f /path/to/whitelist.txt
```

### Запись не была добавлена

Проверьте, существует ли она:

```bash
grep -F "example.com" /etc/postfix/client_whitelist
grep -F "example.com" /etc/postgrey/whitelist_clients.local
```

Также проверьте журнал:

```bash
sudo tail -n 100 /var/log/add_whitelists.log
```

### CIDR отсутствует в Postfix

Это ожидаемое поведение. `hash:`-карты Postfix не поддерживают CIDR-подсети, поэтому CIDR добавляется только в Postgrey.

### Изменения Postfix не применились

Перестройте карту и перезапустите Postfix:

```bash
sudo postmap /etc/postfix/client_whitelist
sudo systemctl restart postfix
```

### Проверка скрипта перед запуском

```bash
bash -n add_whitelists.sh
shellcheck add_whitelists.sh
```

---

## 🔗 Связанные репозитории

| Репозиторий                                                                                  | Назначение                                            |
| -------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| [`miab-whitelists`](https://github.com/Anton-Babaskin/miab-whitelists)                       | Универсальный обработчик whitelist                    |
| [`mass-domain-miab-whitelist`](https://github.com/Anton-Babaskin/mass-domain-miab-whitelist) | Массовый импортёр готового whitelist                  |
| [`miab-whitelist-installer`](https://github.com/Anton-Babaskin/miab-whitelist-installer)     | Автоматический установщик полного набора инструментов |

---

## 🤝 Участие в разработке

Предложения и Pull Request приветствуются.

Перед открытием Pull Request выполните:

```bash
bash -n add_whitelists.sh
shellcheck add_whitelists.sh
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
