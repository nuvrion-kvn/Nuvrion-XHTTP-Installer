# Nuvrion: результаты тестирования 08.10.2026

## Исправление первой установки в том же 1.0.0

Восстановлена первая установка Remnanode: latest/доступная стабильная версия,
проверка чистого сервера и скрытый/root-only SECRET_KEY. Существующий образ
ноды/Xray сохраняется; stopped/неоднозначные ноды и занятые порты не считаются
чистым сервером. Fresh Compose создаётся эксклюзивно, API guard применяется до старта.

- PASS: настоящая первая установка **latest** и **3.4.2** вызовом `prepare_node`
  в отдельных Docker fixtures: API 2222, image ID, NNP, credentials 0600.
- PASS: исходный fresh template использует host network/shared shm. В самом тесте
  только имена, network и writable mounts заменяются на приватные fixture ресурсы.
- PASS: ID/image/StartedAt и Xray hash действующей ноды сохранились.
- PASS: изолированная транспортная проверка Reality/XHTTP, PokéHabitat, Game API,
  HTTP/2, TLS, cookie padding, real IP, DNS fallback и восстановление Nginx.
- PASS: 60 unit/shell tests на Linux, Bash syntax, ShellCheck 0.11.0 и
  воспроизводимая сборка Windows/Linux (119 embedded files).
- PASS: полный повторный запуск исправленного installer на действующей тестовой
  ноде: **RUNNING**, 0 ошибок/ожиданий, сайт HTTP 200, XHTTP backend HTTP 400,
  certbot staging renewal, ZRAM/RPS и firewall. Backups `20261008-074318`
  и финального файла релиза `20261008-075212`.
- PASS: повторный запуск сохранил оба container ID/StartedAt, image/Xray hash,
  SSH, профиль, сертификат и исходный Compose; пересоздания контейнеров не было.
- PASS: рабочая нода после исправления: оба настоящих Xray-клиента получили
  сайт/Game API/remote DNS HTTP 200, по 3 reconnect, 8 677 152 bytes download
  и 1 MiB upload на транспорт. Временные пользователь, Squad и client configs удалены.
- Существующий XHTTP Host оказался видимым (`isHidden=false`), Reality — скрытым.
  Старый тест, читавший только hiddenKeys, остановился; адаптирован developer
  harness для enabledKeys + hiddenKeys, затем оба транспорта прошли. Видимость
  Host не менялась тестом/installer. Старый panel baseline отличается только этим
  флагом; контейнеры ботов/панели, пользователи и остальные Host fields совпадают.
- NOT RUN: полная установка на новой ОС с первоначальной установкой Docker/APT
  и новым выпуском ACME certificate; проверка старта ноды не равна такому испытанию.

Текущий Bash SHA-256: `16ced4c52dee93d803e1d70b182dd288e3eae3820254fb1b062186af5c620952`.
Текущий embedded manager: `8f7029ea248a444ff4ef1200f133a698066916bb65aa867e355d02391eb7be16`.
Версия и release URL остаются **1.0.0** по явному запросу автора. Матрица ниже
описывает предыдущее серверное испытание; её исторические SHA/backup сохранены.

## Предыдущее полное серверное испытание

Проверена security-ревизия автономного `nuvrion-xhttp-install.sh` на разрешённом
тестовом сервере **45.198.0.253**, `test.nodescheburnet.beer`. Итоговое состояние
**RUNNING**, ошибок диагностики **0**, ожиданий Remnawave profile **0**.
Production deployment, commit и push не выполнялись.

Этот отчёт фиксирует серверные испытания до публикации отдельного репозитория.
215 тестов относятся к общему исходному проекту Vision + XHTTP; здесь сохранён
самостоятельный XHTTP-набор из 54 тестов. Старые environment-specific SSH runners
не включены в дистрибутив. Публикация 1.0.0 не меняет состояние тестового сервера.

Первый GitHub CI запуск подтвердил все 54 теста без skips и идентичную сборку,
но ShellCheck 0.9 из Ubuntu выдал SC2015/SC2317 на допустимых fallback/indirect
ветках. CI закреплён на той же проверенной версии ShellCheck 0.11.0, что и
локальная проверка, с SHA-256 официального Linux release archive. Bash-файл
остался побайтно неизменным; правила ShellCheck не отключались.

