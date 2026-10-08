#!/usr/bin/env python3
"""Draw the two README inbound diagrams as editable, dependency-free SVGs."""
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COLORS = {'vpn': '#287d72', 'web': '#a77b32', 'scan': '#a94747', 'muted': '#5d7083'}
FONT = 'DejaVu Sans, Segoe UI, Arial, sans-serif'


class Diagram:
    def __init__(self, name, height, title, description, number):
        self.name = name
        self.items = [
            f'<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="{height}" '
            f'viewBox="0 0 1440 {height}" role="img" aria-labelledby="title desc">',
            f'<title id="title">{escape(title)}</title>',
            f'<desc id="desc">{escape(description)}</desc>',
            '<defs>',
        ]
        for name, color in COLORS.items():
            self.items.append(f'<marker id="{name}" markerWidth="9" markerHeight="9" '
                              f'refX="8" refY="4" orient="auto" markerUnits="strokeWidth">'
                              f'<path d="M0 0L8 4L0 8Z" fill="{color}"/></marker>')
        self.items += ['</defs>', f'<rect width="1440" height="{height}" rx="24" fill="#f8f7f3"/>']
        self.text(48, 46, f'NUVRION / INBOUND {number}', 17, COLORS['web'], 700)
        self.text(48, 93, title, 38, '#233447', 700)
        self.text(48, 128, description, 21)
        for x, key, label in [(48, 'vpn', 'Авторизованный трафик'),
                              (420, 'web', 'HTTPS / активный скан'),
                              (814, 'scan', 'Фильтрация источников')]:
            self.items.append(f'<rect x="{x}" y="153" width="22" height="5" rx="2" fill="{COLORS[key]}"/>')
            self.text(x + 34, 164, label, 19)

    def text(self, x, y, value, size=22, color='#5d7083', weight=400):
        self.items.append(f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" '
                          f'font-weight="{weight}" fill="{color}">{escape(value)}</text>')

    def card(self, ident, x, y, width, height, title, lines=(), accent='vpn', note=False):
        color = COLORS[accent]
        fill = '#f1f4f5' if note else '#ffffff'
        dash = ' stroke-dasharray="6 5"' if note else ''
        self.items.append(f'<g id="{ident}"><rect x="{x}" y="{y}" width="{width}" height="{height}" '
                          f'rx="16" fill="{fill}" stroke="#d8dfdf" stroke-width="1.5"{dash}/>')
        self.items.append(f'<rect x="{x}" y="{y + 18}" width="5" height="{height - 36}" rx="2" fill="{color}"/>')
        self.text(x + 24, y + 39, title, 25, '#233447', 700)
        for row, line in enumerate(lines):
            self.text(x + 24, y + 72 + row * 28, line, 21)
        self.items.append('</g>')

    def arrow(self, route, accent='vpn', dashed=False):
        dash = ' stroke-dasharray="6 6"' if dashed else ''
        self.items.append(f'<path d="{route}" fill="none" stroke="{COLORS[accent]}" '
                          f'stroke-width="3" stroke-linejoin="round" marker-end="url(#{accent})"{dash}/>')

    def common_entry(self, client, client_lines, observer_lines):
        self.card('client', 48, 198, 416, 162, client, client_lines)
        self.card('dpi', 512, 198, 416, 162, 'РКН / DPI · наблюдение', observer_lines, 'muted', note=True)
        self.card('scanner', 976, 198, 416, 162, 'Скан РКН / ГРЧЦ',
                  ['Обычный TLS + HTTPS-запрос.', 'SNI: домен ноды; запрос к /.', 'Нет профиля / UUID клиента.'], 'web')
        self.arrow('M256 360V408H600V446')
        self.arrow('M1184 360V408H840V446', 'web')
        self.card('traffic-control', 220, 446, 972, 128, 'Traffic Control · если установлен',
                  ['Выбранные IP-списки: antiscanner / government_networks / skipa.',
                   'Allowlist и исключения → дальше; блокируемые IP → DROP.'], 'scan')
        self.card('source-drop', 1248, 472, 144, 76, 'DROP', accent='scan')
        self.arrow('M1192 510H1248', 'scan')
        self.arrow('M720 574V642', 'muted')
        self.text(743, 618, 'Источник пропущен firewall', 20)

    def save(self):
        self.items.append('</svg>')
        (ROOT / 'assets' / self.name).write_text('\n'.join(self.items) + '\n', encoding='utf-8')


