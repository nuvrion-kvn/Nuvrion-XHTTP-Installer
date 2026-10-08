# Nuvrion XHTTP: применение и восстановление

Security-ревизия от 08.10.2026. Установщик — один файл `nuvrion-xhttp-install.sh`.
Файлы в `tests/` и `tools/` нужны разработчику для проверки, установка от них не зависит.

## Требования

Только Ubuntu 24.04 LTS / 24.04.x, systemd, root, чистый сервер либо установленный Remnanode с Docker Compose,
`network_mode: host`, выбранный Node API port (default 2222) и общий `/dev/shm`. Нужны домен с A-записью
на сервер, IP панели и email Let's Encrypt. Совместимость cookie-padding проверена
на **Xray 26.7.28 / Remnanode 3.4.2**; другие версии требуют отдельного теста.
Новая нода устанавливается с выбором latest/стабильной версии; отсутствующие
Docker/Compose устанавливаются через APT. Образ и Xray действующей ноды сохраняются.
SECRET_KEY новой ноды вводится скрыто либо читается из root-only файла `0600`.
В начале установки выводятся лицензия MIT, создатель и состав компонентов,
затем жирные жёлтые русские запросы домена, API-порта, IP панели и секретного ключа.
Все A-записи должны совпадать с внешним IPv4 сервера: иначе установка отменяется
до изменения конфигурации, включая `--yes`. `--panel-port` задаёт Node API port,
а не порт веб-интерфейса панели. Тот же порт нужно указать в карточке Node.
Для существующей ноды определяются и сохраняются API-порт и credentials;
в запросе ключа Enter сохраняет действующий ключ, другой ключ отклоняется.

Не переносите JSON другого сервера: Reality private key должен принадлежать этой
ноде. Для существующего профиля экспортируйте полный Config Profile из панели
в root-only файл. Сохраните также исходные Host settings и назначенные inbound.

## Проверка и установка