`PASS` означает выполненный тест с указанным доказательством. `NOT RUN` означает,
что тест не проводился; `BLOCKED` — обнаруженное ограничение среды/доступа.
Исправленные отказы перечислены отдельно, их первоначальный результат не скрыт.

## Окружение и контрольные суммы

| Компонент | Проверенное значение |
|---|---|
| ОС / kernel | Ubuntu 24.04.5 LTS / 6.8.0-146 |
| Docker / Compose | 29.1.3 / 2.40.3 |
| Remnanode / Xray | 3.4.2 / 26.7.28 |
| Nginx | 1.30, существующий Docker image |
| Node image ID | `sha256:1f97485b4bc7e4944f1ae95cc57d176376813b0022e9567b705f384f1a2e909d` |
| Nginx image ID | `sha256:9bf97bd7714f5e24c1ccd545ecb9eb5435cb6d109c97cebb15e7e455e0239edb` |
| Standalone Bash SHA-256 | `b28d8c8e09cdd021961f405885a3397da25e6a70689043117cb5d4949b3e752e` |
| Установленный manager SHA-256 | `fe8c1b2273df477731ec31de03c07bc1191424cab04b956e445938170e1f6bb9` — совпадает с manager внутри Bash archive |
| Исходный Vision Bash SHA-256 | `0daa9b3887ff9d9157a7348b7025980028f153cd6fc0743d005059d455eca123` — без изменений |
| Установленный Xray binary SHA-256 | `64d46afb80adea1bf97a0d467e83f4a9ac1ebd0995891e84bca3f1a1d1affb1d` — без изменений |
| Исходный Compose SHA-256 | `a30dbe5a1ff6221f764c642d107fe54744322a25779aa97260dde094aac53674` — без изменений |
| TLS expiry | 2027-01-05 14:11:42 UTC; существующий сертификат сохранён |
| Последний backup | `/root/nuvrion-xhttp-backups/20261008-063713/` |

Приватные baseline-файлы сохранены только на ноде в
`/root/nuvrion-security-test-20261008/` с доступом root. Реальные credentials,
private keys, UUID временного пользователя и подписки в отчёт не включены.

## Обязательная матрица ТЗ

| Проверка | Статус | Доказательство / границы |
|---|---|---|
| Корректный SNI | PASS | HTTPS 200, проверенный сертификат DOMAIN, HTML PokéHabitat; isolated и live self-check |
| Неправильный SNI | PASS | Handshake завершён, предъявлен существующий сертификат, сайт 200; сертификат проверен относительно DOMAIN, не чужого имени |
| Без SNI | PASS | Сертификат и сайт 200 через Reality fallback; неизвестному SNI внутренние маршруты недоступны |
| TLS 1.2 | PASS | Фактический handshake и HTTP 200 |
| TLS 1.3 | PASS | Фактический handshake и HTTP 200 |
| HTTP/2 | PASS | Curl ответ `200 2`, включая цепочку Reality → Nginx |
| REALITY | PASS | Реальная временная учётная запись; сайт, Game API, внешний HTTPS/DNS, download/upload, 3 переподключения; повтор после reboot |
| XHTTP | PASS | Те же авторизованные испытания через TLS/XHTTP; повтор после reboot |
| XHTTP Padding | PASS | GET/POST/OPTIONS и h2: `Set-Cookie: site_session=`, отсутствие `X-Padding`; полноценная XHTTP-сессия работает |
| XHTTP extra | PASS | Generated JSON → панель → runtime → panel-generated hidden connection keys → настоящий Xray client; все поля extra сохранены |
| DNS | PASS | AdGuard первым, COMSS вторым; реальные DoH A-ответы и VPN DNS; fault injection отказа первого DoH → внешний HTTPS 200 через COMSS |
| NextDNS | PASS | Отсутствует в новом стандартном JSON; unit test генератора. Существующий импорт без явной миграции сохраняет пользовательский DNS |
| Unix-сокеты | PASS | Nginx 0600, XHTTP 0660, каталог 2710 root:GID 33; одинаковый inode host/оба контейнера, UID 65534 отказан; права сохранены после reboot |
| nginx → XHTTP | PASS | HTTP proxy_pass к Unix socket, неполный запрос 400 совпадает с прямым backend, авторизованные сессии работают |
| REALITY → nginx | PASS | Сайт 200 через :443 и local target, PROXY protocol сохранён, XHTTP real IP подтверждён isolated access log |
| Docker | PASS | Реальные NNP=1/Seccomp=2/AppArmor; s6/Node API работают; Nginx read-only/tmpfs/caps; существующие image IDs сохранены |
| Firewall | PASS | Реальная nft namespace проверка IPv4/IPv6, атомарность/fault injection, iptables/ip6tables --noflush; live API connected, foreign tables сохранены |
| Traffic Control | PASS | `ntc check`, filtering/update timers, три списка и owned nft table; SSH/panel исключения; тест не выдаётся за проверку всех RDAP/menu веток |
| Two-Way Ping | PASS | Active/enabled service и privacy rules; installer firewall не добавляет обход этой таблицы |
| Test user | PASS | Временно созданы пользователь 1 час/100 MiB и Squad только двух inbound тестовой ноды; реальные подключения; оба удалены после каждого запуска |
| Чистая установка на ОС без Remnanode | NOT RUN | Последнее ТЗ запрещает установку/замену Xray. Установщик требует существующую ноду; отдельные fresh templates реально подняты в изолированных контейнерах |
| Повторная установка | PASS | Два реальных повторных запуска; сравнение IDs/StartedAt, JSON, cert, SSH, Xray и оригинального Compose до/после без изменений |
| Откат | PASS | Два настоящих installer failure → автоматический rollback exit 8; отдельный invalid Nginx config → no reload → restore/test/reload → сайт 200 |
| SSH | PASS | Все файлы `/etc/ssh` и `/root/.ssh` совпадают по hash с baseline, повторный доступ после reboot; rollback старых SSH paths запрещён и покрыт тестом |
| Xray binary | PASS | Hash совпадает до/после migration, isolated tests, reinstall и reboot; ни установки, ни update binary не выполнялось |

