# Nuvrion XHTTP Installer 1.0.0

Автономная установка Remnawave Node на Ubuntu 24.04.x: VLESS REALITY TCP
selfsteal + XHTTP, Nginx через Unix sockets и локальный сайт декой.

**[Готовая команда установки прямо из GitHub](https://github.com/nuvrion-kvn/Nuvrion-XHTTP-Installer#быстрый-запуск-с-github)** — скачивание публичного релиза, проверка SHA-256 и интерактивный запуск без токена.
[Скачать Bash-файл](https://github.com/nuvrion-kvn/Nuvrion-XHTTP-Installer/releases/latest/download/nuvrion-xhttp-install.sh) · [SHA256SUMS](https://github.com/nuvrion-kvn/Nuvrion-XHTTP-Installer/releases/latest/download/SHA256SUMS).

- Один Bash-файл со встроенными шаблонами, сайтом, API и компонентами.
- В начале: название, лицензия MIT, создатель Nuvrion / nuvrion-kvn и состав установки.
- Ручной ввод домена, API-порта (default 2222), IP панели и секретного ключа:
  жирные жёлтые русские подсказки, ключ скрыт и не записывается в журнал.
- Все DNS A-записи должны совпадать с внешним IPv4 сервера; несовпадение
  отменяет установку до изменений. `--yes` не обходит DNS guard.
- Выбранный API-порт используется в NODE_PORT, firewall IPv4/IPv6, Auto Tuning,
  сохранённом состоянии, автозапуске и диагностике. Доступ — только IP панели.
- Latest или доступный стабильный image для новой ноды; отсутствующие
  Docker/Compose и зависимости устанавливаются через APT.
- Существующие Compose, API-порт, SECRET_KEY, Reality keys, clients, SSH,
  image и бинарник Xray сохраняются. Введённый действующий ключ проверяется;
  автоматическая замена credentials/порта установленной ноды запрещена.
- Config Profile с двумя inbound и XHTTP extra, два Host с Firefox.
  В Host extra оставляется пустым: панель наследует его из inbound.
- Защищённые Unix sockets, TLS 1.2/1.3, HTTP/2, PROXY protocol и client real IP.
- Auto Tuning: BBR/fq, ZRAM, RPS/RFS, sysctl и лимиты; Traffic Control,
  Two-Way Ping, Fail2ban, security automation и обслуживание пакетов.
- Certbot renewal, backup/rollback, diagnostics и self-check.

Порт панели в подсказке — **API-порт на сервере ноды**, а не порт
веб-интерфейса панели. В карточке Node укажите тот же порт. Пользовательские
Host REALITY/XHTTP используют TCP/443. Профиль применяется через Remnawave;
до его загрузки возможен `WAITING_FOR_REMNAWAVE_PROFILE`.

Проверки: 71 unit/shell test на Linux, настоящий терминал со скрытым вводом,
Bash syntax, ShellCheck 0.11.0, воспроизводимая сборка (119 встроенных файлов).
Настоящие Node fixtures: latest/API 2222 и 3.4.2/API 3222; kernel firewall
проверен в отдельном network namespace на обоих портах. REALITY и XHTTP
проверены авторизованными Xray-клиентами, включая сайт, API, TLS/h2, real IP,
cookie-padding, DNS fallback и Nginx rollback.

Полная установка чистой ОС с первоначальным Docker/APT и новым ACME issuance,
HAPP/INCY и WAN throughput не подтверждены; границы проверки описаны в отчёте.

Файлы релиза: **nuvrion-xhttp-install.sh** и **SHA256SUMS**.
SHA-256 Bash:

```text
027748f902320406c6e9dd5e9acb8b986f4b0427b4d13ae8c27a86eb10f19c6d
```

[Установка и команды](https://github.com/nuvrion-kvn/Nuvrion-XHTTP-Installer/blob/main/README.md)
· [Результаты тестов](https://github.com/nuvrion-kvn/Nuvrion-XHTTP-Installer/blob/main/NUVRION-TEST-RESULTS.md)
· [Сообщить об ошибке](https://github.com/nuvrion-kvn/Nuvrion-XHTTP-Installer/issues)
