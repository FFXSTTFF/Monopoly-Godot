# Запуск проекта

## Требования

- Godot **4.6** (в репозитории рядом лежит `Godot_v4.6.1-stable_mono_win64` —
  mono-сборка редактора; см. примечание про .NET ниже).
- Проект открывается как обычно: `Godot_v4.6.1-stable_mono_win64.exe --path monopolia`
  или через `project.godot` в редакторе.

## Примечание про mono/.NET

В `project.godot` есть секция `[dotnet]` с `assembly_name="Monopolis"`, и
используется mono-сборка движка. При этом **весь фактический код проекта —
GDScript** (`.gd`), C#-скриптов в проекте нет. Это, по всей видимости,
задел на будущее или инерция от выбора шаблона проекта — сейчас
mono-специфика не задействована и обычная (не-mono) сборка Godot 4.6 подошла
бы так же.

## Запуск в редакторе (клиент)

`F5` в редакторе или запуск экспортированного билда — стартует `Main.tscn`.
`Main.gd._route()` проверяет:
- `--server` в пользовательских аргументах командной строки, или
- `DisplayServer.get_name() == "headless"`

и либо грузит `server/ServerMain.tscn`, либо `ui/MainMenu.tscn`.

### Быстрый локальный тест без второго игрока

На главном экране — кнопка "ТЕСТИРОВЩИКАМ: НАЧАТЬ ОДИНОЧНУЮ ИГРУ"
(`MainMenu._on_solo_test`). Она вызывает `NetworkManager.host_solo_test()`,
который поднимает `OfflineMultiplayerPeer` (без реального сетевого сокета) и
сразу стартует партию с одним игроком (`solo_test_mode = true`, партия не
завершается автоматически при 1 живом игроке). Удобно для быстрой проверки
UI/рендера без поднятия сервера.

## Запуск headless dedicated-сервера

```
Godot_v4.6.1-stable_mono_win64_console.exe --headless --path monopolia server/ServerMain.tscn -- --port 27015 --ruleset core:classic
```

Аргументы после `--` парсит `ServerMain._parse_args()` (`--key value` пары):

| Аргумент | По умолчанию | Описание |
|---|---|---|
| `--port` | `NetworkManager.DEFAULT_PORT` (27015) | Порт ENet-сервера |
| `--ruleset` | `GameConfig.selected_ruleset` | Полный id ruleset'а (`packId:localId`, напр. `core:classic`) |

Сервер печатает в консоль сигнатуру загруженных паков и список паков —
удобно сверить с тем, что видит клиент, при отладке рассинхрона (см.
[networking.md](networking.md)).

## Подключение клиента к серверу

В главном меню — поля "СЕРВЕР" (адрес/порт) и кнопка "ПРИСОЕДИНИТЬСЯ"
(`MainMenu._on_join` → `NetworkManager.join_game`). Последний
адрес/порт/имя/ruleset сохраняются в `user://settings.cfg`
(`GameConfig.save_settings`).

## Установка модов/DLC

Скопировать папку пака в `res://mods` (для разработки из исходников) или в
`user://mods` (для установленной игры — `ModLoader` создаёт эту папку
автоматически при первом запуске). Подробности формата — в
[modding.md](modding.md) и [`mods/README.md`](../mods/README.md).

## Настройки приложения (`project.godot`)

| Настройка | Значение | Зачем |
|---|---|---|
| `physics/3d/physics_engine` | `Jolt Physics` | Физдвижок (сейчас в игровой логике почти не задействован — рендер процедурный, без коллизий у токенов) |
| `rendering_device/driver.windows` | `d3d12` | Явный выбор Direct3D 12 backend на Windows |
| `rendering/anti_aliasing/quality/msaa_3d` | `2` | MSAA для 3D-сцены |
| `display/window/stretch/mode` | `canvas_items` / `aspect=expand` | Адаптивный UI под разные разрешения |

## Отладка сети локально

Самый быстрый способ проверить многопользовательский сценарий без второго
компьютера — два инстанса редактора/экспортированного билда на одной машине:
один хостит (`ОТКРЫТЬ СВОЙ СТОЛ`, порт по умолчанию 27015), второй
подключается на `127.0.0.1:27015`.