## Дополнительные серверные проверки

| Проверка | Статус | Результат |
|---|---|---|
| Node API 2222 | PASS | Listener rw-node и `isConnected=true` в Remnawave |
| Внешний вход 443 | PASS | Listener rw-core, отдельного Nginx TCP/443 нет |
| Nginx -t/-T | PASS | Конфигурация валидна; загружен нужный location и Unix HTTP upstream |
| XHTTP 502/504/socket errors | PASS | Не обнаружены в актуальных проверках; отсутствие backend не считается успехом |
| SNI/Host API spoof | PASS | Unknown/no SNI и несовпадающий Host возвращают 404 для XHTTP, Game API и `/api/nodes` |
| Сертификат и renewal | PASS | SAN/expiry валидны; Certbot timer enabled/active; настоящий staging renew --dry-run прошёл при reinstall |
| Порт 80 после ACME | PASS | Нет постоянного listener/временного ACME lease; существующие чужие правила не удаляются |
| ZRAM | PASS | Active swap `/dev/zram0`, около 978 MiB, zstd, priority 100; enabled autostart и успешная проверка после reboot |
| RPS/RFS | PASS | RX masks, RFS 32768 и автозапуск подтверждены после reboot |
| BBR/fq/TFO | PASS | Существующие BBR/fq/TFO=3 сохранены; sysctl baseline совпадает |
| Kernel hardening/F2B/security updates | PASS | Hardening active; SSH jail и unattended security automation active/enabled; SSH config только читается |
| Перезагрузка | PASS | Выполнена только на тестовой ноде; tmpfiles/socket group/modes, сеть, ZRAM, контейнеры и VPN повторно проверены |
| Runtime integrity | PASS | Прочитан штатный internal endpoint: streamSettings/socket/DNS/outbounds/routing совпадают. Только служебный API rule и transport flow дополнены Remnawave |
| Сохранность панели | PASS | Container IDs/StartedAt, пользователи и Host совпадают с baseline; оба бота сохранены, база не мигрировалась |
| Полная публичная xray-json подписка | BLOCKED | Endpoint вернул 403; тестовые Host скрыты. Global subscription rules и видимость Host не ослаблялись |
| HAPP / INCY import/UI | NOT RUN | Приложения и авторизованный канал импорта не доступны; Xray core test не заменяет этот результат |
| Private IP через DNS | PASS | В isolated Xray 26.7.28 AsIs запрос не достиг private probe; контроль с временным allow только loopback IP/port вернул 200, исключение удалено |
| Производительность локальной цепочки | PASS | Ограниченный download/upload и параллельные запросы; метрики ниже |
| WAN throughput / 1160–904 Mbps baseline | NOT RUN | Клиент выполнялся на ноде; сопоставимого внешнего стенда до/после нет |
| Источник внешнего поведения 111/646 | NOT RUN | Local listener отсутствует. Connect-only из внешней среды давал неоднозначный результат; tcpdump атрибуция не проведена, firewall вслепую не менялся |
| UFW data plane / ARM64 / другие версии | NOT RUN | Фактическая среда nftables/x86_64/Xray 26.7.28; эти варианты требуют отдельного стенда |

