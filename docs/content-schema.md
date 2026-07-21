# Формат JSON-контента

Весь игровой контент — данные, не код. Загружается `ModLoader` из
`content/<category>/*.json` каждого пака (см. `PackRegistry.CATEGORIES`) и
регистрируется по составному id `packId:localId`. Каждый файл может быть
одним объектом или массивом объектов.

Общие поля, добавляемые движком автоматически при регистрации
(`PackRegistry.register`), которые не нужно указывать руками:

- `full_id` — итоговый `packId:localId`;
- `pack_id` — id пака-владельца;
- `tags` — если не указано в JSON, подставляется `[]`.

---

## `cells` — клетки доски (`packs/core/content/cells/cells.json`)

| Поле | Тип | Обяз. | Описание |
|---|---|---|---|
| `id` | string | да | Локальный id |
| `name` | string | да | Отображаемое имя |
| `type` | string | да | `corner_start` \| `corner_jail` \| `corner_free_parking` \| `corner_go_to_jail` \| `tax` \| `chance` \| `treasury` \| `property` \| `railroad` \| `utility` \| произвольный (для модов через хук `on_land`) |
| `tags` | array | нет | `"corner"` обязателен для угловых клеток — по нему рендер решает делать клетку крупнее |
| `color` | string (`#rrggbb`) | нет | Акцентный цвет плашки/группы |
| `group` | string | для `property` | Группа для расчёта монопольного бонуса ренты (`brown`, `blue`, …) |
| `price` | int | для покупаемых | Цена покупки |
| `mortgage` | int | нет | Сумма залога; по умолчанию `price / 2` |
| `sale_price` | int | нет | Цена продажи банку; по умолчанию `round(price * property_sale_multiplier)` |
| `house_cost` | int | для `property` | Цена одного уровня застройки (дом/отель) |
| `rent_table` | array[int] | да (покупаемые) | Индексируется: `property` — по `improvements` (0..5, где 5 = отель); `railroad` — по (кол-во дорог владельца − 1) |
| `rent_growth` | float | нет, default `1.0` | Множитель ренты за каждое доп. поле группы **до** застройки: `rent *= rent_growth^(owned-1)`. `1.0` = выключено |
| `multiplier_one` / `multiplier_two` | int | для `utility` | Множитель на значение кубика при 1 или 2 коммуналках у владельца |
| `amount` | int | для `tax` | Фиксированный налог |
| `icon` | string (путь) | нет | Текстура иконки поля, относительно корня пака; иначе — плейсхолдер-эмблема |
| `decor_model` | string (путь) | нет | `.glb`/`.gltf`/`.tscn`, чисто декоративная модель поверх тайла |

Пример из `cells.json`:
```json
{"id":"brown_1","name":"Старый двор","type":"property","group":"brown",
 "color":"#70402b","price":60000,"mortgage":30000,"house_cost":50000,
 "rent_table":[8000,40000,120000,360000,640000,900000],"rent_growth":1.1}
```

---

## `rulesets` — режимы игры (`packs/core/content/rulesets/classic.json`)

| Поле | Тип | Default | Описание |
|---|---|---|---|
| `id`, `name`, `tags` | — | — | Идентификация ruleset'а в UI |
| `board_size` | int | 15 | Сторона квадрата доски; периметр = `4*(size-1)` клеток |
| `board_cells` | array[string] | — | Id клеток по порядку кольца, длина должна совпадать с периметром |
| `special_cells` | dict | — | Альтернатива `board_cells`: `{"index": "cell_id"}`, если не все позиции важны |
| `default_cell` | string | — | Fallback, если индекс не покрыт |
| `starting_cash` | int | 1200000 | Стартовый баланс |
| `pass_start_reward` | int | 200000 | Начисление за прохождение через СТАРТ |
| `min_players` | int | 2 | Минимум для старта партии |
| `default_role` / `default_token` | string | — | Роль/фигурка по умолчанию для новых игроков |
| `jail_fine` | int | 100000 | Штраф за выход из тюрьмы |
| `jail_max_turns` | int | 3 | Сколько раз можно "пропустить" до принудительной оплаты |
| `unmortgage_multiplier` | float | 1.1 | Множитель к сумме залога при выкупе |
| `property_sale_multiplier` | float | 0.5 | Доля цены при продаже поля банку |
| `auction_enabled` | bool | false | Уходит ли непроданное поле на закрытый аукцион |
| `dice_model` / `board_model` / `table_model` | string (путь) | — | Кастомные 3D-модели (см. `mods/README.md`) |

