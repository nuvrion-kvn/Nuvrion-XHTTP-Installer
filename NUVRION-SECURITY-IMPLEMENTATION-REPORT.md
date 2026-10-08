# Nuvrion: реализация security-ревизии XHTTP

08.10.2026. Рабочая ветка `security/xhttp-hardening-20261008`.
Изменения применены только к авторизованной тестовой ноде **45.198.0.253**,
`test.nodescheburnet.beer`. Production deployment, commit и push не выполнялись.

Это отчёт об испытаниях до выделения приватного Nuvrion-XHTTP-Installer 1.0.0.
Ссылки на build.py и environment-specific SSH runners относятся к исходному
проекту разработки; отдельный репозиторий содержит XHTTP builder и tests.

## 1. Выполненная работа

Доработан автономный `nuvrion-xhttp-install.sh`: Reality TCP + XHTTP через Unix
socket, встроенный PokéHabitat, полный Config Profile, Host instructions и extra.
Сохранена цепочка eGames/legiz: Xray :443 → локальный TLS Nginx с PROXY protocol
→ HTTP proxy к XHTTP. Отдельная архитектура транспорта не вводилась.
Название «selfsteal» из исходного описания заменено нейтральным Reality TCP;
локальный target и `xver: 1` сохранены.

## 2. Найденные проблемы

- Default vhost отвергал неизвестный SNI вместо выдачи сайта.
- Сокеты `0666` в общем `/dev/shm` были доступны другим локальным UID.
- Extra/DNS могли быть переписаны при повторной генерации.
- Восстановление старой резервной копии могло вернуть SSH drop-in.
- Перестановка firewall правил могла временно ослабить API guard.
- Реальный запуск выявил SIGPIPE при чтении версии Xray через `head`.
- Реальный Compose интерполировал `$p` в команде запуска Nginx.
- NUL-байты из Docker logs вызывали предупреждение Bash при чтении диагностики.
- TCP connect из внешнего окружения недостаточен для оценки открытых портов:
  80/111/646 имели необычное поведение без локальных listener.

## 3. Изменённые файлы

Новый Bash, `tools/build_xhttp.py`, `tests/test_xhttp*.py`, изолированные firewall
и security integration tests, `tests/live_node_client.py`, developer SSH runners,
два закреплённых vendor snapshots, README, SHA256SUMS, build.py и CI validation.
Добавлены три требуемых документа и `NUVRION-SECURITY-CHANGES.diff`.
Функциональный diff сравнивает новый код с manager из backup тестового сервера;
шестимегабайтный архив опущен. Original Vision installer сохранён побайтно.

## 4. Исправления

TLS default vhost обслуживает PokéHabitat. XHTTP/Game API требуют одновременно
правильные SNI и Host; `/api/` и dotfiles закрыты. Padding headers не скрываются.
Ключи, клиенты, flow, SNI, tags и пользовательский extra сохраняются.
Миграция сокетов/DNS/padding выполняется только явно через `--harden-profile`.
NNP/pids limits добавлены без смены образов, root filesystem Nginx read-only.
Firewall применяет атомарные изменения своих правил, не делает flush.
Код не пишет SSH и запрещает даже rollback старых SSH-файлов.
Версия Xray читается с потреблением всего вывода, переменные Compose экранированы.
NUL-байты удаляются до command substitution; критические ошибки в logs по-прежнему
выявляются. Это подтверждено отдельным regression test.
Добавлены реальные тесты Compose create, fault injection и readonly self-check.

## 5. До и после

| Область | Раньше | После явной миграции |
|---|---|---|
| Unknown SNI | TLS reject / 444 | существующий сертификат + PokéHabitat 200 |
| Nginx socket | `/dev/shm/nginx.sock`, 0666 | private directory, 0600 |
| XHTTP socket | `/dev/shm/xrxh.socket,0666` | private directory, 0660 |
| Padding | обычные настройки XHTTP | cookie `site_session`, tokenish |
| DNS | прежний профиль | AdGuard → COMSS; cache/IPv4 сохранены |
| Docker | прежние полномочия | NNP, pids limits; Nginx RO/cap restrictions |
| SSH / Xray | действующие | побайтно сохранены |
| Повторный запуск | риск переписывания defaults | импорт сохраняет все настройки |

