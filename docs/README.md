# Документация Monopolis

Monopolis — сетевая (multiplayer) Монополия на Godot 4.6, с авторитетным
сервером, скрытыми балансами игроков и рантайм-загрузчиком паков/DLC для
модов. Этот раздел — техническая документация проекта: как он устроен, как
его запускать и как расширять.

## Разделы

| Документ | О чём |
|---|---|
| [architecture.md](architecture.md) | Слои проекта, автозагрузки (autoload), поток данных клиент↔сервер |
| [game-rules.md](game-rules.md) | Игровой автомат состояний: ходы, покупка, аукцион, тюрьма, банкротство, сделки |
| [networking.md](networking.md) | Сетевой протокол: RPC, снапшоты, приватное состояние, защита от рассинхрона |
| [content-schema.md](content-schema.md) | Формат JSON-контента: cells, tokens, roles, rulesets, cards, sounds |
| [modding.md](modding.md) | Как устроена система паков/DLC и `ModLoader`, ссылка на гайд для авторов модов |
| [ui-rendering.md](ui-rendering.md) | Экраны UI, 3D-рендер доски/фигурок, тема оформления |
| [running-the-project.md](running-the-project.md) | Запуск в редакторе, headless-сервер, аргументы командной строки |
| [known-issues.md](known-issues.md) | Известные слабые места и рекомендации по улучшению |

## Быстрый обзор проекта

```
monopolia/
  autoload/     — синглтоны (EventBus, PackRegistry, GameConfig, ModLoader, AssetLoader, AudioDirector, NetworkManager)
  core/         — авторитетная игровая логика, без зависимости от сцены/рендера
  packs/core/   — встроенный контент (JSON) + entry-скрипт базового пака
  mods/         — куда игроки/моддеры кладут свои паки (см. mods/README.md)
  render/       — 3D-рендер доски, фигурок, кинематографичной сцены стола
  ui/           — экраны интерфейса (меню, лобби, HUD, диалоги)
  server/       — headless dedicated-server сцена и точка входа
  Main.tscn     — точка входа приложения (выбирает сервер или меню)
  Game.tscn     — игровая сцена (стол + HUD)
```

Название игрового движка: **Godot 4.6**, физика — Jolt Physics, рендер —
Forward+ / D3D12 на Windows. Логика полностью на GDScript (несмотря на
`config/name` в C#-стиле, `.NET`-часть в проекте не используется активно —
см. [running-the-project.md](running-the-project.md)).