---

## `tokens` — фигурки игроков

| Поле | Тип | Описание |
|---|---|---|
| `id`, `name`, `tags` | — | Идентификация в UI-списке кастомизации |
| `mesh` | string | `cylinder` (default) \| `box` \| `capsule` \| `cone` \| `sphere` — форма процедурной фигурки, см. `TokenView._build_mesh` |
| `color` | string (`#rrggbb`) | Цвет по умолчанию, если игрок не задал свой |
| `model` | string (путь) | Кастомная `.glb`/`.gltf`/`.tscn`-модель; заменяет процедурную форму целиком и **не тонируется** кастомизацией игрока |

---

## `roles` — роли/классы игрока

| Поле | Тип | Описание |
|---|---|---|
| `id`, `name`, `description`, `tags` | — | В базовой игре есть только `normal` без эффектов |
| `hooks` | dict | Зарезервировано для декларативного связывания роли с хуками EventBus (см. `RoleDef.from_dict`) |

`"default"` в `tags` помечает роль по умолчанию (`RoleDef.is_default`).

---

## `cards` — карточки "Шанс"/"Казна"

| Поле | Тип | Описание |
|---|---|---|
| `id`, `title`, `text` | — | Отображается в тосте при вытягивании |
| `deck` | string | `"chance"` или `"treasury"` — определяет, в какую колоду попадёт карта (`CardDeck.setup` фильтрует по этому полю) |
| `effects` | array | Список эффектов, применяются по порядку `GameController._apply_card` |

### Типы эффектов карт

| `type` | Поля | Действие |
|---|---|---|
| `credit` | `amount` | Зачислить игроку |
| `debit` | `amount` | Списать (через `_charge`, может уйти в `managing_assets` при нехватке) |
| `move_to` | `index`, `collect_start` (bool) | Телепорт на клетку; если `collect_start` и цель "позади" текущей позиции — начисляется `pass_start_reward` |
| `move_relative` | `steps` (может быть отрицательным) | Сдвиг по кольцу |
| `send_to_jail` | — | В тюрьму |
| `get_out_of_jail` | — | +1 к `get_out_cards` игрока |
| `collect_each` | `amount` | Получить с каждого живого игрока |
| `pay_each` | `amount` | Заплатить каждому живому игроку |
| `repairs` | `per_house`, `per_hotel` | Списать за все постройки игрока (уровни 1–4 = дом, 5 = отель) |

---

## `sounds` — привязка звуковых событий (`packs/core/content/sounds/events.json`)

| Поле | Тип | Описание |
|---|---|---|
| `id` | string | Локальный id записи |
| `event` | string | Логическое имя события (`ui.click`, `game.dice_roll`, `net.error`, …), на которое подписывается `AudioDirector` |
| `bus` | string | `"Music"` \| `"SFX"` \| `"UI"` |
| `volume_db`, `pitch_min`, `pitch_max` | float | Параметры воспроизведения |
| `streams` | array[string] (путь) | Файлы аудио, один выбирается случайно; если пусто/не найдено — фолбэк на `tone` |
| `tone` | dict | Процедурный тон: `wave` (`sine`\|`square`\|`noise`), `frequency`, `end_frequency`, `duration`, `gain`, `decay` — генерируется `AudioDirector._generate_tone`, чтобы пак работал вообще без аудиофайлов |

---

## Правило переопределения (для всех категорий)

Более поздний по порядку загрузки пак **перезаписывает** контент с тем же
`full_id`. Порядок загрузки — топологическая сортировка по `dependencies`
(жёсткая зависимость, ошибка если отсутствует) и `load_after` (мягкий
порядок, не ошибка при отсутствии), при равенстве — по алфавиту id пака.
Директории сканируются в порядке `res://packs → res://mods → user://mods`,
так что пользовательские моды всегда могут переопределить встроенный
контент — это и есть механизм полной конверсии игры.
