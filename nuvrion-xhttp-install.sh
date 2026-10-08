#!/usr/bin/env bash
# Nuvrion XHTTP Installer · v1.0.0
# Автор и разработчик: Nuvrion · GitHub: nuvrion-kvn
# SPDX-License-Identifier: MIT
# Nuvrion: REALITY TCP selfsteal target through local Nginx Unix socket.
# XHTTP: legiz-ru/my-remnawave @ 2af84604 (README, lines 176-313)
# The installed management copy and every template are embedded in this file.
set -Eeuo pipefail
umask 077
export LC_ALL=C.UTF-8
readonly INSTALLER_VERSION=1.0.0
readonly BASE=/opt/remnanode
readonly OWN=$BASE/nuvrion-xhttp
readonly STATE=$OWN/state.json
readonly OVERRIDE=$BASE/docker-compose.nuvrion-xhttp.json
readonly BACKUPS=/root/nuvrion-xhttp-backups
readonly PROFILE=/root/nuvrion-xhttp-profile.json
readonly HOSTS=/root/nuvrion-xhttp-host-settings.txt
readonly EXTRA=/root/nuvrion-xhttp-extra.json
readonly LOG=/var/log/nuvrion-xhttp-installer.log
ACTION=menu DOMAIN='' PANEL_IP='' EMAIL='' NODE_TAG='' XHTTP_PATH=/api/v3/sync/
NODE_PORT=2222 NODE_PORT_EXPLICIT=0 DETECTED_NODE_PORT=''
NODE_CONTAINER='' PROFILE_INPUT='' YES=0 NO_TUNING=0
NO_UPDATES=0 APT_POLICY_ACTIVE=0 APT_POLICY_ORIGINAL=0 APT_PREFERENCES=''
ZRAM_STATUS='NOT CONFIGURED' REBOOT_NEEDED=0
ADMIN_IP='' SSH_PORT='' SSH_KEY_ONLY=0 SSH_KEY_CONFIRMED=0
NO_TRAFFIC=0 NO_PRIVACY=0
SECURE_SOCKETS=0 NGINX_SOCKET=/dev/shm/nginx.sock XHTTP_SOCKET=/dev/shm/xrxh.socket
HARDEN_PROFILE=0
SOCKET_DIR_CREATED=0
NODE_VERSION='' SELECTED_IMAGE='' SECRET_FILE='' NODE_SECRET='' NODE_NEW=0 PATH_EXPLICIT=0
NODE_STOPPED=0 NODE_IMAGE_ID_DETECTED='' NODE_PROBE_USER=''
BACKUP_INPUT='' ERROR_CODE=0 SERVICES_APPLIED=0
PUBLIC_ASSETS_REPLACE=0
FW='' NODE_SERVICE='' PROJECT='' WORKDIR='' XRAY_BIN='' XRAY_VERSION='unknown'
NGINX_KIND='' NGINX_CONTAINER='' NGINX_SERVICE='' NGINX_CONFIG='' NGINX_MAIN=''
NGINX_ROOT='' SITE_ROOT='' WEB_GID=33 IPV4='' A_RECORDS='' BACKUP=''
NGINX_NEW=0 NODE_RECREATE=0 NGINX_RECREATE=0 TRANSACTION=0 LOG_ENABLED=0
STATUS='NOT INSTALLED' DECOY_CODE='000' ROUTE_CODE='000' FAILS=0 WAITS=0 REBOOT_WAITS=0
CERT_LINEAGE='' PUBLIC_KEY='' WORK='' RESTORING=0
ACME_PRE_ACTIVE=0
declare -a COMPOSE_FILES=() COMPOSE_CMD=() INSTALL_PACKAGES=()

