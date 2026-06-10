# uConsole — Режим экономии и сохранение сессии (план)

Документ фиксирует согласованный дизайн. Устройство: **ClockworkPI uConsole CM5**,
Debian 12 (bookworm, образ Rex), голая framebuffer-консоль (без X/Wayland),
работа внутри **tmux**.

## Главное ограничение

`/sys/power/state` пустой → **аппаратного suspend (S3/s2idle) нет**, hibernate тоже нет.
Поэтому:
- Делаем **не «сон», а «режим экономии»** (программные меры).
- Вместо заморозки — **сохранение/восстановление tmux-сессии** через shutdown+boot.

## Доступные рычаги (проверено на железе)

| Рычаг | Состояние | Применение |
|---|---|---|
| Подсветка | `brightness` 0–9, `bl_power` | главный потребитель; глушим до 1 (не в ноль) |
| CPU | governor `ondemand`, 1.5–2.4 ГГц; есть `powersave` | в эконом-режиме пинить в `powersave` |
| Wi-Fi | rfkill `phy0`, `iw … power_save` | power-save всегда; rfkill только по глубокому простою |
| Модем | SIM7600 (ModemManager) | трогаем по желанию (вне текущего плана) |
| AC | `/sys/class/power_supply/axp22x-ac/online` 0/1 | гейт «на зарядке» |
| Батарея | `/sys/class/power_supply/axp20x-battery` `capacity`,`status` | критический заряд |

---

## Режим экономии

**Эффект применяется, когда:** pref `economy=on` **И** на батарее (`online=0`).
На зарядке — никаких мер. pref **запоминается** (постоянный флаг): тумблер ручной,
но кабель только гейтит эффект. Снял с зарядки → если флаг был `on`, эконом включается
сам; был обычный — нет.

### Многоуровневая модель простоя
Один демон следит за бездействием (читает `/dev/input` через `libinput`) и по мере
роста простоя включает всё более жёсткие меры. Любая активность или подключение
кабеля **мгновенно** всё откатывает.

```
economy ON + на батарее:
   CPU → powersave                      (постоянно, пока эконом+батарея)
   простой > IDLE_DIM (~90с)      → яркость до DIM_LEVEL (1, не в ноль)
   простой > IDLE_WIFI (~10мин)   → wifi вниз (если трафик~0 и нет SSH)
   простой > IDLE_SHUTDOWN (~30м) → сохранить сессию + выключиться (с гейтами)
   заряд < BATT_CRITICAL (~5%)    → сохранить сессию + выключиться немедленно
кабель воткнут / economy OFF:
   откат: governor ondemand, яркость восстановлена, wifi up
```

- **Wake мгновенный:** демон ждёт ввод через `libinput`, поэтому при касании яркость
  возвращается сразу, а не по тику опроса.
- **CPU powersave** имеет смысл только постоянно (на батарее в эконом-режиме): пинит на
  1.5 ГГц. Цена — пиковые задачи чуть медленнее. Главный выигрыш всё равно от подсветки.

### Контекстный Wi-Fi (по нарастанию)
1. **Power-save чипа** (`iw dev wlan0 set power_save on`) — всегда; чип в сети, спит между
   маяками, без разрывов.
2. **Глушить по простою трафика, а не ввода** — мерить `rx/tx_bytes`; rfkill только если
   трафик ~0 долго (не оборвём закачку/синк).
3. **Гейты безопасности** — не глушить wifi и **не выключаться**, если есть активная
   **SSH-сессия** в устройство или живой фоновый процесс (`who`/`ss`).

Схема: (1) всегда + (2)+(3) только перед `IDLE_WIFI`/`IDLE_SHUTDOWN`.

---

## Сохранение сессии (вместо сна)

Инструменты: **tmux-resurrect** (save/restore) + **tmux-continuum** (авто-save).

- **Сохраняется:** раскладка tmux (сессии/окна/панели/layout), рабочие каталоги,
  по списку — запущенные программы (vim/nvim с буферами через плагин).
- **НЕ сохраняется:** живое состояние процессов в памяти (нужен hibernate, которого нет).
  Это «переоткрыть как было», а не заморозка.
