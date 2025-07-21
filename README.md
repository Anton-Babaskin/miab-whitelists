# 📬 Universal Postfix & Postgrey Whitelist Loader

This script automates the process of adding trusted domains and IP addresses to Postfix and Postgrey whitelists.

✅ Great for use with [Mail-in-a-Box](https://mailinabox.email) or any Postfix+Postgrey server setup.

---

## 📦 What the script does

- Reads a list of domains and IPs from a plain text file
- Adds them to `/etc/postfix/client_whitelist` (Postfix)
- Adds **only domains** to `/etc/postgrey/whitelist_clients.local` (Postgrey)
- Creates both files if missing
- Eliminates duplicates automatically
- Creates backups of the original files
- Applies `postmap` and restarts services

---

## 🛠 Installation and usage

### 1. Download the script

```bash
curl -O https://raw.githubusercontent.com/youruser/yourrepo/main/add_whitelist_from_file.sh
chmod +x add_whitelist_from_file.sh
2. Подготовьте файл белого списка
Создайте текстовый файл (по умолчанию: whitelist_input.txt) с одним доменом или IP-адресом на строку:




example.com
mail.trustedpartner.com
203.0.113.5
45.76.0.0/16
3. Запустить скрипт
баш




sudo ./add_whitelist_from_file.sh
Или укажите пользовательский файл:






sudo ./add_whitelist_from_file.sh /path/to/my_whitelist.txt
🔒 Конфиденциальность и безопасность
Скрипт не подключается к интернету

Все входные данные являются локальными.

Вы контролируете, что попадает в ваш белый список

⚙️ Требования
Система Debian/Ubuntu с установленными Postfix и Postgrey

Права root ( sudo)

Файл белого списка в текстовом формате

📁 Примеры использованных путей
Файл	Цель
/etc/postfix/client_whitelist	Белый список IP-адресов/доменов Postfix
/etc/postgrey/whitelist_clients.local	Белый список доменов Postgrey

✅ Лицензия
MIT — Свободное использование, изменение и распространение.

👨‍💻 Автор
Антон Бабаскин — DevOps и автоматизация на базе Linux
