# Nuvrion XHTTP Installer 1.0.0

Автономная настройка существующей Remnawave-ноды: VLESS REALITY TCP + XHTTP,
nginx через Unix sockets и локальный PokéHabitat.

- Один Bash-файл со встроенными шаблонами, сайтом, игровым API и компонентами.
- Сохранена схема Xray :443 → Reality local target/PROXY protocol → nginx → XHTTP socket.
- Готовые Config Profile, параметры двух Host с Firefox и полный XHTTP extra.
- Cookie-padding для проверенного Xray 26.7.28, DNS AdGuard → COMSS.
- Защищённые socket permissions, Docker NNP, pids limits и read-only Nginx.
- Auto Tuning, ZRAM/RPS/BBR, Traffic Control, Two-Way Ping, Fail2ban и security automation.
- Certbot renewal, firewall API guard, backup/rollback, диагностика и self-check.
- Повторная установка сохраняет действующие keys, clients, SSH, image и бинарник Xray.

Установщик предназначен для Ubuntu 24.04.x с уже установленным Remnanode.
Установка новой ноды/смена образа и изменения SSH отключены по последнему ТЗ.
Профиль применяется через Remnawave отдельно; до этого возможен статус
WAITING_FOR_REMNAWAVE_PROFILE.

Проверены оба транспорта настоящим Xray-клиентом, сайт HTTP 200, XHTTP backend
HTTP 400, TLS 1.2/1.3, h2, DNS fallback, права сокетов, firewall, reinstall,
rollback и повтор после reboot тестовой ноды. 215 тестов общего проекта прошли
до выделения репозитория. Ошибки SIGPIPE, Compose interpolation и NUL logs исправлены.
HAPP/INCY, публичная подписка скрытых Host, чистая ОС и WAN line-rate не подтверждены.

Файлы релиза: **nuvrion-xhttp-install.sh** и **SHA256SUMS**.
Проверенный SHA-256 Bash:

```text
b28d8c8e09cdd021961f405885a3397da25e6a70689043117cb5d4949b3e752e
```

[Установка и команды](https://github.com/nuvrion-kvn/Nuvrion-XHTTP-Installer/blob/main/README.md)
· [Результаты тестов](https://github.com/nuvrion-kvn/Nuvrion-XHTTP-Installer/blob/main/NUVRION-TEST-RESULTS.md)
· [Сообщить об ошибке](https://github.com/nuvrion-kvn/Nuvrion-XHTTP-Installer/issues)
