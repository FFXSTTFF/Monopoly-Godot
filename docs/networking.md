# Сетевой протокол

Транспорт: `MultiplayerAPI` Godot поверх ENet (`ENetMultiplayerPeer`), либо
`OfflineMultiplayerPeer` для одиночного тестового режима (`host_solo_test`).
Весь код — в `autoload/NetworkManager.gd`, идентификаторы RPC/событий — в
`core/NetProtocol.gd`.

## Роли (`NetworkManager.Mode`)

| Режим | Кто | Особенность |
|---|---|---|
| `HOST` | Сервер + локальный игрок (peer 1) | `GameController` живёт в этом же процессе |
| `DEDICATED` | Headless-сервер, без локального игрока | `server/ServerMain.tscn` |
| `CLIENT` | Только зеркало публичного состояния + свой приватный баланс | Всё действия идут через RPC на peer 1 |

Хост не шлёт себе RPC — вызывает серверные функции напрямую
(`if is_server(): ... else: rpc_id(1, ...)`), но применяет тот же путь
"снапшот → зеркало", что и остальные клиенты, чтобы не дублировать логику
отображения.

## Три канала репликации состояния

1. **Публичный снапшот** (`receive_snapshot`, broadcast всем) — то, что видно
   всем игрокам: фазы, позиции на доске, владельцы полей, постройки, чей ход,
   список ожидающих действий. **Без денег.**
2. **Приватное состояние** (`receive_private_state`, `rpc_id` только владельцу) —
   баланс, текущий долг, входящие/исходящие сделки, "карты освобождения".
3. **Приватный баланс отдельно** (`receive_balance`) — короткий канал только
   для суммы, шлётся при каждом изменении баланса, отдельно от полного
   приватного состояния (чтобы UI успевал реагировать на "+/-" сразу).

Оба состояния версионируются полем `sequence` — клиент отбрасывает более
старый снапшот, если он почему-то пришёл после нового (`_apply_snapshot`,
`_apply_private_state`).

## События (`receive_event`)

Однократные факты (не состояние): `roll`, `turn`, `action`, `trade`
(константы `NetProtocol.EVENT_*`). У каждого события — сквозной
`event_sequence`, дубликаты/устаревшие отбрасываются (`_apply_event`).
`action`-событие несёт произвольное имя (`purchase`, `build`, `bankruptcy`, …)
и данные — по нему HUD показывает всплывающие тосты (`Hud._on_game_action`).

## Хендшейк при подключении

```
Client                                   Server
  │──────── ENet connect ────────────────►│
  │◄─ hello(signature, packs[], api) ──────│   (RPC "authority")
  │  сравнивает свою PackRegistry.signature
  │  совпадает?
  │   да → submit_join(signature, join_payload) ──►│
  │                                         │ game.add_player(...)
  │◄──────── receive_snapshot ──────────────│
  │◄──────── receive_private_state ─────────│
  │   нет → disconnect_session(), эмит desync_detected(diff)
```

Если сигнатуры паков не совпали — клиент **сам себя отключает** ещё до того,
как сервер успел бы что-то сделать; и наоборот, если сервер получит
несовпадающую сигнатуру в `submit_join`, он рвёт соединение с причиной
`"Рассинхрон паков"` (`kicked` RPC). Это защита от того, чтобы игроки с
разным набором модов оказались за одним столом и получили расходящееся
состояние без явной ошибки.

`_diff_packs` строит понятный diff (`missing`/`extra`/`version_mismatch`),
который показывается в UI (`MainMenu._on_desync`).

## RPC-каталог

Все игровые RPC — `@rpc("any_peer", "call_remote", "reliable")`, кроме
серверных push-сообщений (`@rpc("authority", "call_remote", "reliable")`).
Надёжный (reliable) канал выбран сознательно — потеря пакета с намерением
"купить" или "поставить ставку" не должна просто исчезать.

| Клиент → сервер | Действие |
|---|---|
| `server_request_ready` | Готовность в лобби |
| `server_update_profile` | Имя/токен/кастомизация |
| `server_request_start` | Старт партии (только `table_owner`) |
| `server_request_roll` | Бросок кубика |
| `server_request_buy` / `server_request_decline_purchase` | Решение по покупке |
| `server_request_auction_bid` | Ставка/пас на аукционе |
| `server_request_jail_action` | `pay`/`card`/`wait` |
| `server_request_build` / `server_request_sell_building` | Дома/отели |
| `server_request_sell_property` | Продажа поля банку |
| `server_request_mortgage` / `server_request_unmortgage` | Залог |
| `server_request_bankruptcy` | Банкротство |
| `server_propose_trade` / `server_respond_trade` | Сделки |

| Сервер → клиент(ы) | Назначение |
|---|---|
| `hello` | Хендшейк, сигнатура паков |
| `kicked` | Принудительный дисконнект с причиной |
| `receive_snapshot` | Публичное состояние (broadcast) |
| `receive_private_state` / `receive_balance` | Приватные данные (адресно) |
| `receive_event` | Разовые игровые события |

## Итоговая точка: `_publish_result`

Почти все `request_*` на сервере в итоге проходят через `_publish_result(result)`:
если `result.ok`, рассылается новый снапшот, приватные балансы задетых игроков
(`changed_peers`), и — если результат нёс `event` — широковещательное
`action`-событие с урезанными полями (`trade`, `amount` вычищаются, чтобы не
утечь приватные детали через публичное событие). Это единая точка, через
которую *любое* серверное действие превращается в сетевую репликацию —
благодаря этому новый `request_*` не должен заново придумывать, что
рассылать.