- **Поток:**
  1. continuum авто-save каждые ~15 мин (страховка от резкого отруба) + явный save в
     момент `IDLE_SHUTDOWN`/`BATT_CRITICAL`.
  2. авто-выключение — по `IDLE_SHUTDOWN` и/или `BATT_CRITICAL`, только после гейтов.
  3. **восстановление по предложению:** на загрузке (tmux автозапускается) первый шелл
     при наличии снапшота спрашивает `Restore previous session? [Y/n]` → resurrect restore.
     continuum-авто-restore **выключен**; авто-save оставлен.
- **Цена:** зависимость — клон resurrect/continuum в `~/.tmux/plugins`. Восстановление
  программ — best-effort.

---

## Конфигурация и состояние

`/etc/uconsole-power.conf` (правится через sudo):
```
IDLE_DIM=90          # сек простоя → яркость до DIM_LEVEL
IDLE_WIFI=600        # сек → wifi вниз (с учётом трафика+сессий)
IDLE_SHUTDOWN=1800   # сек → сохранить сессию и выключиться (0 = выкл. меру)
DIM_LEVEL=1          # яркость на простое (не ниже 1)
BATT_CRITICAL=5      # % заряда → сохранить сессию и выключиться немедленно
CPU_GOVERNOR=powersave   # governor в эконом-режиме (на батарее), постоянно
WIFI_PS=on               # power-save чипа всегда
WIFI_DEEP=block          # на IDLE_WIFI: rfkill, если трафик~0 и нет SSH
GUARD_SSH=1              # не рубить wifi / не выключаться при активной SSH
```

`~/.config/uconsole/economy` — постоянный pref `on|off` (тумблер пишет без sudo,
демон-root читает; переживает ребут).

---

## Файлы

| Файл | Роль |
|---|---|
| `/etc/uconsole-power.conf` | крутилки таймингов/порогов |
| `~/.config/uconsole/economy` | постоянный pref on/off |
| `~/.local/bin/uconsole-eco` | `on\|off\|toggle\|status` + маркизка `ECONOMY ON/OFF` + refresh бара |
| `/usr/local/bin/uconsole-powerd` | демон-движок (idle state machine) |
| `/etc/systemd/system/uconsole-powerd.service` | запуск демона |
| `/usr/local/bin/power-event` (правка) | пинать демон сигналом при смене питания |
| `~/.local/bin/eco-status` | ячейка `ECO` в статус-баре |
| `~/.tmux/plugins/tmux-resurrect`, `…/tmux-continuum` | сохранение сессии |
| `~/.local/bin/uconsole-session-restore` | prompt-restore на загрузке |
| `~/.bash_profile` (правка) | вызов prompt-restore (один раз за загрузку, маркер в `/run`) |

**Индикатор `ECO` в баре:** показывать, когда pref on; ярко — когда реально активен
(на батарее), тускло/строчно — когда на зарядке (взведён, но спит).

---

## Микро-решения
- Конфиг в `/etc` (sudo), pref в `~/.config` (без sudo, персистентный).
- Prompt-restore — вне tmux в `.bash_profile`, спрашивает один раз за загрузку
  (маркер в `/run`, чистится при ребуте). continuum-авто-restore off, авто-save on.

---

## Фазы реализации

1. **Ядро эконома** — конфиг + pref + `uconsole-eco` + демон (CPU powersave + idle-dim)
   + интеграция с питанием (`power-event` → сигнал демону) + индикатор `ECO`.
2. **Сохранение сессии** — resurrect+continuum, авто-save, prompt-restore на загрузке.
3. **Авто-выключение + контекстный wifi** — `IDLE_SHUTDOWN`/`BATT_CRITICAL` с гейтами
   (SSH/трафик), wifi power-save/block.

Порядок неслучаен: сначала эконом, потом сохранение сессии (без него авто-выключение
бессмысленно), потом само авто-выключение.

---

## Контекст: что уже сделано (отдельно от этого плана)
- Консольный шрифт `TerminusBold 28x14`; статус-бар с разделителем `▒`.
- Клавиши яркости → `triggerhappy`/`ucon-brightness` (пол=1, мгновенный refresh бара).
- Бегущая строка SSID при подключении wifi (NM dispatcher + `network-status`).
- Бегущая строка `CHARGING`/`ON BATTERY` при смене кабеля (udev + `power-event` + `battery-status`).
- Статус-скрипты в `~/.local/bin/`: `brightness-status`, `network-status`, `cm5-temp`,
  `battery-status`, `tmux-system-status`, `net-marquee-trigger`.