Обычный импорт/переустановка сохраняет старые DNS/пути/extra. Перенос профиля на
защищённые пути требует синхронного применения JSON в Remnawave.

## 6. Итоговый default_server

```nginx
server {
    listen unix:/dev/shm/nuvrion-xhttp/nginx.sock ssl proxy_protocol default_server;
    server_name _;
    http2 on;
    ssl_certificate "/etc/letsencrypt/live/DOMAIN/fullchain.pem";
    ssl_certificate_key "/etc/letsencrypt/live/DOMAIN/privkey.pem";
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_tickets off;
    root /var/www/decoy;
    index index.html;
    add_header X-Robots-Tag "noindex, nofollow, noarchive" always;
    location ^~ /api/ { return 404; }
    location ~ /\. { deny all; }
    location / { try_files $uri $uri/ /index.html; }
}
```

Рабочий DOMAIN подставляется установщиком. Сертификат доверенный для DOMAIN;
неправильное имя/IP не становятся валидными SAN. В forensic SNI-тестах проверены
цепочка и SAN настоящего DOMAIN, проверка заведомо неправильного hostname отключена
только в этом тесте. Обычные HTTPS/VPN-тесты проверяют TLS полностью.

## 7. Итоговый XHTTP extra

```json
{
  "noSSEHeader": true,
  "xPaddingBytes": "100-1000",
  "scMaxBufferedPosts": 30,
  "scMaxEachPostBytes": 1000000,
  "scStreamUpServerSecs": "20-80",
  "scMinPostsIntervalMs": 30,
  "noGRPCHeader": false,
  "xmux": {
    "cMaxReuseTimes": 0,
    "maxConcurrency": "16-32",
    "maxConnections": 0,
    "hKeepAlivePeriod": 0,
    "hMaxRequestTimes": "600-900",
    "hMaxReusableSecs": "1800-3000"
  },
  "xPaddingObfsMode": true,
  "xPaddingPlacement": "cookie",
  "xPaddingKey": "site_session",
  "xPaddingMethod": "tokenish"
}
```

