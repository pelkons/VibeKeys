# VibeKeys

Маленькая плавающая панель с клавишами для работы за компьютером без клавиатуры — только мышка и голос.
Панель не забирает фокус: кликнули в поле ввода, потом на кнопку — клавиша уходит в это поле.
Держится поверх всех окон.

| Кнопка | Что делает |
|---|---|
| 🎤 | включает диктовку [OpenWhispr](https://github.com/OpenWhispr/openwhispr) и сама выключает её, когда вы замолчите |
| ✓ | подтвердить (Ctrl+Enter, на Mac — Cmd+Enter) |
| ↵ | Enter |
| ≡ | новая строка (Shift+Enter) |
| ↶ | отменить (Ctrl+Z / Cmd+Z) |
| Esc | Escape |
| ✂ | скриншот области |
| ⌫ | Backspace; если подержать — столбик знаков `.` `?` `,` `!`, выбор скольжением, как на телефоне |

Ещё: масштаб панели 30–200 %, значок в трее / строке меню / верхней панели, автозапуск, панель можно
перетаскивать за ручку слева.

## Скачать

Готовые сборки — в [Releases](https://github.com/pelkons/VibeKeys/releases):

- **Windows 10/11** — `VibeKeys-windows.zip`, внутри `VibeKeys.exe`, установка не нужна.
- **macOS 13+** — `VibeKeys-macos.zip`, внутри `VibeKeys.app`.
- **Ubuntu 24.04+ (GNOME)** — `vibekeys@pelkons.github.io.shell-extension.zip`, расширение GNOME Shell.

## Версии

- [windows/](windows/README.md) — C# / WinForms, собирается встроенным в Windows компилятором.
- [macos/](macos/README.md) — Swift / AppKit.
- [gnome/](gnome/README.md) — расширение GNOME Shell (JavaScript).

Все три собираются и проверяются в GitHub Actions; для тега `v*` автоматически публикуется релиз.

## Лицензия

MIT — см. [LICENSE](LICENSE).