---

# Режимы питания: рефактор + HEADLESS / ROUTER (2026-06-10)

Булев pref `economy on/off` обобщён в **селектор режима**. Назначение новых режимов:
uConsole работает с зависимым устройством (**ESP32-S3**) по USB, экран не нужен.

## Модель режимов
- Канон: `~/.config/uconsole/mode` ∈ `normal | economy | headless | router`
  (legacy `~/.config/uconsole/economy` on/off читается как fallback и зеркалится — для отката).
- `normal` ≡ старый `off`; `economy` ≡ старый `on` (поведение economy/normal — **бит-в-бит прежнее**).
- Команда **`uconsole-mode normal|economy|headless|router|cycle|status`**. `cycle` гоняет только
  `normal↔economy`. `uconsole-eco` остался тонким алиасом (`on`→economy, `off`→normal, `toggle`→cycle).
- **headless/router — только по явной команде** (не в `cycle`, т.к. нужны редко). В будущем —
  контекстно от ESP32-S3 (слушатель serial-событий зовёт `uconsole-mode`).
- Бар (`eco-status`): economy→`ECO`/`eco`, headless→`HDL`, router→`RTR`, normal→пусто;
  маркиза `MODE <NAME>` на 5с при смене.
- Применение эффекта — **в пределах одного тика (≤5с)**: USR1 не прерывает `read` в демоне
  (маркиза мгновенная, само действие догоняет).

## HEADLESS (готов, проверен живьём)

| Рычаг | Поведение |
|---|---|
| Экран | гаснет в ноль (`brightnessctl set 0`) через `HEADLESS_IDLE_OFF` простоя — **AC-агностично** |
| Авто-выключение | **отключено** (idle ≠ «не используется» — устройство работает) |
| Critical-battery | страховка: ≤`BATT_CRITICAL` → save+poweroff сразу, без отсчёта (без присмотра) |
| CPU | `ondemand` (он вычисляет — не троттлим в powersave) |
| Wi-Fi | по флагу `HEADLESS_WIFI` (off → `rfkill block wlan`) |
| USB ESP32 | keepalive: `HEADLESS_USB_KEEP="VID:PID"` → `power/control=on` (пусто = инертно) |
| Выход | `normal`/`economy`: `leave_new_modes` (экран + wifi назад); любая клавиша будит |

Реализация: headless/router перехватываются в начале `evaluate()` **до** гейта по питанию,
в `new_mode_eval()`. Новые ключи `/etc/uconsole-power.conf`:
```
HEADLESS_IDLE_OFF=30     # сек простоя → экран в ноль, независимо от зарядки
HEADLESS_WIFI=off        # off = rfkill block wlan, on = оставить
HEADLESS_USB_KEEP=       # "VID:PID" hex — держать устройство от autosuspend (пусто = не трогать)
```

## ROUTER (готов с моком ESP32; verified 2026-06-10)
Как headless (экран-офф AC-агностично, без авто-выключения), но **wifi не глушит**.
Назначение: держать 4G и **раздавать интернет ESP32 по USB**.

**Реализовано** в `/usr/local/bin/uconsole-router up|down|status|test`; демон зовёт `up` при входе в
режим и `down` при выходе (`router_ensure_up/down`). Что делает `up`: резолвит uplink
(`ROUTER_UPLINK=auto`→текущий дефолтный iface, напр. wlan0 / `modem`→`uconsole-4g enable`+`nmcli up
cyta-4g` / явный iface), поднимает downstream-iface, `ip_forward=1` (исходное → `/run/uconsole-router.state`),
nft-таблица `inet uconsole_router` с `masquerade`, dnsmasq (DHCP+DNS) на downstream. `down` всё
сворачивает и восстанавливает `ip_forward`.

**ESP32 замокирован** как veth-пара, peer в netns `rt-esp32` (клиент 10.55.0.2, шлюз 10.55.0.1/24) —
NAT проверен сквозь мок (`uconsole-router test`: пинг 8.8.8.8 через NAT, 0% потерь; DNS через dnsmasq).
Реальное устройство потом: `ROUTER_MOCK=0` + `ROUTER_DOWN_IFACE=usb0` (cdc_ncm). Инструмент — только
nftables (iptables в системе нет).