Для загрузки и запуска прямо из GitHub используйте [готовую команду в README](README.md#быстрый-запуск-с-github): текущая сборка и SHA-256 скачиваются из одного коммита `main` без авторизации, затем после проверки целостности начинается интерактивная установка.

```bash
sha256sum -c SHA256SUMS
sudo bash ./nuvrion-xhttp-install.sh --diagnose
sudo bash ./nuvrion-xhttp-install.sh --install \
  --domain node.example.com --panel-port 2222 --panel-ip 192.0.2.10 \
  --email admin@example.com --node-tag 'My Node' --node-version keep \
  --profile-input /root/existing-profile.json
```

Меню сначала показывает диагностику и план, затем запрашивает подтверждение.
До изменений создаётся timestamped backup. Обычная переустановка сохраняет
существующие ключи, клиентов, DNS, extra и routing. Для согласованного перехода
старой схемы на защищённые сокеты и новый DNS/padding:

```bash
sudo bash ./nuvrion-xhttp-install.sh --reinstall --harden-profile \
  --node-version keep --profile-input /root/existing-profile.json
```

На действующей ноде спланируйте короткое прерывание: изменение Docker NNP/mounts
требует пересоздания только Remnanode и управляемого Nginx. SSH не меняется.
Изменение одного nginx.conf проходит `nginx -t` и reload с сохранением inode.

## Применение в Remnawave

Установщик создаёт root-only файлы:

- `/root/nuvrion-xhttp-profile.json` — полный Config Profile;
- `/root/nuvrion-xhttp-host-settings.txt` — настройки двух Host;
- `/root/nuvrion-xhttp-extra.json` — необязательный override клиентского extra.

Проверьте JSON и примените его **только к нужному профилю**, сохранив связи inbound.
Назначьте ноде оба inbound, включите их в нужный Internal Squad и назначьте Squad
пользователям. В серверных `clients` UUID добавляет Remnawave.

### Настройки REALITY TCP Host в Remnawave

```text
Адрес:          DOMAIN
Порт:           443
SNI:            DOMAIN
Security Layer: DEFAULT
Отпечаток:      firefox
ALPN:           Наследовать из inbound
Inbound:        NODE_TAG
```

`DEFAULT` наследует REALITY из выбранного inbound. Transport — TCP/RAW,
flow — `xtls-rprx-vision`. Поля Host, Path и XHTTP extra parameters оставьте пустыми.

### Настройки XHTTP Host в Remnawave

```text
Адрес:          DOMAIN
Порт:           443
SNI:            DOMAIN
Security Layer: TLS (Transport Layer Security)
Отпечаток:      firefox
ALPN:           h2,http/1.1
Inbound:        NODE_TAG XHTTP
```

В поле Host укажите `DOMAIN`, в Path — свой путь из профиля (по умолчанию
`/api/v3/sync/`). Transport — XHTTP, mode — `auto` из inbound, flow оставьте пустым.
Адрес и SNI обоих Host должны совпадать с доменом ноды (`DOMAIN` в профиле).
В Inbound выберите соответствующий тег из профиля. Сокет в Host не указывается.
Оставьте extra Host пустым для наследования `xhttpSettings.extra` из inbound.
Непустой Host extra переопределяет клиентский объект в подписке, не меняя
серверный Config Profile. Выгрузка extra не требует отдельного применения.
Копируемые JSON-шаблоны профиля и обоих Host доступны в [README](README.md#шаблон-профиля-ноды)
и каталоге [templates](templates/).
Скрытые Host исключаются из обычной подписки: для теста используйте их connection
keys либо разрешённую отдельную подписку. Не ослабляйте глобальные правила панели.

До загрузки профиля ожидается `WAITING_FOR_REMNAWAVE_PROFILE`.
`xrxh.socket` создаёт Xray после назначения inbound; установщик live config
не редактирует. После применения:

```bash
sudo bash ./nuvrion-xhttp-install.sh --diagnose
sudo bash ./nuvrion-xhttp-install.sh --self-check
```

Успех — `RUNNING`, сайт HTTP 200, XHTTP probe HTTP 400 и одинаковые inode сокетов
на host/в обоих контейнерах. 400 означает отклонение неполного XHTTP запроса
backend; полноценный VPN проверяется авторизованным клиентом. 502/504, отказ
сокета или ошибки permissions требуют исправления, это не успешная установка.

![Пути REALITY, HTTPS и XHTTP](assets/xhttp-scheme.svg)

Авторизованный REALITY-поток с внешнего Xray :443 поступает сразу в routing.
Обычный HTTPS/XHTTP TLS проходит через Reality target `/dev/shm/nuvrion-xhttp/nginx.sock`
→ Nginx HTTPS/PROXY protocol → сайт декой либо HTTP proxy на
`/dev/shm/nuvrion-xhttp/xrxh.socket`. Каталог root:web-group `2710`, Nginx socket
`0600`, XHTTP `0660`. Суффикс `,0660` — mode, не часть имени. Старые пути/0666
сохраняются до явной миграции. Группа наследуется от setgid-каталога при каждом
создании, каталог восстанавливает tmpfiles при загрузке.

Сертификат читается из `/etc/letsencrypt` через read-only mount. Certbot timer
включён; deploy hook проверяет и перезагружает только Nginx. Порт 80 нужен
временно для HTTP-01; неизвестный владелец порта не останавливается. API 2222
доступен только панели для IPv4/IPv6, 443 — пользователям. SSH firewall не меняется.

## Обслуживание, удаление и rollback

```bash
sudo bash ./nuvrion-xhttp-install.sh --reinstall --node-version keep
sudo bash ./nuvrion-xhttp-install.sh --maintain
sudo bash ./nuvrion-xhttp-install.sh --remove
sudo bash ./nuvrion-xhttp-install.sh --restore \
  --backup /root/nuvrion-xhttp-backups/YYYYMMDD-HHMMSS
```

`--maintain` обслуживает Ubuntu/зависимости, ZRAM, сеть и APT cache. OpenSSH,
Docker/containerd/runc закреплены на время операции, конфиги сохраняются,
пакетные перезапуски запрещены. Перезагрузка выполняется отдельно в согласованное
время. Работающее чужое управление ZRAM и пользовательские данные сохраняются.

Удаление затрагивает только отмеченные компоненты установщика. Remnanode,
Docker, сертификаты, другие профили, SSH и база игроков сохраняются. Сначала
согласуйте изменения профиля в панели: удаление infrastructure не убирает
назначенные Remnawave inbound автоматически.

При критической ошибке предлагается rollback; `--yes` заранее разрешает его.
Для rollback security-миграции восстановите также **сохранённый Config Profile
в панели**: старые пути в инфраструктуре должны соответствовать старым target/listen.
Серверный rollback не изменяет панель и live Xray config. Старые backup не могут
восстановить/удалить SSH-файлы. Обновления пакетов/ядра не откатываются копированием
конфигурации; их версии/holds записаны в manifest и packages.tsv.

На production сначала повторите изолированные проверки на его точных image ID.
HAPP/INCY, WAN-скорость и чистая ОС требуют отдельных испытаний; результаты
08.10.2026 перечислены в [матрице тестов](NUVRION-TEST-RESULTS.md).