ui_colors() {
    C_RESET='' C_BOLD='' C_GREEN='' C_RED='' C_YELLOW='' C_CYAN=''
    if [[ -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb && -t 1 ]];then
        C_RESET=$'\033[0m';C_BOLD=$'\033[1m';C_GREEN=$'\033[32m'
        C_RED=$'\033[31m';C_YELLOW=$'\033[33m';C_CYAN=$'\033[36m'
    fi
}
ui_width() {
    local width=${COLUMNS:-}
    if [[ -z $width && -t 1 && ${TERM:-dumb} != dumb ]] && command -v tput >/dev/null;then
        width=$(tput cols 2>/dev/null || true)
    fi
    [[ $width =~ ^[0-9]{1,3}$ ]] || width=80
    width=$((10#$width));(( width>=24 )) || width=24;(( width<=80 )) || width=80
    printf '%s' "$width"
}
ui_wrap() {
    local message=$1 prefix=${2:-} color=${3:-} reset=${4:-} ending=${5:-line} width part
    width=$(ui_width);width=$((width-2-${#prefix}))
    [[ $ending != prompt ]] || width=$((width-1))
    while (( ${#message}>width ));do
        part=${message:0:width};[[ $part != *' '* ]] || part=${part% *}
        [[ -n $part ]] || part=${message:0:width}
        printf '  %s%s%s%s\n' "$color" "$prefix" "$part" "$reset"
        message=${message:${#part}};message=${message# }
        printf -v prefix '%*s' "${#prefix}" ''
    done
    if [[ $ending == prompt ]];then printf '  %s%s%s%s ' "$color" "$prefix" "$message" "$reset"
    else printf '  %s%s%s%s\n' "$color" "$prefix" "$message" "$reset";fi
}
ui_text() { ui_wrap "$1" "${2:-}" "${3:-}" "$C_RESET"; }
ui_separator() {
    local line width
    width=$(ui_width);printf -v line '%*s' "$width" '';line=${line// /═}
    printf '%s%s%s\n' "$C_CYAN" "$line" "$C_RESET"
}
ui_heading() {
    printf '\n';ui_separator
    ui_text "$1" '' "$C_BOLD$C_CYAN"
    ui_separator
}
ui_message() {
    local badge=$1 color=$2 message=$3 width part
    width=$(ui_width);width=$((width-6))
    while (( ${#message}>width ));do
        part=${message:0:width};[[ $part != *' '* ]] || part=${part% *}
        [[ -n $part ]] || part=${message:0:width}
        printf '  %s%s%s%s %s\n' "$C_BOLD" "$color" "$badge" "$C_RESET" "$part"
        message=${message:${#part}};message=${message# };badge='   '
    done
    printf '  %s%s%s%s %s\n' "$C_BOLD" "$color" "$badge" "$C_RESET" "$message"
}
ui_question() {
    # Questions go to the controlling terminal even when stdout is redirected.
    local color='' reset=''
    if [[ -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]];then
        color=$'\033[1;33m';reset=$'\033[0m'
    fi
    ui_wrap "$*" '[?] ' "$color" "$reset" prompt > /dev/tty
}
ui_colors
log_info() { ui_message '[•]' "$C_CYAN" "$*"; [[ $LOG_ENABLED == 0 ]] || printf '%s INFO %s\n' "$(date -Is)" "$*" >> "$LOG"; }
log_ok() { ui_message '[✓]' "$C_GREEN" "$*"; [[ $LOG_ENABLED == 0 ]] || printf '%s OK %s\n' "$(date -Is)" "$*" >> "$LOG"; }
log_warn() { ui_message '[!]' "$C_YELLOW" "$*"; [[ $LOG_ENABLED == 0 ]] || printf '%s WARN %s\n' "$(date -Is)" "$*" >> "$LOG"; }
log_error() { ui_message '[✗]' "$C_RED" "$*" >&2; [[ $LOG_ENABLED == 0 ]] || printf '%s ERROR %s\n' "$(date -Is)" "$*" >> "$LOG"; }
die() { local rc=$1; shift; log_error "$*"; exit "$rc"; }
ask_yes() {
    local answer
    [[ -r /dev/tty && -w /dev/tty ]] || { log_warn 'Нет интерактивного ввода; действие отменено.';return 1; }
    while true;do
        ui_question "$1 [Д/Н; Enter — Н]:" 2>/dev/null || { log_warn 'Нет управляющего терминала; действие отменено.';return 1; }
        IFS= read -r answer < /dev/tty || { log_warn 'Ввод завершён; действие отменено.';return 1; }
        case "$answer" in
            Д|д|Да|да|ДА|y|Y|yes|YES|Yes) return 0;;
            Н|н|Нет|нет|НЕТ|n|N|no|NO|No|'') return 1;;
            *) log_warn 'Введите Д (да) или Н (нет). Enter означает отказ.';;
        esac
    done
}
prompt() {
    local name=$1 title=$2 default=${3:-} value
    [[ -r /dev/tty && -w /dev/tty ]] || die 1 "Требуется параметр $name для неинтерактивного запуска."
    ui_question "$title [${default:-обязательное значение}]:" 2>/dev/null || die 1 "Нет управляющего терминала; задайте параметр $name."
    IFS= read -r value < /dev/tty || die 1 'Ввод прерван.'
    printf -v "$name" '%s' "${value:-$default}"
}
banner() {
    printf '\n';ui_separator
    ui_text "Nuvrion XHTTP Installer · v$INSTALLER_VERSION" '' "$C_BOLD$C_CYAN"
    ui_text 'Лицензия: MIT'
    ui_text 'Создатель: Nuvrion · nuvrion-kvn'
    ui_text 'https://github.com/nuvrion-kvn'
    ui_separator
    ui_text 'Reality TCP selfsteal + XHTTP · сайт декой'
    ui_text 'Д = Да · Н = Нет'
    printf '\n'
}
installation_components() {
    ui_text 'Компоненты установки:'
    ui_text 'Remnawave Node: установка при отсутствии; выбор версии.' '  • '
    ui_text 'Xray: REALITY TCP selfsteal и XHTTP через Unix-сокеты.' '  • '
    ui_text 'Nginx: HTTPS/HTTP2, локальный сайт декой и проксирование XHTTP.' '  • '
    ui_text "Let's Encrypt: сертификат и автоматическое продление." '  • '
    ui_text 'Брандмауэр: публичный 443; API ноды только для IP панели.' '  • '
    if (( NO_TUNING==0 ));then ui_text 'Оптимизация сервера: BBR, sysctl, ZRAM, RPS/RFS и лимиты.' '  • ';fi
    if (( NO_TRAFFIC==0 ));then ui_text 'Traffic Control: блок-листы IPv4/IPv6 и список исключений.' '  • ';fi
    if (( NO_PRIVACY==0 ));then ui_text 'Two-Way Ping: защита от входящего ping.' '  • ';fi
    ui_text 'Fail2ban, обновления безопасности, резервное копирование, откат и диагностика.' '  • '
    ui_text 'Готовый профиль ноды с extra и настройки двух Host.' '  • '
    printf '\n'
    ui_text 'Порт панели здесь — порт API ноды для подключения панели, по умолчанию 2222. Это отдельный канал управления.'
    ui_text 'Секретный ключ вводится скрыто и не попадает в журнал.'
    printf '\n'
}
show_menu() {
    ui_text '1. Установить'
    ui_text '2. Переустановить / восстановить'
    ui_text '3. Диагностика XHTTP'
    ui_text '4. Удалить XHTTP-компоненты'
    ui_text '5. Восстановить последнюю резервную копию'
    ui_text '6. Обновление, ZRAM и очистка'
    ui_text '0. Выход'
    printf '\n'
}
validate_node_port() {
    [[ $NODE_PORT =~ ^[0-9]{1,5}$ ]] || die 1 'Порт API ноды должен быть числом от 1 до 65535.'
    NODE_PORT=$((10#$NODE_PORT))
    (( NODE_PORT>=1 && NODE_PORT<=65535 && NODE_PORT!=80 && NODE_PORT!=443 )) || die 1 'Порт API: допустимы 1–65535, кроме 80 и 443.'
}
require_root() { (( EUID == 0 )) || die 1 'Запустите от root.'; }
detect_os() {
    # shellcheck disable=SC1091
    source /etc/os-release
    log_info "ОС: ${PRETTY_NAME:-unknown}; ядро: $(uname -r); время работы: $(uptime -p)"
    [[ $ACTION == diagnose || $ACTION == self-check ]] || { [[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 24.04 ]] || die 2 'Поддерживается Ubuntu 24.04/24.04.x.'; }
    if [[ $ACTION != diagnose && $ACTION != self-check ]]; then
        case $(uname -m) in x86_64|aarch64) :;;
            *) die 2 'Поддерживаются только x86_64 и aarch64; изменения не начаты.';;
        esac
        [[ -d /run/systemd/system ]] || die 2 'Требуется работающий systemd; изменения не начаты.'
    fi
    command -v python3 >/dev/null || die 1 'Требуется системный python3 (входит в Ubuntu 24.04).'
}

# Python is a system dependency. No PyYAML, downloaded templates or repo files
# are required. Compose itself parses YAML; the override is JSON-compatible YAML.
helper() {
    python3 -c "$(cat <<'NUVRION_PY'
import copy, hashlib, ipaddress, json, os, re, shlex, shutil, socket, sys, tarfile, tempfile, urllib.request
from pathlib import Path

BEGIN='# BEGIN NUVRION XHTTP'
END='# END NUVRION XHTTP'
OWN=Path('/opt/remnanode/nuvrion-xhttp')
STATE=OWN/'state.json'
PROFILE=Path('/root/nuvrion-xhttp-profile.json')
EXTRA=Path('/root/nuvrion-xhttp-extra.json')
HOSTS=Path('/root/nuvrion-xhttp-host-settings.txt')
SECURITY_PATHS=[
 '/etc/tmpfiles.d/nuvrion-xhttp.conf',
 '/etc/fail2ban/jail.d/99-nuvrion-sshd.conf',
 '/etc/apt/apt.conf.d/52nuvrion-unattended-upgrades',
 '/etc/sysctl.d/99-zzzzz-nuvrion-xhttp-tfo.conf',
 '/usr/local/bin/nuvrion-traffic-control','/usr/local/bin/ntc',
 '/usr/local/sbin/nuvrion-two-way-ping.sh',
 '/etc/systemd/system/nuvrion-two-way-ping.service',
 *['/etc/systemd/system/nuvrion-traffic-control'+x for x in
   ('.service','-update.service','-update.timer','-rollback.service','-rollback.timer')]]

def read(p): return json.loads(Path(p).read_text(encoding='utf-8'))
def write(p, value, mode=0o600):
    p=Path(p)
    if p.is_symlink(): raise ValueError('Отказ от записи через символическую ссылку: '+str(p))
    p.parent.mkdir(parents=True,exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix='.'+p.name+'.',dir=p.parent)
    try:
        with os.fdopen(fd,'w',encoding='utf-8',newline='\n') as f:
            os.fchmod(f.fileno(),mode)
            f.write(json.dumps(value,ensure_ascii=False,indent=2)+'\n' if not isinstance(value,str) else value)
            f.flush();os.fsync(f.fileno())
        os.replace(tmp,p)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def write_nginx(p,text):
    p=Path(p)
    if p.is_symlink():raise ValueError('Файл Nginx является символической ссылкой')
    # A bind mount of a single file follows its inode. Keep that inode so a
    # tested reload can read the new text without recreating the container.
    with p.open('w',encoding='utf-8',newline='\n') as stream:
        stream.write(text);stream.flush();os.fsync(stream.fileno())

def immutable_path(p):
    # Even restoring an older backup must not undo existing SSH settings.
    return str(p)=='/etc/ssh' or str(p).startswith(('/etc/ssh/','/root/.ssh/'))

def socket_paths(state):
    base='/dev/shm/nuvrion-xhttp' if state.get('secure_sockets') else '/dev/shm'
    return base+'/nginx.sock',base+'/xrxh.socket'

def padding_extra():
    # Verified in Xray v26.7.28 infra/conf/transport_method.go and xpadding.go.
    return {'xPaddingObfsMode':True,'xPaddingPlacement':'cookie',
            'xPaddingKey':'site_session','xPaddingMethod':'tokenish'}

def padding_supported(version):
    # Conservative gate: newer/older binaries need their own compatibility test.
    return bool(re.search(r'\bXray\s+26\.7\.28\b',version))

def atlas_locations(indent='    '):
    # Modules must have a JavaScript MIME type even on older/custom mime.types.
    # Files are deliberately not fingerprinted: revalidate on every visit.
    paths=['= /index.html','= /app.mjs','= /catalog.mjs','= /content.mjs','= /topography.mjs',
           '= /style.css','= /tokens.css','= /beers.json','^~ /assets/','^~ /vendor/','~* \\.(?:mjs|js|css|json|webp|woff2|svg|txt)$']
    directives='types { text/html html; text/javascript js mjs; text/css css; application/json json; image/webp webp; image/svg+xml svg; font/woff2 woff2; text/plain txt; }\n'
    directives+='if ($uri ~ \\/\\.) { return 404; }\n'
    directives+='default_type application/octet-stream;\ntry_files $uri =404;\n'
    directives+='add_header Cache-Control "no-cache" always;\n'
    directives+='add_header X-Content-Type-Options "nosniff" always;\n'
    directives+='add_header X-Robots-Tag "noindex, nofollow, noarchive" always;'
    body='\n'.join(indent+'    '+line for line in directives.splitlines())
    return '\n'.join(indent+'location '+path+' {\n'+body+'\n'+indent+'}' for path in paths)

def default_server(domain,lineage,root,sock):
    return f'''    server {{
        listen unix:{sock} ssl proxy_protocol default_server;
        server_name _;
        http2 on;
        ssl_certificate "{lineage}/fullchain.pem";
        ssl_certificate_key "{lineage}/privkey.pem";
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_session_tickets off;
        root {root};
        index index.html;
        add_header X-Robots-Tag "noindex, nofollow, noarchive" always;
        location ^~ /api/ {{ return 404; }}
{atlas_locations('        ')}
        location ~ /\\. {{ deny all; }}
        location / {{ try_files $uri $uri/ =404; }}
    }}'''

def nginx_template(state,lineage):
    domain=valid_domain(state['domain']);ng,_=socket_paths(state)
    root='/var/www/decoy'
    return f'''# Nuvrion owns this complete file (recorded in state.json).
user www-data;
worker_processes auto;
error_log /dev/stderr warn;
pid /var/run/nginx.pid;
events {{ worker_connections 4096; }}
http {{
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log off;
    server_tokens off;
    server {{
        server_name {domain};
        listen unix:{ng} ssl proxy_protocol;
        http2 on;
        ssl_certificate "{lineage}/fullchain.pem";
        ssl_certificate_key "{lineage}/privkey.pem";
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_session_tickets off;
        root {root};
        index index.html;
        add_header X-Robots-Tag "noindex, nofollow, noarchive" always;
        location / {{ try_files $uri $uri/ =404; }}
        location ~ /\\. {{ deny all; }}
    }}
{default_server(domain,lineage,root,ng)}
}}
'''
def valid_domain(s):
    if len(s)>253 or '.' not in s or not re.fullmatch(r'[a-zA-Z0-9.-]+',s): raise ValueError('Некорректный домен')
    if any(not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?',x) for x in s.split('.')): raise ValueError('Некорректный домен')
    return s.lower()
def validate(domain,panel,email,tag,path,download):
    valid_domain(domain);ipaddress.ip_address(panel);valid_domain(download or domain)
    if not re.fullmatch(r'[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+',email): raise ValueError('Некорректный адрес электронной почты')
    if not tag.strip() or len(tag)>100 or any(ord(x)<32 for x in tag): raise ValueError('Некорректный тег')
    if not re.fullmatch(r'/(?:[A-Za-z0-9_-]+/)+',path): raise ValueError('Путь XHTTP: /segment/; только буквы, цифры, _ и -')
    if path=='/api/' or path.startswith(('/api/game/','/assets/','/vendor/')): raise ValueError('Путь XHTTP конфликтует с файлами Атласа пива или зарезервированным API')

def tokens(text):
    # Nginx-aware scanner: comments, quoted strings and escaped characters do
    # not contribute braces. Offsets refer to the ORIGINAL document.
    result=[];i=0
    while i<len(text):
        if text[i].isspace(): i+=1;continue
        if text[i]=='#':
            i=text.find('\n',i)
            if i<0:break
            continue
        start=i
        if text[i] in '{};':result.append((text[i],i,i+1));i+=1;continue
        value=''
        while i<len(text) and not text[i].isspace() and text[i] not in '{};#':
            if text[i] in "\"'":
                quote=text[i];i+=1
                while i<len(text) and text[i]!=quote:
                    if text[i]=='\\' and i+1<len(text):i+=1
                    value+=text[i];i+=1
                if i==len(text):raise ValueError('Незакрытая строка nginx')
                i+=1
            elif text[i]=='\\' and i+1<len(text):value+=text[i+1];i+=2
            else:value+=text[i];i+=1
        result.append((value,start,i))
    return result
def blocks(text):
    t=tokens(text);stack=[];out=[];begin=0
    for i,(v,a,b) in enumerate(t):
        if v=='{':stack.append((begin,i));begin=i+1
        elif v=='}':
            if not stack:raise ValueError('Лишняя } в nginx')
            first,opening=stack.pop()
            out.append((first,opening,i));begin=i+1
        elif v==';':begin=i+1
    if stack:raise ValueError('Незакрытый блок nginx')
    return t,out
def block_directives(t,opening,end):
    depth=0;directives=[];begin=opening+1
    for i in range(opening+1,end):
        v=t[i][0]
        if v=='{':depth+=1
        elif v=='}':depth-=1;begin=i+1
        elif v==';' and depth==0:
            directives.append(t[begin:i]);begin=i+1
    return directives

def server(text,domain):
    t,bs=blocks(text);found=[]
    for start,opening,end in bs:
        if t[start][0]!='server':continue
        directives=block_directives(t,opening,end)
        names=[x[0] for d in directives if d and d[0][0]=='server_name' for x in d[1:]]
        listen=[' '.join(x[0] for x in d[1:]) for d in directives if d and d[0][0]=='listen']
        if domain in names and any(re.search(r'unix:/dev/shm/(?:nuvrion-xhttp/)?nginx\.sock',x) and 'ssl' in x and 'proxy_protocol' in x for x in listen):
            roots=[d[1][0] for d in directives if d and d[0][0]=='root' and len(d)==2]
            if len(roots)!=1 or '$' in roots[0]:raise ValueError('Требуется один простой root в decoy server')
            found.append((t[start][1],t[end][2],roots[0],directives))
    if len(found)!=1:raise ValueError('Не найден единственный HTTPS server домена на nginx.sock')
    return found[0]
def strip_marked(text):
    if text.count(BEGIN)!=text.count(END) or text.count(BEGIN)>2:raise ValueError('Повреждены маркеры Nuvrion')
    return re.sub(r'(?m)^[ \t]*'+re.escape(BEGIN)+r'[^\n]*\n.*?^[ \t]*'+re.escape(END)+r'[^\n]*\n?','',text,flags=re.S)
def nginx_patch(text,domain,path,lineage,meta=None,state=None):
    state=state or {};ng,xh=socket_paths(state)
    text=strip_marked(text)
    if meta:
        for old,new in meta.get('replacements',[]):
            if new in text:text=text.replace(new,old,1)
    start,end,root,ds=server(text,domain)
    body=text[start:end];changes=[]
    for d in ds:
        if state.get('secure_sockets') and d and d[0][0]=='listen' and 'unix:/dev/shm/nginx.sock' in [x[0] for x in d]:
            if not text.startswith('# Nuvrion owns this complete file'):raise ValueError('Путь сокета стороннего Nginx требует ручной миграции')
            old=text[d[0][1]:d[-1][2]]+';';new=old.replace('/dev/shm/nginx.sock',ng)
            body=body.replace(old,new,1);changes.append([old,new])
        if d and d[0][0] in ('ssl_certificate','ssl_certificate_key','ssl_trusted_certificate'):
            filename='privkey.pem' if d[0][0]=='ssl_certificate_key' else 'fullchain.pem'
            old=text[d[0][1]:d[-1][2]]+';'
            new=f'{d[0][0]} "{lineage}/{filename}";'
            body=body.replace(old,new,1);changes.append([old,new])
    # Locations outside our marked block must not silently be overwritten.
    bt,bb=blocks(body)
    for a,o,z in bb:
        if bt[a][0]=='location' and any(x[0] in (path,'/api/','/api/game/','/_game_unavailable.json','/assets/','/vendor/','/index.html','/app.mjs','/catalog.mjs','/content.mjs','/topography.mjs','/style.css','/tokens.css','/beers.json') for x in bt[a+1:o]):
            raise ValueError('Существующий немаркированный location конфликтует с установкой')
    route=f'''
    {BEGIN} ROUTES
    location ^~ {path} {{
        if ($ssl_server_name != "{domain}") {{ return 404; }}
        if ($host != "{domain}") {{ return 404; }}
        client_max_body_size 0;
        proxy_set_header X-Real-IP $proxy_protocol_addr;
        proxy_set_header X-Forwarded-For $proxy_protocol_addr;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        client_body_timeout 5m;
        proxy_connect_timeout 10s;
        proxy_read_timeout 315s;
        proxy_send_timeout 5m;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_pass http://unix:{xh};
    }}
{atlas_locations()}
    location ^~ /api/ {{ return 404; }}
    {END} ROUTES
'''
    body=body[:-1].rstrip()+route+'}';text=text[:start]+body+text[end:]
    # Upgrade only the exact default vhost previously generated by Nuvrion.
    # Retain a reversible replacement; foreign default servers need review.
    if text.startswith('# Nuvrion owns this complete file'):
        t,bs=blocks(text)
        defaults=[]
        for a,o,z in bs:
            if t[a][0]!='server':continue
            ds=block_directives(t,o,z)
            if any(d and d[0][0]=='server_name' and '_' in [v[0] for v in d[1:]] for d in ds) and any(d and d[0][0]=='listen' and 'default_server' in [v[0] for v in d[1:]] for d in ds):
                defaults.append((t[a][1],t[z][2]))
        if len(defaults)>1:raise ValueError('Неоднозначный default server Nuvrion')
        if defaults:
            a,z=defaults[0];old=text[a:z];new=default_server(domain,lineage,root,ng).lstrip()
            if old!=new:text=text[:a]+new+text[z:];changes.append([old,new])
    if not re.search(r'\bmap\s+\$http_upgrade\s+\$connection_upgrade\s*\{',text):
        mp=f'{BEGIN} MAP\nmap $http_upgrade $connection_upgrade {{ default upgrade; "" close; }}\n{END} MAP\n'
        t,bs=blocks(text);http=[o for a,o,z in bs if t[a][0]=='http']
        offset=t[http[0]][2] if http else 0
        text=text[:offset].rstrip()+'\n'+mp+text[offset:].lstrip('\n')
    return text,{'replacements':changes,'root':root}

def mounts(service):
    out={}
    for x in service.get('volumes',[]):
        if isinstance(x,str):
            a=x.split(':');out[a[1]]={'type':'bind','source':a[0],'target':a[1],'read_only':len(a)>2 and a[2]=='ro'}
        else:out[x['target']]=x
    return out
def add_mount(service,source,target,ro=False):
    m=mounts(service);old=m.get(target)
    if old and (old.get('type')!='bind' or old.get('source')!=source or bool(old.get('read_only'))!=ro):
        raise ValueError('Конфликтующий mount '+target+'; требуется ручное решение')
    if not old:service.setdefault('volumes',[]).append({'type':'bind','source':source,'target':target,'read_only':ro})
def compose_override(state,config,existing):
    services=copy.deepcopy(existing.get('services',{}));node=state['node_service'];ng=state['nginx_service']
    if config['services'][node].get('network_mode')!='host':raise ValueError('Remnanode должен уже использовать network_mode: host')
    ns=services.setdefault(node,{})
    ns['image']=state['node_image_id'] # exact running image; never pull a new node
    def ensure(dst,base,source,target,ro=False):
        current=mounts(base).get(target)
        if current:
            if current.get('type')!='bind' or current.get('source')!=source or bool(current.get('read_only'))!=ro:raise ValueError('Конфликтующий mount '+target)
            # Preserve propagation/SELinux/bind options of an existing mount.
            return
        add_mount(dst,source,target,ro)
    ensure(ns,config['services'][node],'/dev/shm','/dev/shm')
    if state.get('docker_hardening'):
        if config['services'][node].get('privileged'):raise ValueError('Привилегированная нода требует отдельной проверки')
        opts=list(config['services'][node].get('security_opt',[]))
        if any(x in opts for x in ('no-new-privileges:false','no-new-privileges=false')):raise ValueError('Конфликт настройки no-new-privileges')
        if not any(x in opts for x in ('no-new-privileges:true','no-new-privileges=true')):opts.append('no-new-privileges:true')
        ns['security_opt']=opts
        # Keep s6/Node capabilities and writable runtime until separately verified.
        ns['pids_limit']=max(int(config['services'][node].get('pids_limit') or 0),1024)
        if config['services'][node].get('pids_limit')==-1:ns['pids_limit']=-1
    current=config['services'][node].get('ulimits',{}).get('nofile',{})
    if isinstance(current,int):current={'soft':current,'hard':current}
    ns.setdefault('ulimits',{})['nofile']={k:max(int(current.get(k,0)),1048576) if int(current.get(k,0))!=-1 else -1 for k in ('soft','hard')}
    if state['nginx_kind']=='docker':
        gs=services.setdefault(ng,{})
        gs['image']=state['nginx_image_id']
        if state['nginx_new']:
            ngsock,_=socket_paths(state)
            start=f'if [ -S {ngsock} ]; then rm -f {ngsock}; fi; '
            if state.get('secure_sockets'):
                start+=f'nginx -g "daemon off;" & p=$!; trap \'kill -TERM "$p"; wait "$p"\' TERM INT; '
                start+=f'for i in $(seq 1 100); do if [ -S {ngsock} ]; then chmod 0600 {ngsock}; break; fi; sleep 0.1; done; '
                start+=f'[ -S {ngsock} ] || {{ kill -TERM "$p"; wait "$p"; exit 1; }}; wait "$p"'
            else:start+='exec nginx -g "daemon off;"'
            base=config['services'].get(ng,{})
            for field,value in {'network_mode':'host','restart':'unless-stopped',
                                'logging':{'driver':'json-file','options':{'max-size':'10m','max-file':'3'}}}.items():
                gs.setdefault(field,copy.deepcopy(base.get(field,value)))
            gs.setdefault('labels',copy.deepcopy(base.get('labels',{})))['com.nuvrion.xhttp.managed']='1'
            opts=list(base.get('security_opt',[]))
            if any(v in opts for v in ('no-new-privileges:false','no-new-privileges=false')):raise ValueError('Конфликт политики no-new-privileges Nginx')
            if not any(v in opts for v in ('no-new-privileges:true','no-new-privileges=true')):opts.append('no-new-privileges:true')
            required_caps={'CHOWN','DAC_OVERRIDE','SETUID','SETGID'}
            if set(base.get('cap_add',[]))-required_caps:
                raise ValueError('Пользовательские capabilities Nginx требуют отдельной проверки; сохранены')
            tmpfs=list(base.get('tmpfs',[]))
            for entry in ['/var/cache/nginx:rw,noexec,nosuid,size=64m','/var/run:rw,noexec,nosuid,size=16m']:
                target=entry.split(':')[0]
                previous=[v for v in tmpfs if v.split(':')[0]==target]
                if previous and previous!=[entry]:raise ValueError('Конфликт настройки tmpfs Nginx: '+target)
                if not previous:tmpfs.append(entry)
            command=base.get('command')
            if isinstance(command,list) and len(command)==3 and command[:2]==['sh','-c']:
                command=[*command[:2],command[2].replace('$$','$')]
            legacy_commands=[['sh','-c',f'if [ -S {sock} ]; then rm -f {sock}; fi; exec nginx -g "daemon off;"']
                             for sock in ['/dev/shm/nginx.sock','/dev/shm/nuvrion-xhttp/nginx.sock']]
            if command and command not in [*legacy_commands,['sh','-c',start]]:
                raise ValueError('Пользовательская команда Nginx требует отдельной проверки; сохранена')
            # Compose interpolates dollars even inside a JSON command array.
            # Double them so PID/trap variables reach the container shell.
            gs.update({'command':['sh','-c',start.replace('$','$$')],
                       'security_opt':opts,'cap_drop':['ALL'],
                       'cap_add':['CHOWN','DAC_OVERRIDE','SETUID','SETGID'],
                       'pids_limit':max(int(base.get('pids_limit') or 0),512),'read_only':True,
                       'tmpfs':tmpfs})
            if base.get('pids_limit')==-1:gs['pids_limit']=-1
            gs.setdefault('ulimits',{})['nofile']={'soft':1048576,'hard':1048576}
            add_mount(gs,state['nginx_config'],'/etc/nginx/nginx.conf',True)
            add_mount(gs,state['site_root'],'/var/www/decoy',True)
        base=config['services'].get(ng,{})
        ensure(gs,base,'/dev/shm','/dev/shm')
        ensure(gs,base,'/etc/letsencrypt','/etc/letsencrypt',True)
        # Keep any existing legacy bind for reversible upgrades; new installs
        # do not create a game socket mount or a backend service.
    return {'services':services}
def verify_compose(before,after,state):
    a=copy.deepcopy(before);b=copy.deepcopy(after)
    names=[state['node_service']]
    if state.get('nginx_kind','docker')=='docker':names.append(state['nginx_service'])
    for name in names:
        if name not in a.get('services',{}):
            if name==state['nginx_service'] and state['nginx_new']:b['services'].pop(name,None);continue
            raise ValueError('Неожиданное изменение services')
        x=a['services'][name];y=b['services'][name]
        if name==state['node_service'] and state.get('docker_hardening'):
            for field in ('security_opt','pids_limit'):x.pop(field,None);y.pop(field,None)
        if name==state['nginx_service'] and state['nginx_new']:
            for field in ('command','security_opt','cap_drop','cap_add','pids_limit','read_only','tmpfs'):
                x.pop(field,None);y.pop(field,None)
        y['image']=x.get('image')
        mx=mounts(x);my=mounts(y)
        expected={'/dev/shm'} if name==state['node_service'] else {'/dev/shm','/etc/letsencrypt'}
        for k,v in mx.items():
            if k not in my or v!=my[k]:raise ValueError('Изменён существующий mount '+k)
        if set(my)-set(mx)-expected:raise ValueError('Лишние mounts')
        x.pop('volumes',None);y.pop('volumes',None)
        if name==state['node_service'] or name==state['nginx_service'] and state['nginx_new']:
            ux=x.setdefault('ulimits',{});uy=y.setdefault('ulimits',{})
            uy.pop('nofile',None);ux.pop('nofile',None)
            if not uy:y.pop('ulimits',None)
            if not ux:x.pop('ulimits',None)
    if a!=b:raise ValueError('Compose изменяет сторонние поля; применение остановлено')

def profile(state,key,public,source=None):
    ngsock,xhsock=socket_paths(state)
    migrate=state.get('harden_profile',False)
    sockopt={'tcpFastOpen':True,'tcpcongestion':'bbr','tcpKeepAliveIdle':60,'tcpKeepAliveInterval':30}
    d=copy.deepcopy(source) if source else {'log':{'access':'none','dnsLog':False,'loglevel':'warning'},
        'dns':{'servers':[{'address':'https+local://dns.adguard-dns.com/dns-query','timeoutMs':2500,'queryStrategy':'UseIPv4'},
                         {'address':'https+local://dns.comss.one/dns-query','timeoutMs':2000,'queryStrategy':'UseIPv4'}],
               'serveStale':True,'disableCache':False,'queryStrategy':'UseIPv4','disableFallback':False,
               'serveExpiredTTL':600,'enableParallelQuery':False},'inbounds':[],
        'outbounds':[{'tag':'DIRECT','protocol':'freedom','settings':{'domainStrategy':'UseIPv4'},
                      'streamSettings':{'sockopt':copy.deepcopy(sockopt)}},{'tag':'BLOCK','protocol':'blackhole'}]}
    ins=d.setdefault('inbounds',[])
    reality=[i for i in ins if i.get('port')==443 and i.get('streamSettings',{}).get('security')=='reality']
    if len(reality)>1:raise ValueError('Несколько Reality inbounds на 443')
    if not reality and any(i.get('port')==443 for i in ins):raise ValueError('Существующий inbound :443 не Reality; профиль не перезаписывается')
    tag=state['node_tag'];xh=tag+' XHTTP'
    if reality:
        r=reality[0]
        if r['streamSettings']['realitySettings'].get('privateKey')!=key:raise ValueError('Изменение существующего ключа запрещено')
        if r.get('tag')!=tag:raise ValueError('Сохраните tag существующего Reality inbound')
        if r['streamSettings'].get('network') not in ('tcp','raw'):raise ValueError('Существующий Reality transport не TCP/RAW')
        rs=r['streamSettings']['realitySettings']
        if migrate and rs.get('target',rs.get('dest'))=='/dev/shm/nginx.sock':rs['target' if 'target' in rs else 'dest']=ngsock
        if rs.get('xver')!=1 or rs.get('target',rs.get('dest'))!=ngsock or state['domain'] not in rs.get('serverNames',[]):
            raise ValueError('Действующие параметры REALITY отличаются; требуется явная миграция')
    else:
        r={'tag':tag,'port':443,'protocol':'vless','settings':{'clients':[],'decryption':'none'},
           'sniffing':{'enabled':True,'routeOnly':True,'destOverride':['http','tls','quic']},
           'streamSettings':{'network':'raw','sockopt':copy.deepcopy(sockopt),'security':'reality',
               'realitySettings':{'show':False,'xver':1,'target':ngsock,'spiderX':'','minClientVer':'0.0.0',
               'shortIds':[''],'privateKey':key,'serverNames':[state['domain']]}}}
        ins.append(r)
    old=[i for i in ins if i.get('tag')==xh]
    listener=xhsock+(',0660' if state.get('secure_sockets') else ',0666')
    if old and (len(old)!=1 or old[0].get('listen') not in ({listener,'/dev/shm/xrxh.socket,0666'} if migrate else {listener})):raise ValueError('Конфликт XHTTP tag; требуется явная миграция')
    if any(i.get('tag')==tag and i is not r for i in ins):raise ValueError('Дублирующийся Reality tag')
    if any(str(i.get('listen','')).split(',')[0]==xhsock and i not in old for i in ins):raise ValueError('Дублирующийся XHTTP socket')
    # Server and client knobs are combined in the supported extra object.
    # Remnawave Host still controls the client-side subscription overrides.
    settings={'mode':'auto','path':state['xhttp_path'],'extra':{'noSSEHeader':True,'xPaddingBytes':'100-1000',
        'scMaxBufferedPosts':30,'scMaxEachPostBytes':1000000,'scStreamUpServerSecs':'20-80',
        'scMinPostsIntervalMs':30,'noGRPCHeader':False,
        'xmux':{'cMaxReuseTimes':0,'maxConcurrency':'16-32','maxConnections':0,'hKeepAlivePeriod':0,
                'hMaxRequestTimes':'600-900','hMaxReusableSecs':'1800-3000'}}}
    if state.get('padding_supported'):settings['extra'].update(padding_extra())
    inbound=copy.deepcopy(old[0]) if old else {}
    inbound.update({'tag':xh,'listen':listener,'protocol':'vless',
             'settings':inbound.get('settings',{'clients':[],'fallbacks':[],'decryption':'none'}),
             'sniffing':{'enabled':True,'routeOnly':True,'destOverride':['http','tls','quic']},
             'streamSettings':{'network':'xhttp','xhttpSettings':settings}})
    if not state.get('trusted_xff'):raise ValueError('Версия Xray не подтверждает trustedXForwardedFor; обновление автоматически не выполняется')
    inbound['streamSettings']['sockopt']={'trustedXForwardedFor':['X-Forwarded-For']}
    if old:
        # Imports/reinstall preserve ALL user transport settings, clients and
        # extension fields. New defaults apply only to a new inbound.
        inbound=copy.deepcopy(old[0])
        if migrate:
            if not state.get('padding_supported'):raise ValueError('Cookie padding требует проверенного Xray 26.7.28; автоматическое обновление запрещено')
            inbound['listen']=listener
            existing_settings=inbound['streamSettings']['xhttpSettings']
            extra_settings=existing_settings.setdefault('extra',{})
            # Legacy root options must be retained when normalizing to extra;
            # otherwise Xray extra parsing would ignore those root values.
            for name in list(settings['extra']):
                if name in existing_settings:extra_settings.setdefault(name,existing_settings.pop(name))
            for name,value in settings['extra'].items():extra_settings.setdefault(name,copy.deepcopy(value))
            extra_settings.update(padding_extra())
    ins[:]=[inbound if i in old else i for i in ins]
    if not old:ins.append(inbound)
    if not source:
        both=[tag,xh]
        rules=[{'port':'443','type':'field','network':'udp','inboundTag':both,'outboundTag':'BLOCK'},
               {'port':'25','type':'field','network':'tcp','inboundTag':both,'outboundTag':'BLOCK'},
               {'type':'field','protocol':['bittorrent'],'inboundTag':both,'outboundTag':'BLOCK'},
               {'ip':['geoip:private'],'type':'field','inboundTag':both,'outboundTag':'BLOCK'},
               {'type':'field','domain':['geosite:private'],'inboundTag':both,'outboundTag':'BLOCK'},
               {'type':'field','domain':['geosite:category-ads-all','domain:analytics.google.com','domain:adjust.net.in',
                    'domain:amplitude.com','domain:metrika.yandex.ru','domain:mytracker.ru'],'inboundTag':both,'outboundTag':'BLOCK'}]
        d['routing']={'rules':rules,'domainMatcher':'hybrid','domainStrategy':'AsIs'}
    if source and migrate:
        # Explicitly requested revision, not an implicit reinstall/import change.
        d['dns']=profile({**state,'harden_profile':False},key,public)[0]['dns']
    tags=[i.get('tag') for i in ins]
    if len(tags)!=len(set(tags)):raise ValueError('Дублирующиеся inbound tags')
    extra={'xmux':{'cMaxReuseTimes':0,'maxConcurrency':'16-32','maxConnections':0,'hKeepAlivePeriod':0,
                   'hMaxRequestTimes':'600-900','hMaxReusableSecs':'1800-3000'},
           'noGRPCHeader':False,'xPaddingBytes':'100-1000','scMaxEachPostBytes':1000000,'scMinPostsIntervalMs':30}
    server_extra=inbound.get('streamSettings',{}).get('xhttpSettings',{}).get('extra',{})
    for name in list(extra):
        if name in server_extra:extra[name]=copy.deepcopy(server_extra[name])
    for name in padding_extra():
        if name in server_extra:extra[name]=server_extra[name]
    sid=next((x for x in r['streamSettings']['realitySettings'].get('shortIds',[]) if x),'')
    host=f'''Nuvrion · настройки Host в Remnawave

Настройки REALITY TCP Host в Remnawave

Адрес:          {state['domain']}
Порт:           443
SNI:            {state['domain']}
Security Layer: DEFAULT
Отпечаток:      firefox
ALPN:           Наследовать из inbound
Inbound:        {tag}

REALITY, Public key, Short ID, TCP/RAW и flow наследуются из выбранного inbound.
Public key:     {public}
Short ID:       {sid}
Flow:           xtls-rprx-vision
Host, Path и XHTTP extra parameters: оставить пустыми.

Настройки XHTTP Host в Remnawave

Адрес:          {state['domain']}
Порт:           443
SNI:            {state['domain']}
Security Layer: TLS (Transport Layer Security)
Отпечаток:      firefox
ALPN:           h2,http/1.1
Inbound:        {xh}

TLS завершается в Nginx. Transport — XHTTP из inbound.
Host:           {state['domain']}
Path:           {state['xhttp_path']}
Mode:           auto
Flow:           пусто
XHTTP extra parameters: оставить пустым для наследования extra из профиля.
Для явного переопределения: /root/nuvrion-xhttp-extra.json
Extra не включает stream separation или downloadSettings.

Адрес и SNI обоих Host должны совпадать с доменом ноды.
Внешний порт обоих Host — 443; Unix socket в Host не указывается.
Назначьте ноде оба inbound из профиля. Пользователи управляются панелью.
'''
    return d,extra,host

def secure_directory(path,gid):
    # Published only after ownership/mode have been assigned; never chmod shm.
    p=Path(path)
    if p.is_symlink():raise ValueError('Каталог сокетов является символической ссылкой')
    if p.exists():
        st=p.stat()
        if not p.is_dir() or st.st_uid!=0 or st.st_gid!=gid or st.st_mode & 0o7777!=0o2710:
            raise ValueError('Чужой или небезопасный каталог сокетов; автоматическая смена владельца запрещена')
    else:
        p.mkdir(mode=0o700)
        os.chown(p,0,gid);os.chmod(p,0o2710)

def profile_checks(data,require_new=False):
    results=[]
    def check(ok,name):results.append(('PASS' if ok else 'FAIL',name))
    ins=data.get('inbounds',[])
    r=[i for i in ins if i.get('streamSettings',{}).get('security')=='reality']
    x=[i for i in ins if i.get('streamSettings',{}).get('network')=='xhttp']
    check(len(r)==1 and r[0].get('port')==443 and r[0]['streamSettings'].get('network') in ('raw','tcp'),'REALITY TCP :443')
    check(len(x)==1 and x[0].get('listen','').startswith('/dev/shm/'),'XHTTP Unix socket')
    if x:
        settings=x[0]['streamSettings']['xhttpSettings'];extra=settings.get('extra',{})
        check(settings.get('mode')=='auto' and settings.get('path','').endswith('/'),'XHTTP: режим и путь')
        check(all(k in extra for k in ('xmux','noSSEHeader','noGRPCHeader','scMaxBufferedPosts','scMaxEachPostBytes','scMinPostsIntervalMs','scStreamUpServerSecs')),'XHTTP: обязательные параметры extra')
        if require_new:check(all(extra.get(k)==v for k,v in padding_extra().items()),'Cookie padding с методом tokenish')
    check(len({i.get('tag') for i in ins})==len(ins),'Уникальные теги inbound')
    if require_new:
        check([i.get('address') for i in data.get('dns',{}).get('servers',[])]==
              ['https+local://dns.adguard-dns.com/dns-query','https+local://dns.comss.one/dns-query'],'DNS AdGuard → COMSS')
    return results

def tls_audit(state):
    import ssl
    domain=state['domain'];results=[]
    def request(sni,host,path='/',version=None):
        ctx=ssl.create_default_context();ctx.check_hostname=False
        if version:ctx.minimum_version=ctx.maximum_version=version
        with socket.create_connection(('127.0.0.1',443),timeout=8) as sock:
            with ctx.wrap_socket(sock,server_hostname=sni) as conn:
                names=[v.lower() for k,v in conn.getpeercert().get('subjectAltName',[]) if k=='DNS']
                if not any(v==domain or v.startswith('*.') and domain.partition('.')[2]==v[2:] for v in names):
                    raise ValueError('Сертификат содержит неожиданные имена SAN')
                conn.sendall((f'GET {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n').encode())
                data=b''
                while len(data)<1024*1024:
                    chunk=conn.recv(65536)
                    if not chunk:break
                    data+=chunk
                return data.decode(errors='replace')
    cases=[('правильный SNI',domain,domain),('неправильный SNI','wrong.invalid','wrong.invalid'),
           ('без SNI',None,domain),('IP в Host',None,state.get('ipv4','127.0.0.1'))]
    for label,sni,host in cases:
        try:
            response=request(sni,host);ok=' 200 ' in response.splitlines()[0] and '<!doctype html' in response.lower() and 'атлас пива' in response.lower()
        except (OSError,ValueError):ok=False
        results.append(('PASS' if ok else 'FAIL','HTTPS: '+label+'; доверенный сертификат домена и Атлас пива'))
    for path,mime in [('/app.mjs','text/javascript'),('/vendor/topolines-0.3.0.js','text/javascript'),
                      ('/beers.json','application/json'),('/style.css','text/css')]:
        try:
            response=request(domain,domain,path)
            head=response.split('\r\n\r\n',1)[0].lower()
            ok=' 200 ' in response.splitlines()[0] and 'content-type: '+mime in head
        except (OSError,ValueError):ok=False
        results.append(('PASS' if ok else 'FAIL','Атлас пива: '+path+' и MIME '+mime))
    for version in (ssl.TLSVersion.TLSv1_2,ssl.TLSVersion.TLSv1_3):
        try:ok=' 200 ' in request(domain,domain,version=version).splitlines()[0]
        except (OSError,ValueError):ok=False
        results.append(('PASS' if ok else 'FAIL',version.name))
    for sni,host in [('wrong.invalid',domain),(None,domain),(domain,'wrong.invalid')]:
        for path in (state['xhttp_path'],'/api/game/me','/api/nodes'):
            try:ok=' 404 ' in request(sni,host,path).splitlines()[0]
            except (OSError,ValueError):ok=False
            results.append(('PASS' if ok else 'FAIL','Защита API: SNI='+str(sni)+' Host='+host+' '+path))
    try:
        response=request(domain,domain,state['xhttp_path'])
        ok=' 400 ' in response.splitlines()[0] and 'set-cookie: site_session=' in response.lower() and 'x-padding:' not in response.lower()
    except (OSError,ValueError):ok=False
    results.append(('PASS' if ok else 'FAIL','XHTTP: Cookie padding и HTTP 400 от backend'))
    return results

def tuning_checks(config,tfo,modprobe,pending):
    import subprocess
    target=Path(config)
    if not target.is_file() or target.is_symlink():raise ValueError('Отсутствует безопасный профиль sysctl Nuvrion')
    desired={}
    for path in (target,Path(tfo)):
        if not path.exists():continue
        if path.is_symlink():raise ValueError('Профиль sysctl является символической ссылкой')
        for line in path.read_text().splitlines():
            if not line.strip() or line.lstrip().startswith(('#',';')):continue
            match=re.fullmatch(r'\s*-?([A-Za-z0-9_.]+)\s*=\s*(.*?)\s*(?:#.*)?',line)
            if not match:raise ValueError('Некорректная строка профиля sysctl')
            desired[match[1]]=' '.join(match[2].split())
    if not desired:raise ValueError('Профиль sysctl не содержит проверяемых значений')
    for key,expected in desired.items():
        try:
            result=subprocess.run(['sysctl','-n',key],capture_output=True,text=True,timeout=5)
            actual=' '.join(result.stdout.split()) if result.returncode==0 else 'недоступно'
        except (OSError,subprocess.TimeoutExpired):actual='недоступно'
        status='PASS' if actual==expected else 'FAIL'
        if status=='FAIL' and key=='net.netfilter.nf_conntrack_buckets':
            boot=Path(modprobe)
            if Path(pending).is_file() and boot.is_file() and not boot.is_symlink() and re.search(
                r'(?m)^\s*options\s+nf_conntrack\s+.*\bhashsize='+re.escape(expected)+r'(?:\s|$)',boot.read_text()):
                result=subprocess.run(['systemctl','is-enabled','--quiet','nuvrion-performance-sysctl.service'],capture_output=True,timeout=5)
                if result.returncode==0:status='WAIT'
        yield status,f'sysctl {key}: требуется {expected}; фактически {actual}'
    for key,expected,label in [('net.ipv4.tcp_congestion_control','bbr','BBR'),('net.core.default_qdisc','fq','qdisc')]:
        result=subprocess.run(['sysctl','-n',key],capture_output=True,text=True,timeout=5)
        actual=result.stdout.strip() if result.returncode==0 else 'недоступно'
        yield 'PASS' if actual==expected else 'FAIL',f'{label}: {actual}; требуется {expected}'
    result=subprocess.run(['systemctl','is-enabled','--quiet','nuvrion-performance-sysctl.service'],capture_output=True,timeout=5)
    yield 'PASS' if result.returncode==0 else 'FAIL','Автоприменение профиля sysctl после загрузки'

def nft_security_rules(panel,api_only,ruleset,node_port=2222):
    node_port=int(node_port)
    if not 1<=node_port<=65535 or node_port in (80,443):raise ValueError('Некорректный порт API ноды')
    address=ipaddress.ip_address(panel);items=ruleset.get('nftables',[])
    def q(value):
        value=str(value)
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.-]*',value):raise ValueError('Неподдерживаемый идентификатор nftables; автоматическое изменение запрещено')
        return value
    tables=[i['table'] for i in items if 'table' in i]
    chains=[i['chain'] for i in items if 'chain' in i]
    lines=[]
    # Delete/reinsert ONLY owned marked rules in ONE kernel transaction. The
    # previous API guard remains effective until the complete batch commits.
    for item in items:
        rule=item.get('rule',{})
        if rule.get('comment')=='Nuvrion-XHTTP':
            family=rule['family']
            if family not in ('inet','ip','ip6'):raise ValueError('Неожиданное семейство nftables')
            lines.append(f'delete rule {family} {q(rule["table"])} {q(rule["chain"])} handle {int(rule["handle"])}')
    if not any(t.get('family')=='inet' and t.get('name')=='nuvrion_xhttp' for t in tables):
        lines.append('add table inet nuvrion_xhttp')
    guard=next((c for c in chains if c.get('family')=='inet' and c.get('table')=='nuvrion_xhttp' and c.get('name')=='api_guard'),None)
    if guard:
        if guard.get('hook')!='input' or guard.get('prio')!=-250 or guard.get('type')!='filter' or guard.get('policy')!='accept':
            raise ValueError('Конфликтующая цепочка защиты API')
        if any(i.get('rule',{}).get('table')=='nuvrion_xhttp' and i['rule'].get('chain')=='api_guard' and
               i['rule'].get('comment')!='Nuvrion-XHTTP' for i in items):
            raise ValueError('В цепочке защиты API есть сторонние правила; требуется ручная проверка')
    else:lines.append('add chain inet nuvrion_xhttp api_guard { type filter hook input priority -250; policy accept; }')
    lines.append(f'insert rule inet nuvrion_xhttp api_guard tcp dport {node_port} drop comment "Nuvrion-XHTTP"')
    ip='ip' if address.version==4 else 'ip6'
    lines.append(f'insert rule inet nuvrion_xhttp api_guard {ip} saddr {address} tcp dport {node_port} accept comment "Nuvrion-XHTTP"')
    for c in chains:
        family=c.get('family');table=c.get('table');chain=c.get('name')
        if c.get('hook')!='input' or family not in ('inet','ip','ip6') or table in ('nuvrion_xhttp','nuvrion_tc','nuvrion_privacy'):continue
        if not api_only:lines.append(f'insert rule {family} {q(table)} {q(chain)} tcp dport 443 accept comment "Nuvrion-XHTTP"')
        if family=='inet' or family==ip:
            lines.append(f'insert rule {family} {q(table)} {q(chain)} {ip} saddr {address} tcp dport {node_port} accept comment "Nuvrion-XHTTP"')
    return '\n'.join(lines)+'\n'

def check_nft_guard(panel,node_port,ruleset):
    address=ipaddress.ip_address(panel);port=int(node_port);items=ruleset.get('nftables',[])
    chains=[i['chain'] for i in items if 'chain' in i]
    guard=[c for c in chains if c.get('family')=='inet' and c.get('table')=='nuvrion_xhttp' and c.get('name')=='api_guard']
    if len(guard)!=1 or any(guard[0].get(k)!=v for k,v in
            {'hook':'input','prio':-250,'type':'filter','policy':'accept'}.items()):
        raise ValueError('Цепочка защиты API не подключена к INPUT с ожидаемой политикой')
    def match(protocol,field,value):
        return {'match':{'op':'==','left':{'payload':{'protocol':protocol,'field':field}},'right':value}}
    expected=[[match('ip' if address.version==4 else 'ip6','saddr',str(address)),
               match('tcp','dport',port),{'accept':None}],
              [match('tcp','dport',port),{'drop':None}]]
    rules=[i['rule'] for i in items if 'rule' in i and i['rule'].get('family')=='inet' and
           i['rule'].get('table')=='nuvrion_xhttp' and i['rule'].get('chain')=='api_guard']
    if len(rules)!=2 or any(r.get('comment')!='Nuvrion-XHTTP' for r in rules) or [r.get('expr') for r in rules]!=expected:
        raise ValueError('Порядок или состав правил защиты API изменён')

def check_iptables_guard(panel,node_port,family,api_only,text):
    lines=[shlex.split(line) for line in text.splitlines() if line.strip()]
    inputs=[r for r in lines if r[:2]==['-A','INPUT']]
    if not inputs or inputs[0]!=['-A','INPUT','-j','NUVRION_XHTTP'] or \
       sum(r==['-A','INPUT','-j','NUVRION_XHTTP'] for r in inputs)!=1:
        raise ValueError('Переход к защите API должен быть первым и единственным в INPUT')
    address=ipaddress.ip_address(panel);port=str(int(node_port))
    def canonical(rule):
        result={};i=2
        while i<len(rule):
            if rule[i:i+2]==['-m','tcp']:i+=2;continue
            flag=rule[i];value=rule[i+1] if i+1<len(rule) else ''
            if flag=='-s':value=str(ipaddress.ip_network(value,strict=False))
            if flag not in ('-p','-s','--dport','-j') or flag in result:raise ValueError('Неподтверждённая опция правила iptables')
            result[flag]=value;i+=2
        return result
    expected=[]
    if address.version==int(family):
        expected.append({'-p':'tcp','-s':str(ipaddress.ip_network(str(address))),'--dport':port,'-j':'ACCEPT'})
    expected.append({'-p':'tcp','--dport':port,'-j':'DROP'})
    if not api_only:expected.append({'-p':'tcp','--dport':'443','-j':'ACCEPT'})
    own=[canonical(r) for r in lines if r[:2]==['-A','NUVRION_XHTTP']]
    if own!=expected:raise ValueError('Порядок или состав правил iptables защиты API изменён')

def check_ufw_guard(panel,node_port,api_only,text):
    if not re.search(r'^Status: active$',text,re.M):raise ValueError('UFW выключен')
    rows=[];address=ipaddress.ip_address(panel);port=str(int(node_port))+'/tcp'
    for line in text.splitlines():
        match=re.match(r'^\[\s*\d+\]\s+(.*?)\s+#\s*(.*)$',line)
        if match:rows.append((match[1],match[2]))
        elif re.match(r'^\[\s*\d+\]',line):rows.append((re.sub(r'^\[\s*\d+\]\s*','',line),''))
    def fields(body):
        match=re.fullmatch(r'(.*?)\s+(ALLOW|DENY|REJECT|LIMIT)\s+(IN|OUT)\s+(.+?)\s*',body)
        if not match:raise ValueError('Не удалось разобрать правило UFW')
        return tuple(re.sub(r'\s*\(v6\)$','',part.strip()) for part in match.groups())
    def panel_source(source):
        try:
            network=ipaddress.ip_network(source,strict=False)
            return network.prefixlen==network.max_prefixlen and network.network_address==address
        except ValueError:return False
    def overlaps_api(destination):
        if destination=='Anywhere':return True
        match=re.fullmatch(r'([0-9,:]+)(?:/(tcp|udp))?',destination)
        if not match:return True # an application profile cannot be certified from its title
        if match[2]=='udp':return False
        for segment in match[1].split(','):
            bounds=segment.split(':')
            if len(bounds)==1 and int(bounds[0])==int(node_port):return True
            if len(bounds)==2 and int(bounds[0])<=int(node_port)<=int(bounds[1]):return True
        return False
    for family in (4,6):
        rules=[(body,comment) for body,comment in rows if ('(v6)' in body)==(family==6)]
        guards=[i for i,(body,comment) in enumerate(rules) if comment=='Nuvrion-XHTTP API guard' and
                fields(body)==(port,'DENY','IN','Anywhere')]
        if len(guards)!=1:raise ValueError('Не найден единственный UFW deny API для IPv'+str(family))
        guard=guards[0]
        prefix=rules[:guard]
        if address.version==family:
            panels=[i for i,(body,comment) in enumerate(prefix) if comment=='Nuvrion-XHTTP panel' and
                    fields(body)[:3]==(port,'ALLOW','IN') and panel_source(fields(body)[3])]
            if len(panels)!=1:raise ValueError('UFW allow панели не предшествует deny API')
        else:panels=[]
        for i,(body,comment) in enumerate(prefix):
            if i in panels or (comment=='Nuvrion-XHTTP HTTPS' and body.startswith('443/tcp ')):continue
            # An unknown application/range/general allow above our API deny
            # cannot be certified safe just from a comment on another rule.
            destination,action,direction,_=fields(body)
            if action in ('ALLOW','LIMIT') and direction=='IN' and overlaps_api(destination):
                raise ValueError('Выше ограничения API есть неподтверждённое разрешение UFW')
        if not api_only and not any(comment=='Nuvrion-XHTTP HTTPS' and body.startswith('443/tcp ') and 'ALLOW IN' in body for body,comment in rules):
            raise ValueError('Не найден UFW allow HTTPS для IPv'+str(family))

def safe_asset_path(path):
    p=Path(path)
    if not p.is_absolute() or '..' in p.parts:raise ValueError('Недопустимый путь файла сайта')
    for current in [*reversed(p.parents),p]:
        if current.is_symlink():raise ValueError('Symlink в пути файла сайта: '+str(current))
        if current!=p and current.exists() and not current.is_dir():raise ValueError('Не каталог в пути файла сайта: '+str(current))
    return p

def asset_collisions(names,dest,manifest):
    dest=safe_asset_path(dest);old=read(manifest) if Path(manifest).exists() else {}
    for name,expected in old.items():
        relative=Path(name)
        if relative.is_absolute() or '..' in relative.parts:raise ValueError('Недопустимое имя в описи сайта')
        target=safe_asset_path(dest/relative)
        if target.exists() and digest(target)!=expected:raise ValueError('Файл сайта изменён пользователем: '+name)
    collisions=[]
    for name in names:
        relative=Path(name)
        if relative.is_absolute() or '..' in relative.parts:raise ValueError('Недопустимое имя файла сайта')
        target=safe_asset_path(dest/relative)
        if target.exists() and not target.is_file():raise ValueError('Цель файла сайта не является обычным файлом: '+str(target))
        if target.exists() and name not in old:collisions.append(name)
    return collisions

def check_owned_unit(path,marker):
    p=Path(path)
    if not p.exists() and not p.is_symlink():return
    if p.is_symlink() or not p.is_file() or p.stat().st_uid!=0 or p.stat().st_mode & 0o022:
        raise ValueError('Небезопасный существующий unit: '+str(p))
    if not STATE.exists() or marker not in p.read_text():raise ValueError('Сторонний systemd-unit не заменяется: '+str(p))
    manifest=OWN/'component-paths.json';expected=read(manifest).get(str(p)) if manifest.exists() else None
    legacy=OWN/'owned-delta.json'
    if expected is None and legacy.exists():expected=read(legacy).get(str(p),{}).get('after')
    if expected is None or digest(p)!=expected:raise ValueError('Unit не подтверждён manifest или изменён после установки: '+str(p))

def write_owned_unit(path,marker,text):
    check_owned_unit(path,marker)
    if marker not in text:raise ValueError('В новом unit отсутствует маркер владения')
    manifest=OWN/'component-paths.json';owned=read(manifest) if manifest.exists() else {}
    # Record the intended content before writing, so an interrupted first
    # installation can verify the unit without a final ownership delta.
    owned[str(Path(path))]=hashlib.sha256(text.encode('utf-8')).hexdigest();write(manifest,owned)
    write(path,text,0o644)

def digest(p):
    p=Path(p)
    if p.is_symlink():return 'link:'+os.readlink(p)
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None
def safe_backup(p):
    p=Path(p).resolve()
    if p.parent!=Path('/root/nuvrion-xhttp-backups') or not re.fullmatch(r'\d{8}-\d{6}(?:-\d+)?',p.name):raise ValueError('Недопустимый путь резервной копии')
    return p
SAFE_SNAPSHOT_LINKS={'/usr/local/bin/ntc':'/usr/local/bin/nuvrion-traffic-control'}
def safe_snapshot_link(p):
    return p.is_symlink() and os.readlink(p)==SAFE_SNAPSHOT_LINKS.get(str(p))
def snapshot(folder,paths):
    folder=safe_backup(folder);folder.mkdir(mode=0o700)
    records=[];covered=[]
    for name in sorted(set(paths),key=lambda x:(len(Path(x).parts),x)):
        p=Path(name)
        if not p.is_absolute() or '..' in p.parts:raise ValueError('Недопустимый snapshot path')
        if p.is_symlink() and not safe_snapshot_link(p):raise ValueError('Объект резервного копирования является символической ссылкой: '+name)
        exists=p.exists() or p.is_symlink();records.append({'path':name,'exists':exists,'dir':p.is_dir() and not p.is_symlink()})
        if any(p.is_relative_to(q) for q in covered):continue
        if exists:
            target=folder/'files'/p.relative_to('/')
            target.parent.mkdir(parents=True,exist_ok=True)
            if p.is_dir():shutil.copytree(p,target,symlinks=True);covered.append(p)
            else:shutil.copy2(p,target,follow_symlinks=False)
    write(folder/'files.json',records)
def snapshot_delta(folder,output,managed_only=False,owned_roots=()):
    folder=safe_backup(folder);out={};previous=read(output) if managed_only and Path(output).exists() else {}
    shared={'/etc/sysctl.d','/etc/modules-load.d','/etc/modprobe.d','/etc/security/limits.d','/run/sysctl.d','/usr/local/lib/sysctl.d'}
    def sysctl_edit(source,target):
        if not source.is_file() or not target.is_file() or source.is_symlink() or target.is_symlink():return False
        def normalized(p):
            return [re.sub(r'^#\s*\[Nuvrion v[0-9.]+\]\s+отключено:\s(.*)$',r'\1',line) for line in p.read_text().splitlines()]
        return normalized(source)==normalized(target)
    for rec in read(folder/'files.json'):
        p=Path(rec['path']);old=folder/'files'/p.relative_to('/')
        names=set()
        for root in (p,old):
            if root.is_dir():names.update(q.relative_to(root).as_posix() for q in root.rglob('*') if q.is_file() or q.is_symlink())
            elif root.exists() or root.is_symlink():names.add('')
        for name in names:
            target=p/name if name else p;source=old/name if name else old
            if str(target)==str(output):continue
            # A new unrelated file in a shared snapshot tree belongs to its
            # creator. Never adopt it merely because it appeared during setup.
            owned=any(str(target)==x or str(target).startswith(x.rstrip('/')+'/') for x in owned_roots if x)
            if managed_only and rec['dir'] and not source.exists() and not source.is_symlink() and 'nuvrion' not in str(target).lower() and not owned:continue
            before,after=digest(source),digest(target)
            if before==after:continue
            if managed_only and (str(p) in shared or str(p)=='/etc/sysctl.conf') and 'nuvrion' not in str(target).lower() and not owned:
                # Only recognize the tuner's exact reversible marker edit in
                # foreign sysctl files. All other concurrent edits stay foreign.
                if str(target).startswith('/etc/sysctl') and sysctl_edit(source,target):
                    out[str(target)]={'before':before,'after':after}
                elif str(target) in previous:out[str(target)]=previous[str(target)]
                continue
            out[str(target)]={'before':before,'after':after}
    write(output,out)

def restore(folder,selection,journal=None,validate_only=False):
    folder=safe_backup(folder)
    records=read(folder/'files.json')
    if journal is None:
        # Compatibility for the allowlisted ntc link and immutable SSH tests.
        # General configuration restores always require a saved journal.
        if any(not immutable_path(p) and p not in SAFE_SNAPSHOT_LINKS for p in selection):
            raise ValueError('Restore requires an ownership journal')
        delta={p:{'after':digest(p)} for p in selection if p in SAFE_SNAPSHOT_LINKS}
    else:delta=read(journal)
    chosen=[(name,data) for name,data in delta.items() if not immutable_path(name) and
            any(name==x or name.startswith(x.rstrip('/')+'/') for x in selection)]
    # Validate the entire selection before changing any file. If another
    # process edited an owned file after the checkpoint, preserve that edit.
    for name,data in chosen:
        p=Path(name)
        if digest(p)!=data['after']:raise ValueError('Файл изменён после снимка; восстановление остановлено: '+name)
        if any(parent.is_symlink() for parent in p.parents):raise ValueError('Restore parent is a symlink: '+name)
        source=folder/'files'/p.relative_to('/')
        if any(parent.is_symlink() for parent in source.parents):raise ValueError('Backup parent is a symlink: '+name)
        if source.is_symlink() and os.readlink(source)!=SAFE_SNAPSHOT_LINKS.get(str(p)):
            raise ValueError('Unsafe backup symlink: '+str(p))
        if p.is_symlink() and not safe_snapshot_link(p):raise ValueError('Restore target is a symlink: '+str(p))
    if validate_only:return
    for name,data in chosen:
        p=Path(name);source=folder/'files'/p.relative_to('/')
        if source.is_symlink() and os.readlink(source)!=SAFE_SNAPSHOT_LINKS.get(str(p)):
            raise ValueError('Небезопасная символическая ссылка резервной копии: '+str(p))
        if p.is_symlink():
            if not safe_snapshot_link(p):raise ValueError('Объект восстановления является символической ссылкой: '+str(p))
            p.unlink()
        if source.exists() or source.is_symlink():
            if source.is_symlink():
                p.parent.mkdir(parents=True,exist_ok=True);p.unlink(missing_ok=True);p.symlink_to(os.readlink(source))
            elif source.is_file():
                p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,p)
        elif p.is_file() or p.is_symlink():p.unlink()
    # Remove only empty directories created by this transaction. Shared trees
    # and directories containing unknown files are never removed recursively.
    for rec in sorted(records,key=lambda x:len(Path(x['path']).parts),reverse=True):
        if rec['exists'] or rec['path'] not in selection:continue
        p=Path(rec['path'])
        if p.is_dir() and not p.is_symlink():
            for child in sorted((x for x in p.rglob('*') if x.is_dir() and not x.is_symlink()),key=lambda x:len(x.parts),reverse=True):
                try:child.rmdir()
                except OSError:pass
            try:p.rmdir()
            except OSError:pass

def uninstall_selection(records,own,compose,nginx):
    preserved={own,compose,nginx,'/etc/letsencrypt',
               '/etc/systemd/system/nuvrion-xhttp-firewall.service',
               '/root/nuvrion-xhttp-profile.json','/root/nuvrion-xhttp-extra.json',
               '/root/nuvrion-xhttp-host-settings.txt'}
    # Tuning runtime reports/boot markers are mutated by its own boot services.
    # Keep these records; strict ownership checks still protect static configs.
    return [r['path'] for r in records if r['path'] not in preserved and
            not immutable_path(r['path']) and r['path'] not in SECURITY_PATHS and
            r['path']!='/var/lib/nuvrion-traffic-control' and
            not r['path'].startswith(own+'/') and
            r['path']!='/var/lib/nuvrion-tuning' and
            not r['path'].startswith('/var/lib/nuvrion-tuning/')]

def run():
    action=sys.argv[1];args=sys.argv[2:]
    if action=='validate':validate(*args)
    elif action=='domain':print(valid_domain(args[0]))
    elif action=='public-key':
        import base64,subprocess
        private=base64.urlsafe_b64decode(sys.stdin.read().strip()+'=')
        if len(private)!=32:raise ValueError('Некорректный закрытый ключ X25519')
        der=bytes.fromhex('302e020100300506032b656e04220420')+private
        result=subprocess.run(['openssl','pkey','-inform','DER','-pubout','-outform','DER'],input=der,capture_output=True,check=True)
        print(base64.urlsafe_b64encode(result.stdout[-32:]).decode().rstrip('='))
    elif action=='secure-directory':secure_directory(args[0],int(args[1]))
    elif action=='profile-check':
        results=profile_checks(read(args[0]),len(args)>1 and args[1]=='new')
        for status,name in results:print(f'[{status}] {name}')
        if any(status=='FAIL' for status,_ in results):raise ValueError('Самопроверка профиля не пройдена')
    elif action=='tuning-check':
        for status,name in tuning_checks(*args):print(status,name,sep='\t')
    elif action=='nft-security-rules':print(nft_security_rules(args[0],args[1]=='1',json.load(sys.stdin),args[2] if len(args)>2 else 2222),end='')
    elif action=='nft-guard-check':check_nft_guard(args[0],args[1],json.load(sys.stdin))
    elif action=='iptables-guard-check':check_iptables_guard(args[0],args[1],args[2],args[3]=='1',sys.stdin.read())
    elif action=='ufw-guard-check':check_ufw_guard(args[0],args[1],args[2]=='1',sys.stdin.read())
    elif action=='owned-unit-check':check_owned_unit(args[0],args[1])
    elif action=='owned-unit-write':write_owned_unit(args[0],args[1],sys.stdin.read())
    elif action=='bundle-assets-preflight':
        names=[];seen=set()
        with tarfile.open(fileobj=sys.stdin.buffer,mode='r|gz') as tar:
            for member in tar:
                if not member.isfile() or member.name.startswith('/') or '..' in Path(member.name).parts or member.name in seen:raise ValueError('Небезопасный встроенный архив')
                seen.add(member.name)
                prefix='beer-atlas/public/'
                if member.name.startswith(prefix):names.append(member.name[len(prefix):])
        if 'index.html' not in names or 'beers.json' not in names:raise ValueError('Встроенный Атлас пива неполон')
        public=asset_collisions(names,args[0],str(OWN/'assets.json'))
        if public and (OWN/'assets.json').exists():raise ValueError('Новые сторонние файлы сайта не заменяются: '+', '.join(public[:5]))
        print(json.dumps(public,ensure_ascii=False))
    elif action=='external-ip':
        for url in ('https://api.ipify.org','https://ifconfig.me/ip'):
            try:
                with urllib.request.urlopen(url,timeout=10) as response:value=response.read(128).decode().strip()
                if ipaddress.ip_address(value).version==4:print(value);break
            except (OSError,ValueError):pass
    elif action=='dns':
        try:print(' '.join(sorted({x[4][0] for x in socket.getaddrinfo(args[0],None,socket.AF_INET)})))
        except socket.gaierror:print('')
    elif action=='get':
        obj=read(args[0])
        for part in args[1].split('.'):obj=obj.get(part,{}) if isinstance(obj,dict) else {}
        print(json.dumps(obj) if isinstance(obj,(dict,list,bool)) else obj)
    elif action=='parent-lock':
        # Certbot's subprocess closes inherited descriptors. Permit a hook
        # only while its actual ancestor still holds this root-owned lock.
        import fcntl
        owner=int(args[0]);pid=int(args[1]);lock=Path(args[2]);found=False
        if owner<=1 or owner==pid:raise ValueError('Некорректный владелец блокировки родительского процесса')
        for _ in range(128):
            stat=Path('/proc',str(pid),'stat').read_text()
            parent=int(stat[stat.rfind(')')+2:].split()[1])
            if parent==owner:found=True;break
            if parent<=1:break
            pid=parent
        proc=Path('/proc',str(owner));fd=proc/'fd/9'
        if not found or proc.stat().st_uid!=0 or not fd.exists() or not os.path.samefile(fd,lock):
            raise ValueError('Parent lock ancestry not verified')
        handle=os.open(lock,os.O_RDWR|os.O_CLOEXEC)
        try:
            try:fcntl.flock(handle,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:pass
            else:
                fcntl.flock(handle,fcntl.LOCK_UN)
                raise ValueError('Parent lock is no longer held')
        finally:os.close(handle)
    elif action=='set':
        obj=read(args[0]);obj[args[1]]=json.loads(args[2]);write(args[0],obj)
    elif action=='state':
        obj={k.lower():v for k,v in os.environ.items() if k in ('DOMAIN','PANEL_IP','NODE_PORT','EMAIL','NODE_TAG','XHTTP_PATH',
             'NODE_CONTAINER','NODE_SERVICE','PROJECT','WORKDIR','NGINX_KIND','NGINX_CONTAINER','NGINX_SERVICE',
             'NGINX_CONFIG','NGINX_MAIN','NGINX_ROOT','SITE_ROOT','WEB_GID','CERT_LINEAGE','XRAY_BIN','IPV4')}
        obj.update(read(STATE) if STATE.exists() else {})
        for k in list(obj):
            if k.upper() in os.environ:obj[k]=os.environ[k.upper()]
        obj['nginx_new']=os.environ['NGINX_NEW']=='1';obj['compose_files']=json.loads(os.environ['FILES_JSON'])
        obj['node_image_id']=os.environ['NODE_IMAGE_ID'];obj['nginx_image_id']=os.environ['NGINX_IMAGE_ID']
        obj.setdefault('initial_backup',os.environ['BACKUP']);obj['last_backup']=os.environ['BACKUP']
        obj['firewall']=os.environ['FW'];obj['trusted_xff']=os.environ['TRUSTED_XFF']=='1'
        obj['secure_sockets']=os.environ.get('SECURE_SOCKETS')=='1'
        obj['padding_supported']=padding_supported(os.environ.get('XRAY_VERSION',''))
        obj['harden_profile']=os.environ.get('HARDEN_PROFILE')=='1'
        obj['docker_hardening']=True
        write(STATE,obj)
    elif action=='nodes':
        items=json.load(sys.stdin)
        for c in items:
            env=c.get('Config',{}).get('Env',[]);image=c.get('Config',{}).get('Image','')
            if re.search(r'(?:^|/)remnawave/node(?::|@|$)',image) or any(x.startswith('NODE_PORT=') for x in env):print(c['Name'].lstrip('/'))
    elif action=='node-info':
        c=json.load(sys.stdin)[0];cfg=c['Config'];hc=c['HostConfig'];labels=cfg.get('Labels') or {}
        print(json.dumps({'name':c['Name'].lstrip('/'),'image':cfg['Image'],'image_id':c['Image'],
             'running':c['State']['Running'],'network_mode':hc['NetworkMode'],'mounts':c['Mounts'],
             'env_names':[x.split('=',1)[0] for x in cfg.get('Env',[])], 'capabilities':hc.get('CapAdd'),
             'security_opt':hc.get('SecurityOpt'),'restart':hc.get('RestartPolicy'),'labels':sorted(labels),
             'logging':hc.get('LogConfig'),'healthcheck_present':bool(cfg.get('Healthcheck')),
             'workdir':labels.get('com.docker.compose.project.working_dir',''),
             'files':labels.get('com.docker.compose.project.config_files',''),
             'service':labels.get('com.docker.compose.service',''),'project':labels.get('com.docker.compose.project',''),
             'node_port':next((x.split('=',1)[1] for x in cfg.get('Env',[]) if x.startswith('NODE_PORT=')),'2222')}))
    elif action=='nginx-info':
        text=sys.stdin.read();start,end,root,ds=server(text,args[0]);print(root)
    elif action=='nginx-template':print(nginx_template(read(STATE),args[0]))
    elif action=='patch-nginx':
        p=Path(args[0]);meta=read(args[4]) if Path(args[4]).exists() else None
        text,m=nginx_patch(p.read_text(),args[1],args[2],args[3],meta,read(STATE));write_nginx(p,text);write(args[4],m)
    elif action=='unpatch-nginx':
        p=Path(args[0]);text=strip_marked(p.read_text());meta=read(args[1])
        for old,new in meta.get('replacements',[]):
            if new not in text:raise ValueError('Директива сертификата изменена вне установщика')
            text=text.replace(new,old,1)
        write_nginx(p,text)
    elif action=='overlay':write(args[1],compose_override(read(STATE),read(args[0]),read(args[1]) if Path(args[1]).exists() else {}))
    elif action=='verify-compose':verify_compose(read(args[0]),read(args[1]),read(STATE))
    elif action=='profile':
        data=json.load(sys.stdin);src=read(args[0]) if args[0] else None
        state=read(STATE)
        p,e,h=profile(state,data['private'],data['public'],src);write(PROFILE,p);write(EXTRA,e);write(HOSTS,h)
        if state.get('harden_profile') and src:
            state['profile_pending']=any(i.get('listen')=='/dev/shm/xrxh.socket,0666' for i in src.get('inbounds',[]))
            write(STATE,state)
    elif action=='keys':
        d=read(args[0]);r=[x for x in d.get('inbounds',[]) if x.get('port')==443 and x.get('streamSettings',{}).get('security')=='reality']
        if len(r)==1:print(r[0]['streamSettings']['realitySettings']['privateKey']);print(r[0]['tag'])
    elif action=='releases':
        # List published Docker images, rather than GitHub releases that may
        # not yet have a pullable image. Ignore dev/RC and architecture aliases.
        versions=set();url='https://hub.docker.com/v2/repositories/remnawave/node/tags?page_size=100'
        for _ in range(5):
            if not url:break
            if not url.startswith('https://hub.docker.com/v2/repositories/remnawave/node/tags'):raise ValueError('Неожиданный адрес реестра образов')
            req=urllib.request.Request(url,headers={'User-Agent':'Nuvrion-XHTTP/1.0'})
            with urllib.request.urlopen(req,timeout=15) as response:data=json.load(response)
            for tag in data['results']:
                if re.fullmatch(r'\d+\.\d+\.\d+',tag['name']) and tag.get('images'):versions.add(tag['name'])
            url=data.get('next')
        for version in sorted(versions,key=lambda v:tuple(map(int,v.split('.'))),reverse=True):print(version)
    elif action=='fresh-compose':
        value={'services':{'remnanode':{'image':args[1],'container_name':'remnanode','network_mode':'host',
             'restart':'unless-stopped','env_file':[str(OWN/'node.env')],
             'labels':{'io.nuvrion.xhttp.installed':'true'},
             'security_opt':['no-new-privileges:true'],'pids_limit':1024,
             'volumes':[{'type':'bind','source':'/dev/shm','target':'/dev/shm'},
                        {'type':'bind','source':'/var/log/remnanode','target':'/var/log/remnanode'}],
             'ulimits':{'nofile':{'soft':1048576,'hard':1048576}},
             'logging':{'driver':'json-file','options':{'max-size':'10m','max-file':'3'}}}}}
        # Exclusive creation also protects a stopped/custom Compose appearing
        # between diagnostics and application of the installation plan.
        fd=os.open(args[0],os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'w',encoding='utf-8') as stream:json.dump(value,stream,indent=2);stream.write('\n')
    elif action=='delta':
        snapshot_delta(args[0],args[1])
    elif action=='rollback-delta':snapshot_delta(args[0],args[1],True,args[2:])
    elif action=='restore-delta':
        folder=safe_backup(args[0]);delta=read(args[1]);selection=json.load(sys.stdin)
        # Restore only files changed by this run, only while their recorded
        # contents still match. Foreign later edits are never discarded.
        for name,hashes in delta.items():
            if immutable_path(name):continue
            # Component files inside a broad snapshot (e.g. /etc/sysctl.d)
            # were already restored by their separate ownership manifest.
            if len(args)>2 and args[2]=='core' and (name in SECURITY_PATHS or name=='/var/lib/nuvrion-traffic-control' or name.startswith('/var/lib/nuvrion-traffic-control/')):continue
            if not any(name==x or name.startswith(x.rstrip('/')+'/') for x in selection):continue
            p=Path(name);old=folder/'files'/p.relative_to('/')
            if digest(p)!=hashes['after']:raise ValueError('Восстановление запрещено: файл позже изменён пользователем: '+name)
            if old.is_symlink():
                p.unlink(missing_ok=True);p.symlink_to(os.readlink(old))
            elif old.is_file():
                p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(old,p)
            elif p.is_file() or p.is_symlink():p.unlink()
    elif action=='xff-version':
        # Present and implemented in the verified v26.3.27 release and later.
        m=re.search(r'Xray\s+(\d+)\.(\d+)\.(\d+)',args[0])
        print('1' if m and tuple(map(int,m.groups()))>=(26,3,27) else '0')
    elif action=='snapshot':snapshot(args[0],json.load(sys.stdin))
    elif action=='restore':restore(args[0],json.load(sys.stdin),args[1])
    elif action=='restore-check':restore(args[0],json.load(sys.stdin),args[1],True)
    elif action=='rollback-runtime-journal':
        journal=read(args[0])
        # These files may be changed by our own explicit security_stop before
        # applying the already validated rollback; no shared files are adopted.
        for name,data in journal.items():
            if name.startswith('/var/lib/nuvrion-traffic-control/'):
                data['after']=digest(name)
        write(args[0],journal)
    elif action=='uninstall-selection':print(json.dumps(uninstall_selection(read(args[0]),*args[1:])))
    elif action=='security-paths':print(json.dumps(SECURITY_PATHS))
    elif action=='tls-audit':
        for status,name in tls_audit(read(args[0])):print(status,name,sep='\t')
    elif action=='security-selection':
        owned=read(args[0]);paths=list(SECURITY_PATHS)
        if not owned.get('traffic_owned'):paths=[p for p in paths if 'traffic-control' not in p and p!='/usr/local/bin/ntc']
        if not owned.get('privacy_owned'):paths=[p for p in paths if 'two-way-ping' not in p]
        print(json.dumps(paths))
    elif action=='rollback-selection':
        owned=read(args[1]) if Path(args[1]).exists() else {}
        allowed=set(SECURITY_PATHS)
        if not owned.get('traffic_owned'):allowed={p for p in allowed if 'traffic-control' not in p and p!='/usr/local/bin/ntc'}
        if not owned.get('privacy_owned'):allowed={p for p in allowed if 'two-way-ping' not in p}
        print(json.dumps([r['path'] for r in read(args[0]) if not immutable_path(r['path']) and r['path']!='/etc/letsencrypt' and
            (r['path'] not in SECURITY_PATHS or r['path'] in allowed) and
            (r['path']!='/var/lib/nuvrion-traffic-control' or owned.get('traffic_owned'))]))
    elif action=='nft-chains':
        for x in json.load(sys.stdin).get('nftables',[]):
            c=x.get('chain',{})
            if c.get('hook')=='input' and c.get('family') in ('inet','ip','ip6') and c.get('table')!='nuvrion_xhttp' and (not args or c.get('table') not in ('nuvrion_tc','nuvrion_privacy')):
                print(c['family'],c['table'],c['name'],sep='\t')
    elif action=='nft-native-chains':
        for x in json.load(sys.stdin).get('nftables',[]):
            c=x.get('chain',{})
            if c.get('hook')=='input' and c.get('family') in ('inet','ip','ip6') and c.get('table')!='nuvrion_xhttp':
                if c.get('family') in ('ip','ip6') and c.get('table')=='filter' and c.get('name')=='INPUT':continue
                print(c['family'],c['table'],c['name'],sep='\t')
    elif action=='runtime-after':
        import subprocess
        keys={'net.core.rps_sock_flow_entries','net.netfilter.nf_conntrack_max','net.netfilter.nf_conntrack_buckets'}
        declared=OWN/'runtime-keys.json'
        if declared.exists():keys.update(read(declared))
        for root in ('/etc/sysctl.d','/run/sysctl.d','/usr/local/lib/sysctl.d'):
            for p in Path(root).glob('*nuvrion*.conf'):
                for line in p.read_text().splitlines():
                    m=re.match(r'^\s*(-?[A-Za-z0-9_.]+)\s*=',line)
                    if m:keys.add(m[1].lstrip('-'))
        values={}
        for k in keys:
            r=subprocess.run(['sysctl','-n',k],capture_output=True,text=True)
            if r.returncode==0:values[k]=r.stdout.strip()
        write(args[0],values)
    elif action=='runtime-keys':
        # Declare the pinned tuner's keys BEFORE it writes any runtime sysctl.
        # If it fails during its first loop, the completed .conf may not exist.
        keys=sorted(set(re.findall(r'\b(?:net|kernel|fs|vm)\.[A-Za-z0-9_.]+',Path(args[0]).read_text())))
        write(args[1],keys)
    elif action=='rps-snapshot':
        values={str(p):p.read_text().strip() for p in Path('/sys/class/net').glob('*/queues/rx-*/rps_*') if p.is_file()}
        write(args[0],values)
    elif action=='rps-restore':
        if Path(args[0]).exists() and Path(args[1]).exists():
            before=read(args[0]);after=read(args[1])
            for name,value in before.items():
                p=Path(name)
                if p.exists() and p.read_text().strip()==after.get(name) and value!=after.get(name):p.write_text(value+'\n')
    elif action=='nft-owned':
        for x in json.load(sys.stdin).get('nftables',[]):
            r=x.get('rule',{})
            if r.get('comment')==args[0]:print(r['family'],r['table'],r['chain'],r['handle'],sep='\t')
    elif action=='assets':
        source=Path(args[0]);dest=Path(args[1]);old=read(args[2]) if Path(args[2]).exists() else {}
        names=[p.relative_to(source).as_posix() for p in source.rglob('*') if p.is_file()]
        collisions=asset_collisions(names,dest,args[2])
        if collisions and (len(args)<4 or args[3]!='1' or old):
            raise ValueError('Сторонние файлы сайта не заменяются без подтверждённого плана: '+', '.join(collisions[:5]))
        result={}
        for p in sorted(source.rglob('*')):
            if p.is_symlink():raise ValueError('Архив сайта содержит символическую ссылку')
            if p.is_file():
                name=p.relative_to(source).as_posix();target=safe_asset_path(dest/name)
                target.parent.mkdir(parents=True,exist_ok=True,mode=0o755);target.parent.chmod(0o755)
                fd,tmp=tempfile.mkstemp(prefix='.'+target.name+'.',dir=target.parent)
                try:
                    with os.fdopen(fd,'wb') as stream,p.open('rb') as incoming:
                        os.fchmod(stream.fileno(),0o644);shutil.copyfileobj(incoming,stream)
                        stream.flush();os.fsync(stream.fileno())
                    os.replace(tmp,target)
                finally:
                    if os.path.exists(tmp):os.unlink(tmp)
                result[name]=digest(target)
        # Remove only obsolete files whose hashes were verified before writes.
        # Untracked files are preserved and rollback restores removed old assets.
        for name in sorted(set(old)-set(result)):
            target=safe_asset_path(dest/name)
            if target.exists():
                if digest(target)!=old[name]:raise ValueError('Файл сайта изменён во время обновления: '+name)
                target.unlink()
        write(args[2],result)
    elif action=='asset-check':
        dest=Path(args[0]);expected=read(args[1])
        for name,h in expected.items():
            if digest(dest/name)!=h:raise ValueError('Сайт изменён после установки: '+name)
    elif action=='unpack':
        with tarfile.open(args[0],'r:gz') as tar:
            members=tar.getmembers();names=set();dest=Path(args[1])
            for m in members:
                path=Path(m.name)
                if not m.isfile() or path.is_absolute() or '..' in path.parts or not path.parts or m.name in names:
                    raise ValueError('Небезопасный встроенный архив')
                names.add(m.name)
            # Write regular file contents only: no archive ownership, links or
            # special modes, and no dependency on newer tar extraction filters.
            dest.mkdir(mode=0o700)
            for m in members:
                target=dest/m.name;target.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
                with tar.extractfile(m) as source, target.open('xb') as output:
                    os.fchmod(output.fileno(),0o600);shutil.copyfileobj(source,output)
    elif action=='hook':
        # Preserve foreign hook commands; attach one owned command exactly once.
        p=Path(args[0]);op=args[1];original=Path(args[2]);owned=args[3]
        text=p.read_text();original.parent.mkdir(parents=True,exist_ok=True)
        if not original.exists():write(original,text)
        text=re.sub(r'(?m)^# BEGIN NUVRION XHTTP HOOKS\n.*?^# END NUVRION XHTTP HOOKS\n?','',text,flags=re.S)
        baseline=original.read_text();hooks={}
        for name in ('pre_hook','post_hook','deploy_hook','renew_hook'):
            m=re.search(r'(?m)^'+name+r'\s*=\s*(.*)$',baseline)
            if m:hooks[name]=m[1]
        standalone=bool(re.search(r'(?m)^authenticator\s*=\s*standalone\s*$',text))
        if standalone:
            hooks['pre_hook']=(hooks.get('pre_hook','')+' && ' if hooks.get('pre_hook') else '')+owned+' --acme-pre'
            hooks['post_hook']=owned+' --acme-post'+('; '+hooks['post_hook'] if hooks.get('post_hook') else '')
        hooks['deploy_hook']=(hooks.get('deploy_hook','')+' && ' if hooks.get('deploy_hook') else '')+owned+' --acme-deploy'
        text=re.sub(r'(?m)^(pre_hook|post_hook|deploy_hook|renew_hook)\s*=.*\n?','',text)
        text+='\n# BEGIN NUVRION XHTTP HOOKS\n'+'\n'.join(k+' = '+v for k,v in hooks.items())+'\n# END NUVRION XHTTP HOOKS\n'
        write(p,text)
    elif action=='unhook':
        p=Path(args[0]);original=Path(args[1]);text=p.read_text();baseline=original.read_text()
        text=re.sub(r'(?m)^# BEGIN NUVRION XHTTP HOOKS\n.*?^# END NUVRION XHTTP HOOKS\n?','',text,flags=re.S)
        for name in ('pre_hook','post_hook','deploy_hook','renew_hook'):
            text=re.sub(r'(?m)^'+name+r'\s*=.*\n?','',text)
            m=re.search(r'(?m)^'+name+r'\s*=\s*(.*)$',baseline)
            if m:text+='\n'+name+' = '+m[1]+'\n'
        write(p,text)
    else:raise ValueError('Неизвестное действие вспомогательной программы: '+action)

if __name__=='__main__':
    try:run()
    except (ValueError,KeyError,OSError,json.JSONDecodeError) as e:
        # No configuration values/private keys are included in command logs.
        print('Nuvrion: '+str(e),file=sys.stderr);sys.exit(1)
NUVRION_PY
)" "$@"
}

jget() {
    python3 -c 'import json,sys;v=json.load(sys.stdin)
for k in sys.argv[1].split("."):v=v[int(k)] if isinstance(v,list) else v.get(k,"")
print(json.dumps(v) if isinstance(v,(dict,list,bool)) else v)' "$1"
}
state_value() { [[ -f $STATE ]] && helper get "$STATE" "$1" || true; }
load_settings() {
    [[ -f $STATE ]] || return 0
    [[ -O $STATE && ! -L $STATE && $(stat -c %a "$STATE") == 600 ]] || die 1 'Небезопасные права state.json; ожидаются root и 0600.'
    local name value
    for name in DOMAIN PANEL_IP EMAIL NODE_TAG NODE_CONTAINER; do
        value=$(state_value "${name,,}")
        [[ -n ${!name} || $value == '{}' ]] || printf -v "$name" '%s' "$value"
    done
    if [[ $PATH_EXPLICIT == 0 ]]; then value=$(state_value xhttp_path); [[ $value == '{}' ]] || XHTTP_PATH=$value; fi
    if [[ $NODE_PORT_EXPLICIT == 0 ]];then value=$(state_value node_port);[[ $value == '{}' ]] || NODE_PORT=$value;fi
    validate_node_port
    [[ $(state_value secure_sockets) != true ]] || SECURE_SOCKETS=1
    socket_settings
}
socket_settings() {
    if (( SECURE_SOCKETS==1 ));then
        NGINX_SOCKET=/dev/shm/nuvrion-xhttp/nginx.sock
        XHTTP_SOCKET=/dev/shm/nuvrion-xhttp/xrxh.socket
    else NGINX_SOCKET=/dev/shm/nginx.sock;XHTTP_SOCKET=/dev/shm/xrxh.socket;fi
}
configure_socket_directory() {
    (( SECURE_SOCKETS==1 )) || return 0
    if [[ -e /dev/shm/nuvrion-xhttp || -e /etc/tmpfiles.d/nuvrion-xhttp.conf ]];then
        [[ -f $STATE && $(state_value secure_sockets) == true ]] || die 6 'Найден чужой каталог сокетов или tmpfiles; автоматическая перезапись запрещена.'
    fi
    [[ -d /dev/shm/nuvrion-xhttp ]] || SOCKET_DIR_CREATED=1
    helper secure-directory /dev/shm/nuvrion-xhttp "$WEB_GID"
    printf 'd /dev/shm/nuvrion-xhttp 2710 root %s - -\n' "$WEB_GID" > /etc/tmpfiles.d/nuvrion-xhttp.conf
    chmod 644 /etc/tmpfiles.d/nuvrion-xhttp.conf
    log_ok 'Общий каталог сокетов: root:группа Nginx 2710; XHTTP 0660; Nginx 0600.'
}
detect_network() {
    IPV4=''; A_RECORDS=''
    if command -v curl >/dev/null; then
        local endpoint value
        for endpoint in https://api.ipify.org https://ifconfig.me/ip; do
            value=$(curl --noproxy '*' -4 -fsS --connect-timeout 5 --max-time 10 "$endpoint" 2>/dev/null || true)
            if python3 -c 'import ipaddress,sys;assert ipaddress.ip_address(sys.argv[1]).version==4' "$value" 2>/dev/null; then IPV4=$value;break;fi
        done
    else IPV4=$(helper external-ip);fi
    [[ -z $DOMAIN ]] || A_RECORDS=$(helper dns "$DOMAIN")
    log_info "Внешний IPv4: ${IPV4:-не определён}; A ${DOMAIN:-—}: ${A_RECORDS:-не найден}"
}
validate_domain_address() {
    [[ -n $IPV4 && -n $A_RECORDS ]] || die 4 'Установка отменена: не удалось проверить внешний IPv4 или DNS A домена. Исправьте DNS/доступ к сети.'
    local address
    for address in $A_RECORDS;do
        [[ $address == "$IPV4" ]] || die 4 "Установка отменена: DNS A домена $DOMAIN ($A_RECORDS) не совпадает с IPv4 сервера $IPV4. Исправьте A-запись и повторите запуск."
    done
    log_ok 'Все DNS A-записи домена совпадают с внешним IPv4 сервера.'
}
compose_command() {
    COMPOSE_CMD=(docker compose --project-directory "$WORKDIR" -p "$PROJECT")
    local file
    for file in "${COMPOSE_FILES[@]}"; do COMPOSE_CMD+=(-f "$file"); done
}
owned_stopped_node() {
    # Restart only a fresh node actually created by this installer. A matching
    # name alone is not ownership, and a foreign stopped node stays untouched.
    local info=$1
    [[ -f $STATE && ! -L $STATE && -O $STATE && $(stat -c %a "$STATE") == 600 &&
       -f $OWN/owned-delta.json && ! -L $OWN/owned-delta.json && -O $OWN/owned-delta.json &&
       $(stat -c %a "$OWN/owned-delta.json") == 600 ]] || return 3
    [[ $(docker inspect -f '{{index .Config.Labels "io.nuvrion.xhttp.installed"}}' "$NODE_CONTAINER") == true ]] || return 3
    python3 -c 'import hashlib,json,pathlib,sys
state=json.load(open(sys.argv[1]));delta=json.load(open(sys.argv[2]));info=json.load(sys.stdin)
if state.get("node_new") is not True or state.get("removed") is True:raise SystemExit(3)
for key,actual in (("node_container",info["name"]),("node_service",info["service"]),
                   ("project",info["project"]),("workdir",info["workdir"]),("node_image_id",info["image_id"])):
 if state.get(key)!=actual:raise SystemExit(3)
if not info["image_id"].startswith("sha256:"):raise SystemExit(3)
compose=pathlib.Path(sys.argv[3]);record=delta.get(str(compose),{})
if compose.is_symlink() or not compose.is_file() or record.get("before") is not None:raise SystemExit(3)
if not record.get("after") or hashlib.sha256(compose.read_bytes()).hexdigest()!=record["after"]:raise SystemExit(3)
' "$STATE" "$OWN/owned-delta.json" "$BASE/docker-compose.yml" <<< "$info"
}
node_probe() {
    if (( NODE_STOPPED==0 ));then docker exec "$NODE_CONTAINER" "$@"
    else
        local -a user_args=()
        [[ -z $NODE_PROBE_USER ]] || user_args=(--user "$NODE_PROBE_USER")
        # Never start the real node, attach its volumes/environment or pull a
        # mutable tag during discovery. Only the existing exact image is used.
        docker run --rm --network none --read-only --cap-drop ALL \
          --security-opt no-new-privileges:true --pull never "${user_args[@]}" \
          --entrypoint "$1" "$NODE_IMAGE_ID_DETECTED" "${@:2}"
    fi
}
assert_stopped_node_ports_free() {
    local listeners
    listeners=$(ss -H -lnt "( sport = :443 or sport = :$NODE_PORT )") || die 3 'Не удалось проверить порты остановленной ноды.'
    [[ -z $listeners ]] || die 3 "Порты 443/$NODE_PORT заняты: остановленная нода не будет запущена поверх другого сервиса."
}
detect_remnanode() {
    local mode=${1:-running}
    [[ $mode == running || $mode == allow-stopped || $mode == metadata ]] || return 3
    NODE_STOPPED=0;NODE_IMAGE_ID_DETECTED='';NODE_PROBE_USER=''
    command -v docker >/dev/null && docker info >/dev/null 2>&1 || return 3
    docker compose version >/dev/null 2>&1 || return 3
    local containers info files candidate
    mapfile -t containers < <(docker ps -aq)
    ((${#containers[@]})) || return 3
    if [[ -z $NODE_CONTAINER ]]; then
        mapfile -t containers < <(docker inspect "${containers[@]}" | helper nodes)
        ((${#containers[@]} == 1)) || { log_warn 'Нужен один Remnanode; при нескольких используйте --node-container.';return 3; }
        NODE_CONTAINER=${containers[0]}
    fi
    info=$(docker inspect "$NODE_CONTAINER" | helper node-info) || return 3
    NODE_SERVICE=$(jget service <<< "$info"); PROJECT=$(jget project <<< "$info"); WORKDIR=$(jget workdir <<< "$info")
    files=$(jget files <<< "$info")
    [[ -n $NODE_SERVICE && -n $PROJECT && -d $WORKDIR && -n $files ]] || { log_warn 'У ноды отсутствуют Compose-метаданные. Безопасная автоматическая правка невозможна.';return 3; }
    DETECTED_NODE_PORT=$(jget node_port <<< "$info")
    [[ $NODE_PORT_EXPLICIT == 0 || $NODE_PORT == "$DETECTED_NODE_PORT" ]] || { log_warn "Установленная нода использует API :$DETECTED_NODE_PORT. Изменение её порта автоматически не выполняется.";return 3; }
    NODE_PORT=$DETECTED_NODE_PORT;validate_node_port
    [[ $(jget network_mode <<< "$info") == host ]] || { log_warn 'Для схемы Nuvrion требуется уже настроенный network_mode: host.';return 3; }
    IFS=',' read -r -a COMPOSE_FILES <<< "$files"
    # A fresh node may not need recreation when the first override is added;
    # its Docker label then still lists only the base file. Retain our overlay
    # from the ownership record instead of recreating Nginx on every rerun.
    if [[ -f $STATE && -f $OVERRIDE && $(state_value project) == "$PROJECT" && $(state_value removed) != true && ,$files, != *,"$OVERRIDE",* ]];then
        COMPOSE_FILES+=("$OVERRIDE")
    fi
    for candidate in "${!COMPOSE_FILES[@]}"; do
        [[ ${COMPOSE_FILES[candidate]} == /* ]] || COMPOSE_FILES[candidate]=$WORKDIR/${COMPOSE_FILES[candidate]}
        [[ -f ${COMPOSE_FILES[candidate]} && ! -L ${COMPOSE_FILES[candidate]} ]] || return 3
    done
    compose_command
    NODE_IMAGE_ID_DETECTED=$(jget image_id <<< "$info")
    if [[ $(jget running <<< "$info") != true ]];then
        if [[ $mode == running ]] || ! owned_stopped_node "$info";then
            log_warn 'Остановленная нода не подтверждена как собственная; автоматический запуск запрещён.';return 3
        fi
        NODE_STOPPED=1
        NODE_PROBE_USER=$(docker inspect -f '{{.Config.User}}' "$NODE_CONTAINER") || return 3
        log_info 'Собственная Remnanode остановлена; восстановление запуска планируется после backup.'
    fi
    log_info "Remnanode: $NODE_CONTAINER; service=$NODE_SERVICE; project=$PROJECT"
    log_info "Образ: $(jget image <<< "$info"); сеть: host; API: $NODE_PORT"
    log_info "Переменные окружения (только имена): $(jget env_names <<< "$info")"
    log_info "Capabilities: $(jget capabilities <<< "$info"); security_opt: $(jget security_opt <<< "$info")"
    log_info "Политика перезапуска: $(jget restart <<< "$info"); проверка работоспособности: $(jget healthcheck_present <<< "$info")"
    log_info "Журналирование: $(jget logging <<< "$info"); метки (имена): $(jget labels <<< "$info")"
    docker inspect -f '{{range .Mounts}}{{println .Source "->" .Destination "rw=" .RW}}{{end}}' "$NODE_CONTAINER"
    XRAY_BIN=''; XRAY_VERSION='unknown'
    # Config restoration needs Compose identity, not a working Xray process.
    [[ $mode != metadata ]] || return 0
    for candidate in /usr/local/bin/rw-core /usr/local/bin/xray xray; do
        if XRAY_VERSION=$(node_probe "$candidate" version 2>/dev/null); then XRAY_BIN=$candidate;break;fi
    done
    XRAY_VERSION=${XRAY_VERSION%%$'\n'*}
    [[ -n $XRAY_BIN ]] || { XRAY_VERSION='unknown';return 3; }
    log_info "$XRAY_VERSION ($XRAY_BIN)"
}
map_container_path() {
    docker inspect "$1" | python3 -c 'import json,pathlib,sys
p=sys.argv[1];matches=[]
for m in json.load(sys.stdin)[0]["Mounts"]:
 d=m["Destination"].rstrip("/")
 if m["Type"]=="bind" and (p==d or p.startswith(d+"/")):matches.append((len(d),m["Source"]+p[len(d):]))
print(max(matches)[1] if matches else "")' "$2"
}
nginx_source() {
    python3 -c 'import re,sys
text=sys.stdin.read();domain=sys.argv[1]
for m in re.finditer(r"(?m)^# configuration file ([^\n]+):\n",text):
 end=text.find("\n# configuration file ",m.end());chunk=text[m.end():end if end>=0 else len(text)]
 if re.search(r"server_name\s+[^;]*\b"+re.escape(domain)+r"\b",chunk) and re.search(r"unix:/dev/shm/(?:nuvrion-xhttp/)?nginx\.sock",chunk):
  print(m[1]);break' "$DOMAIN"
}
detect_nginx() {
    NGINX_KIND='';NGINX_CONTAINER='';NGINX_NEW=0
    local container dump source hostroot candidates=0 main user
    while IFS= read -r container; do
        [[ -n $container ]] || continue
        dump=$(docker exec "$container" nginx -T 2>&1 || true)
        [[ $dump == *"unix:$NGINX_SOCKET"* ]] || continue
        source=$(nginx_source <<< "$dump")
        [[ -n $source ]] || { log_warn "Nginx $container занимает nginx.sock, но server_name $DOMAIN не найден.";return 5; }
        NGINX_KIND=docker;NGINX_CONTAINER=$container
        NGINX_CONFIG=$(map_container_path "$container" "$source")
        [[ -f $NGINX_CONFIG && ! -L $NGINX_CONFIG ]] || { log_warn 'Конфигурация Nginx не является обычным файлом, подключённым через bind mount.';return 5; }
        hostroot=$(helper nginx-info "$DOMAIN" < "$NGINX_CONFIG") || return 5
        NGINX_ROOT=$hostroot;SITE_ROOT=$(map_container_path "$container" "$hostroot")
        [[ -n $SITE_ROOT && $SITE_ROOT == /* && ! -L $SITE_ROOT ]] || return 5
        NGINX_MAIN=$(sed -n 's/^# configuration file \([^:]*\):$/\1/p' <<< "$dump" | sed -n '1p')
        NGINX_SERVICE=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$container")
        local ngproject
        ngproject=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$container")
        [[ $ngproject == "$PROJECT" && -n $NGINX_SERVICE ]] || { log_warn 'Nginx и нода принадлежат разным Compose-проектам; автоматическая правка остановлена.';return 5; }
        user=$(sed -nE 's/^user[[:space:]]+([^; ]+).*;/\1/p' <<< "$dump" | sed -n '1p')
        WEB_GID=$(docker exec "$container" id -g "${user:-nginx}") || return 5
        candidates=$((candidates+1))
    done < <(docker ps --format '{{.Names}}' 2>/dev/null || true)
    (( candidates<=1 )) || { log_warn 'Несколько владельцев nginx.sock.';return 5; }
    if (( candidates==0 )) && command -v nginx >/dev/null; then
        main=$(ps -C nginx -o args= | sed -nE 's/.*master process:.* -c ([^ ]+).*/\1/p' | sed -n '1p')
        main=${main:-/etc/nginx/nginx.conf}
        dump=$(nginx -T -c "$main" 2>&1 || true)
        if [[ $dump == *"unix:$NGINX_SOCKET"* ]]; then
            source=$(nginx_source <<< "$dump");[[ -f $source && ! -L $source ]] || return 5
            NGINX_KIND=host;NGINX_CONFIG=$source;NGINX_MAIN=$main
            SITE_ROOT=$(helper nginx-info "$DOMAIN" < "$source") || return 5
            NGINX_ROOT=$SITE_ROOT
            user=$(sed -nE 's/^user[[:space:]]+([^; ]+).*;/\1/p' <<< "$dump" | sed -n '1p')
            WEB_GID=$(id -g "${user:-www-data}") || return 5
        elif pgrep -x nginx >/dev/null; then
            log_warn 'Найден сторонний Nginx на хосте без сокета selfsteal. Нужна явная адаптация его конфигурации; второй Nginx не создаётся.';return 5
        fi
    fi
    if [[ -z $NGINX_KIND && -f $STATE && $(state_value nginx_new) == true ]];then
        NGINX_KIND=docker;NGINX_NEW=1;NGINX_SERVICE=$(state_value nginx_service)
        NGINX_CONFIG=$(state_value nginx_config);NGINX_MAIN=$(state_value nginx_main)
        NGINX_ROOT=$(state_value nginx_root);SITE_ROOT=$(state_value site_root);WEB_GID=$(state_value web_gid)
    fi
    if [[ -z $NGINX_KIND ]]; then
        [[ ! -S /dev/shm/nginx.sock ]] || { log_warn 'nginx.sock существует, владелец не определён.';return 5; }
        NGINX_KIND=docker;NGINX_NEW=1;NGINX_SERVICE=nuvrion-xhttp-nginx
        NGINX_CONFIG=$OWN/nginx.conf;NGINX_MAIN=/etc/nginx/nginx.conf
        NGINX_ROOT=/var/www/decoy;SITE_ROOT=$OWN/decoy;WEB_GID=33
        [[ ! -f $STATE ]] || NGINX_NEW=$(state_value nginx_new | sed 's/true/1/;s/false/0/')
    fi
    if [[ -f $STATE && $(state_value nginx_new) == true ]];then NGINX_NEW=1;fi
    [[ $SITE_ROOT != / && $SITE_ROOT != /etc && $SITE_ROOT != /opt/remnanode ]] || return 5
    log_info "Nginx: $NGINX_KIND ${NGINX_CONTAINER:-$NGINX_SERVICE}; конфигурация: $NGINX_CONFIG; сайт: $SITE_ROOT"
}
detect_firewall() {
    FW=''
    local managed
    managed=$(state_value firewall)
    if [[ $managed == ufw || $managed == nft || $managed == iptables ]];then
        FW=$managed
    elif command -v ufw >/dev/null && ufw status 2>/dev/null | grep '^Status: active' >/dev/null; then FW=ufw
    elif command -v nft >/dev/null && nft -j list ruleset 2>/dev/null | helper nft-native-chains | grep . >/dev/null; then FW=nft
    elif command -v iptables >/dev/null && command -v ip6tables >/dev/null; then FW=iptables
    elif command -v nft >/dev/null; then FW=nft
    fi
    log_info "Брандмауэр: ${FW:-не обнаружен; потребуется nftables}"
}
scrub() { sed -E '/privateKey|SECRET_KEY|[Tt]oken|[Pp]assword|Authorization|BEGIN .*PRIVATE KEY/c\[секретная строка скрыта]'; }
nginx_command() {
    if [[ $NGINX_KIND == docker ]]; then docker exec "$NGINX_CONTAINER" nginx "$@" -c "$NGINX_MAIN"
    else nginx "$@" -c "$NGINX_MAIN"; fi
}
validate_nginx() {
    [[ -n $NGINX_KIND ]] || return 5
    nginx_command -t || return 5
}
reload_nginx() {
    validate_nginx || die 5 'Проверка nginx -t не пройдена; перезагрузка конфигурации запрещена.'
    nginx_command -s reload
}
check_result() {
    local ok=$1 title=$2
    if [[ $ok == 1 ]]; then log_ok "$title"
    else log_error "$title";FAILS=$((FAILS+1));fi
}
validate_sockets() {
    local path inode inner container
    for path in "$NGINX_SOCKET" "$XHTTP_SOCKET"; do
        if [[ ! -S $path ]]; then
            if [[ $path == "$XHTTP_SOCKET" && ! -f $OWN/profile-applied ]]; then
                WAITS=$((WAITS+1));log_warn 'Ожидание: xrxh.socket: ожидает применения профиля Remnawave';continue
            fi
            check_result 0 "$path существует";continue
        fi
        stat -c '  %n: %F %a %U:%G inode=%i' "$path";ls -lah "$path"
        if (( SECURE_SOCKETS==1 ));then
            local expected=660
            [[ $path != "$NGINX_SOCKET" ]] || expected=600
            if [[ $(stat -c %a "$path") == "$expected" && $(stat -c %u "$path") == 0 && $(stat -c %g "$path") == "$WEB_GID" ]];then
                check_result 1 "$path ограниченные права доступа"
            else check_result 0 "$path ограниченные права доступа";fi
        fi
        inode=$(stat -c '%d:%i' "$path")
        for container in "$NODE_CONTAINER" "$NGINX_CONTAINER"; do
            [[ -n $container ]] || continue
            inner=$(docker exec "$container" stat -c '%d:%i' "$path" 2>/dev/null || true)
            if [[ $inner == "$inode" ]]; then check_result 1 "$container видит тот же $path"
            else check_result 0 "$container видит тот же $path";fi
        done
    done
    ss -xlpn | grep -E 'nginx.sock|xrxh.socket' || true
}
validate_https() {
    [[ -n $DOMAIN ]] || return 0
    DECOY_CODE=$(curl --noproxy '*' --resolve "$DOMAIN:443:127.0.0.1" -sS --connect-timeout 5 --max-time 20 -o /dev/null -w '%{http_code}' "https://$DOMAIN/" 2>/dev/null || true)
    ROUTE_CODE=$(curl --noproxy '*' --resolve "$DOMAIN:443:127.0.0.1" -sS --connect-timeout 5 --max-time 20 -o /dev/null -w '%{http_code}' "https://$DOMAIN$XHTTP_PATH" 2>/dev/null || true)
    if [[ $DECOY_CODE == 200 ]]; then check_result 1 'HTTPS сайта декой: HTTP 200; TLS проверен'
    elif (( WAITS>0 )) && [[ ! -f $OWN/profile-applied ]]; then WAITS=$((WAITS+1));log_warn "Ожидание: HTTPS сайта декой: $DECOY_CODE; примените Reality inbound"
    else check_result 0 "HTTPS сайта декой: $DECOY_CODE";fi
    if [[ -S $XHTTP_SOCKET ]]; then
        local direct
        direct=$(curl --noproxy '*' --unix-socket "$XHTTP_SOCKET" -sS --max-time 10 -H "Host: $DOMAIN" -o /dev/null -w '%{http_code}' "http://localhost$XHTTP_PATH" 2>/dev/null || true)
        if [[ $ROUTE_CODE == 400 && $direct == 400 ]]; then check_result 1 'XHTTP: HTTP 400 совпадает с прямым ответом backend'
        else check_result 0 "XHTTP backend: proxy=$ROUTE_CODE direct=$direct; ожидается 400/400";fi
    else log_warn "Ожидание: Маршрут XHTTP: $ROUTE_CODE; сокет ещё не создан панелью";fi
}
diagnostic_logs() {
    local output
    output=$(docker logs --since 3m --tail 120 "$NODE_CONTAINER" 2>&1 | tr -d '\000' || true)
    if [[ -n $NGINX_CONTAINER ]]; then output+=$'\n'$(docker logs --since 3m --tail 120 "$NGINX_CONTAINER" 2>&1 | tr -d '\000' || true)
    elif [[ -f /var/log/nginx/error.log ]]; then output+=$'\n'$(tail -n 60 /var/log/nginx/error.log | tr -d '\000');fi
    local errors
    errors=$(grep -Ei 'connect\(\).*xrxh.socket.*failed|permission denied|address already in use|duplicate inbound|failed to listen|invalid config' <<< "$output" || true)
    # A missing backend before panel application is expected, never marked PASS.
    if [[ ! -S $XHTTP_SOCKET && ! -f $OWN/profile-applied ]]; then errors=$(grep -Eiv 'connect\(\).*xrxh.socket.*No such file' <<< "$errors" || true);fi
    if [[ -n $errors ]]; then printf '%s\n' "$errors" | scrub;check_result 0 'Свежие ошибки nginx/Xray'
    else check_result 1 'Критических ошибок nginx/Xray за последние 3 минуты не найдено';fi
}
validate_firewall_and_preservation() {
    [[ -f $STATE ]] || return 0
    local ok=1 backupfile file api_only=0
    [[ $(state_value removed) != true ]] || api_only=1
    case $FW in
        ufw)
            ufw status numbered | helper ufw-guard-check "$PANEL_IP" "$NODE_PORT" "$api_only" || ok=0;;
        nft)
            nft -a -j list ruleset | helper nft-guard-check "$PANEL_IP" "$NODE_PORT" || ok=0;;
        iptables)
            iptables -S | helper iptables-guard-check "$PANEL_IP" "$NODE_PORT" 4 "$api_only" || ok=0
            ip6tables -S | helper iptables-guard-check "$PANEL_IP" "$NODE_PORT" 6 "$api_only" || ok=0;;
        *) ok=0;;
    esac
    check_result "$ok" 'Брандмауэр: ограничения API присутствуют для IPv4/IPv6'
    if systemctl is-active --quiet certbot.timer && systemctl is-enabled --quiet certbot.timer;then check_result 1 'Таймер продления Certbot активен и включён'
    else check_result 0 'Таймер продления Certbot активен и включён';fi
    backupfile=$(state_value last_backup)
    if [[ -f $backupfile/ssh.sha256 ]];then
        if sha256sum -c --status "$backupfile/ssh.sha256";then check_result 1 'Конфигурация и ключи SSH не изменены'
        else check_result 0 'Конфигурация и ключи SSH не изменены';fi
    fi
    for file in "${COMPOSE_FILES[@]}";do
        [[ $file != "$OVERRIDE" && -f $backupfile/files$file ]] || continue
        if cmp -s "$file" "$backupfile/files$file";then check_result 1 "Исходный Compose сохранён: $file"
        else check_result 0 "Исходный Compose сохранён: $file";fi
    done
}
run_diagnostics() {
    FAILS=0;WAITS=0;REBOOT_WAITS=0
    detect_os;detect_network;detect_firewall
    if ! detect_remnanode; then log_warn 'Remnanode/Compose/Xray не обнаружен либо конфигурация неоднозначна.';FAILS=$((FAILS+1));fi
    [[ -z $DOMAIN ]] || detect_nginx || { log_warn 'Nginx не удалось однозначно определить.';FAILS=$((FAILS+1)); }
    docker --version 2>/dev/null || true;docker compose version 2>/dev/null || true;docker ps -a 2>/dev/null || true
    ss -H -lntp "( sport = :443 or sport = :$NODE_PORT or sport = :80 )" || true
    if [[ -n $NODE_CONTAINER ]]; then
        local running api external
        running=$(docker inspect -f '{{.State.Running}}' "$NODE_CONTAINER" 2>/dev/null || true)
        if [[ $running == true ]];then check_result 1 'Remnanode запущен';else check_result 0 'Remnanode запущен';fi
        api=$(ss -H -lntp "( sport = :$NODE_PORT )");external=$(ss -H -lntp '( sport = :443 )')
        if [[ $api == *rw-node* ]];then check_result 1 "API ноды :$NODE_PORT принадлежит rw-node";else check_result 0 "API ноды :$NODE_PORT принадлежит rw-node";fi
        if [[ $external == *rw-core* || $external == *xray* ]]; then check_result 1 ':443 принадлежит Xray'
        elif [[ ! -f $OWN/profile-applied ]]; then WAITS=$((WAITS+1));log_warn 'Ожидание: Xray :443: примените профиль'
        else check_result 0 ':443 принадлежит Xray';fi
        docker inspect -f '{{range .Mounts}}{{println .Source "->" .Destination "rw=" .RW}}{{end}}' "$NODE_CONTAINER"
        validate_sockets
        if [[ -n $NGINX_KIND && -n $NGINX_CONTAINER || $NGINX_KIND == host ]]; then
            if validate_nginx;then check_result 1 'Конфигурация Nginx проверена';else check_result 0 'Конфигурация Nginx проверена';fi
            local loaded
            loaded=$(nginx_command -T 2>&1 || true)
            printf '%s\n' "$loaded" | grep -E '# configuration file|listen .*nginx.sock|location .*api|proxy_pass .*xrxh|ssl_certificate' | scrub
            if [[ $loaded == *"location ^~ $XHTTP_PATH"* && $loaded == *"proxy_pass http://unix:$XHTTP_SOCKET;"* && $loaded != *'grpc_pass'* ]]; then check_result 1 'Загружен HTTP proxy_pass к XHTTP socket'
            else check_result 0 'Загружен HTTP proxy_pass к XHTTP socket';fi
            validate_https
        fi
        diagnostic_logs
    fi
    if [[ -n $DOMAIN ]]; then
        CERT_LINEAGE=${CERT_LINEAGE:-$(state_value cert_lineage)}
        [[ $CERT_LINEAGE != '{}' ]] || CERT_LINEAGE=''
        if [[ -n $CERT_LINEAGE && -f $CERT_LINEAGE/fullchain.pem ]]; then
            openssl x509 -in "$CERT_LINEAGE/fullchain.pem" -noout -subject -ext subjectAltName -enddate
            if openssl x509 -in "$CERT_LINEAGE/fullchain.pem" -noout -checkhost "$DOMAIN" >/dev/null && openssl x509 -in "$CERT_LINEAGE/fullchain.pem" -noout -checkend 0 >/dev/null; then check_result 1 'Сертификат покрывает домен и не истёк'
            else check_result 0 'Сертификат покрывает домен и не истёк';fi
        else log_warn 'Сертификат пока не найден.';fi
    fi
    systemctl status certbot.timer --no-pager 2>/dev/null || true
    case $FW in ufw) ufw status verbose;;nft) nft -t list ruleset | scrub;;iptables) iptables -S INPUT;ip6tables -S INPUT;;esac
    validate_firewall_and_preservation
    validate_security_components
    validate_rps
    validate_tuning
    if [[ $(state_value tuning_expected) == true || -f /etc/systemd/system/nuvrion-zram.service ]];then validate_zram;fi
    if [[ -f $STATE ]]; then
        if (( FAILS>0 )); then STATUS=BROKEN
        elif (( WAITS>REBOOT_WAITS )); then STATUS=WAITING_FOR_REMNAWAVE_PROFILE
        elif (( REBOOT_WAITS>0 )); then STATUS=WAITING_FOR_REBOOT
        else STATUS=RUNNING;fi
    elif [[ -d $OWN ]]; then STATUS='PARTIALLY INSTALLED'
    else STATUS='NOT INSTALLED';fi
    log_info "Состояние: $(display_status); ошибок: $FAILS; ожидают профиля: $((WAITS-REBOOT_WAITS)); ожидают перезагрузки: $REBOOT_WAITS"
}
run_self_check() {
    # No locks, logging setup, downloads, installs or configuration writes.
    local source=${BASH_SOURCE[0]} command_line container field previous_fails tls_results
    if bash -n "$source";then check_result 1 'Синтаксис Bash';else check_result 0 'Синтаксис Bash';fi
    if command -v shellcheck >/dev/null;then
        if shellcheck "$source";then check_result 1 'ShellCheck';else check_result 0 'ShellCheck';fi
    else log_warn 'Не выполнено: ShellCheck: пакет отсутствует';fi
    if [[ -f $PROFILE ]];then
        if helper profile-check "$PROFILE";then check_result 1 'JSON профиля, транспорт и extra';else check_result 0 'JSON профиля, транспорт и extra';fi
    else log_warn 'Не выполнено: Профиль: файл отсутствует';fi
    previous_fails=$FAILS;run_diagnostics;FAILS=$((FAILS+previous_fails))
    for container in "$NODE_CONTAINER" "$NGINX_CONTAINER";do
        [[ -n $container ]] || continue
        command_line=$(docker inspect "$container" | python3 -c 'import json,sys
d=json.load(sys.stdin)[0];h=d["HostConfig"]
print(json.dumps({"apparmor":d.get("AppArmorProfile"),"privileged":h.get("Privileged"),"security_opt":h.get("SecurityOpt"),"cap_add":h.get("CapAdd"),"cap_drop":h.get("CapDrop"),"pids_limit":h.get("PidsLimit"),"read_only":h.get("ReadonlyRootfs"),"docker_socket":any(m["Destination"]=="/var/run/docker.sock" for m in d["Mounts"])}))')
        printf '  Docker %s: %s\n' "$container" "$command_line"
        if python3 -c 'import json,sys;d=json.load(sys.stdin);assert not d["privileged"] and not d["docker_socket"];assert d["apparmor"];assert any(x in ("no-new-privileges:true","no-new-privileges=true") for x in (d["security_opt"] or []));assert (d["pids_limit"] or 0)>0' <<< "$command_line";then
            check_result 1 "$container изоляция"
        else check_result 0 "$container изоляция";fi
        field=$(docker exec "$container" sh -c 'grep -E "^(NoNewPrivs|Seccomp):" /proc/1/status' 2>/dev/null || true)
        printf '  %s\n' "$field"
        if [[ $field == *$'NoNewPrivs:\t1'* && $field == *$'Seccomp:\t2'* ]];then check_result 1 "$container NNP/seccomp"
        else check_result 0 "$container NNP/seccomp";fi
    done
    if [[ -f $STATE && -S $XHTTP_SOCKET ]];then
        if tls_results=$(helper tls-audit "$STATE");then
            if [[ -n $tls_results ]];then
                while IFS=$'\t' read -r field command_line;do
                    check_result "$([[ $field == PASS ]] && printf 1 || printf 0)" "$command_line"
                done <<< "$tls_results"
            else check_result 0 'Проверка TLS/SNI не вернула результатов';fi
        else check_result 0 'Проверка TLS/SNI завершилась ошибкой';fi
        field=$(curl --noproxy '*' --http2 --resolve "$DOMAIN:443:127.0.0.1" -sS --max-time 15 -o /dev/null -w '%{http_code} %{http_version}' "https://$DOMAIN/" || true)
        check_result "$([[ $field == '200 2' ]] && printf 1 || printf 0)" "HTTP/2: $field"
    else log_warn 'Не выполнено: TLS/SNI/padding: ожидает применения профиля.';fi
    log_warn 'Не выполнено: Чистая установка, откат и перезагрузка требуют изолированных тестов; эта самопроверка не выполняет их.'
    log_warn 'Не выполнено: Подключение REALITY/XHTTP с авторизацией, резервный DNS и HAPP/INCY требуют тестового пользователя и интеграционных тестов.'
    log_info "Самопроверка: ошибок $FAILS; ожидают применения $WAITS. Непроведённые интеграционные тесты указаны выше."
    (( FAILS==0 ))
}

remove_nft_comment() {
    local family table chain handle
    while IFS=$'\t' read -r family table chain handle; do
        [[ -n $handle ]] || continue
        nft delete rule "$family" "$table" "$chain" handle "$handle"
    done < <(nft -j list ruleset | helper nft-owned "$1")
}
remove_ufw_comment() {
    local number
    while IFS= read -r number; do
        [[ $number =~ ^[0-9]+$ ]] || continue
        ufw --force delete "$number" >/dev/null
    done < <(ufw status numbered | awk -v comment="$1" 'index($0,"# " comment) {if(match($0,/\[[ ]*[0-9]+\]/)){n=substr($0,RSTART,RLENGTH);gsub(/[^0-9]/,"",n);print n}}' | sort -rn)
}
firewall_remove() {
    case $FW in
        ufw) remove_ufw_comment 'Nuvrion-XHTTP ';remove_ufw_comment Nuvrion-XHTTP-ACME;remove_ufw_comment Nuvrion-XHTTP-API-STAGING;;
        nft)
            remove_nft_comment Nuvrion-XHTTP;remove_nft_comment Nuvrion-XHTTP-ACME
            if nft list table inet nuvrion_xhttp >/dev/null 2>&1; then nft delete table inet nuvrion_xhttp;fi;;
        iptables)
            local binary
            for binary in iptables ip6tables; do
                while "$binary" -w 10 -C INPUT -j NUVRION_XHTTP 2>/dev/null; do "$binary" -w 10 -D INPUT -j NUVRION_XHTTP;done
                if "$binary" -w 10 -S NUVRION_XHTTP >/dev/null 2>&1; then
                    # Delete exact rules individually; never flush any chain.
                    while "$binary" -w 10 -D NUVRION_XHTTP 1 2>/dev/null; do :;done
                    "$binary" -w 10 -X NUVRION_XHTTP
                fi
            done;;
    esac
}
configure_firewall() {
    local panel_version family table chain binary args api_only=0
    [[ $(state_value removed) != true ]] || api_only=1
    panel_version=$(python3 -c 'import ipaddress,sys;print(ipaddress.ip_address(sys.argv[1]).version)' "$PANEL_IP")
    case $FW in
        ufw)
            if ! command -v ufw >/dev/null || ! ufw status | grep -qx 'Status: active';then
                die 7 'UFW выключен или недоступен: защита API не применяется. Восстановите выбранный firewall явно.'
            fi
            # Reconcile only our marked rules; retain all foreign rules.
            # Temporary deny precedes removal, so API cannot become public.
            ufw insert 1 deny "$NODE_PORT/tcp" comment 'Nuvrion-XHTTP-API-STAGING' >/dev/null
            remove_ufw_comment 'Nuvrion-XHTTP '
            ufw insert 1 deny "$NODE_PORT/tcp" comment 'Nuvrion-XHTTP API guard' >/dev/null
            ufw insert 1 allow from "$PANEL_IP" to any port "$NODE_PORT" proto tcp comment 'Nuvrion-XHTTP panel' >/dev/null
            (( api_only==1 )) || ufw insert 1 allow 443/tcp comment 'Nuvrion-XHTTP HTTPS' >/dev/null
            remove_ufw_comment 'Nuvrion-XHTTP-API-STAGING'
            grep -Eq '^IPV6=yes$' /etc/default/ufw || die 7 'UFW не фильтрует IPv6. Глобальная настройка UFW автоматически не меняется.';;
        nft)
            local rules
            rules=$(nft -a -j list ruleset | helper nft-security-rules "$PANEL_IP" "$api_only" "$NODE_PORT") || die 7 'Не удалось подготовить атомарные правила firewall.'
            printf '%s\n' "$rules" | nft -c -f - || die 7 'nftables отклонил новые правила; действующие правила сохранены.'
            printf '%s\n' "$rules" | nft -f - || die 7 'Атомарное применение не удалось; прежняя защита сохранена.';;
        iptables)
            for binary in iptables ip6tables; do
                if ! command -v "$binary" >/dev/null || ! command -v "$binary-restore" >/dev/null;then die 7 "Недоступна выбранная подсистема $binary.";fi
                local previous inputs batch
                previous=$("$binary" -w 10 -S NUVRION_XHTTP 2>/dev/null || true)
                inputs=$("$binary" -w 10 -S INPUT) || die 7 "Не удалось прочитать INPUT для $binary."
                batch=$(printf '%s\n' "$previous" | python3 -c 'import sys
lines=sys.stdin.read().splitlines()
print("*filter")
if not any(line.startswith("-N ") for line in lines):print(":NUVRION_XHTTP - [0:0]")
for line in lines:
 if line.startswith("-A "):print("-D "+line[3:])')
                if [[ $binary == iptables && $panel_version == 4 || $binary == ip6tables && $panel_version == 6 ]]; then
                    batch+=$'\n'"-A NUVRION_XHTTP -p tcp -s $PANEL_IP --dport $NODE_PORT -j ACCEPT"
                fi
                batch+=$'\n'"-A NUVRION_XHTTP -p tcp --dport $NODE_PORT -j DROP"
                (( api_only==1 )) || batch+=$'\n''-A NUVRION_XHTTP -p tcp --dport 443 -j ACCEPT'
                # Promote our exact jump atomically on EVERY apply. A later
                # foreign ACCEPT inserted above it must never expose the API.
                while IFS= read -r chain;do
                    [[ $chain != '-A INPUT -j NUVRION_XHTTP' ]] || batch+=$'\n''-D INPUT -j NUVRION_XHTTP'
                done <<< "$inputs"
                batch+=$'\n''-I INPUT 1 -j NUVRION_XHTTP'
                batch+=$'\nCOMMIT\n'
                printf '%s' "$batch" | "$binary-restore" -w 10 --test --noflush || die 7 'Проверка iptables не пройдена; прежние правила сохранены.'
                printf '%s' "$batch" | "$binary-restore" -w 10 --noflush || die 7 'Применение iptables не удалось; прежние правила сохранены.'
            done;;
        *) die 7 'Не удалось определить реализацию брандмауэра.';;
    esac
    log_ok 'Добавлены точечные правила 443 и ограничения API; SSH-правила сохранены.'
}
acme_firewall() {
    local operation=$1 family table chain binary failed=0
    local traffic_lock
    if [[ -e /usr/local/bin/nuvrion-traffic-control ]];then
        exec {traffic_lock}>/run/nuvrion-traffic-control.lock
        flock -w 30 "$traffic_lock" || die 4 'Traffic Control занят: повторите продление сертификата.'
    fi
    if [[ $operation == close ]]; then
        rm -f /run/nuvrion-xhttp-acme-open
        case $FW in
            ufw) remove_ufw_comment Nuvrion-XHTTP-ACME || failed=1;;
            nft) remove_nft_comment Nuvrion-XHTTP-ACME || failed=1;;
            iptables) for binary in iptables ip6tables; do
                while "$binary" -w 10 -C INPUT -p tcp --dport 80 -m comment --comment Nuvrion-XHTTP-ACME -j ACCEPT 2>/dev/null; do
                    "$binary" -w 10 -D INPUT -p tcp --dport 80 -m comment --comment Nuvrion-XHTTP-ACME -j ACCEPT || { failed=1;break; }
                done
            done;;
        esac
        if command -v nft >/dev/null; then remove_nft_comment Nuvrion-XHTTP-ACME || failed=1;fi
        [[ -z ${traffic_lock:-} ]] || { flock -u "$traffic_lock";exec {traffic_lock}>&-; }
        return "$failed"
    fi
    printf '%s\n' "$(date +%s)" > /run/nuvrion-xhttp-acme-open
    chmod 600 /run/nuvrion-xhttp-acme-open
    case $FW in
        ufw) ufw insert 1 allow 80/tcp comment Nuvrion-XHTTP-ACME >/dev/null;;
        nft) while IFS=$'\t' read -r family table chain; do
            [[ -n $chain ]] || continue
            nft insert rule "$family" "$table" "$chain" tcp dport 80 accept comment Nuvrion-XHTTP-ACME
        done < <(nft -j list ruleset | helper nft-chains);;
        iptables) for binary in iptables ip6tables; do
            "$binary" -w 10 -C INPUT -p tcp --dport 80 -m comment --comment Nuvrion-XHTTP-ACME -j ACCEPT 2>/dev/null ||
              "$binary" -w 10 -I INPUT 1 -p tcp --dport 80 -m comment --comment Nuvrion-XHTTP-ACME -j ACCEPT
        done;;
    esac
    # Nuvrion Traffic Control may filter before INPUT. Temporarily bypass only
    # its own scanner list for HTTP-01, retaining the rest of the firewall.
    if command -v nft >/dev/null && nft list chain inet nuvrion_tc ingress >/dev/null 2>&1; then
        nft insert rule inet nuvrion_tc ingress tcp dport 80 return comment Nuvrion-XHTTP-ACME
    fi
    [[ -z ${traffic_lock:-} ]] || { flock -u "$traffic_lock";exec {traffic_lock}>&-; }
}
port80_plan() {
    python3 -c 'import json,re,subprocess,pathlib,shutil
def command(*a):return subprocess.check_output(a,text=True,stderr=subprocess.DEVNULL)
listeners=command("ss","-H","-lntp","( sport = :80 )")
pids=set(re.findall(r"pid=(\d+)",listeners));units=set();containers=set()
if listeners.strip() and not pids:raise SystemExit("Nuvrion: не удалось определить владельца :80")
ids=command("docker","ps","-q").split() if shutil.which("docker") else []
inspect=json.loads(command("docker","inspect",*ids)) if ids else []
for pid in pids:
 cg=pathlib.Path("/proc/"+pid+"/cgroup").read_text();cmd=pathlib.Path("/proc/"+pid+"/cmdline").read_bytes().replace(b"\0",b" ").decode()
 matched=False
 for unit in ("nginx.service","apache2.service","caddy.service"):
  if unit in cg and subprocess.run(["systemctl","is-active","--quiet",unit]).returncode==0:units.add(unit);matched=True
 for c in inspect:
  if c["Id"] in cg:containers.add(c["Id"]);matched=True
 if "docker-proxy" in cmd and re.search(r"-host-port\s+80\b",cmd):
  for c in inspect:
   ports=c.get("NetworkSettings",{}).get("Ports",{}) or {}
   if any(x.get("HostPort")=="80" for p,values in ports.items() if p.endswith("/tcp") for x in values or []):containers.add(c["Id"]);matched=True
 if not matched:raise SystemExit("Nuvrion: :80 занят неизвестным процессом pid="+pid+"; остановка запрещена")
print(json.dumps({"units":sorted(units),"containers":sorted(containers)}))'
}
acme_pre() {
    local plan unit container
    [[ ! -f /run/nuvrion-xhttp-acme.json ]] || die 4 'Есть незавершённая ACME-операция. Выполните --acme-post для восстановления.'
    plan=$(port80_plan) || die 4 'Не удалось безопасно освободить порт 80.'
    printf '%s\n' "$plan" > /run/nuvrion-xhttp-acme.json
    ACME_PRE_ACTIVE=1
    while IFS= read -r unit; do [[ -z $unit ]] || systemctl stop "$unit";done < <(python3 -c 'import json,sys;print("\n".join(json.load(sys.stdin)["units"]))' <<< "$plan")
    while IFS= read -r container; do [[ -z $container ]] || docker stop "$container" >/dev/null;done < <(python3 -c 'import json,sys;print("\n".join(json.load(sys.stdin)["containers"]))' <<< "$plan")
    acme_firewall open
    [[ -z $(ss -H -lnt '( sport = :80 )') ]] || die 4 ':80 остался занят; Certbot не запущен.'
}
acme_post() {
    [[ -f /run/nuvrion-xhttp-acme.json ]] || return 0
    local unit container failed=0 plan
    plan=$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1]));assert isinstance(d,dict)