Private-IP проверка подтверждена именно на текущем core: его Freedom имеет final
private-IP guard для VLESS даже при AsIs. Контроль без этого guard сделан только
в отдельном контейнере. Routing production и пользовательские rules не менялись.
Произвольные пользовательские `finalRules allow` могут изменить этот результат.

## 13 сценариев установщика

| Сценарий | Статус | Выполненная проверка |
|---|---|---|
| 1. Чистая ОС без ноды | NOT RUN | Запрет установки Xray; не заявляется полноценная fresh-server acceptance |
| 2. Повторная установка | PASS | Реальные backups `20261008-062505` и `20261008-063713`, baseline без изменений |
| 3. Обновление существующей установки | PASS | Security migration существующей ноды, прежние image IDs и ключи сохранены |
| 4. Восстановление частичного отказа | PASS | SIGPIPE/Compose rollback и повторная успешная установка; cleanup только собственного каталога без listener |
| 5. Существующие Unix-сокеты | PASS | Работающие legacy sockets мигрированы явно, повторный запуск protected sockets без дубликатов |
| 6. Существующие Docker-контейнеры | PASS | Сохранены окружение/volumes/caps/restart/logging; повторная установка не пересоздаёт контейнеры |
| 7. Существующие nftables-таблицы | PASS | Seed foreign DROP/TC/privacy в private network namespace; остались, TC не обходится |
| 8. Существующий сертификат | PASS | Повторное использование без смены cert hash, staging renewal с hooks |
| 9. Отсутствие сертификата | NOT RUN | В этой ревизии новый production certificate не выпускался; существующий валиден |
| 10. Невалидная конфигурация | PASS | Реальное Nginx -t отказал, running site сохранился; конфликтующие command/caps/tmpfs также отвергаются unit tests |
| 11. Резервное копирование | PASS | Timestamped files/manifest; реальные rollback используют сохранённый Compose/Nginx/firewall/services |
| 12. Корректный откат | PASS | Настоящие ошибки откатились exit 8, сервис восстановлен; отдельный Nginx restore проверен |
| 13. Сохранность конфигураций | PASS | Hash baseline SSH/Xray/cert/original Compose; panel keys/SNI/clients/routing сохранены; ordinary import сохраняет DNS/custom extra |

Полное удаление и повторная установка текущей security-ревизии на чистой ОС —
`NOT RUN`. Чтобы не нарушить новое ограничение, установленная нода, сертификаты,
ключи и рабочая база PokéHabitat не стирались. Uninstall ownership/SSH safety,
backup handling, cleanup и restore-to-removed-state проверены автоматическими
тестами; это отдельно от полномасштабного live удаления.
Полный APT/kernel upgrade при security migration не повторялся: использованы
`--no-updates --no-tuning`, ранее установленные компоненты проверены и сохранены.
Safe package maintenance/cleanup покрыты shell fixtures, не выдаются за live upgrade.

## Найденные ошибки и исправления

1. **FAIL → исправлено:** SIGPIPE 141 из `version | head` при pipefail.
   Настоящий rollback exit 8, backup `20261008-061433`; чтение заменено на
   потребление полного вывода. Повторный installer запуск успешен.
2. **FAIL → исправлено:** Compose подставлял `$p` в стартовой команде Nginx.
   Настоящий rollback exit 8, backup `20261008-061527`; добавлено `$$` escaping
   и normalization для idempotence. Real Compose create/inspect подтверждает `$p`
   внутри контейнера; Nginx стартует и повторная установка его не пересоздаёт.