`mode: auto` и path остаются в `xhttpSettings`, параметры выше — внутри `extra`.
В точном [конвертере Xray 26.7.28](https://github.com/XTLS/Xray-core/blob/v26.7.28/infra/conf/transport_method.go)
подтверждена поддержка extra. Поведение cookie/tokenish сверено с
[xpadding.go](https://github.com/XTLS/Xray-core/blob/v26.7.28/transport/internet/splithttp/xpadding.go)
и проверено GET/POST/OPTIONS. Версии, отличные от проверенной, не обновляются
автоматически и не получают непроверенные новые padding settings.
Значение `noGRPCHeader: false` сохранено из рабочего шаблона пользователя.

## 8. DNS

```json
{
  "servers": [
    {"address":"https+local://dns.adguard-dns.com/dns-query","timeoutMs":2500,"queryStrategy":"UseIPv4"},
    {"address":"https+local://dns.comss.one/dns-query","timeoutMs":2000,"queryStrategy":"UseIPv4"}
  ],
  "serveStale":true,"disableCache":false,"queryStrategy":"UseIPv4",
  "disableFallback":false,"serveExpiredTTL":600,"enableParallelQuery":false
}
```

NextDNS отсутствует в новом default. Системный DNS Ubuntu не менялся.
Обычный импорт сохраняет пользовательский DNS. Проверены реальные DoH A-ответы
обоих провайдеров и HTTPS через VPN при отказе первого DoH.

## 9. Сокеты и автосоздание

Общий bind `/dev/shm:/dev/shm:rw` сохранён для ноды и Nginx. Новый каталог
`/dev/shm/nuvrion-xhttp` — root:GID workers `2710`, setgid задаёт группе новых
сокетов правильный GID. Здесь GID 33; существующий worker GID определяется.
XHTTP `0660`, Nginx `0600`, другие UID не проходят в каталог даже до chmod сокета.
Tmpfiles создаёт каталог при загрузке. `/dev/shm` не chmod-ится.
Проверены inode внутри обоих контейнеров, UID/GID/mode и отказ UID 65534.
Для неподдерживаемого UID/чужого каталога установка останавливается.

## 10. Docker

Remnanode: прежний image ID, host network, environment, volumes, caps, restart,
logging сохранены; NNP и pids 1024. Writable runtime/s6 capabilities сохранены.
Nginx: тот же image ID, NNP, pids 512, read-only rootfs, tmpfs pid/cache,
cap_drop ALL + CHOWN/DAC_OVERRIDE/SETUID/SETGID. Privileged и Docker socket отсутствуют.
AppArmor docker-default и Seccomp 2 активны. Реальный s6/Node API проверен в
отдельном контейнере без сети. Чужие caps/tmpfs/start command не заменяются молча.
Во время повторной установки container IDs/StartedAt не изменились.

## 11. Firewall

В nft изменения собственных marked rules — одна проверенная kernel transaction.
API guard приоритет -250: panel IPv4 allow, затем общий drop TCP/2222, включая IPv6.
Узкие исключения не обходят Traffic Control/privacy. В iptables/ip6tables
используется restore --noflush с предварительной проверкой, в UFW — staging deny.
Reset/flush, изменение SSH правил и отключение IPv6 отсутствуют.
Реальные namespace tests подтвердили разрешение API панели, deny чужого IPv4/IPv6,
сохранение foreign tables, отсутствие дублей и сохранение правил при ошибке batch.
На ноде API соединён с панелью, TC/Two-Way Ping/Fail2ban активны.
111/646 не имеют local listener; необычный внешний TCP результат не использован
как повод менять firewall. Источник промежуточного TCP поведения не установлен.

## 12. Тестовый пользователь и панель

`NUVRION_CODEX_TEST`: срок 1 час, лимит 100 MiB, Squad только двух inbound тестовой
ноды. После каждого теста пользователь/Squad удалены через API. Другие пользователи,
Host, контейнеры панели и оба бота сверяются с baseline; секреты в отчёт не включены.
Тестовый Config Profile обновлён штатным API с сохранением keys/SNI/users/tags/routing.
Проверены реальные **hidden connection keys**, созданные генератором панели:
оба Host Firefox, extra полностью совпадает с серверным. Эти ссылки разобраны
в клиентский JSON и использованы для подключения существующим Xray.
Публичный xray-json endpoint вернул 403; Host скрыты. Глобальные subscription rules
не изменялись, этот канал выдачи отдельно не подтверждён.
Штатный внутренний runtime endpoint прочитан без записи или вывода секретов:
streamSettings, пути сокетов, DNS, outbounds и порядок пользовательских routing
rules совпадают с generated profile. Remnawave добавляет служебный API inbound/rule
и flow `xtls-rprx-vision`/пустой flow; эти штатные дополнения проверены отдельно.

## 13–16. Reality, XHTTP, TLS, DNS и routing

На действующей ноде оба транспорта получили PokéHabitat 200, Game API 200,
внешний HTTPS/DNS 200, большой JS asset и upload. Три переподключения на транспорт.
XHTTP path без клиента — 400, совпадает с прямым backend; 502/504 не обнаружены.
TLS 1.2, TLS 1.3, h2, correct/wrong/no SNI, IP Host и SNI/Host spoof API guards прошли.
`trustedXForwardedFor` сверена с core, backend получил исходный IP в изолированном
access log. Nginx использует proxy_pass, не grpc_pass.

Проверка private IP через DNS сначала выявила timeout даже без routing rules.
Причина установлена в [Freedom 26.7.28](https://github.com/XTLS/Xray-core/blob/v26.7.28/proxy/freedom/freedom.go):
для VLESS есть final private-IP block после разрешения имени. Контроль в **отдельном
контейнере** с временным allow только loopback-IP/порт probe вернул 200; без него
private endpoint не достигнут. Routing AsIs сохранён. На другие версии результат
не распространяется; пользовательские finalRules allow могут отключить защиту.

## 17. Производительность

Короткий тест уже настроенной ноды: 12×723096 байт на транспорт (8677152 байта),
Reality 0.474 с, XHTTP 0.879 с; upload по 1048576 байт вернул 200 для обоих.
Прямой JS asset: 0.04693 с. После нагрузки Docker CPU 1.75%, memory 156 MiB/3.823 GiB;
общий host TCP retransmit delta 37 не приписывается только VPN.
После reboot повторный тест: те же 8677152 байта на транспорт, Reality 1.230 с,
XHTTP 0.894 с; оба upload по 1 MiB — HTTP 200. CPU 1.77%, memory 239.4 MiB;
host TCP retransmit delta 39. Это отдельный короткий функциональный запуск.
Клиент выполнялся на самой тестовой ноде: это функциональная локальная нагрузка,
не WAN line-rate и не доказательство сохранения 1160/904 Mbps.
BBR/fq/TFO/RPS, MTU и системный DNS ради результата не менялись.

## 18–20. Установка, идемпотентность и rollback

215 unit/shell tests, Bash syntax и ShellCheck прошли. Отдельно запущены реальные
Docker/Compose/TLS/Xray tests без pulls, изменения бинарника или mounts действующей
ноды. Есть реальные firewall fault injection и Nginx invalid-config/restore/reload.
Два обнаруженных реальных installer failure автоматически откатились с exit 8:
backup `20261008-061433` (SIGPIPE) и `20261008-061527` (Compose interpolation).
После исправления установка `20261008-062100` подготовила инфраструктуру и WAIT;
после API применения профиля диагностика дала RUNNING. Повторный запуск
`20261008-062505` сохранил Docker IDs/StartedAt, profile, certificate, SSH и Compose.
После reboot повторная установка `20261008-063713` также прошла без пересоздания
контейнеров. Reboot проверен на самой тестовой ноде: tmpfiles восстановил каталог,
socket modes/GID, ZRAM, RPS, firewall и оба VPN-транспорта подтвердились снова.
Итоговый standalone Bash и установленная копия имеют SHA-256
`b28d8c8e09cdd021961f405885a3397da25e6a70689043117cb5d4949b3e752e`.
Воспроизводимая сборка Linux даёт тот же файл, что сборка Windows.
Установленный manager совпадает с embedded source. Финальный scan 337 repo files
и 119 embedded files не обнаружил реальные credentials. Временный checkout,
clients и isolated containers удалены; после очистки decoy остался HTTP 200.
Частичный каталог неудачного теста удалён только после подтверждения отсутствия
listener/посторонних файлов; такой cleanup добавлен для новой транзакции rollback.
Обратный перенос профиля в панели при manual rollback выполняется отдельно.

## 21–22. Неустранённые вопросы и границы проверки

- HAPP/INCY UI/import и публичная подписка — NOT RUN/BLOCKED; не заменены core-тестом.
- Установка Remnanode на чистую ОС — NOT RUN: новый запрет замены/установки Xray
  имеет приоритет над прежним меню выбора latest. Fresh-server installer без ноды
  завершится exit 3 до изменения системы. Изолированные fresh templates проверены.
- ARM64, UFW data-plane и другие image/core versions требуют отдельных окружений.
- Нет длительного WAN load test, tcpdump атрибуции 111/646, сравнимого speed baseline.
- Padding улучшает вид HTTP, но не гарантирует нераспознаваемость DPI. Сохранённые
  XHTTP CORS/неполный-request 400 и noGRPCHeader:false могут оставаться признаками.
- Package/kernel upgrades не откатываются копированием configs. На этом запуске
  повторный security hardening выполнялся с --no-updates/--no-tuning, рабочие ранее
  установленные компоненты сохранены; повторное APT/kernel обновление не заявляется.

## 23–24. Применение и восстановление

Смотрите [инструкцию](NUVRION-DEPLOYMENT-GUIDE.md). Production сначала требует
своего backup, согласованного окна, проверки точных image IDs и профиля. `--restore`
возвращает infrastructure только по записи владения и не затрагивает SSH.
Для test baseline до миграции сохранены root-only копии в
`/root/nuvrion-security-test-20261008`; полные installer backup —
`/root/nuvrion-xhttp-backups/20261008-062100` и последующие.

## 25. Готовность

Два транспорта, decoy, DNS, ограничения Docker/сокетов и повторная установка
подтверждены на тестовой ноде. Заявляется готовность проверенной серверной схемы
для дальнейшего review, с перечисленными ограничениями; не безусловный production
или HAPP/INCY acceptance. Финальные статусы, reboot и контрольные суммы —
[в матрице](NUVRION-TEST-RESULTS.md).