for k in ("units","containers"):
 assert isinstance(d.get(k),list) and all(isinstance(x,str) and "\n" not in x for x in d[k])
print(json.dumps(d))' /run/nuvrion-xhttp-acme.json) || die 4 'Повреждён журнал ACME: автоматическое удаление запрещено.'
    acme_firewall close || failed=1
    while IFS= read -r unit; do [[ -z $unit ]] || systemctl start "$unit" || failed=1;done < <(python3 -c 'import json,sys;print("\n".join(json.load(sys.stdin)["units"]))' <<< "$plan")
    while IFS= read -r container; do [[ -z $container ]] || docker start "$container" >/dev/null || failed=1;done < <(python3 -c 'import json,sys;print("\n".join(json.load(sys.stdin)["containers"]))' <<< "$plan")
    (( failed==0 )) || die 4 'Не восстановлены правила ACME или службы; запись операции оставлена для повторной очистки.'
    rm -f /run/nuvrion-xhttp-acme.json
    ACME_PRE_ACTIVE=0
}
acme_hook_cleanup() {
    local rc=$?
    trap - EXIT INT TERM
    if (( rc!=0 && ACME_PRE_ACTIVE==1 )) && [[ -f /run/nuvrion-xhttp-acme.json ]];then
        log_error 'Подготовка ACME прервана; восстанавливаю порт 80 и остановленные службы.'
        # A separate process can retry --acme-post if cleanup itself fails.
        ( acme_post ) || log_error 'Восстановление ACME не завершено; выполните --acme-post.'
    fi
    exit "$rc"
}
lock_changes() {
    local proc_pid
    # /proc may be mounted in a parent PID namespace. Its self entry gives
    # the correct identifier for ancestry checks in that mounted namespace.
    read -r proc_pid _ < /proc/self/stat
    # Certbot uses close_fds=True. Validate its real installer ancestor when
    # fd9 was closed; an arbitrary environment value alone never bypasses lock.
    if [[ ${NUVRION_LOCK_OWNER_PID:-} =~ ^[1-9][0-9]*$ && ${NUVRION_LOCK_OWNER_PID} != "$proc_pid" ]] &&
       helper parent-lock "$NUVRION_LOCK_OWNER_PID" "$proc_pid" /run/nuvrion-xhttp-installer.lock >/dev/null 2>&1;then
        return 0
    fi
    # A direct Bash child may still inherit the original open description.
    if [[ ! -e /proc/$proc_pid/fd/9 || $(readlink "/proc/$proc_pid/fd/9") != /run/nuvrion-xhttp-installer.lock ]];then
        exec 9>/run/nuvrion-xhttp-installer.lock
    fi
    flock -n 9 || die 1 'Другой экземпляр установщика уже выполняет изменения.'
    export NUVRION_LOCK_OWNER_PID=$proc_pid
}
find_certificate() {
    local cert
    CERT_LINEAGE=''
    [[ -d /etc/letsencrypt/live ]] || return 0
    while IFS= read -r cert; do
        [[ -f $cert/privkey.pem ]] || continue
        if openssl x509 -in "$cert/fullchain.pem" -noout -checkhost "$DOMAIN" >/dev/null 2>&1 && openssl x509 -in "$cert/fullchain.pem" -noout -checkend 86400 >/dev/null 2>&1; then CERT_LINEAGE=$cert;break;fi
    done < <(find /etc/letsencrypt/live -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
}
configure_certbot() {
    find_certificate
    if [[ -z $CERT_LINEAGE ]]; then
        log_info "Выпуск Let's Encrypt HTTP-01; TCP/80 открыт только на время проверки."
        acme_pre
        local rc=0
        certbot certonly --standalone --preferred-challenges http --cert-name "$DOMAIN" -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --key-type ecdsa || rc=$?
        acme_post
        (( rc==0 )) || die 4 'Certbot не выдал сертификат.'
        find_certificate;[[ -n $CERT_LINEAGE ]] || die 4 'Не найден действительный сертификат домена.'
    fi
    helper set "$STATE" cert_lineage "\"$CERT_LINEAGE\""
    local renewal=/etc/letsencrypt/renewal/${CERT_LINEAGE##*/}.conf
    [[ -f $renewal && ! -L $renewal ]] || die 4 'У сертификата нет конфигурации продления Certbot.'
    helper hook "$renewal" install "$OWN/renewal-original.conf" "$OWN/installer.sh"
    systemctl enable --now certbot.timer
    systemctl is-active --quiet certbot.timer || die 4 'Таймер Certbot не активен.'
    # Validate scheduling/HTTP-01 hooks with staging, without reloading the
    # production certificate or running a deployment hook on --dry-run.
    certbot renew --cert-name "${CERT_LINEAGE##*/}" --dry-run --no-random-sleep-on-renew || die 4 'Проверка автоматического продления не пройдена.'
    log_ok "TLS и автоматическое продление: $CERT_LINEAGE"
}

create_backup() {
    local stamp counter=0
    stamp=$(date +%Y%m%d-%H%M%S); BACKUP=$BACKUPS/$stamp
    while [[ -e $BACKUP ]]; do counter=$((counter+1));BACKUP=$BACKUPS/$stamp-$counter;done
    local paths
    paths=$(python3 -c 'import json,sys;print(json.dumps([x for x in sys.argv[1:] if x]))' "${COMPOSE_FILES[@]}" "$OVERRIDE" "$NGINX_CONFIG" "$SITE_ROOT" "$OWN" /etc/letsencrypt /etc/sysctl.conf /etc/sysctl.d /etc/modules-load.d /etc/modprobe.d /etc/security/limits.conf /etc/security/limits.d /etc/nuvrion-tuning /var/lib/nuvrion-tuning /etc/systemd/system/nuvrion-performance-sysctl.service /etc/systemd/system/nuvrion-zram.service /etc/systemd/system/nuvrion-zram-next-boot.service /etc/systemd/system/nuvrion-rps.service /etc/systemd/system/nuvrion-post-reboot-check.service /etc/systemd/system/nuvrion-xhttp-firewall.service /etc/systemd/system/nuvrion-pokehabitat.service /etc/nuvrion-pokehabitat.env /usr/local/lib/nuvrion-pokehabitat /opt/nuvrion-node "$PROFILE" "$HOSTS" "$EXTRA")
    paths=$(python3 -c 'import json,sys;d=json.loads(sys.argv[1]);d.extend(json.loads(sys.argv[2]));d.extend(sys.argv[3:]);print(json.dumps(d))' "$paths" "$(helper security-paths)" /var/lib/nuvrion-traffic-control /usr/local/sbin/nuvrion-zram-setup.sh /usr/local/sbin/nuvrion-rps-setup.sh /usr/local/sbin/nuvrion-post-reboot-check.sh /etc/systemd/system.conf.d/99-nuvrion-limits.conf /etc/systemd/system/nuvrion-conntrack.service /run/sysctl.d /usr/local/lib/sysctl.d /usr/sbin/policy-rc.d)
    command install -d -m 700 "$BACKUPS"
    helper snapshot "$BACKUP" <<< "$paths"
    if [[ -n $NODE_CONTAINER ]] && docker container inspect "$NODE_CONTAINER" >/dev/null 2>&1;then
        docker inspect -f '{{.State.Running}}' "$NODE_CONTAINER" > "$BACKUP/node-running.txt"
    fi
    command -v nft >/dev/null && nft list ruleset > "$BACKUP/firewall.nft" || true
    command -v iptables-save >/dev/null && iptables-save > "$BACKUP/firewall.v4" || true
    command -v ip6tables-save >/dev/null && ip6tables-save > "$BACKUP/firewall.v6" || true
    command -v ufw >/dev/null && ufw status numbered > "$BACKUP/firewall.ufw" || true
    sysctl -a 2>/dev/null > "$BACKUP/sysctl-runtime.txt" || true
    helper rps-snapshot "$BACKUP/rps-runtime.json"
    find /etc/ssh -type f -exec sha256sum '{}' + | sort > "$BACKUP/ssh.sha256"
    sshd -T > "$BACKUP/ssh-effective.txt"
    python3 -c 'import json,subprocess,sys
d={}
for unit in ["nuvrion-pokehabitat.service","nuvrion-xhttp-firewall.service","nuvrion-performance-sysctl.service","nuvrion-zram.service","nuvrion-rps.service","nuvrion-post-reboot-check.service","nuvrion-two-way-ping.service","nuvrion-traffic-control.service","nuvrion-traffic-control-update.timer","nuvrion-traffic-control-rollback.timer","fail2ban.service","apt-daily.timer","apt-daily-upgrade.timer"]:
 d[unit]={k:subprocess.run(["systemctl",k,unit],capture_output=True,text=True).stdout.strip() for k in ["is-active","is-enabled"]}
open(sys.argv[1],"w").write(json.dumps(d))' "$BACKUP/units.json"
    systemctl is-enabled certbot.timer > "$BACKUP/certbot-enabled.txt" 2>/dev/null || true
    systemctl is-active certbot.timer > "$BACKUP/certbot-active.txt" 2>/dev/null || true
    dpkg-query -W -f='${binary:Package}\t${Version}\t${Status}\n' > "$BACKUP/packages.tsv"
    apt-mark showhold > "$BACKUP/packages-held.txt"
    apt-mark showmanual > "$BACKUP/packages-manual.txt"
    {
        printf 'Nuvrion XHTTP %s\nDate: %s\nHostname: %s\nIPv4: %s\nXray: %s\n' "$INSTALLER_VERSION" "$(date -Is)" "$(hostname)" "$IPV4" "$XRAY_VERSION"
        docker --version 2>/dev/null || true;docker compose version 2>/dev/null || true;docker ps -a 2>/dev/null || true
        printf '\nSaved paths:\n';python3 -c 'import json,sys;print("\n".join(x["path"]+" (present="+str(x["exists"])+")" for x in json.load(open(sys.argv[1]))))' "$BACKUP/files.json"
    } > "$BACKUP/manifest.txt"
    log_ok "Резервная копия: $BACKUP"
}
capture_transaction() {
    [[ -n $BACKUP && -f $BACKUP/files.json ]] || return 0
    helper rollback-delta "$BACKUP" "$BACKUP/after-delta.json" "$SITE_ROOT"
}
capture_runtime_after() {
    [[ -d $OWN ]] || return 0
    helper runtime-after "$OWN/sysctl-after.json"
    helper rps-snapshot "$OWN/rps-after.json"
}
save_state() {
    local NODE_IMAGE_ID NGINX_IMAGE_ID FILES_JSON TRUSTED_XFF
    NODE_IMAGE_ID=$(docker inspect -f '{{.Image}}' "$NODE_CONTAINER")
    if [[ -n $NGINX_CONTAINER ]]; then NGINX_IMAGE_ID=$(docker inspect -f '{{.Image}}' "$NGINX_CONTAINER")
    elif [[ $NGINX_KIND == docker ]];then NGINX_IMAGE_ID=$(docker image inspect -f '{{.Id}}' nginx:1.30)
    else NGINX_IMAGE_ID='';fi
    FILES_JSON=$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1:]))' "${COMPOSE_FILES[@]}")
    TRUSTED_XFF=$(helper xff-version "$XRAY_VERSION")
    export DOMAIN PANEL_IP NODE_PORT EMAIL NODE_TAG XHTTP_PATH NODE_CONTAINER NODE_SERVICE PROJECT WORKDIR NGINX_KIND NGINX_CONTAINER NGINX_SERVICE NGINX_CONFIG NGINX_MAIN NGINX_ROOT SITE_ROOT WEB_GID CERT_LINEAGE XRAY_BIN IPV4 NGINX_NEW NODE_IMAGE_ID NGINX_IMAGE_ID FILES_JSON BACKUP FW TRUSTED_XFF SECURE_SOCKETS XRAY_VERSION HARDEN_PROFILE
    helper state
}
unpack_bundle() {
    WORK=$(mktemp -d /tmp/nuvrion-xhttp.XXXXXXXX)
    payload | base64 -d > "$WORK/bundle.tar.gz"
    printf '%s  %s\n' "$(payload_hash)" "$WORK/bundle.tar.gz" | sha256sum -c --status - || die 1 'Встроенный архив повреждён.'
    helper unpack "$WORK/bundle.tar.gz" "$WORK/bundle"
    command install -m 600 "$WORK/bundle.tar.gz" "$OWN/bundle.tar.gz"
    payload_hash > "$OWN/bundle.sha256"
    command install -m 700 "$WORK/bundle/installer-manager.sh" "$OWN/installer.sh"
}
generate_reality_keys() {
    local output private='' imported='' tag=''
    if [[ -n $PROFILE_INPUT ]]; then
        imported=$(helper keys "$PROFILE_INPUT") || die 1 'Не удалось разобрать исходный профиль.'
        private=${imported%%$'\n'*};tag=${imported#*$'\n'}
        [[ -n $private && $tag == "$NODE_TAG" ]] || die 1 'Исходный профиль должен содержать один Reality :443 с тем же NODE_TAG.'
    elif [[ -f $PROFILE ]]; then
        PROFILE_INPUT=$PROFILE
        imported=$(helper keys "$PROFILE")
        private=${imported%%$'\n'*}
    fi
    if [[ -n $private ]]; then
        PUBLIC_KEY=$(printf '%s' "$private" | helper public-key)
    else
        [[ -z $(ss -H -lnt '( sport = :443 )') ]] || die 1 'На :443 уже есть вход. Импортируйте профиль для сохранения действующих ключей.'
        output=$(docker exec "$NODE_CONTAINER" "$XRAY_BIN" x25519)
        private=$(sed -nE 's/^[Pp]rivate[[:space:]]*[Kk]ey:[[:space:]]*//p' <<< "$output" | sed -n '1p')
        PUBLIC_KEY=$(sed -nE 's/^(Public[[:space:]]*[Kk]ey|Password([[:space:]]+\(PublicKey\))?):[[:space:]]*//p' <<< "$output" | sed -n '1p')
    fi
    [[ $private =~ ^[A-Za-z0-9_-]{43}$ && $PUBLIC_KEY =~ ^[A-Za-z0-9_-]{43}$ ]] || die 1 'Не удалось разобрать штатный вывод Xray x25519.'
    # Secrets travel only through stdin, never command logging or stdout.
    printf '%s\n%s\n' "$private" "$PUBLIC_KEY" | python3 -c 'import json,sys;a=sys.stdin.read().splitlines();print(json.dumps(dict(private=a[0],public=a[1])))' > "$WORK/keys.json"
    unset private output imported
}
generate_remnawave_profile() {
    helper profile "$PROFILE_INPUT" < "$WORK/keys.json"
    rm -f "$WORK/keys.json"
    # Test an OWN temporary file. Do not write any generated/live Xray config.
    # shellcheck disable=SC2016
    local -a test_command=(docker exec -i "$NODE_CONTAINER" sh -c)
    # shellcheck disable=SC2016
    if ! "${test_command[@]}" 'umask 077; f=$(mktemp /tmp/nuvrion-profile.XXXXXX); trap '\''rm -f "$f"'\'' EXIT; cat > "$f"; "$1" run -test -format json -config "$f"' sh "$XRAY_BIN" < "$PROFILE" > "$WORK/profile-test.txt" 2>&1; then
        scrub < "$WORK/profile-test.txt";die 1 'Xray отклонил профиль. Версия ядра не изменена.'
    fi
    log_ok 'Профиль ноды проверен установленным Xray; настройки Host и extra сохранены.'
    if [[ $(state_value profile_pending) == true ]];then
        rm -f "$OWN/profile-applied"
        log_warn 'Миграция ожидает применения итогового JSON в Remnawave; диагностика покажет ожидание до создания нового сокета.'
    fi
}
configure_nginx() {
    if [[ $NGINX_NEW == 1 && ! -f $NGINX_CONFIG ]]; then
        helper nginx-template "$CERT_LINEAGE" > "$NGINX_CONFIG"
        chmod 644 "$NGINX_CONFIG"
    fi
    helper patch-nginx "$NGINX_CONFIG" "$DOMAIN" "$XHTTP_PATH" "$CERT_LINEAGE" "$OWN/nginx-patch.json"
}
configure_shared_shm() {
    "${COMPOSE_CMD[@]}" config --format json > "$WORK/compose-before.json"
    helper overlay "$WORK/compose-before.json" "$OVERRIDE"
    local found=0 file
    for file in "${COMPOSE_FILES[@]}"; do [[ $file != "$OVERRIDE" ]] || found=1;done
    (( found==1 )) || COMPOSE_FILES+=("$OVERRIDE")
    compose_command
    "${COMPOSE_CMD[@]}" config --format json > "$WORK/compose-after.json"
    helper verify-compose "$WORK/compose-before.json" "$WORK/compose-after.json"
    NODE_RECREATE=$(python3 -c 'import json,sys;a=json.load(open(sys.argv[1]))["services"][sys.argv[3]];b=json.load(open(sys.argv[2]))["services"][sys.argv[3]];a.pop("image",None);b.pop("image",None);print(int(a!=b))' "$WORK/compose-before.json" "$WORK/compose-after.json" "$NODE_SERVICE")
    if [[ $NGINX_KIND == docker ]]; then
        NGINX_RECREATE=$(python3 -c 'import json,sys;a=json.load(open(sys.argv[1]))["services"].get(sys.argv[3]);b=json.load(open(sys.argv[2]))["services"][sys.argv[3]];a.pop("image",None) if a else None;b.pop("image",None);print(int(a!=b))' "$WORK/compose-before.json" "$WORK/compose-after.json" "$NGINX_SERVICE")
    fi
    helper set "$STATE" compose_files "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1:]))' "${COMPOSE_FILES[@]}")"
}

choose_node_version() {
    if (( NODE_NEW==0 ));then
        [[ -z $NODE_VERSION || $NODE_VERSION == keep ]] || die 3 'Нода уже установлена: используйте --node-version keep; её образ/Xray не заменяются.'
        NODE_VERSION=keep;SELECTED_IMAGE=''
        return 0
    fi
    local available='' choice index=0 version
    local -a versions=()
    if [[ -z $NODE_VERSION ]];then
        if (( YES==1 ));then NODE_VERSION=latest
        else
            printf '\n  Версия новой Remnawave Node:\n    1. Последняя стабильная (latest)\n'
            if available=$(helper releases);then
                mapfile -t versions <<< "$available"
                for version in "${versions[@]}";do
                    [[ -n $version ]] || continue
                    index=$((index+1));printf '    %s. %s\n' "$((index+1))" "$version"
                done
            else log_warn 'Список реестра образов недоступен; можно выбрать latest или ввести точный номер версии.';fi
            while true;do
                prompt choice 'Выбор: номер пункта / версия' 1
                if [[ $choice == 1 || $choice == latest ]];then NODE_VERSION=latest;break
                elif [[ $choice =~ ^[0-9]+$ && ${#choice} -le 3 ]] && (( 10#$choice>=2 && 10#$choice<=index+1 ));then
                    NODE_VERSION=${versions[$((10#$choice-2))]};break
                elif [[ $choice =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]];then
                    if [[ -z $available ]];then available=$(helper releases) || { log_warn 'Не удалось получить версии; выберите latest или повторите ввод.';continue; };fi
                    if grep -Fxq "$choice" <<< "$available";then NODE_VERSION=$choice;break;fi
                    log_warn 'Версия не найдена среди опубликованных образов.'
                else log_warn 'Введите номер показанного пункта, latest или версию X.Y.Z.';fi
            done
        fi
    fi
    [[ $NODE_VERSION == latest || $NODE_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 3 'Для новой ноды выберите latest или стабильную версию X.Y.Z.'
    if [[ $NODE_VERSION != latest ]];then
        [[ -n $available ]] || available=$(helper releases) || die 3 'Не удалось проверить доступные версии официального образа Docker.'
        grep -Fxq "$NODE_VERSION" <<< "$available" || die 3 'Выбранная версия отсутствует среди опубликованных официальных образов Docker.'
    fi
    SELECTED_IMAGE=remnawave/node:$NODE_VERSION
    log_info "Новая Remnanode: $SELECTED_IMAGE (после загрузки закрепляется точный ID образа)."
}
assert_clean_node_target() {
    local candidate ids nodes
    [[ -z $NODE_CONTAINER ]] || die 3 'Указанная существующая нода не распознана. Выполните диагностику.'
    [[ ! -e $STATE && ! -e $OVERRIDE ]] || die 3 'Обнаружены файлы существующей установки: требуется восстановление, не новая нода.'
    for candidate in docker-compose.yml docker-compose.yaml compose.yml compose.yaml nuvrion-node.env;do
        [[ ! -e $BASE/$candidate && ! -L $BASE/$candidate ]] || die 3 'Существующий Compose/credentials не заменяются. Выполните диагностику.'
    done
    [[ -z $(ss -H -lnt "( sport = :443 or sport = :$NODE_PORT )") ]] || die 3 "Порты 443/$NODE_PORT заняты: сервер не является чистым для установки ноды."
    if command -v docker >/dev/null;then
        docker info >/dev/null 2>&1 || die 3 'Существующий Docker daemon недоступен: сначала восстановите его; новая установка не выполняется.'
        ids=$(docker ps -aq) || die 3 'Не удалось проверить существующие контейнеры.'
        if [[ -n $ids ]];then
            local -a containers=()
            mapfile -t containers <<< "$ids"
            nodes=$(docker inspect "${containers[@]}" | helper nodes) || die 3 'Не удалось проверить существующие ноды.'
            [[ -z $nodes ]] || die 3 'Есть существующие/остановленные/неоднозначные Remnanode: автоматическая новая установка запрещена.'
        fi
        ! docker container inspect remnanode >/dev/null 2>&1 || die 3 'Имя remnanode занято существующим контейнером.'
    fi
}
collect_node_secret() {
    if [[ -n $SECRET_FILE ]];then
        [[ -f $SECRET_FILE && ! -L $SECRET_FILE && -O $SECRET_FILE ]] || die 3 'Файл SECRET_KEY должен быть обычным файлом root.'
        [[ $(stat -c %a "$SECRET_FILE") == 600 ]] || die 3 'Файл SECRET_KEY: нужны права 0600.'
        NODE_SECRET=$(< "$SECRET_FILE")
    else
        if (( YES==1 && NODE_NEW==0 ));then return 0;fi
        (( YES==0 )) && [[ -r /dev/tty ]] || die 3 'Для новой ноды нужен --secret-key-file с правами 0600.'
        local hint='ввод скрыт'
        (( NODE_NEW==1 )) || hint='ввод скрыт; Enter — сохранить действующий ключ'
        ui_question "Секретный ключ ноды из панели ($hint):"
        IFS= read -rs NODE_SECRET < /dev/tty || die 3 'Ввод SECRET_KEY прерван.'
        printf '\n' > /dev/tty
        if (( NODE_NEW==0 )) && [[ -z $NODE_SECRET ]];then return 0;fi
    fi
    [[ $NODE_SECRET =~ ^[A-Za-z0-9_./+=-]+$ && ${#NODE_SECRET} -ge 32 ]] || die 3 'Некорректный SECRET_KEY; получите его в панели Remnawave.'
    if (( NODE_NEW==0 ));then
        local existing_secret
        existing_secret=$(docker inspect "$NODE_CONTAINER" | python3 -c 'import json,sys
print(next((v.split("=",1)[1] for v in json.load(sys.stdin)[0]["Config"].get("Env",[]) if v.startswith("SECRET_KEY=")),""))') || die 3 'Не удалось проверить действующий SECRET_KEY.'
        [[ -n $existing_secret && $NODE_SECRET == "$existing_secret" ]] || die 3 'Введённый ключ отличается от действующего SECRET_KEY. Автоматическая замена ключа существующей ноды запрещена.'
        unset NODE_SECRET existing_secret
        log_ok 'Введённый секретный ключ соответствует существующей ноде.'
    fi
}
collect_inputs() {
    if (( YES==0 ));then prompt DOMAIN 'Домен сайта декой / SNI' "$DOMAIN"
    else [[ -n $DOMAIN ]] || die 1 'Для --yes требуется --domain.';fi
    DOMAIN=$(helper domain "$DOMAIN")
    if (( YES==0 ));then prompt NODE_PORT 'Порт API ноды для панели' "$NODE_PORT";fi
    validate_node_port
    [[ -z $DETECTED_NODE_PORT || $NODE_PORT == "$DETECTED_NODE_PORT" ]] || die 3 "Установка отменена: API существующей ноды :$DETECTED_NODE_PORT; его порт сохраняется."
    if (( YES==0 ));then prompt PANEL_IP 'IP панели Remnawave' "$PANEL_IP"
    else [[ -n $PANEL_IP ]] || die 1 'Для --yes требуется --panel-ip.';fi
    collect_node_secret
    [[ -n $EMAIL ]] || prompt EMAIL "Адрес электронной почты Let's Encrypt" ''
    [[ -n $NODE_TAG ]] || prompt NODE_TAG 'Тег inbound REALITY' Nuvrion
    [[ $PATH_EXPLICIT == 1 || $YES == 1 ]] || prompt XHTTP_PATH 'Путь XHTTP' "$XHTTP_PATH"
    helper validate "$DOMAIN" "$PANEL_IP" "$EMAIL" "$NODE_TAG" "$XHTTP_PATH" "$DOMAIN" || die 1 'Параметры не прошли проверку.'
    [[ -z $PROFILE_INPUT || -f $PROFILE_INPUT && ! -L $PROFILE_INPUT ]] || die 1 'Исходный профиль должен быть обычным JSON-файлом.'
}
plan_install() {
    installation_components;detect_os
    if ! detect_remnanode allow-stopped;then NODE_NEW=1;fi
    collect_inputs;detect_network;validate_domain_address;detect_firewall
    [[ $(ss -H -lntp "( sport = :443 or sport = :$NODE_PORT )") != *sshd* ]] || die 7 "SSH использует 443/$NODE_PORT: установка могла бы ограничить SSH. Выберите другой порт API/сервер."
    ss -H -lntp "( sport = :443 or sport = :$NODE_PORT or sport = :80 )" || true
    stat -c '%n %F %a %U:%G' /dev/shm/nginx.sock /dev/shm/xrxh.socket 2>/dev/null || true
    if (( NODE_NEW==1 ));then
        # An existing, ambiguous or stopped installation must be repaired
        # explicitly; it is never mistaken for a clean server.
        assert_clean_node_target
        NODE_NEW=1;NODE_SERVICE=remnanode;PROJECT=remnanode;WORKDIR=$BASE
        NODE_CONTAINER=remnanode;COMPOSE_FILES=("$BASE/docker-compose.yml");compose_command
        log_info 'Remnanode отсутствует: будет создан новый Compose, существующие файлы не заменяются.'
    fi
    choose_node_version
    detect_nginx || die 5 'Нельзя безопасно адаптировать найденный Nginx.'
    if (( HARDEN_PROFILE==1 ));then SECURE_SOCKETS=1
    elif [[ ! -f $STATE && ! -f $PROFILE && -z $PROFILE_INPUT && $NGINX_NEW == 1 ]];then SECURE_SOCKETS=1;fi
    socket_settings
    if (( SECURE_SOCKETS==1 ));then
        if [[ -e /dev/shm/nuvrion-xhttp || -e /etc/tmpfiles.d/nuvrion-xhttp.conf ]];then
            [[ -f $STATE && $(state_value secure_sockets) == true ]] || die 6 'Защищённый каталог/tmpfiles уже существует без записи владения; установка остановлена.'
        fi
        if (( NODE_NEW==0 ));then
            [[ $(node_probe id -u) == 0 ]] || die 6 'Защищённые sockets требуют проверенного root Xray; UID контейнера не меняется автоматически.'
        fi
    fi
    if (( NODE_NEW==0 )); then
        [[ $(helper xff-version "$XRAY_VERSION") == 1 ]] || die 3 'Установленный Xray старше проверенного v26.3.27. Обновление Xray автоматически не выполняется; установка остановлена.'
        local config
        config=$("${COMPOSE_CMD[@]}" config --format json) || die 3 'Исходный Compose не проходит проверку.'
        # Validate conflicts in the original mounts before making an override.
        python3 -c 'import json,sys
d=json.load(sys.stdin)["services"][sys.argv[1]]
for m in d.get("volumes",[]):
 if m["target"]=="/dev/shm" and (m.get("type")!="bind" or m.get("source")!="/dev/shm" or m.get("read_only")):raise SystemExit("Конфликтующий shared /dev/shm mount")' "$NODE_SERVICE" <<< "$config" || die 6 'Совместимость /dev/shm не подтверждена.'
    fi
    if [[ -n $NGINX_CONTAINER && $(state_value nginx_new) == true ]]; then NGINX_NEW=1;fi
    [[ $SITE_ROOT == /* && ! -L $SITE_ROOT && ! -L $OWN && ! -L $BASE ]] || die 1 'Небезопасный путь установки.'
    local aaaa
    aaaa=$(python3 -c 'import socket,sys
try: print(" ".join(sorted({x[4][0] for x in socket.getaddrinfo(sys.argv[1],None,socket.AF_INET6)})))
except socket.gaierror: pass' "$DOMAIN")
    [[ -z $aaaa ]] || log_warn "Есть AAAA: $aaaa. Этот адрес также должен вести на сервер для HTTP-01."
    if [[ $FW == ufw ]]; then grep -Eq '^IPV6=yes$' /etc/default/ufw || die 7 'UFW IPV6=no: невозможно гарантировать закрытие API по IPv6.';fi
    if [[ ! -f $STATE ]]; then
        if command -v nft >/dev/null && nft list table inet nuvrion_xhttp >/dev/null 2>&1; then die 7 'Таблица nuvrion_xhttp уже существует без записи владения.';fi
        if command -v iptables >/dev/null && iptables -S NUVRION_XHTTP >/dev/null 2>&1; then die 7 'Цепочка NUVRION_XHTTP уже существует без записи владения.';fi
    fi
    if [[ -n $NGINX_CONFIG && -f $NGINX_CONFIG ]]; then
        helper nginx-info "$DOMAIN" < "$NGINX_CONFIG" >/dev/null || die 5 'Конфигурация decoy не распознана.'
    fi
    [[ ! -f $OWN/assets.json ]] || helper asset-check "$SITE_ROOT" "$OWN/assets.json" || die 1 'Сайт изменён после установки; автоматическая замена запрещена.'
    preflight_component_files
    if [[ -z $PROFILE_INPUT && ! -f $PROFILE && -n $(ss -H -lnt '( sport = :443 )') ]]; then
        die 1 'Для существующего входа :443 нужен --profile-input с сохранёнными ключами.'
    fi
    if (( NO_TUNING==0 )); then
        log_info 'Тюнинг: BBR/fq, TCP/UDP буферы, conntrack, nofile, ZRAM/RPS по ресурсам; сетевые sysctl из Nuvrion Vision.'
    fi
    security_plan
    find_certificate
    if [[ -z $CERT_LINEAGE ]]; then port80_plan >/dev/null || die 4 'Неизвестный владелец порта 80.';fi
    printf '\n  Будет изменено:\n'
    printf '    Remnanode: %s\n    Nginx: %s (%s)\n    Общие сокеты: /dev/shm\n    Сайт декой → %s\n' "${SELECTED_IMAGE:-сохранить текущий образ}" "$NGINX_CONFIG" "${NGINX_CONTAINER:-новый отдельный сервис}" "$SITE_ROOT"
    printf '    Compose: отдельный override %s\n    TLS: %s\n    Брандмауэр: 443 публичный, API %s только %s, временный 80\n' "$OVERRIDE" "${CERT_LINEAGE:-новый Let’s Encrypt сертификат}" "$NODE_PORT" "$PANEL_IP"
    printf '    Резервная копия: %s/<timestamp>/\n    Выход: профиль ноды, настройки Host, extra\n' "$BACKUPS"
    package_plan
    log_warn 'Если действующей ноде понадобятся новая точка подключения или лимит nofile, VPN-соединения могут кратковременно прерваться.'
    (( YES==1 )) || ask_yes 'Применить перечисленные изменения после резервного копирования?' || exit 0
}
preflight_component_files() {
    # Run BEFORE prepare_node/save_state. A freshly created state file must
    # never be mistaken for ownership of a pre-existing application/unit.
    helper owned-unit-check /etc/systemd/system/nuvrion-pokehabitat.service '# BEGIN NUVRION XHTTP GAME' || die 1 'Существующий игровой unit не принадлежит этой установке.'
    helper owned-unit-check /etc/systemd/system/nuvrion-xhttp-firewall.service '# BEGIN NUVRION XHTTP FIREWALL' || die 1 'Существующий firewall-unit не принадлежит этой установке.'
    local collisions
    collisions=$(payload | base64 -d | helper bundle-assets-preflight "$SITE_ROOT") || die 1 'Файлы Атласа пива не прошли проверку владения.'
    PUBLIC_ASSETS_REPLACE=0
    if [[ $collisions != '[]' ]];then
        PUBLIC_ASSETS_REPLACE=1
        log_warn 'План включает замену существующих файлов сайта декой; исходные файлы будут сохранены в резервной копии:'
        python3 -c 'import json,sys
names=json.load(sys.stdin)
for name in names[:12]:print("    "+name)
if len(names)>12:print("    … ещё "+str(len(names)-12)+" файлов")' <<< "$collisions"
    fi
}
package_plan() {
    if (( NO_UPDATES==0 )); then
        log_info 'APT: обновление индексов и пакетов Ubuntu без удаления; существующие Docker/containerd/runc закреплены.'
        log_warn 'Обновление ядра может потребовать перезагрузку. Пакеты/ядро не откатываются при восстановлении конфигурации.'
    else log_info 'Обновления Ubuntu пропущены по --no-updates; недостающие зависимости будут установлены.';fi
    log_info 'Очистка: проверяемые неиспользуемые пакеты и устаревший APT-кэш. Ядра, SSH, сеть, Docker и данные сохраняются.'
}
begin_package_maintenance() {
    # Apt pins apply to this process only, without changing administrator holds.
    APT_PREFERENCES=$WORK/apt-preferences
    [[ ! -f /etc/apt/preferences ]] || cat /etc/apt/preferences > "$APT_PREFERENCES"
    touch "$APT_PREFERENCES"
    dpkg-query -W -f='${binary:Package}\t${Version}\t${Status}\n' 2>/dev/null | python3 -c 'import sys
with open(sys.argv[1],"a") as f:
 for line in sys.stdin:
  p,v,s=line.rstrip().split("\t",2)
  if s=="install ok installed" and p.split(":")[0].startswith(("docker","containerd","runc","openssh")):
   f.write("\nPackage: "+p+"\nPin: version "+v+"\nPin-Priority: 1001\n")' "$APT_PREFERENCES"
    # Prevent maintainer scripts/needrestart from restarting SSH, Docker or VPN.
    # Preserve an existing policy, including symlinks and its permissions.
    [[ ! -e /usr/sbin/policy-rc.d && ! -L /usr/sbin/policy-rc.d ]] || {
        cp -a /usr/sbin/policy-rc.d "$WORK/policy-rc.d.original";APT_POLICY_ORIGINAL=1;
    }
    printf '#!/bin/sh\n# NUVRION XHTTP TEMPORARY APT POLICY\nexit 101\n' > "$WORK/policy-rc.d"
    chmod 755 "$WORK/policy-rc.d"
    mv -fT "$WORK/policy-rc.d" /usr/sbin/policy-rc.d
    APT_POLICY_ACTIVE=1
}
end_package_maintenance() {
    (( APT_POLICY_ACTIVE==1 )) || return 0
    if ! grep -qx '# NUVRION XHTTP TEMPORARY APT POLICY' /usr/sbin/policy-rc.d; then
        log_error 'policy-rc.d изменён другим процессом: исходный файл сохранён в резервной копии.';return 1
    fi
    if (( APT_POLICY_ORIGINAL==1 )); then
        rm -f /usr/sbin/policy-rc.d
        cp -a "$WORK/policy-rc.d.original" /usr/sbin/policy-rc.d
    else rm -f /usr/sbin/policy-rc.d;fi
    APT_POLICY_ACTIVE=0
}
apt_run() {
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l NEEDRESTART_SUSPEND=1 \
      apt-get -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confold \
        -o Acquire::Retries=2 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 \
        -o "Dir::Etc::preferences=$APT_PREFERENCES" "$@"
}
apt_apply_checked() {
    local simulation plan verified
    simulation=$(apt_run -s "$@") || die 1 'APT: предварительная проверка не удалась.'
    plan=$(awk '$1=="Inst" || $1=="Conf" || $1=="Remv"' <<< "$simulation")
    [[ -n $plan ]] || return 0
    [[ ! $plan =~ (^|$'\n')Remv[[:space:]] ]] || die 1 'APT предложил удаление при обновлении: изменения запрещены.'
    log_info 'Проверенный план пакетов (журнал содержит версии):'
    printf '%s\n' "$plan" | tee -a "$LOG"
    verified=$(apt_run -s "$@") || die 1 'APT: повторная проверка не удалась.'
    [[ $plan == "$(awk '$1=="Inst" || $1=="Conf" || $1=="Remv"' <<< "$verified")" ]] || die 1 'План APT изменился; повторите запуск.'
    apt_run -y --no-remove "$@" >> "$LOG" 2>&1 || die 1 "APT завершился ошибкой; журнал: $LOG"
}
install_dependencies() {
    local pair command_name package
    INSTALL_PACKAGES=()
    for pair in curl:curl jq:jq openssl:openssl certbot:certbot dig:dnsutils tar:tar xz:xz-utils modprobe:kmod zramctl:util-linux nft:nftables; do
        command_name=${pair%%:*};package=${pair#*:}
        command -v "$command_name" >/dev/null || INSTALL_PACKAGES+=("$package")
    done
    [[ -n $FW ]] || { INSTALL_PACKAGES+=(nftables);FW=nft; }
    command -v docker >/dev/null || INSTALL_PACKAGES+=(docker.io)
    docker compose version >/dev/null 2>&1 || INSTALL_PACKAGES+=(docker-compose-v2)
    dpkg-query -W -f='${Status}' ca-certificates 2>/dev/null | grep -qx 'install ok installed' || INSTALL_PACKAGES+=(ca-certificates)
    if (( NO_TUNING==0 ));then
        for package in fail2ban python3-systemd unattended-upgrades;do
            dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed' || INSTALL_PACKAGES+=("$package")
        done
    fi
    if (( NO_UPDATES==0 || ${#INSTALL_PACKAGES[@]}>0 )); then
        log_info 'Обновляю индексы APT; перезапуски служб временно запрещены.'
        apt_run update >> "$LOG" 2>&1 || die 1 "Обновление индексов APT не выполнено; журнал: $LOG"
    fi
    ((${#INSTALL_PACKAGES[@]}==0)) || apt_apply_checked install --no-install-recommends "${INSTALL_PACKAGES[@]}"
    (( NO_UPDATES==1 )) || apt_apply_checked --with-new-pkgs upgrade
    docker info >/dev/null 2>&1 || { (( NODE_NEW==1 )) && systemctl start docker; }
    docker info >/dev/null 2>&1 || die 3 'Docker недоступен.'
}
cleanup_system_packages() {
    local simulation plan verified package
    local protected='^(linux-|grub|shim|initramfs|dracut|intel-microcode|amd64-microcode|apt|dpkg|systemd|udev|openssh|ufw|nftables|iptables|fail2ban|docker|containerd|runc|nginx|cloud-init|netplan|network-manager|ifupdown|iproute2|python3|ca-certificates|curl|jq|gnupg|openssl|dnsutils|certbot|kmod|util-linux|zram|unattended-upgrades)'
    local -a protection=(-o "APT::NeverAutoRemove::=$protected")
    simulation=$(apt_run -s "${protection[@]}" autoremove) || { log_warn 'Очистка пропущена: предварительная проверка APT не пройдена.';return 0; }
    plan=$(awk '$1=="Inst" || $1=="Conf" || $1=="Remv"' <<< "$simulation")
    if [[ -n $plan ]];then
        [[ ! $plan =~ (^|$'\n')(Inst|Conf)[[:space:]] ]] || { log_warn 'Очистка пропущена: план содержит установку/настройку пакетов.';return 0; }
        while read -r package;do
            [[ ! $package =~ $protected ]] || { log_warn "Очистка пропущена: защищённый пакет $package.";return 0; }
        done < <(awk '$1=="Remv" {print $2}' <<< "$plan")
        log_info 'Будут удалены неиспользуемые пакеты:';printf '%s\n' "$plan" | tee -a "$LOG"
        verified=$(apt_run -s "${protection[@]}" autoremove) || { log_warn 'Очистка пропущена: повторная проверка не удалась.';return 0; }
        [[ $plan == "$(awk '$1=="Inst" || $1=="Conf" || $1=="Remv"' <<< "$verified")" ]] || { log_warn 'План очистки изменился; удаление пропущено.';return 0; }
        apt_run "${protection[@]}" -y autoremove >> "$LOG" 2>&1 || die 1 'Не удалось завершить безопасную очистку пакетов.'
    fi
    apt_run autoclean >> "$LOG" 2>&1 || die 1 'Не удалось очистить устаревший APT-кэш.'
    log_ok 'Неиспользуемые пакеты и устаревший кэш проверены; загрузочные ядра и пользовательские данные сохранены.'
}
prepare_node() {
    local origin_new candidate current_info
    origin_new=$(state_value node_new)
    if (( NODE_STOPPED==1 ));then
        (( NODE_NEW==0 && TRANSACTION==1 )) && [[ -n $BACKUP && -f $BACKUP/files.json ]] || die 3 'Запуск остановленной ноды разрешён только после резервного копирования и начала транзакции.'
        current_info=$(docker inspect "$NODE_CONTAINER" | helper node-info) || die 3 'Остановленная нода исчезла после диагностики.'
        owned_stopped_node "$current_info" || die 3 'Владение остановленной нодой изменилось; запуск запрещён.'
        [[ $(jget image_id <<< "$current_info") == "$NODE_IMAGE_ID_DETECTED" ]] || die 3 'Образ остановленной ноды изменился; запуск запрещён.'
        if [[ $(jget running <<< "$current_info") != true ]];then
            assert_stopped_node_ports_free
            SERVICES_APPLIED=1;NODE_RECREATE=1
            docker start "$NODE_CONTAINER" >/dev/null || die 3 'Не удалось запустить собственную остановленную ноду.'
        fi
        NODE_STOPPED=0
    fi
    if [[ -n $SELECTED_IMAGE ]]; then
        (( NODE_NEW==1 )) || die 3 'Выбор образа допустим только при первой установке; действующая нода сохраняется.'
        docker pull "$SELECTED_IMAGE" || die 3 'Не удалось загрузить выбранный официальный образ.'
        SELECTED_IMAGE=$(docker image inspect -f '{{.Id}}' "$SELECTED_IMAGE")
        XRAY_BIN=''
        for candidate in /usr/local/bin/rw-core /usr/local/bin/xray xray;do
            if XRAY_VERSION=$(docker run --rm --network none --entrypoint "$candidate" "$SELECTED_IMAGE" version 2>/dev/null);then XRAY_BIN=$candidate;break;fi
        done
        XRAY_VERSION=${XRAY_VERSION%%$'\n'*}
        [[ -n $XRAY_BIN && $(helper xff-version "$XRAY_VERSION") == 1 ]] || die 3 'Выбранный образ не поддерживает проверенный XHTTP/trustedXForwardedFor; выберите совместимую версию.'
        if (( SECURE_SOCKETS==1 ));then
            [[ $(docker run --rm --network none --entrypoint id "$SELECTED_IMAGE" -u) == 0 ]] || die 6 'Новый образ не работает от root; совместимость защищённых sockets не подтверждена.'
        fi
    fi
    if (( NODE_NEW==1 )); then
        [[ -n $SELECTED_IMAGE && -n $NODE_SECRET ]] || die 3 'Для новой ноды необходимы выбранный образ и SECRET_KEY.'
        ! docker container inspect "$NODE_CONTAINER" >/dev/null 2>&1 || die 3 'Контейнер с выбранным именем появился после диагностики; новая установка остановлена.'
        printf 'NODE_PORT=%s\nSECRET_KEY=%s\n' "$NODE_PORT" "$NODE_SECRET" | python3 -c 'import os,sys;fd=os.open(sys.argv[1],os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600);f=os.fdopen(fd,"w");f.write(sys.stdin.read());f.close()' "$OWN/node.env"
        unset NODE_SECRET
        helper fresh-compose "$BASE/docker-compose.yml" "$SELECTED_IMAGE"
        command install -d -m 755 /var/log/remnanode
        SERVICES_APPLIED=1
        "${COMPOSE_CMD[@]}" up -d --no-deps --pull never "$NODE_SERVICE"
    fi
    local _attempt
    XRAY_BIN=${XRAY_BIN:-/usr/local/bin/rw-core}
    for _attempt in {1..30}; do
        if docker exec "$NODE_CONTAINER" "$XRAY_BIN" version >/dev/null 2>&1; then break;fi
        sleep 1
    done
    XRAY_VERSION=$(docker exec "$NODE_CONTAINER" "$XRAY_BIN" version | sed -n '1p')
    [[ $(helper xff-version "$XRAY_VERSION") == 1 ]] || die 3 'Выбранный Xray старше проверенного синтаксиса trustedXForwardedFor.'
    if (( NGINX_NEW==1 )); then
        docker image inspect nginx:1.30 >/dev/null 2>&1 || docker pull nginx:1.30
    fi
    save_state
    if [[ -n $SELECTED_IMAGE ]]; then helper set "$STATE" node_image_id "\"$SELECTED_IMAGE\"";fi
    helper set "$STATE" node_new "$([[ $NODE_NEW == 1 || $origin_new == true ]] && printf true || printf false)"
}
configure_site() {
    helper assets "$WORK/bundle/beer-atlas/public" "$SITE_ROOT" "$OWN/assets.json" "$PUBLIC_ASSETS_REPLACE"
    chmod 755 "$SITE_ROOT"
    # Every parent of the public bind is traversable; state stays root-only.
    chmod 711 "$OWN"
    # Preflight proved ownership before any changes. Keep the unit/code/data
    # so a backup can restore the former game, but stop its unused process.
    if [[ -f /etc/systemd/system/nuvrion-pokehabitat.service ]];then
        helper owned-unit-check /etc/systemd/system/nuvrion-pokehabitat.service '# BEGIN NUVRION XHTTP GAME' || die 1 'Игровой unit изменился после проверки; остановка запрещена.'
        systemctl disable --now nuvrion-pokehabitat.service
        log_info 'Старый игровой сервис остановлен; Атлас пива обслуживается Nginx без Node.js.'
    fi
}
# Compatibility with ExecStartPost in a restored pre-Atlas game unit.
game_socket() {
    local _attempt
    for _attempt in {1..50}; do
        if [[ -S /run/nuvrion-pokehabitat/game.sock ]]; then
            chgrp "$WEB_GID" /run/nuvrion-pokehabitat/game.sock
            chmod 660 /run/nuvrion-pokehabitat/game.sock;return 0
        fi
        sleep 0.1
    done
    return 6
}
prevalidate_nginx() {
    local image cfg_target=/etc/nginx/nginx.conf
    declare -a args=(docker run --rm --network none --ulimit nofile=1048576:1048576 --entrypoint nginx)
    if [[ -n $NGINX_CONTAINER ]]; then
        image=$(docker inspect -f '{{.Image}}' "$NGINX_CONTAINER")
        args+=(--volumes-from "$NGINX_CONTAINER")
    elif [[ $NGINX_KIND == host ]]; then validate_nginx || die 5 'Проверка nginx -t не пройдена.';return 0
    else
        image=$(docker image inspect -f '{{.Id}}' nginx:1.30)
        args+=(-v "$NGINX_CONFIG:$cfg_target:ro" -v "$SITE_ROOT:/var/www/decoy:ro" -v /dev/shm:/dev/shm:rw)
    fi
    args+=(-v /etc/letsencrypt:/etc/letsencrypt:ro)
    "${args[@]}" "$image" -t -c "$NGINX_MAIN" || die 5 'Nginx отклонил конфигурацию; reload не выполняется.'
}
apply_compose() {
    SERVICES_APPLIED=1
    if (( NODE_RECREATE==1 )); then
        log_warn 'Пересоздание только Remnanode: VPN-соединения могут кратковременно прерваться.'
        "${COMPOSE_CMD[@]}" up -d --no-deps --pull never "$NODE_SERVICE"
    fi
    if [[ $NGINX_KIND == docker ]]; then
        if (( NGINX_RECREATE==1 )) || [[ -z $NGINX_CONTAINER ]]; then
            "${COMPOSE_CMD[@]}" up -d --no-deps --pull never --force-recreate "$NGINX_SERVICE"
            NGINX_CONTAINER=$("${COMPOSE_CMD[@]}" ps -q "$NGINX_SERVICE")
            [[ -n $NGINX_CONTAINER ]] || die 5 'Не найден запущенный служба Nginx.'
            helper set "$STATE" nginx_container "\"$NGINX_CONTAINER\""
        else reload_nginx;fi
    else reload_nginx;fi
    local _attempt
    for _attempt in {1..20}; do [[ -S $NGINX_SOCKET ]] && break;sleep 1;done
    validate_nginx || die 5 'Конфигурация Nginx не прошла проверку после запуска.'
}
configure_firewall_service() {
    cat <<EOF | helper owned-unit-write /etc/systemd/system/nuvrion-xhttp-firewall.service '# BEGIN NUVRION XHTTP FIREWALL'
# BEGIN NUVRION XHTTP FIREWALL
[Unit]
Description=Nuvrion XHTTP narrow firewall rules
After=network-pre.target ufw.service nftables.service netfilter-persistent.service
Before=docker.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$OWN/installer.sh --firewall-apply
[Install]
WantedBy=multi-user.target
# END NUVRION XHTTP FIREWALL
EOF
    chmod 644 /etc/systemd/system/nuvrion-xhttp-firewall.service
    systemctl daemon-reload;systemctl enable nuvrion-xhttp-firewall.service
}
security_plan() {
    local connection=${SSH_CONNECTION:-} candidate
    if [[ -n $connection ]];then
        read -r candidate _ _ _ <<< "$connection"
        [[ -n $ADMIN_IP ]] || ADMIN_IP=$candidate
        [[ -n $SSH_PORT ]] || SSH_PORT=${connection##* }
    fi
    [[ -n $SSH_PORT ]] || SSH_PORT=$(sshd -T 2>/dev/null | awk '$1=="port" {print $2;exit}')
    [[ -n $SSH_PORT ]] || die 1 'Не определён SSH-порт; задайте --ssh-port.'
    if (( NO_TRAFFIC==0 )) && [[ -z $ADMIN_IP ]];then
        (( YES==0 )) || die 1 'Для Traffic Control нужен --admin-ip или текущий SSH_CONNECTION.'
        prompt ADMIN_IP 'IP администратора для исключения Traffic Control' ''
    fi
    python3 -c 'import ipaddress,sys;assert 1<=int(sys.argv[2])<=65535;assert not sys.argv[1] or ipaddress.ip_address(sys.argv[1])' "$ADMIN_IP" "$SSH_PORT" || die 1 'Некорректный IP администратора/SSH-порт.'
    [[ $NODE_PORT != "$SSH_PORT" ]] || die 7 'Порт API ноды совпадает с SSH-портом. Выберите другой API-порт.'
    (( SSH_KEY_ONLY==0 && SSH_KEY_CONFIRMED==0 )) || die 1 'Изменения SSH отключены этой версией установщика.'
    log_info 'Оптимизация сервера: сеть, безопасность, Fail2ban, обновления, NTP/TRIM; SSH только аудит.'
    (( NO_PRIVACY==1 )) || log_info 'Two-Way Ping: собственные правила; PMTU и исходящий ping сохраняются.'
    (( NO_TRAFFIC==1 )) || log_info 'Traffic Control: списки, исключения панели/администратора, таймер и ntc.'

}
security_baseline() {
    [[ -f $STATE ]] || die 1 'Для компонентов безопасности нужна запись установленной ноды.'
    if [[ ! -f $OWN/components.json ]];then
        printf '{"traffic_owned":false,"privacy_owned":false}\n' > "$OWN/components.json"
        chmod 600 "$OWN/components.json"
    fi
    if [[ $(state_value components_backup) == '{}' ]];then
        helper set "$STATE" components_backup "\"$BACKUP\""
    fi
}
configure_ssh() { log_info 'SSH: только аудит; параметры и ключи не изменяются.'; }
configure_privacy() {
    (( NO_PRIVACY==0 )) || return 0
    local owned
    owned=$(helper get "$OWN/components.json" privacy_owned)
    if [[ $owned != true ]] && { [[ -e /usr/local/sbin/nuvrion-two-way-ping.sh || -e /etc/systemd/system/nuvrion-two-way-ping.service ]] || nft list table inet nuvrion_privacy >/dev/null 2>&1; };then
        log_info 'Two-Way Ping уже существует: проверяется без перезаписи.'
    else
        helper set "$OWN/components.json" privacy_owned true
        command install -m 755 "$WORK/bundle/nuvrion-two-way-ping.sh" /usr/local/sbin/nuvrion-two-way-ping.sh
        command install -m 644 "$WORK/bundle/nuvrion-two-way-ping.service" /etc/systemd/system/nuvrion-two-way-ping.service
        systemctl daemon-reload
        systemctl enable --now nuvrion-two-way-ping.service
        /usr/local/sbin/nuvrion-two-way-ping.sh start
    fi
    helper set "$STATE" privacy_expected true
}
configure_traffic_control() {
    (( NO_TRAFFIC==0 )) || return 0
    local owned=$OWN/components.json binary=/usr/local/bin/nuvrion-traffic-control
    local root=/var/lib/nuvrion-traffic-control
    if [[ $(helper get "$owned" traffic_owned) != true ]] && { [[ -e $binary || -e $root/state.json || -e /usr/local/bin/ntc ]] || nft list table inet nuvrion_tc >/dev/null 2>&1; };then
        [[ -x $binary ]] || die 7 'Найдены чужие/частичные данные Traffic Control; автоматическая перезапись запрещена.'
        "$binary" check || die 7 'Существующий Traffic Control не прошёл диагностику.'
        log_info 'Существующий Traffic Control сохранён; его включённый/выключенный режим не изменяется.'
    else
        helper set "$owned" traffic_owned true
        if [[ -f $root/state.json ]];then
            python3 "$WORK/bundle/nuvrion-traffic-control.py" repair --yes
            if [[ ! -e $root/enabled ]];then "$binary" activate;fi
        else
            python3 "$WORK/bundle/nuvrion-traffic-control.py" install --yes --ssh-port "$SSH_PORT" --allow "$PANEL_IP" --allow "$ADMIN_IP"
        fi
        # Explicit addresses remain in the allowlist on later runs; preserve
        # all manual bans and existing sources. Only add missing exceptions.
        "$binary" allow "$PANEL_IP"
        "$binary" allow "$ADMIN_IP"
        "$binary" check || die 7 'Traffic Control: проверка после установки не пройдена.'
    fi
    helper set "$STATE" traffic_expected true
    log_ok 'Traffic Control: программа, списки, исключения, журнал, меню и автообновление доступны.'
}
configure_security_components() {
    security_baseline
    # The upstream tuner handles the complete hardening/security module; the
    # installer owns firewall and TLS. Persist the Vision server/client TFO bits.
    if (( NO_TUNING==0 ));then
        printf '# BEGIN NUVRION XHTTP\nnet.ipv4.tcp_fastopen = 3\n# END NUVRION XHTTP\n' > /etc/sysctl.d/99-zzzzz-nuvrion-xhttp-tfo.conf
        chmod 644 /etc/sysctl.d/99-zzzzz-nuvrion-xhttp-tfo.conf
        sysctl -q -p /etc/sysctl.d/99-zzzzz-nuvrion-xhttp-tfo.conf
    fi
    configure_ssh
    configure_privacy
    # Apply the filter last, after packages, image pulls and ACME.
    configure_traffic_control
    helper delta "$(state_value components_backup)" "$OWN/components-delta.json"
}
validate_security_components() {
    local key value ok=1
    if [[ $(state_value security_expected) == true ]];then
        for key in kernel.dmesg_restrict fs.protected_hardlinks fs.protected_symlinks;do
            [[ $(sysctl -n "$key" 2>/dev/null) == 1 ]] || ok=0
        done
        check_result "$ok" 'Защита ядра включена'
        if systemctl is-active --quiet fail2ban.service && systemctl is-enabled --quiet fail2ban.service && fail2ban-client status sshd >/dev/null 2>&1;then check_result 1 'Fail2ban: SSH jail активен и включён'
        else check_result 0 'Fail2ban: SSH jail активен и включён';fi
        if apt-config dump | grep 'APT::Periodic::Unattended-Upgrade "1"' >/dev/null && systemctl is-active --quiet apt-daily-upgrade.timer;then check_result 1 'Автоматические обновления безопасности настроены'
        else check_result 0 'Автоматические обновления безопасности настроены';fi
        if [[ $(sysctl -n net.ipv4.tcp_fastopen) == 3 ]];then check_result 1 'TCP Fast Open: клиент и сервер'
        else check_result 0 'TCP Fast Open: клиент и сервер';fi
    fi
    if command -v sshd >/dev/null;then
        if sshd -t >/dev/null 2>&1;then check_result 1 'Конфигурация SSH проверена без изменений'
        else check_result 0 'Конфигурация SSH проверена без изменений';fi
    fi
    if [[ $(state_value privacy_expected) == true ]];then
        if systemctl is-active --quiet nuvrion-two-way-ping.service && systemctl is-enabled --quiet nuvrion-two-way-ping.service && nft list table inet nuvrion_privacy >/dev/null 2>&1;then check_result 1 'Two-Way Ping активен и включён'
        else check_result 0 'Two-Way Ping активен и включён';fi
    fi
    if [[ $(state_value traffic_expected) == true ]];then
        if /usr/local/bin/nuvrion-traffic-control check > /dev/null 2>&1;then check_result 1 'Traffic Control: конфигурация, правила и таймеры проверены'
        else check_result 0 'Traffic Control: конфигурация, правила и таймеры проверены';fi
        if [[ -f $OWN/components.json && $(helper get "$OWN/components.json" traffic_owned) == true ]];then
            if [[ -e /var/lib/nuvrion-traffic-control/enabled ]] && systemctl is-active --quiet nuvrion-traffic-control-update.timer;then check_result 1 'Фильтрация и обновление Traffic Control активны'
            else check_result 0 'Фильтрация и обновление Traffic Control активны';fi
        fi
    fi
}
security_stop() {
    [[ -f $OWN/components.json ]] || return 0
    if [[ $(helper get "$OWN/components.json" traffic_owned) == true ]];then
        systemctl stop nuvrion-traffic-control-update.timer nuvrion-traffic-control-update.service nuvrion-traffic-control-rollback.timer >/dev/null 2>&1 || true
        [[ ! -x /usr/local/bin/nuvrion-traffic-control ]] || /usr/local/bin/nuvrion-traffic-control disable
    fi
    if [[ $(helper get "$OWN/components.json" privacy_owned) == true ]];then
        systemctl stop nuvrion-two-way-ping.service >/dev/null 2>&1 || true
        if nft list table inet nuvrion_privacy >/dev/null 2>&1;then nft delete table inet nuvrion_privacy;fi
    fi
}
security_restore_runtime() {
    systemctl daemon-reload
    if systemctl is-active --quiet fail2ban.service;then fail2ban-client -t >/dev/null;systemctl reload-or-restart fail2ban.service;fi
    if [[ -x /usr/local/bin/nuvrion-traffic-control && -e /var/lib/nuvrion-traffic-control/enabled ]];then /usr/local/bin/nuvrion-traffic-control restore;fi
}
repair_owned_rps() {
    [[ $(state_value rps_managed) == true ]] || return 0
    local script=/usr/local/sbin/nuvrion-rps-setup.sh unit=/etc/systemd/system/nuvrion-rps.service flows
    [[ -f $OWN/rps-managed.sh && -f $OWN/rps-managed.service ]] || die 1 'Нет сохранённых файлов собственного RPS.'
    [[ ! -L $script && ! -L $unit ]] || die 1 'Путь RPS является символической ссылкой.'
    if { [[ -f $script ]] && ! cmp -s "$script" "$OWN/rps-managed.sh"; } ||
       { [[ -f $unit ]] && ! cmp -s "$unit" "$OWN/rps-managed.service"; };then
        log_warn 'RPS изменён после установки; сохранённый шаблон не перезаписывает его.'
        return 0
    fi
    # Removal can restore RFS=0 while keeping the original nonzero RX masks.
    # The upstream helper then preserves those masks and exits early. Repair
    # only our recorded RFS allocation, without rewriting any RX queue.
    if [[ $(sysctl -n net.core.rps_sock_flow_entries) == 0 ]];then
        flows=$(awk -F"'" '/^FLOW_GLOBAL=/{print $2;exit}' "$OWN/rps-managed.sh")
        [[ $flows =~ ^[0-9]{1,8}$ && $flows != 0 ]] || die 1 'Некорректное сохранённое распределение RFS.'
        sysctl -q -w "net.core.rps_sock_flow_entries=$flows"
    fi
    if [[ ! -f $script || ! -f $unit ]];then
        command install -m 755 "$OWN/rps-managed.sh" "$script"
        command install -m 644 "$OWN/rps-managed.service" "$unit"
        systemctl daemon-reload
        systemctl enable --now nuvrion-rps.service
        log_ok 'Восстановлен автозапуск собственного RPS без сброса работающих RX-масок.'
    fi
}
capture_owned_rps() {
    local original script=/usr/local/sbin/nuvrion-rps-setup.sh unit=/etc/systemd/system/nuvrion-rps.service
    [[ -f $script && -f $unit && ! -L $script && ! -L $unit ]] || return 0
    original=$(state_value initial_backup)
    if [[ $(state_value rps_managed) != true &&
          ( -e $original/files$script || -e $original/files$unit ) ]];then return 0;fi
    command install -m 600 "$script" "$OWN/rps-managed.sh"
    command install -m 600 "$unit" "$OWN/rps-managed.service"
    helper set "$STATE" rps_managed true
}
validate_rps() {
    [[ $(state_value rps_managed) == true ]] || return 0
    local ok=0
    if systemctl is-active --quiet nuvrion-rps.service && systemctl is-enabled --quiet nuvrion-rps.service &&
       python3 -c 'from pathlib import Path
import subprocess
iface=subprocess.check_output(["ip","-o","route","show","default"],text=True).split()[4]
paths=list(Path("/sys/class/net",iface,"queues").glob("rx-*/rps_cpus"))
assert paths and all(int(p.read_text().strip().replace(",",""),16)>0 for p in paths)
assert int(subprocess.check_output(["sysctl","-n","net.core.rps_sock_flow_entries"],text=True))>0';then ok=1;fi
    check_result "$ok" 'RPS: RX-маски, RFS и автозапуск подтверждены'
}
validate_tuning() {
    [[ $(state_value tuning_expected) == true ]] || return 0
    local results status title
    if results=$(helper tuning-check /etc/sysctl.d/99-zzzz-nuvrion-performance.conf /etc/sysctl.d/99-zzzzz-nuvrion-xhttp-tfo.conf /etc/modprobe.d/99-nuvrion-nf-conntrack.conf /var/lib/nuvrion-tuning/post-reboot-check.pending);then
        [[ -n $results ]] || { check_result 0 'Проверка тюнинга не вернула результатов';return 0; }
        while IFS=$'\t' read -r status title;do
            case $status in
                PASS) check_result 1 "$title";;
                WAIT) log_warn "Ожидание перезагрузки: $title";WAITS=$((WAITS+1));REBOOT_WAITS=$((REBOOT_WAITS+1));REBOOT_NEEDED=1;;
                *) check_result 0 "$title";;
            esac
        done <<< "$results"
    else check_result 0 'Не удалось проверить фактическое состояние тюнинга';fi
}
apply_tuning() {
    (( NO_TUNING==0 )) || { log_warn 'Тюнинг пропущен по --no-tuning.';return 0; }
    security_baseline
    repair_owned_rps
    helper runtime-keys "$WORK/bundle/nuvrion-auto-tuning.sh" "$OWN/runtime-keys.json"
    # Protect existing SSH/Docker/host Xray from vendor fallback restarts.
    # The pinned performance logic is embedded; its firewall delegates above.
    # Invoked indirectly by the embedded performance subprocess.
    # shellcheck disable=SC2329
    systemctl() {
        case " $* " in *' ssh.service '*|*' sshd.service '*|*' xray.service '*|*' remnanode.service '*)
            case $1 in restart|stop|disable|cat) return 1;;esac;;esac
        case $1 in restart|stop) [[ " $* " != *' docker.service '* ]] || return 1;;esac
        command systemctl "$@"
    }
    # shellcheck disable=SC2329
    docker() {
        case $1 in restart|stop|kill) return 1;;compose)
            case " $* " in *' up '*|*' down '*|*' restart '*) return 1;;esac;;esac
        command docker "$@"
    }
    export -f systemctl docker
    local rc=0
    NEEDRESTART_MODE=l NEEDRESTART_SUSPEND=1 NUVRION_ASSUME_YES=1 \
      NUVRION_SECURITY=1 NUVRION_INSTALL_SECURITY_PACKAGES=0 NUVRION_HARDEN_SSH=0 \
      NUVRION_SSH_KEY_LOGIN_CONFIRMED=0 NUVRION_MANAGED_FIREWALL=1 NUVRION_ENABLE_UFW=0 \
      NUVRION_ALLOW_NODE_RECREATE=0 NUVRION_ALLOW_DOCKER_RESTART=0 NUVRION_CERTIFICATES=0 \
      NUVRION_INSTALL_ZRAM_MODULES=1 NUVRION_PANEL_PORT="$NODE_PORT" NUVRION_PANEL_IPS="$PANEL_IP" \
      bash -c '
        source "$1"
        # Reuse the pinned tuner setup without resetting an active swap. Its
        # original active-swap branch does not repair a missing boot service.
        if [[ -n $(get_active_zram) ]] && ! has_external_zram_manager;then
            if [[ ! -f $ZRAM_SERVICE || ! -f $ZRAM_SETUP ]] ||
               ! systemctl is-enabled --quiet nuvrion-zram.service ||
               ! systemctl is-active --quiet nuvrion-zram.service;then
                create_or_repair_nuvrion_zram || exit 1
            fi
        fi
      ' nuvrion-tuning "$WORK/bundle/nuvrion-auto-tuning.sh" < /dev/null > "$OWN/tuning-report.log" 2>&1 || rc=$?
    unset -f systemctl docker
    (( rc==0 )) || die 1 'Тюнинг завершился ошибкой; отчёт в /opt/remnanode/nuvrion-xhttp/tuning-report.log.'
    capture_owned_rps
    helper set "$STATE" security_expected true
    log_ok 'Применены улучшения сервера и сети из Nuvrion Vision.'
}
zram_pending_ready() {
    local kernel running
    [[ -r /var/lib/nuvrion-tuning/zram-pending-kernel ]] || return 1
    kernel=$(< /var/lib/nuvrion-tuning/zram-pending-kernel)
    running=$(uname -r)
    [[ $kernel =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[A-Za-z0-9-]+$ && ${kernel##*-} == "${running##*-}" ]] || return 1
    dpkg --compare-versions "$kernel" gt "$running" || return 1
    [[ -s /boot/vmlinuz-$kernel && -s /boot/initrd.img-$kernel ]] || return 1
    compgen -G "/lib/modules/$kernel/kernel/drivers/block/zram/zram.ko*" >/dev/null || return 1
    systemctl is-enabled --quiet nuvrion-zram.service
}
zram_autostart_ready() {
    local unit
    if [[ -f /etc/systemd/system/nuvrion-zram.service ]];then
        systemctl is-active --quiet nuvrion-zram.service && systemctl is-enabled --quiet nuvrion-zram.service
        return
    fi
    # Known external managers remain in charge. Generated swap units prove
    # persistence for systemd-zram-generator; an active device alone does not.
    while read -r unit _;do
        [[ -n $unit ]] || continue
        if systemctl is-active --quiet "$unit" && systemctl is-enabled --quiet "$unit";then return 0;fi
    done < <(systemctl list-units --all --no-legend --plain '*zram*.service' 'dev-zram*.swap' 2>/dev/null)
    return 1
}
validate_zram() {
    local active
    active=$(swapon --noheadings --show=NAME 2>/dev/null | awk '$1 ~ /^\/dev\/zram[0-9]+$/ {print $1}')
    if [[ -n $active ]];then
        if ! zram_autostart_ready;then
            ZRAM_STATUS=BROKEN;check_result 0 'ZRAM swap существует, но его служба/автозапуск не подтверждены';return 0
        fi
        ZRAM_STATUS=RUNNING;check_result 1 "Активный swap ZRAM: $active"
        zramctl --bytes --output NAME,ALGORITHM,DISKSIZE,DATA,COMPR,TOTAL 2>/dev/null || true
        swapon --show=NAME,TYPE,SIZE,USED,PRIO
    elif zram_pending_ready;then
        ZRAM_STATUS=REBOOT_REQUIRED;REBOOT_NEEDED=1;WAITS=$((WAITS+1));REBOOT_WAITS=$((REBOOT_WAITS+1))
        log_warn 'Ожидание: ZRAM: новое ядро, модуль и автозапуск подготовлены; требуется перезагрузка.'
    else
        ZRAM_STATUS=BROKEN;check_result 0 'ZRAM не работает; подготовленный запуск после перезагрузки не подтверждён'
    fi
    [[ ! -e /run/reboot-required ]] || REBOOT_NEEDED=1
}

maintain() {
    load_settings
    [[ -f $STATE && $(state_value removed) != true ]] || die 3 'Обслуживание требует установленную XHTTP-ноду.'
    run_diagnostics
    (( FAILS==0 )) || log_warn 'Обнаружены проблемы. Обслуживание проверит ZRAM повторно после изменений.'
    printf '\n  Будет изменено: системные пакеты, нужные зависимости и улучшения Nuvrion Vision.\n'
    package_plan
    security_plan
    log_info 'Профиль, ключи REALITY, Compose и версии образов остаются текущими.'
    (( YES==1 )) || ask_yes 'Применить обслуживание после резервного копирования?' || return 0
    create_backup;TRANSACTION=1
    touch "$LOG";chmod 600 "$LOG";LOG_ENABLED=1
    unpack_bundle;begin_package_maintenance;install_dependencies;capture_transaction
    apply_tuning;capture_transaction
    configure_security_components;capture_transaction
    (( NO_TUNING==1 )) || helper set "$STATE" tuning_expected true
    cleanup_system_packages;end_package_maintenance
    helper set "$STATE" last_backup "\"$BACKUP\""
    helper runtime-after "$OWN/sysctl-after.json"
    helper rps-snapshot "$OWN/rps-after.json"
    run_diagnostics
    (( FAILS==0 )) || die 1 'Проверки после обслуживания не пройдены.'
    helper delta "$(state_value initial_backup)" "$OWN/owned-delta.json"
    TRANSACTION=0
    log_ok "Обслуживание завершено. XHTTP: $(display_status); ZRAM: $(display_zram); резервная копия: $BACKUP"
    if (( REBOOT_NEEDED==1 ));then log_warn 'Требуется перезагрузка; затем выполните --diagnose. Автоматическая перезагрузка не выполняется.';fi
}

restore_services() {
    local old_config=$1 node_changed=$2 ng_changed=$3
    [[ -f $STATE ]] && load_settings
    if [[ -f $old_config ]]; then
        NODE_SERVICE=$(helper get "$old_config" node_service);PROJECT=$(helper get "$old_config" project)
        WORKDIR=$(helper get "$old_config" workdir)
        mapfile -t COMPOSE_FILES < <(python3 -c 'import json,sys;print("\n".join(json.load(open(sys.argv[1]))["compose_files"]))' "$old_config")
        if [[ $(helper get "$old_config" removed) == true && ! -f $OVERRIDE ]];then
            local -a removed_files=();local restored_file
            for restored_file in "${COMPOSE_FILES[@]}";do [[ $restored_file == "$OVERRIDE" ]] || removed_files+=("$restored_file");done
            COMPOSE_FILES=("${removed_files[@]}")
            compose_command
            (( node_changed==0 )) || "${COMPOSE_CMD[@]}" up -d --no-deps --pull never "$NODE_SERVICE"
            [[ $(helper get "$old_config" nginx_new) != true ]] || return 0
        fi
        compose_command
        if (( node_changed==1 )); then
            log_warn 'Восстановление точек подключения и образа только ноды; VPN-соединения могут кратковременно прерваться.'
            "${COMPOSE_CMD[@]}" up -d --no-deps --pull never "$NODE_SERVICE"
        fi
        NGINX_KIND=$(helper get "$old_config" nginx_kind)
        NGINX_CONTAINER=$(helper get "$old_config" nginx_container)
        NGINX_SERVICE=$(helper get "$old_config" nginx_service)
        NGINX_MAIN=$(helper get "$old_config" nginx_main)
        if [[ $NGINX_KIND == docker && $ng_changed == 1 ]]; then
            "${COMPOSE_CMD[@]}" up -d --no-deps --pull never --force-recreate "$NGINX_SERVICE"
            NGINX_CONTAINER=$("${COMPOSE_CMD[@]}" ps -q "$NGINX_SERVICE")
        fi
        [[ -z $NGINX_CONTAINER && $NGINX_KIND != host ]] || reload_nginx
    else
        # Original Compose still exists: recreate only if its mount changed.
        COMPOSE_FILES=("${COMPOSE_FILES[@]/$OVERRIDE/}")
        local -a filtered=();local file
        for file in "${COMPOSE_FILES[@]}";do [[ -z $file ]] || filtered+=("$file");done
        COMPOSE_FILES=("${filtered[@]}");compose_command
        if (( node_changed==1 && NODE_NEW==0 )); then "${COMPOSE_CMD[@]}" up -d --no-deps --pull never "$NODE_SERVICE";fi
        if [[ $NGINX_NEW == 0 ]]; then
            if [[ $NGINX_KIND == docker && $ng_changed == 1 ]]; then
                "${COMPOSE_CMD[@]}" up -d --no-deps --pull never "$NGINX_SERVICE"
            fi
            [[ -z $NGINX_CONTAINER && $NGINX_KIND != host ]] || reload_nginx
        fi
    fi
}
restore_node_running() {
    local folder=$1
    [[ -f $folder/node-running.txt && $(< "$folder/node-running.txt") == false ]] || return 0
    # Only an installer-created stopped node is eligible for automatic repair.
    # Return that same node to its pre-transaction stopped state on rollback.
    [[ $(docker inspect -f '{{index .Config.Labels "io.nuvrion.xhttp.installed"}}' "$NODE_CONTAINER" 2>/dev/null) == true ]] || die 3 'Не подтверждено владение остановленной нодой для восстановления её состояния.'
    docker stop "$NODE_CONTAINER" >/dev/null || die 3 'Не удалось вернуть ноду в исходное остановленное состояние.'
}
rollback() {
    local folder=${1:-$BACKUP} journal=${2:-${1:-$BACKUP}/after-delta.json} selection keep_state node_changed=$NODE_RECREATE ng_changed=$NGINX_RECREATE
    [[ -n $folder && -f $folder/files.json ]] || die 1 'Резервная копия не найдена.'
    [[ -f $journal ]] || die 1 'Нет журнала принадлежащих установщику изменений; автоматическое восстановление запрещено.'
    selection=$(helper rollback-selection "$folder/files.json" "$OWN/components.json")
    # Reject foreign edits BEFORE stopping services/removing firewall rules.
    helper restore-check "$folder" "$journal" <<< "$selection" || die 1 'Восстановление отменено до изменений: файлы отличаются от журнала владения.'
    RESTORING=1;TRANSACTION=0
    keep_state=$(mktemp /tmp/nuvrion-rollback-state.XXXXXXXX)
    if [[ -f $folder/files/opt/remnanode/nuvrion-xhttp/state.json ]];then cp "$folder/files/opt/remnanode/nuvrion-xhttp/state.json" "$keep_state";else rm -f "$keep_state";fi
    [[ ! -f /run/nuvrion-xhttp-acme.json ]] || acme_post
    [[ -z $FW ]] || firewall_remove
    if [[ $NGINX_NEW == 1 && -n $NGINX_CONTAINER ]] && { [[ ! -f $keep_state ]] || [[ $(helper get "$keep_state" removed) == true ]]; };then
        docker stop "$NGINX_CONTAINER" >/dev/null;docker rm "$NGINX_CONTAINER" >/dev/null
    fi
    if [[ ! -f $keep_state ]] && { (( NODE_NEW==1 )) || [[ $(state_value node_new) == true ]]; } &&
       [[ $(docker inspect -f '{{index .Config.Labels "io.nuvrion.xhttp.installed"}}' "$NODE_CONTAINER" 2>/dev/null || true) == true ]];then
        docker stop "$NODE_CONTAINER" >/dev/null 2>&1 || true
        docker rm "$NODE_CONTAINER" >/dev/null 2>&1 || true
        NODE_NEW=1
    fi
    security_stop
    restore_unit_states "$folder" before
    restore_sysctl "$folder"
    helper rps-restore "$folder/rps-runtime.json" "$OWN/rps-after.json"
    # Issued certificates are retained. Restore only our hook modification;
    # replacing all of /etc/letsencrypt could erase another lineage renewed
    # concurrently. The complete tree remains available in the резервную копию.
    if [[ -n $CERT_LINEAGE && -f $OWN/renewal-original.conf ]];then
        local renewal=/etc/letsencrypt/renewal/${CERT_LINEAGE##*/}.conf
        if [[ -f $folder/files$renewal ]];then cp "$folder/files$renewal" "$renewal"
        else helper unhook "$renewal" "$OWN/renewal-original.conf";fi
    fi
    helper rollback-runtime-journal "$journal"
    helper restore "$folder" "$journal" <<< "$selection"
    systemctl daemon-reload
    restore_unit_states "$folder" after
    security_restore_runtime
    if [[ -f $keep_state ]];then
        PANEL_IP=$(helper get "$keep_state" panel_ip);FW=$(helper get "$keep_state" firewall);configure_firewall
    fi
    if (( SERVICES_APPLIED==1 ));then restore_services "$keep_state" "$node_changed" "$ng_changed";fi
    restore_node_running "$folder"
    rm -f "$keep_state"
    log_ok "Откат выполнен: $folder"
    RESTORING=0
}
restore_sysctl() {
    local folder=$1 key value expected current after_file=$OWN/sysctl-after.json
    [[ -f $folder/sysctl-runtime.txt && -f $after_file ]] || return 0
    while IFS=$'\t' read -r key value expected;do
        [[ -n $key ]] || continue
        current=$(sysctl -n "$key" 2>/dev/null || true)
        [[ -n $current && $current == "$expected" ]] || continue
        sysctl -q -w "$key=$value" 2>/dev/null || log_warn "Текущее значение sysctl $key применится после перезагрузки."
    done < <(python3 -c 'import json,sys
before={}
for line in open(sys.argv[1]):
 if " = " in line:k,v=line.rstrip("\n").split(" = ",1);before[k]=v
after=json.load(open(sys.argv[2]))
for k,v in after.items():
 if k in before and before[k]!=v:print(k,before[k],v,sep="\t")' "$folder/sysctl-runtime.txt" "$after_file")
}
restore_unit_states() {
    local folder=$1 phase=$2 keep_firewall=${3:-0} unit active enabled
    [[ -f $folder/units.json ]] || return 0
    while IFS=$'\t' read -r unit active enabled;do
        [[ $unit != nuvrion-xhttp-firewall.service || $keep_firewall == 0 ]] || continue
        case $unit in fail2ban.service|apt-daily.timer|apt-daily-upgrade.timer)
            if [[ $phase == before ]];then
                [[ $active == active ]] || systemctl stop "$unit" >/dev/null 2>&1 || true
                [[ $enabled == enabled || $enabled == enabled-runtime ]] || systemctl disable "$unit" >/dev/null 2>&1 || true
            else
                [[ $enabled != enabled && $enabled != enabled-runtime ]] || systemctl enable "$unit" >/dev/null
                [[ $active != active ]] || systemctl start "$unit"
            fi
            continue;;esac
        if [[ $phase == before ]];then
            if [[ $unit == nuvrion-pokehabitat.service || $active != active || ! -f $folder/files/etc/systemd/system/$unit ]];then systemctl stop "$unit" >/dev/null 2>&1 || true;fi
            if [[ $enabled != enabled && $enabled != enabled-runtime || ! -f $folder/files/etc/systemd/system/$unit ]];then systemctl disable "$unit" >/dev/null 2>&1 || true;fi
        elif [[ -f /etc/systemd/system/$unit ]];then
            if [[ $enabled == enabled || $enabled == enabled-runtime ]];then systemctl enable "$unit" >/dev/null;fi
            if [[ $active == active ]];then systemctl start "$unit";fi
            # These enabled oneshot services normally report "inactive"
            # after completion. Reapply their restored settings explicitly.
            if [[ $enabled == enabled || $enabled == enabled-runtime ]];then
                case $unit in nuvrion-performance-sysctl.service|nuvrion-rps.service) systemctl restart "$unit";;esac
            fi
        fi
    done < <(python3 -c 'import json,sys
for unit,d in json.load(open(sys.argv[1])).items():print(unit,d["is-active"] or "unknown",d["is-enabled"] or "unknown",sep="\t")' "$folder/units.json")
}
restore_backup() {
    load_settings
    [[ -f $STATE ]] || die 1 'Нет записи установленной системы для восстановления.'
    detect_remnanode metadata || die 3 'Remnanode не обнаружен.'
    detect_nginx || die 5 'Nginx не обнаружен.'
    detect_firewall
    BACKUP=${BACKUP_INPUT:-$(state_value last_backup)}
    helper get "$BACKUP/files.json" '' >/dev/null 2>&1 || [[ -f $BACKUP/files.json ]] || die 1 'Резервная копия отсутствует.'
    printf '  Восстановление: %s\n  Содержимое:\n' "$BACKUP"
    cat "$BACKUP/manifest.txt"
    log_warn 'Восстановление возвращает сохранённые конфигурации и точки подключения. VPN-соединения могут кратковременно прерваться.'
    (( YES==1 )) || ask_yes 'Восстановить эту резервную копию?' || exit 0
    if (( NODE_STOPPED==1 ));then assert_stopped_node_ports_free;fi
    NODE_RECREATE=1;NGINX_RECREATE=1;SERVICES_APPLIED=1
    rollback "$BACKUP" "$OWN/owned-delta.json"
    exit 8
}
uninstall() {
    load_settings
    [[ -f $STATE ]] || die 1 'Нет записи владения XHTTP-компонентами. Автоматическое удаление запрещено.'
    detect_os;detect_network
    detect_remnanode || die 3 'Remnanode не обнаружен.'
    detect_nginx || die 5 'Nginx не обнаружен.'
    detect_firewall
    local original selection old_ng=$NGINX_NEW components_backup security_selection='[]'
    original=$(state_value initial_backup)
    [[ -f $OWN/owned-delta.json && -f $original/files.json ]] || die 1 'Для безопасного удаления нужны опись и исходная резервная копия.'
    helper asset-check "$SITE_ROOT" "$OWN/assets.json" || die 1 'Сайт изменён пользователем; автоматическое удаление запрещено.'
    log_info 'Будут удалены только маркированные XHTTP location, собственный Nginx и правила/hook/service установщика; файлы тюнинга восстановлены по описи.'
    log_info 'Remnanode, Docker, сертификаты и данные игроков сохраняются.'
    log_warn 'Возврат точек подключения потребует пересоздания только ноды. VPN-соединения могут кратковременно прерваться.'
    (( YES==1 )) || ask_yes 'Удалить компоненты, принадлежащие этому установщику?' || exit 0
    create_backup;TRANSACTION=1
    # Removal can stop/delete Nginx before a later guard rejects a file. The
    # rollback must restore the running service as well as its saved files.
    SERVICES_APPLIED=1;NGINX_RECREATE=1
    components_backup=$(state_value components_backup)
    if [[ -f $OWN/components-delta.json && -f $components_backup/files.json ]];then
        security_selection=$(helper security-selection "$OWN/components.json")
        security_stop
        restore_unit_states "$components_backup" before 1
        helper restore-delta "$components_backup" "$OWN/components-delta.json" <<< "$security_selection"
    fi
    if [[ $NGINX_NEW == 0 ]];then helper unpatch-nginx "$NGINX_CONFIG" "$OWN/nginx-patch.json";fi
    if [[ -n $CERT_LINEAGE && -f $OWN/renewal-original.conf ]];then helper unhook "/etc/letsencrypt/renewal/${CERT_LINEAGE##*/}.conf" "$OWN/renewal-original.conf";fi
    restore_unit_states "$original" before 1
    restore_sysctl "$original"
    helper rps-restore "$original/rps-runtime.json" "$OWN/rps-after.json"
    # The preserved Remnanode must keep its API restricted after removal.
    helper set "$STATE" removed true
    configure_firewall
    if [[ $old_ng == 1 && -n $NGINX_CONTAINER ]];then docker stop "$NGINX_CONTAINER" >/dev/null;docker rm "$NGINX_CONTAINER" >/dev/null;fi
    selection=$(helper uninstall-selection "$original/files.json" "$OWN" "$BASE/docker-compose.yml" "$NGINX_CONFIG")
    # Files from later installs are compared against the current ownership
    # manifest, while the initial backup supplies their original contents.
    NODE_RECREATE=1
    helper restore-delta "$original" "$OWN/owned-delta.json" core <<< "$selection"
    if [[ -f $original/files/opt/remnanode/docker-compose.nuvrion-xhttp.json ]];then cp "$original/files/opt/remnanode/docker-compose.nuvrion-xhttp.json" "$OVERRIDE"
    else rm -f "$OVERRIDE";fi
    # Fresh Remnanode keeps its root-only panel credentials after removal.
    if [[ $(state_value node_new) == true ]];then
        local node_env=$BASE/nuvrion-node.env
        cp "$OWN/node.env" "$node_env";chmod 600 "$node_env"
        python3 -c 'import json,sys;from pathlib import Path;p=Path(sys.argv[1]);d=json.loads(p.read_text());d["services"]["remnanode"]["env_file"]=[sys.argv[2]];p.write_text(json.dumps(d,indent=2)+"\n")' "$BASE/docker-compose.yml" "$node_env"
    fi
    local -a remaining=();local f
    for f in "${COMPOSE_FILES[@]}";do [[ $f == "$OVERRIDE" && ! -f $f ]] || remaining+=("$f");done
    COMPOSE_FILES=("${remaining[@]}");compose_command
    "${COMPOSE_CMD[@]}" up -d --no-deps --pull never "$NODE_SERVICE"
    if [[ $old_ng == 0 ]];then
        if [[ $NGINX_KIND == docker ]];then "${COMPOSE_CMD[@]}" up -d --no-deps --pull never "$NGINX_SERVICE";fi
        reload_nginx
    fi
    systemctl daemon-reload
    restore_unit_states "$original" after 1
    if [[ -f $components_backup/units.json ]];then restore_unit_states "$components_backup" after 1;fi
    security_restore_runtime
    # Leave state/backup references and SQLite data for recovery. No recursive
    # deletion of a shared /opt/remnanode or game data directory is performed.
    helper set "$STATE" removed true
    for selection in security_expected ssh_managed ssh_key_only privacy_expected traffic_expected;do helper set "$STATE" "$selection" false;done
    TRANSACTION=0
    log_ok "XHTTP-компоненты удалены; API остаётся доступен только панели; резервная копия: $BACKUP"
}
display_zram() {
    case $ZRAM_STATUS in RUNNING) printf 'активен';;REBOOT_REQUIRED) printf 'ожидает перезагрузки';;BROKEN) printf 'проверка не пройдена';;*) printf 'не настраивался';;esac
}
display_status() {
    case $STATUS in
        RUNNING) printf 'работает' ;; BROKEN) printf 'есть ошибки' ;;
        WAITING_FOR_REMNAWAVE_PROFILE) printf 'ожидает применения профиля Remnawave' ;;
        WAITING_FOR_REBOOT) printf 'ожидает перезагрузки' ;;
        'PARTIALLY INSTALLED') printf 'установлено частично' ;; *) printf 'не установлен' ;;
    esac
}
report_row() {
    local title=$1 value=$2 padding width=20 columns=${COLUMNS:-80} remaining prefix part
    # Controlled labels contain single-width Latin/Cyrillic glyphs. Bash counts
    # characters in C.UTF-8; ANSI is never included in the aligned label.
    [[ $columns =~ ^[0-9]{1,3}$ ]] || columns=80
    columns=$((10#$columns));(( columns>=24 )) || columns=24;(( columns<=80 )) || columns=80
    if (( columns<48 ));then
        printf '  %s:\n' "$title"
        ui_message '   ' '' "$value"
        return 0
    fi
    padding=$((width-${#title}));(( padding>=0 )) || padding=0
    printf -v prefix '  %s%*s  ' "$title" "$padding" ''
    remaining=$((columns-${#prefix}))
    while (( ${#value}>remaining ));do
        part=${value:0:remaining};[[ $part != *' '* ]] || part=${part% *}
        [[ -n $part ]] || part=${value:0:remaining}
        printf '%s%s\n' "$prefix" "$part"
        value=${value:${#part}};value=${value# };printf -v prefix '%*s' "${#prefix}" ''
    done
    printf '%s%s\n' "$prefix" "$value"
}
final_report() {
    local actual traffic_state
    ui_heading "ИТОГОВЫЙ ОТЧЁТ · Nuvrion v$INSTALLER_VERSION"
    report_row 'Компонент' 'Фактическое состояние'
    if timeout 10 docker info >/dev/null 2>&1;then report_row Docker '✓ установлен; служба доступна';else report_row Docker '✗ служба недоступна';fi
    if docker compose version >/dev/null 2>&1;then report_row 'Docker Compose' '✓ установлен';else report_row 'Docker Compose' '✗ недоступен';fi
    actual=$(docker inspect -f '{{.State.Running}}' "$NODE_CONTAINER" 2>/dev/null || true)
    if [[ $actual == true ]];then report_row 'Remnawave Node' "✓ запущен ($NODE_CONTAINER)";else report_row 'Remnawave Node' '✗ не запущен';fi
    actual=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
    if [[ $actual == bbr ]];then report_row BBR '✓ включён';else report_row BBR "! ${actual:-недоступен}";fi
    actual=$(sysctl -n net.core.default_qdisc 2>/dev/null || true)
    if [[ $actual == fq ]];then report_row qdisc '✓ fq по умолчанию';else report_row qdisc "! ${actual:-недоступен}";fi
    case $ZRAM_STATUS in RUNNING) report_row ZRAM '✓ активен; автозапуск проверен';;REBOOT_REQUIRED) report_row ZRAM '! подготовлен; требуется перезагрузка';;BROKEN) report_row ZRAM '✗ проверка не пройдена';;*)
        actual=$(swapon --noheadings --show=NAME 2>/dev/null | awk '$1 ~ /^\/dev\/zram[0-9]+$/ {print $1}')
        if [[ -n $actual ]];then report_row ZRAM '! swap активен; автозапуск не проверен';else report_row ZRAM '• не активен; не настраивался';fi;;esac
    if systemctl is-active --quiet fail2ban.service && fail2ban-client status sshd >/dev/null 2>&1;then report_row Fail2ban '✓ SSH jail активен';else report_row Fail2ban '! SSH jail не активен или не проверен';fi
    if systemctl is-active --quiet certbot.timer && systemctl is-enabled --quiet certbot.timer;then report_row Certbot '✓ таймер продления активен';else report_row Certbot '✗ таймер продления не активен';fi
    if systemctl is-active --quiet nuvrion-two-way-ping.service && nft list table inet nuvrion_privacy >/dev/null 2>&1;then report_row 'Two-Way Ping' '✓ активен';else report_row 'Two-Way Ping' '• не активен';fi
    if [[ -x /usr/local/bin/nuvrion-traffic-control ]];then
        if actual=$(timeout 10 /usr/local/bin/nuvrion-traffic-control status --json 2>/dev/null) &&
           traffic_state=$(python3 -c 'import json,sys
x=json.load(sys.stdin)
assert all(isinstance(x.get(k),bool) for k in ("enabled","filter_active","pending"))
print("pending" if x["pending"] else "active" if x["enabled"] and x["filter_active"] else "disabled" if not x["enabled"] and not x["filter_active"] else "broken")' <<< "$actual" 2>/dev/null);then
            case $traffic_state in
                active)
                    if systemctl is-active --quiet nuvrion-traffic-control-update.timer && systemctl is-enabled --quiet nuvrion-traffic-control-update.timer;then report_row 'Traffic Control' '✓ фильтрация и автообновление активны';else report_row 'Traffic Control' '! фильтрация включена; автозапуск таймера не подтверждён';fi;;
                disabled) report_row 'Traffic Control' '• установлен; фильтрация выключена';;
                pending) report_row 'Traffic Control' '! включение фильтрации не завершено';;
                *) report_row 'Traffic Control' '! состояние фильтрации не согласовано; требуется проверка';;
            esac
        else report_row 'Traffic Control' '! фактическое состояние фильтрации не определено';fi
    else report_row 'Traffic Control' '• не установлен';fi
    printf '\n'
    report_row 'Состояние' "$(display_status)"
    report_row 'Ошибки / ожидания' "$FAILS / $WAITS"
    report_row 'Домен' "$DOMAIN"
    report_row Xray "${XRAY_VERSION/unknown/не определён}"
    report_row 'API ноды' ":$NODE_PORT; разрешённый IP панели: $PANEL_IP"
    report_row 'Сайт декой' "HTTP $DECOY_CODE"
    report_row 'Маршрут XHTTP' "HTTP $ROUTE_CODE"
    report_row 'Сокет Nginx' "$NGINX_SOCKET"
    report_row 'Сокет XHTTP' "$([[ -S $XHTTP_SOCKET ]] && printf '%s' "$XHTTP_SOCKET" || printf 'ожидает применения профиля Remnawave')"
    report_row 'Путь XHTTP' "$XHTTP_PATH"
    report_row 'Сертификат TLS' "$CERT_LINEAGE"
    if [[ -n $CERT_LINEAGE ]];then
        actual=$(openssl x509 -in "$CERT_LINEAGE/fullchain.pem" -noout -enddate 2>/dev/null || true)
        report_row 'Срок сертификата' "${actual#notAfter=}"
    fi
    report_row 'Открытый ключ REALITY' "$PUBLIC_KEY"
    report_row 'Резервная копия' "$BACKUP"
    report_row 'Профиль Remnawave' "$PROFILE"
    report_row 'Настройки Host' "$HOSTS"
    report_row 'Параметры extra' "$EXTRA"
    if (( FAILS>0 ));then log_error 'Итоговая проверка выявила ошибки.'
    elif (( WAITS>0 ));then log_warn 'Инфраструктура подготовлена; полная готовность ещё не подтверждена.'
    else log_ok 'Обязательные проверки системы пройдены. Клиентские интеграционные тесты выполняются отдельно.';fi
    (( REBOOT_NEEDED==0 )) || log_warn 'Требуется перезагрузка, затем --diagnose.'
    if (( WAITS>REBOOT_WAITS ));then
        log_warn 'Вставьте JSON в профиль Remnawave и назначьте оба inbound ноде.'
        log_info 'Создайте два Host по сохранённой инструкции, затем повторите --diagnose.'
        log_info 'Поле xHTTP extra parameters можно оставить пустым: extra уже в профиле.'
    fi
}
install() {
    load_settings;plan_install
    create_backup;TRANSACTION=1
    command install -d -m 700 "$OWN"
    touch "$LOG";chmod 600 "$LOG";LOG_ENABLED=1
    unpack_bundle;begin_package_maintenance;install_dependencies;capture_transaction
    [[ ! -f $STATE ]] || helper set "$STATE" removed false
    # Restrict the API BEFORE a new Remnanode can bind its public host port.
    configure_firewall;prepare_node;configure_firewall_service;capture_transaction
    configure_certbot;capture_transaction
    configure_socket_directory;configure_site;configure_nginx;configure_shared_shm;capture_transaction
    generate_reality_keys;generate_remnawave_profile;capture_transaction
    prevalidate_nginx;apply_compose;apply_tuning;capture_transaction
    configure_security_components;capture_transaction
    (( NO_TUNING==1 )) || helper set "$STATE" tuning_expected true
    cleanup_system_packages;end_package_maintenance
    helper runtime-after "$OWN/sysctl-after.json"
    helper rps-snapshot "$OWN/rps-after.json"
    run_diagnostics
    (( FAILS==0 )) || die 1 'Приёмочные проверки не пройдены. Успех не объявляется.'
    if (( WAITS==REBOOT_WAITS ));then touch "$OWN/profile-applied";chmod 600 "$OWN/profile-applied";helper set "$STATE" profile_pending false;fi
    local initial
    initial=$(state_value initial_backup)
    helper delta "$initial" "$OWN/owned-delta.json"
    TRANSACTION=0;final_report
}
reinstall() { install; }
cleanup() {
    local rc=$?;trap - EXIT ERR INT TERM
    end_package_maintenance || { log_error 'Не удалось восстановить APT policy; используйте сохранённую копию из резервной копии.';rc=1; }
    if (( rc!=0 && TRANSACTION==1 && RESTORING==0 ));then
        # A failed tuning stage may already have changed live sysctl/RPS.
        # Record those values before comparing them with the before snapshot.
        capture_runtime_after || { log_error 'Не удалось сохранить runtime-снимок; автоматический откат запрещён.';TRANSACTION=0;rc=1; }
        capture_transaction || { log_error 'Не удалось записать журнал изменений; автоматический откат запрещён.';TRANSACTION=0;rc=1; }
        log_error "Ошибка (код $rc). Резервная копия: $BACKUP"
        if (( TRANSACTION==1 )) && { (( YES==1 )) || ask_yes 'Выполнить откат последнего изменения?'; };then
            rollback "$BACKUP";rc=8
            if (( SOCKET_DIR_CREATED==1 )) && [[ ! -e /etc/tmpfiles.d/nuvrion-xhttp.conf ]];then
                # Only the directory created by THIS transaction is eligible.
                # Live sockets and any unexpected content prevent removal.
                python3 -c 'import os,stat,subprocess
from pathlib import Path
p=Path("/dev/shm/nuvrion-xhttp")
if p.is_dir() and not p.is_symlink():
 active=subprocess.check_output(["ss","-xlpn"],text=True)
 if str(p)+"/" not in active:
  children=list(p.iterdir())
  if all(x.name in ("nginx.sock","xrxh.socket") and stat.S_ISSOCK(x.lstat().st_mode) and x.lstat().st_uid==0 for x in children):
   for x in children:x.unlink()
   p.rmdir()' || log_warn 'Каталог сокетов сохранён; проверьте его перед повторным запуском.'
            fi
        fi
    fi
    [[ -z $WORK || $WORK != /tmp/nuvrion-xhttp.* ]] || rm -rf -- "$WORK"
    exit "$rc"
}
usage() {
    cat <<'EOF'
Nuvrion XHTTP Installer v1.0.0
  --install | --reinstall | --maintain | --diagnose | --self-check | --remove | --restore
  --domain DOMAIN --panel-port PORT --panel-ip IP --email EMAIL --node-tag TAG
      --panel-port: порт API ноды для панели, по умолчанию 2222; не порт веб-панели
  --xhttp-path /api/v3/sync/ --node-container NAME
  --node-version latest|X.Y.Z|keep
      новая нода: latest или доступная стабильная версия; существующая: только keep
  --harden-profile       (явная миграция профиля: защищённые сокеты, Cookie padding, AdGuard/COMSS)
  --secret-key-file /root/node-secret.txt   (root 0600; существующий ключ только проверяется)
  --profile-input /root/existing-profile.json
  Действующие ключи REALITY сохраняются; --allow-new-reality отклоняется.
  --backup /root/nuvrion-xhttp-backups/TIMESTAMP --no-tuning --no-updates --yes
  --admin-ip IP --ssh-port PORT
  --no-traffic-control --no-two-way-ping --no-ssh-hardening
  SSH: только аудит; прежние параметры изменения SSH отклоняются.
Диагностика ничего не меняет. --yes подтверждает показанный план и откат
при критической ошибке. Существующие образ ноды и бинарник Xray не заменяются.
Несовпадение DNS A и IPv4 сервера всегда отменяет установку, включая --yes.
--maintain: пакеты Ubuntu, зависимости, ZRAM/сеть и безопасная очистка;
без изменения профиля/образов и автоматической перезагрузки.
EOF
}
parse_args() {
    while (($#));do
        case $1 in
            --install) ACTION=install;;--reinstall) ACTION=reinstall;;--maintain) ACTION=maintain;;--diagnose) ACTION=diagnose;;--self-check) ACTION=self-check;;--remove) ACTION=remove;;--restore) ACTION=restore;;
            --acme-pre) ACTION=acme-pre;;--acme-post) ACTION=acme-post;;--acme-deploy) ACTION=acme-deploy;;
            --firewall-apply) ACTION=firewall-apply;;--game-socket) ACTION=game-socket;;
            --domain|--panel-port|--panel-ip|--email|--node-tag|--xhttp-path|--node-container|--node-version|--secret-key-file|--profile-input|--backup|--admin-ip|--ssh-port)
                (($#>=2)) && [[ -n $2 && $2 != --* ]] || die 1 "Для $1 нужен аргумент."
                case $1 in --domain) DOMAIN=$2;;--panel-port) NODE_PORT=$2;NODE_PORT_EXPLICIT=1;validate_node_port;;--panel-ip) PANEL_IP=$2;;--email) EMAIL=$2;;--node-tag) NODE_TAG=$2;;
                    --xhttp-path) XHTTP_PATH=$2;PATH_EXPLICIT=1;;--node-container) NODE_CONTAINER=$2;;--node-version) NODE_VERSION=$2;;
                    --secret-key-file) SECRET_FILE=$2;;--profile-input) PROFILE_INPUT=$2;;--backup) BACKUP_INPUT=$2;;--admin-ip) ADMIN_IP=$2;;--ssh-port) SSH_PORT=$2;;esac;shift;;
            --no-traffic-control) NO_TRAFFIC=1;;--no-two-way-ping) NO_PRIVACY=1;;--no-ssh-hardening) :;;
            --ssh-key-only|--ssh-key-login-confirmed) die 1 'Изменения SSH запрещены; используйте отдельную процедуру вне установщика.';;
            --harden-profile) HARDEN_PROFILE=1;;
            --allow-new-reality) die 1 'Замена действующих ключей REALITY запрещена; импортируйте существующий профиль.';;--no-tuning) NO_TUNING=1;;--no-updates) NO_UPDATES=1;;--yes) YES=1;;--help|-h) usage;exit 0;;*) die 1 "Неизвестный параметр: $1";;
        esac;shift
    done
}
main() {
    parse_args "$@";require_root
    if [[ $ACTION == self-check ]];then load_settings;banner;run_self_check;return;fi
    if [[ $ACTION == diagnose ]];then load_settings;banner;run_diagnostics;(( FAILS==0 ));return;fi
    case $ACTION in
        acme-pre|acme-post|acme-deploy|firewall-apply|game-socket)
            load_settings;FW=$(state_value firewall);WEB_GID=$(state_value web_gid)
            # ExecStartPost runs while install waits for the game service.
            # It changes only permissions of its own socket, so it must not
            # wait on the installation lock held by that parent process.
            [[ $ACTION == game-socket ]] || lock_changes
            if [[ $ACTION == acme-pre ]];then
                ACME_PRE_ACTIVE=0
                trap acme_hook_cleanup EXIT
                trap 'exit 130' INT
                trap 'exit 143' TERM
            fi
            case $ACTION in
                acme-pre) acme_pre;ACME_PRE_ACTIVE=0;;acme-post) acme_post;;
                acme-deploy)
                    CERT_LINEAGE=$(state_value cert_lineage)
                    [[ ${RENEWED_LINEAGE:-$CERT_LINEAGE} == "$CERT_LINEAGE" ]] || return 0
                    # A host Nginx stopped for HTTP-01 must be started before
                    # its deploy reload; Certbot may deploy before post_hook.
                    acme_post
                    PROJECT=$(state_value project);detect_nginx || die 5 'Продление сертификата: Nginx не найден.';reload_nginx;;
                firewall-apply) configure_firewall;;game-socket) game_socket;;
            esac;return;;
    esac
    banner
    if [[ $ACTION == menu ]];then
        show_menu
        local choice
        while true;do
            prompt choice 'Выбор' 0
            case $choice in 1) ACTION=install;;2) ACTION=reinstall;;3) ACTION=diagnose;;4) ACTION=remove;;5) ACTION=restore;;6) ACTION=maintain;;0) return 0;;*) log_warn 'Введите номер пункта от 0 до 6.';continue;;esac
            break
        done
    fi
    if [[ $ACTION == diagnose ]];then load_settings;run_diagnostics;(( FAILS==0 ));return;fi
    # Installation, deletion and renewal cannot race with one another.
    lock_changes
    # Renewal releases its process lock between pre and post hooks. Its lease
    # keeps installation/removal from changing the same files in that window.
    [[ ! -f /run/nuvrion-xhttp-acme.json ]] || die 4 'Есть незавершённая ACME-операция; выполните --acme-post перед изменениями.'
    trap 'ERROR_CODE=$?; log_error "Сбой на строке $LINENO (код $ERROR_CODE)."' ERR
    trap cleanup EXIT
    trap 'exit 1' INT TERM
    case $ACTION in install) install;;reinstall) reinstall;;maintain) maintain;;remove) uninstall;;restore) restore_backup;;esac
}

# @NUVRION_XHTTP_PAYLOAD@

if [[ ${BASH_SOURCE[0]} == "$0" ]];then main "$@";fi