def reality():
    d = Diagram('reality-scheme.svg', 1584, 'REALITY TCP / RAW',
                'Клиент с профилем → VLESS. Обычный HTTPS-скан → свой сайт через selfsteal.', '01')
    d.common_entry('Клиент REALITY',
                   ['VLESS · fingerprint: firefox.', 'SNI: домен ноды.', 'Flow: xtls-rprx-vision.'],
                   ['Видны IP, SNI и TCP/443.', 'ClientHello профиля: Firefox.', 'Время и размеры пакетов видны.'])
    d.card('reality-inbound', 352, 642, 736, 144, 'Xray · REALITY TCP/RAW · :443',
           ['Tag: NODE_TAG · внешний listener Remnawave Node.',
            'REALITY проверяет данные рукопожатия.',
            'Обычный TLS перенаправляется в локальный target.'])
    d.items.append('<path d="M1158 157H1180" stroke="#a77b32" stroke-width="3" stroke-dasharray="5 4"/>')
    d.text(1192, 164, 'TLS-target', 19)
    d.arrow('M1088 715H1340V894', 'web', dashed=True)
    d.text(1110, 757, 'TLS-рукопожатие', 19, COLORS['web'])
    d.text(1110, 785, 'для REALITY', 19, COLORS['web'])
    d.arrow('M500 786V831H348V894')
    d.arrow('M940 786V831H1068V894', 'web')
    d.text(72, 866, 'REALITY-доступ', 22, COLORS['vpn'], 600)
    d.text(768, 866, 'Обычный TLS / fallback', 21, COLORS['web'], 600)
    d.card('vless-auth', 48, 894, 600, 150, 'VLESS · проверка UUID',
           ['Пользователей передаёт Remnawave.',
            'Разрешённый UUID → обработка VPN-трафика.',
            'Неизвестный UUID → отказ в доступе.'])
    d.card('tls-target', 744, 894, 648, 150, 'Nginx · локальный selfsteal target',
           ['nginx.sock · TLS-сертификат своего домена.',
            'xver: 1 → PROXY v1 передаёт IP клиента.',
            'Здесь завершается TLS обычного HTTPS.'], 'web')
    d.arrow('M348 1044V1104')
    d.arrow('M1068 1044V1104', 'web')
    d.card('routing', 48, 1104, 600, 126, 'Xray routing → Internet',
           ['DIRECT → разрешённый целевой ресурс.',
            'BLOCK → запрещённые профилем назначения.'])
    d.card('decoy', 744, 1104, 648, 126, 'Атлас пива · ответ на HTTPS /',
           ['По домену ноды скан видит сайт и HTTP 200.',
            'HTML / JS / assets + локальный API игры.'], 'web')
    d.card('reality-camouflage', 48, 1288, 648, 172, 'Маскировка для DPI',
           ['firefox задаёт профиль TLS ClientHello.',
            'Данные клиента защищены REALITY.',
            'IP, SNI и статистика соединения наблюдаемы.'], 'muted', note=True)
    d.card('reality-probe-result', 744, 1288, 648, 172, 'Поведение при активном скане',
           ['Обычный HTTPS получает сертификат и сайт.',
            'default_server обслуживает сайт на /.',
            'Чужой SNI / Host на API → HTTP 404.'], 'web', note=True)
    d.text(48, 1513, 'Unix target: /dev/shm/nuvrion-xhttp/nginx.sock · отдельного публичного upstream-порта нет.', 20)
    d.text(48, 1545, 'Показана новая установка. Legacy-путь: /dev/shm/nginx.sock. Имя домена задаётся пользователем.', 19)
    d.save()