3. **FAIL → исправлено:** binary padding в Docker logs вызывал NUL warning Bash.
   NUL фильтруется до command substitution; regression подтверждает сохранение
   обнаружения `invalid config`, финальная live диагностика без предупреждения.
4. **Первый private-DNS probe был неоднозначным:** timeout сам по себе не доказывал
   защиту. Добавлен положительный control с узким временным finalRules allow в
   isolated контейнере: 200. Повтор без исключения не достиг probe; причина guard
   установлена по точному source Xray 26.7.28. Исключения на ноде не применялись.
5. **Прямое равенство runtime/source не прошло:** Remnawave штатно добавляет flow
   и API routing rule. Дополнения проверены, все пользовательские rules сохранились
   в исходном порядке; socket/extra/DNS полностью совпадают.

Успешная migration backup: `20261008-062100`. До применения JSON состояние WAIT;
после штатного API применения профиля — RUNNING. Финальная проверка также RUNNING.

## Производительность: ограниченный функциональный тест

| Замер | До test reboot | После test reboot |
|---|---|---|
| Download на каждый транспорт | 12 × 723096 = 8677152 байта | тот же объём |
| Reality, время этого download | 0.474 с | 1.230 с |
| XHTTP, время этого download | 0.879 с | 0.894 с |
| Upload, каждый транспорт | 1048576 байт, HTTP 200 | 1048576 байт, HTTP 200 |
| Docker CPU после нагрузки | 1.75% | 1.77% |
| Docker memory | 156 MiB / 3.823 GiB | 239.4 MiB |
| Host TCP retransmit delta | 37 | 39 |

Это короткие локальные измерения, без заявления line-rate WAN скорости или
достоверного сравнения эффективности тюнинга. Host retransmits включают весь
трафик сервера. MTU/BBR/системный DNS ради результата не менялись.

## Набор проверок и воспроизведение

Linux regression suite: **215 тестов, PASS**, 6.558 с. Bash syntax и
ShellCheck 0.11.0 — PASS. Воспроизводимая сборка Linux/Windows — byte-identical
SHA-256 из таблицы. `git diff --check` — PASS; commit/push отсутствуют.
Проверка реальных credentials в исходниках и embedded archive — PASS:
337 репозиторных файлов и 119 embedded файлов, совпадений нет.
ShellCheck выполнен локально; readonly self-check на ноде сообщает NOT RUN для
ShellCheck, поскольку пакет там не установлен. Это не заменяет локальный результат.

Команды разработчика из корня репозитория:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
bash -n nuvrion-xhttp-install.sh
shellcheck -S style nuvrion-xhttp-install.sh
python3 tools/build_xhttp.py
sha256sum -c SHA256SUMS
git diff --check
```

Реальные isolated проверки на авторизованном Linux стенде с уже установленными
image IDs, сертификатом и game API (никаких image pulls):

```bash
sudo unshare --net python3 tests/xhttp_firewall_integration.py
sudo python3 tests/xhttp_security_integration.py \
  --domain test.nodescheburnet.beer \
  --node-container remnanode \
  --nginx-container remnanode-nuvrion-xhttp-nginx-1
sudo bash /root/nuvrion-xhttp-install.sh --self-check
```

Firewall test откажет в host network namespace. Security test создаёт собственные
временные контейнеры/credentials, проверяет старые IDs/StartedAt и binary hash при
завершении, удаляет только свои ресурсы. Environment-specific developer runner
исходного проекта использовал заранее проверенный SSH host key и credentials
через stdin. Его live checks сравнили panel-generated clients, runtime profile
и baseline. Этот runner не включён в отдельный репозиторий: в нём нет доступа
к реальным серверам или credentials.

Временные клиентские конфиги, isolated containers и checkout
`/tmp/nuvrion-xhttp-regression` удалены; после очистки socket modes сохранились,
сайт снова HTTP 200. Остались только рабочие Remnanode/Nginx containers.
Секреты и временные clients не включены в артефакты. Рабочая нода, её сертификаты,
backup и установщик сохранены. См. [технический отчёт](NUVRION-SECURITY-IMPLEMENTATION-REPORT.md),
[инструкцию](NUVRION-DEPLOYMENT-GUIDE.md) и [функциональный diff](NUVRION-SECURITY-CHANGES.diff).