**4G-обвязка уже есть** (не блокер — модем просто выключен по умолчанию):
- `uconsole-4g enable|disable` (`/usr/bin/uconsole-4g` → `uconsole-4g-cm4.sh`, GPIO `pinctrl 24/15`)
  — питание модуля. Сервис `uconsole-4g-cm4.service` **disabled**, оттого модем при загрузке не
  виден в `mmcli`. (Скрипт назван cm4; на CM5 перепроверить применимость пинов.)
- Данные — через NM gsm-профиль: `nmcli connection up cyta-4g` (fallback `cyta-4g-internet`),
  оператор CYTA `28001`.
- TUI `uconsole-4g-tui` (он же `4g-tui`): статус/power/register/data/SMS/USSD/calls/PIN.

ROUTER переиспользует это (`uconsole-4g enable` + `nmcli connection up cyta-4g`) для `ROUTER_UPLINK=modem`;
роутерная часть (`ip_forward`+NAT+dnsmasq) — в `uconsole-router`. Для отладки дефолт `ROUTER_UPLINK=auto`
(текущий wlan0), чтобы не жечь 4G-трафик.

## ⚠️ Найдено при тестах ROUTER: дрейф трекбола ломает idle-детект
`event9` (трекбол) периодически сыплет непрерывный `POINTER_MOTION` (дрейф). Демон висит на
`read -t TICK` из `libinput debug-events`; в момент дрейфа `read` постоянно возвращает события →
срабатывает ветка сброса ввода, а `evaluate()` по таймауту **не зовётся** → простой не накапливается и
смена режима применяется только в тихие окна (или при рестарте демона — стартовый `evaluate` всегда
отрабатывает). Касается **всех режимов** (economy-dim, headless screen-off, router up/down). **Не
исправлено.** Варианты: исключить трекбол из источника idle в powerd; игнорировать под-пороговый
`POINTER_MOTION`; либо развязать частоту `evaluate()` от чтения ввода (тик по монотонным часам, ввод —
только сброс `last`).

## Зависимое устройство — ESP32-S3 (архитектура USB)
- **uConsole = USB host**, ESP32-S3 — периферия на внешнем USB-A.
  Gadget-режим невозможен: единственный UDC-способный контроллер `dwc2` занят внутренним хабом
  (клавиатура+wifi), а внешние порты `xhci` — только хост.
- ESP32-S3 через TinyUSB — **композитное устройство** стандартных классов (драйверы у uConsole есть):
  CDC-ACM (`/dev/ttyACMx` — события/управление), CDC-NCM/ECM (`usbN` — интернет для ROUTER),
  UAC2 (USB-аудио), HID.
- Потолок: USB ESP32-S3 — **full-speed 12 Мбит/с** на всё сразу (аудио+сеть+serial делят полосу).
- **Аудио — push-to-talk с кнопки ESP32** (голос после индикатора готовности; лаг допустим)
  → звуковую карту/поток держать **холодными** до нажатия (экономнее).

## Файлы (новые/изменённые этим этапом)
| Файл | Роль |
|---|---|
| `~/.config/uconsole/mode` | канонический pref режима |
| `~/.local/bin/uconsole-mode` | селектор режима (+маркиза +сигнал демону +refresh) |
| `~/.local/bin/uconsole-eco` | теперь тонкий алиас на `uconsole-mode` |
| `~/.local/bin/eco-status` | mode-aware ячейка (ECO/HDL/RTR) |
| `/usr/local/bin/uconsole-powerd` | +`new_mode_eval`, `screen_off/on`, wifi/usb-keepalive, HEADLESS-ключи |
| `~/.config/uconsole/refactor-backup-*` | бэкап скриптов до рефактора (откат) |

## Осталось
- **ROUTER:** оживить модем → `ip_forward`+NAT+dnsmasq на `usbN`.
- **ESP32-S3:** канал событий (CDC), PTT-аудио (UAC2), интернет (CDC-NCM); вписать `VID:PID`
  в `HEADLESS_USB_KEEP`.
- **Контекстное** переключение режимов от ESP32 (слушатель serial → `uconsole-mode`).
- Опц.: **мгновенное** применение режима (правка цикла демона; сейчас ≤5с).
