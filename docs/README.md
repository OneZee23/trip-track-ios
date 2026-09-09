# docs

Что где лежит. Корень папки публикуется GitHub Pages (`master:/docs`) — HTML-файлы
из него не двигать: на `privacy-policy.html` и `terms*.html` ссылаются App Store
Connect и `Info.plist`.

| Папка | Что там |
|---|---|
| `releases/<версия>/` | всё к одному релизу: `app-store.md` (тексты стора ×12 локалей), `checklist.md` (что нажать, в каком порядке), `tg-post.md` (пост в канал) |
| `releases/app-review-notes.md` | заметки ревьюеру по всем версиям, свежая сверху |
| `store/` | справочники по карточке: privacy labels, живое ASO |
| `security/` | модель угроз, план по 152-ФЗ / GDPR / рейтингу |
| `architecture/` | заметки по архитектуре, не привязанные к релизу |
| `superpowers/specs`, `superpowers/plans`, `specs/`, `internal/` | в гите нет (`.gitignore`): дизайн-спеки, планы реализации, DPIA и договоры |

Новый релиз — новая папка `releases/<версия>/` с теми же тремя файлами.