def xhttp():
    d = Diagram('xhttp-scheme.svg', 1708, 'XHTTP + TLS через Nginx',
                'HTTP-транспорт внутри TLS. Общий TCP/443 → Nginx → локальный XHTTP inbound.', '02')
    d.common_entry('Клиент XHTTP + TLS',
                   ['VLESS · mode: auto · Firefox.', 'SNI: домен ноды.', 'ALPN: h2,http/1.1.'],
                   ['Видны IP, SNI и TCP/443.', 'HTTP-путь и данные внутри TLS.', 'Время и размеры пакетов видны.'])
    d.card('shared-front', 352, 642, 736, 130, 'Xray · общий listener TCP/443',
           ['Обычный TLS, без REALITY-авторизации.',
            'target: nginx.sock · пересылка TLS + PROXY v1.'], 'web')
    d.arrow('M720 772V824', 'web')
    d.card('nginx', 220, 824, 1000, 150, 'Nginx · завершение TLS и HTTP-маршрутизация',
           ['Сертификат своего домена · TLS 1.2/1.3 · HTTP/2.',
            'Перед доступом к XHTTP / API проверяет SNI и Host.',
            'X-Forwarded-For и X-Real-IP берутся из PROXY v1.'], 'web')
    d.arrow('M500 974V1016H372V1070')
    d.arrow('M940 974V1016H1068V1070', 'web')
    d.text(72, 1042, 'XHTTP-запрос', 22, COLORS['vpn'], 600)
    d.text(768, 1042, 'HTTPS / скан', 22, COLORS['web'], 600)
    d.card('xhttp-location', 48, 1070, 648, 146, 'Nginx location → XHTTP',
           ['Path: /api/v3/sync/ или свой путь из профиля.',
            'proxy_pass → Unix socket xrxh.socket.',
            'HTTP/1.1 локально · buffering off.'])
    d.card('https-response', 744, 1070, 648, 146, 'Ответ сайта или API',
           ['/ → Атлас пива · HTTP 200.',
            'Чужой SNI / Host на API → HTTP 404.',
            'XHTTP path без сессии: возможен HTTP 400.'], 'web')
    d.arrow('M372 1216V1276')
    d.card('xhttp-inbound', 48, 1276, 648, 146, 'Xray · VLESS XHTTP inbound',
           ['Tag: NODE_TAG XHTTP · mode auto.',
            'Проверка UUID пользователя из Remnawave.',
            'trustedXForwardedFor сохраняет IP клиента.'])
    d.card('http-camouflage', 744, 1276, 648, 146, 'Маскировка HTTP внутри TLS',
           ['firefox задаёт профиль ClientHello.',
            'Padding 100–1000 байт берётся из extra.',
            'Cookie-padding — после проверки core.'], 'muted', note=True)
    d.arrow('M372 1422V1482')
    d.card('routing', 48, 1482, 648, 126, 'Xray routing → Internet',
           ['DIRECT → разрешённый целевой ресурс.',
            'BLOCK → запрещённые профилем назначения.'])
    d.card('local-only', 744, 1482, 648, 126, 'Локальная связь через Unix socket',
           ['XHTTP backend без отдельного TCP-порта.',
            'Для клиента снаружи: домен ноды и TCP/443.'], 'muted', note=True)
    d.text(48, 1655, 'XHTTP socket: /dev/shm/nuvrion-xhttp/xrxh.socket · между Nginx и Xray локальный HTTP без TLS.', 20)
    d.text(48, 1686, 'Показана новая установка. Legacy-путь: /dev/shm/xrxh.socket. Пользователь может задать другой path.', 19)
    d.save()


if __name__ == '__main__':
    reality()
    xhttp()
    print('Updated assets/reality-scheme.svg and assets/xhttp-scheme.svg')
