# Архитектура

## Слои проекта

Monopolis построен по чёткому разделению: **данные → правила → сеть → рендер/UI**.
Ниже — слои снизу вверх.

```
┌─────────────────────────────────────────────────────────────┐
│  UI (ui/*.gd)              Экраны, диалоги, HUD              │
├─────────────────────────────────────────────────────────────┤
│  Render (render/*.gd)      3D-доска, фигурки, кости, стол    │
├─────────────────────────────────────────────────────────────┤
│  Network (autoload/NetworkManager.gd)                        │
│    Единственная точка входа между UI и авторитетной логикой  │
├─────────────────────────────────────────────────────────────┤
│  Core (core/*.gd)          Правила игры. RefCounted, без     │
│                             зависимости от сцены/рендера      │
├─────────────────────────────────────────────────────────────┤
│  Content (autoload/PackRegistry.gd + packs/*/content/*.json) │
│    Вся игровая "база данных": клетки, токены, роли, карты…   │
└─────────────────────────────────────────────────────────────┘
```

Ключевое архитектурное решение: **core/ ничего не знает о рендере и UI**. `GameController`
принимает "намерения" (`request_roll`, `request_buy`, …) и возвращает обычные
`Dictionary` с результатом — никаких сигналов Godot, никакой сцены. Это то, что
делает ядро тестируемым в изоляции (см. [known-issues.md](known-issues.md) —
этим сейчас никто не пользуется, тестов нет).

## Автозагрузки (autoload), порядок из `project.godot`

Порядок в `[autoload]` важен — каждый следующий может использовать предыдущий
в своём `_ready()`.

1. **EventBus** — глобальная шина сигналов + именованный реестр хуков
   (`add_hook`/`run_hook`), через который паки внедряют поведение в игровой
   цикл, не будучи известными ядру заранее.
2. **PackRegistry** — контент-база: `category -> {"packId:localId": Dictionary}`.
   Также хранит `scene_overrides` (подмена меню/лобби/игры/сервера полной
   конверсией) и `signature` — детерминированный хэш загруженного набора
   паков.
3. **GameConfig** — локальные настройки клиента (имя, токен, кастомизация,
   выбранный ruleset, громкость, качество эффектов). Никогда не несёт
   авторитетное состояние партии.
4. **ModLoader** — сканирует `res://packs`, `res://mods`, `user://mods`,
   строит порядок загрузки (топологическая сортировка по `dependencies` +
   `load_after`), регистрирует контент в `PackRegistry`, запускает
   entry-скрипты паков, считает `signature`.
5. **AssetLoader** — резолвит и кэширует пак-относительные 3D/текстурные
   ассеты (`.glb`/`.gltf`/`.tscn`) для модов; при ошибке всегда откатывается
   на процедурную геометрию/плейсхолдер — сломанный ассет мода не может
   уронить клиент.
6. **AudioDirector** — событийная аудио-система: логическое событие
   (`game.dice_roll`) → звук из пака или процедурный тон-фолбэк.
7. **NetworkManager** — сетевой слой поверх `MultiplayerAPI`/ENet. Единственный
   мост между UI и `GameController`.

## Поток одного хода (пример: бросок кубика)

```
UI (Hud.gd)
  → NetworkManager.request_roll()
      если host/dedicated: вызывает GameController.resolve_roll() локально
      если client:          rpc_id(1, "server_request_roll")
          → на сервере: server_request_roll() → GameController.resolve_roll()
      GameController мутирует ledger/players/board_index, возвращает Dictionary
  → NetworkManager._broadcast_event(EVENT_ROLL, res) всем через rpc()
  → NetworkManager._broadcast_snapshot() — публичный снапшот всем,
    приватное состояние (баланс, долг, аукцион) — каждому отдельно через rpc_id
  ← клиенты получают receive_event/receive_snapshot/receive_private_state
  ← EventBus эмитит dice_rolled/player_moved/game_state_changed
  ← BoardRenderer и Hud подписаны на EventBus и перерисовывают себя
```

Подробности состояний хода — в [game-rules.md](game-rules.md), протокол RPC —
в [networking.md](networking.md).

## Сценарный флоу приложения

```
Main.tscn (Main.gd)
  ├─ headless или --server  → server/ServerMain.tscn (dedicated)
  └─ иначе                  → ui/MainMenu.tscn
        │ host_game() / host_solo_test()
        ▼
     ui/WaitingRoom.tscn  (лобби: готовность игроков, старт хоста)
        │ фаза партии стала "playing"
        ▼
     Game.tscn  (render/GameScene.gd + ui/Hud.gd)
```

Каждый переход сцены идёт через `PackRegistry.resolve_scene(key, fallback)` —
это позволяет DLC полностью подменить любой экран через `scene_overrides` в
`pack.json`, не трогая vanilla-файлы.

## Почему ядро не хранит деньги в публичном состоянии

`MoneyLedger` — единственное место, где живут балансы. `PlayerState.to_public_dict()`
сознательно **не** включает баланс — это то, что делает "скрытые балансы"
(ключевая фича игры, см. `MainMenu.gd`: "СКРЫТЫЕ БАЛАНСЫ" в фиче-листе)
возможными в принципе, а не просто "не показывать в UI". Баланс отправляется
только владельцу, через `_push_balance`/`receive_balance`.
