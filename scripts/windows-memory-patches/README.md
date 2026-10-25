# Патчи: утечки памяти Octo под Windows

Всё лежит здесь, сам клон `C:\Projects\octo\octo-player` остаётся чистым —
патчи не в репозитории, чтобы накатывать их на любую свежую выгрузку.

```
patches\0001..0004-*.patch   четыре коммита по git format-patch
windows-native-memory.bundle тот же набор одним файлом (git bundle)
apply-patches.ps1            накатывает патчи на новую версию
README.md                    этот файл
```

База, на которой патчи сделаны и проверены: `ab79bfe` (main, desktop 1.10.x).
В клоне они лежат в ветке `fix/windows-native-memory` — там же история и
комментарии в коде, на английском, в стиле репозитория.

## 1. Быстрый вариант: клон обновился до новой версии

```bash
cd C:/Projects/octo/octo-player
git fetch origin --tags --prune
git rebase --onto desktop-v1.11.0 ab79bfe fix/windows-native-memory
```

`ab79bfe` — старая база, её менять не надо; именно по ней git понимает,
какие коммиты наши. Конфликты разрешаются штатно: поправить файл, `git add`,
`git rebase --continue`. Четыре коммита маленькие, разбор занимает минуты.

Если история апстрима перестала включать `ab79bfe` (ребейс/squash у автора) —
вариант 2, он от истории не зависит.

## 2. Свежая выгрузка новой версии

```bash
git clone https://github.com/winters27/octo-player C:/Projects/octo/octo-1.11
powershell -File C:/Projects/octo/patches/windows-native-memory/apply-patches.ps1 `
  -Repo C:/Projects/octo/octo-1.11 -Base desktop-v1.11.0
```

Патчи применяются по одному через `git am -3` (three-way), тексты коммитов
сохраняются. На конфликте скрипт печатает список файлов с метками
`<<<<<<<` и три команды: `am --continue` после правки, `am --skip`, `am --abort`.

Скрипт проверен на свежем клоне от `ab79bfe`: четыре коммита лёгли чисто, дерево
вышло побайтово тем же, что в ветке. Если кириллица в консоли показывается
вопросительными знаками — это кодовая страница консоли, помогает `chcp 65001`
перед запуском; если политика выполнения не даёт запустить файл, добавь
`-ExecutionPolicy Bypass`. Ветка по умолчанию называется
`fix/windows-native-memory-<короткий хеш базы>`, имя задаётся через `-Branch`.

## 3. Если клона нет совсем — восстановить из bundle

```bash
git clone C:/Projects/octo/patches/windows-native-memory/windows-native-memory.bundle -b fix/windows-native-memory C:/Projects/octo/octo-restored
```

Bundle тонкий: требует, чтобы в репозитории был `ab79bfe`. Клон оригинального
репозитория его содержит, поэтому бандл + клон = полная ветка. Надёжнее
держать связку «bundle + клон апстрима», а не один bundle.

## Где патчи чаще всего цепляют апстрим

По опыту этих четырёх коммитов и истории репозитория (там был `fix/desktop-memory`):

| Файл | Почему задевает |
|---|---|
| `desktop/.../system/OctopusArt.kt` | рисование иконок правят часто (форма, размеры, файл-иконки) |
| `desktop/.../Main.kt` | стартовый поток окна и слушатели фокуса |
| `desktop/.../search/Fetches.kt` | загрузка песен с сервера |
| `desktop/.../library/PlaylistArtStore.kt` | обложки плейлистов и их кэш |
| `audio-engine/src/deck.rs` | чтение и гейты деки |
| `desktop/.../lyrics/FlowingLyrics.kt` | маска слова в тексте песни |

Правая логика в этих местах — «закрыть нативный объект» и «ограничить карту»,
а она в конфликтах решается просто: брать апстримовский код и вставлять в него
наши `use {}`, `finally { x.close() }`, `LateClose.close(...)` и подрезку карт.

## Проверка после накатки (проверено на этой машине)

```bash
export JAVA_HOME="C:/Projects/octo/tools-dl/jdk-17.0.20.1+1"; export PATH="$JAVA_HOME/bin:$PATH"
./gradlew :desktop:compileKotlin :desktop:test :desktop-design:test --daemon
cd audio-engine && cargo test --release
./gradlew :desktop:packageMsi :desktop:packagePortableZip -PoctoBuild=$(git rev-list --count HEAD) --daemon
```

- MSI и zip выходят в `desktop\build\compose\binaries\main\msi|zip\` (номер сборки = число коммитов; WiX плагин скачивает сам).
- **Локаль:** тесты `SongFiltersTest.theCountSaysHowManyOfHowMany` и
  `FrameFitTest.countsMarkThousandsAndSayOne` ждут разделитель «2,835» и на русской
  системе падают сами по себе (форматирование берёт системную локаль). Проходить
  полную проверку надо с `-Duser.language=en -Duser.country=US`, иначе эти два —
  ожидаемый шум. С `JAVA_TOOL_OPTIONS` ещё падает
  `SingleInstanceAcrossProcessesTest` («Picked up…» в stdout дочерней JVM) — его тоже
  считать шумом, проверять отдельно без переопределения локали.
- Масштабный замер роста: `powershell -File scripts/soak-desktop.ps1 -Label fixed -Minutes 120`
  (нужен тестовый профиль со входом в сервер; снимает private bytes, working set,
  потоки, ручки, heap и NMT, в конце делает две полные сборки мусора).

## Состав коммитов

1. `fix(desktop): the drawing hands its native objects back` — закрытие Paint/Path/Image/Bitmap/Canvas/Surface
   на горячих путях (иконки трея и панели задач, кривая эквалайзера, слайдеры, обложки, wash),
   кэш оконных иконок, учёт байтов в кэше обложек, `restore()` в `finally` в маске текста песни.
2. `fix(desktop): the per-song records a run keeps are bounded` — ограниченные карты: фазы загрузок
   и `askedAt`/`landed`, измеренные длительности, ревизии текстов, `failedAt` в Discord.
3. `fix(desktop): one thread for the focus reads, and browsers let go` — один поток на чтение системных
   настроек при фокусе окна вместо потока на каждый фокус; освобождение процессов «открыть в браузере».
4. `fix(audio-engine): the engine's own memory stops growing per song` — Rust: `Player::infos` до 256 записей,
   сжатие PCM-буфера деки до steady-размера (`Fifo::shrink_to`).

Итог проверок на базе `ab79bfe`: `:desktop:test` + `:desktop-design:test` — 1210 тестов, падения только
обусловленные локалью/переопределением JVM; `cargo test --release` — 206 тестов без падений; MSI и portable zip
собираются и запускаются.
