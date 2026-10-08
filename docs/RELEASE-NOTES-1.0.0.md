# Nuvrion XHTTP Installer 1.0.0

Автономная установка и настройка Remnawave-ноды: VLESS REALITY TCP + XHTTP,
nginx через Unix sockets и локальный PokéHabitat.

- Один Bash-файл со встроенными шаблонами, сайтом, игровым API и компонентами.
- Первая установка Node: latest или доступная стабильная версия официального image.
- Отсутствующие Docker/Compose устанавливаются через APT; SECRET_KEY вводится скрыто/файлом 0600.
- Сохранена схема Xray :443 → Reality local target/PROXY protocol → nginx → XHTTP socket.
- Готовые Config Profile, параметры двух Host с Firefox и полный XHTTP extra.
- Cookie-padding для проверенного Xray 26.7.28, DNS AdGuard → COMSS.
- Защищённые socket permissions, Docker NNP, pids limits и read-only Nginx.
- Auto Tuning, ZRAM/RPS/BBR, Traffic Control, Two-Way Ping, Fail2ban и security automation.
- Certbot renewal, firewall API guard, backup/rollback, диагностика и self-check.
- Повторная установка сохраняет действующие keys, clients, SSH, image и бинарник Xray.

Установщик предназначен для Ubuntu 24.04.x: чистый сервер или существующий Remnanode.
Смена образа/Xray действующей ноды и изменения SSH запрещены.
Исправление первой установки опубликовано **в том же релизе 1.0.0**, по запросу автора.
Профиль применяется через Remnawave отдельно; до этого возможен статус
WAITING_FOR_REMNAWAVE_PROFILE.

Проверены оба транспорта настоящим Xray-клиентом, сайт HTTP 200, XHTTP backend
HTTP 400, TLS 1.2/1.3, h2, DNS fallback, права сокетов, firewall, reinstall,
rollback и повтор после reboot тестовой ноды. 215 тестов общего проекта прошли
до выделения репозитория. Ошибки SIGPIPE, Compose interpolation и NUL logs исправлены.
HAPP/INCY, публичная подписка скрытых Host, чистая ОС и WAN line-rate не подтверждены.

Дополнительно проверен реальный первый запуск **latest и 3.4.2** в изолированных
Node fixtures: API, NNP, image ID, credentials 0600 и сохранение действующей ноды.
60 unit/shell tests прошли на Linux. Полный reinstall исправленного скрипта
на действующей тестовой ноде дал RUNNING, сайт 200/XHTTP 400 и успешный staging
renewal; контейнеры, image/Xray, SSH и профиль сохранились.
Полная установка новой ОС с первоначальным Docker/APT и новым ACME issuance
не проводилась; эта граница отражена в отчёте.

Файлы релиза: **nuvrion-xhttp-install.sh** и **SHA256SUMS**.
Проверенный SHA-256 Bash:

```text
16ced4c52dee93d803e1d70b182dd288e3eae3820254fb1b062186af5c620952
```

[Установка и команды](https://github.com/nuvrion-kvn/Nuvrion-XHTTP-Installer/blob/main/README.md)
· [Результаты тестов](https://github.com/nuvrion-kvn/Nuvrion-XHTTP-Installer/blob/main/NUVRION-TEST-RESULTS.md)
· [Сообщить об ошибке](https://github.com/nuvrion-kvn/Nuvrion-XHTTP-Installer/issues)
