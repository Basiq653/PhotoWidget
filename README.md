# Фото-виджет (Photo Widget)

Настоящий системный виджет для рабочего стола iOS 16, который показывает **любое фото из галереи**.
Сделано под **Dopamine (rootless, `/var/jb`), iOS 16.7.x**.

Что внутри:

| Часть | Что делает |
|---|---|
| `PhotoWidget.app` | приложение с выбором фото (`PhotosPicker`, без запроса доступа ко всей галерее) |
| `PhotoWidgetExt.appex` | WidgetKit-виджет, размеры **S / M / L** |
| `scripts/make_deb.py` | сборка rootless `.deb` без `dpkg`/`fakeroot` |
| `.github/workflows/build.yml` | сборка `.deb` на macOS-раннере GitHub — локально ничего ставить не нужно |

Фото хранится в `/var/mobile/Library/PhotoWidget/photo.jpg` (плюс копия в бандле расширения —
на случай, если расширение окажется в песочнице). Поэтому после выбора фото виджет обновляется
через `WidgetCenter.reloadAllTimelines()`, без перезагрузки устройства.

Готовый архив с исходниками лежит рядом: `PhotoWidget-src.zip` (там же внутри скрытая папка `.github`
с workflow — Windows её не показывает, но в архиве она есть).

---

## Сборка через GitHub Actions (Windows подходит)

1. Зайди на github.com → **New repository** → имя, например `PhotoWidget` → **Private** → Create.
2. Распакуй `PhotoWidget-src.zip`, зайди в папку `PhotoWidget`.
3. На странице пустого репозитория: **Add file → Upload files** → перетащи в окно браузера **всё содержимое**
   этой папки (`App`, `Extension`, `Shared`, `scripts`, `Support`, `.github`, `project.yml`, `README.md`, `LICENSE`, `.gitignore`).
   Проще всего: выделить всё в проводнике (Ctrl+A) и перетащить.
4. **Commit changes**.
5. Если папка `.github` не попала в репозиторий (проверь на странице репозитория): **Add file → Create new file**,
   в поле имени введи ровно `.github/workflows/build.yml`, и вставь туда содержимое файла
   `.github/workflows/build.yml` из архива. Commit.
6. Вкладка **Actions** → слева workflow **Build DEB** → **Run workflow** → **Run workflow**.
7. Через ~5 минут открой завершившийся запуск, внизу раздел **Artifacts** → скачай
   `PhotoWidget-deb.zip` → внутри `PhotoWidget_1.0.0_iphoneos-arm64.deb`.

Если сборка упала — скачай там же артефакт `build-log` и покажи мне, поправлю.

### Установка

Любым из способов:

- **Sileo / Zebra**: открой скачанный `.deb` (поделиться → Sileo) или `dpkg -i`.
- **Filza**: тап по `.deb` → Install.
- Терминал (NewTerm): `dpkg -i /var/mobile/Downloads/PhotoWidget_1.0.0_iphoneos-arm64.deb`

После установки Sileo предложит respring — согласись.

### Как поставить виджет

1. Открой приложение **«Фото-виджет»** (иконка появится на рабочем столе).
2. **Выбрать фото из галереи** → выбери любое фото.
3. Рабочий стол → зажми пустое место → **«Изменить экран»** → **«+»** сверху.
4. В списке найди **«Фото-виджет»** → выбери размер → **«Добавить виджет»**.

Тап по виджету открывает приложение (можно быстро поменять фото).

---

## Если что-то не так

**Виджета нет в галерее виджетов**

WidgetKit-расширения на джейлбрейке регистрируются через `pluginkit`, и иногда системе нужно помочь:

```sh
uicache -a
pluginkit -a /var/jb/Applications/PhotoWidget.app/PlugIns/PhotoWidgetExt.appex
ldrestart        # или respring из Sileo
```

Ещё вариант — открыть приложение один раз после установки и подождать 10–20 секунд.

Если после этого виджета всё равно нет — скажи мне, тогда переделаю на вариант «фото-плитка
поверх рабочего стола» (SpringBoard-твик), он не зависит от WidgetKit вообще.

**Виджет пустой (плейсхолдер «Выбери фото»)**

Открой приложение: внизу раздел **«Диагностика»** — там видно оба пути к файлу и есть ли к ним доступ.
Если у общего пути статус «папка недоступна», а у пути в бандле — «есть», значит сработала страховка,
и виджет всё равно должен показать фото после `respring`.

**Приложение не запускается**

Проверь, что джейлбрейк именно **rootless** (Dopamine, а не roothide/rootful). Для roothide пути
начинаются не с `/var/jb`, а с `$JBROOT` — тогда в `scripts/make_deb.py` нужно поменять `INSTALL_DIR`,
а в `Shared/PhotoStore.swift` — путь к общей папке.

**Хочу поменять имя / bundle id**

`project.yml` → `CFBundleDisplayName` и `PRODUCT_BUNDLE_IDENTIFIER` (у приложения и у расширения —
расширение обязательно должно начинаться с id приложения: `com.photowidget.widget`).

---

## Локальная сборка (если есть Mac)

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project PhotoWidget.xcodeproj -scheme PhotoWidget \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
python3 scripts/make_deb.py build/Build/Products/Release-iphoneos/PhotoWidget.app \
  dist/PhotoWidget_1.0.0_iphoneos-arm64.deb
```

---

## Известные ограничения

- WidgetKit-расширения официально не поддерживаются джейлбрейком: всё держится на том, что
  Sileo ставит бандл в `/var/jb/Applications` и `uicache` регистрирует его в LaunchServices.
  На Dopamine 2.x (iOS 15–16) это работает; на некоторых сборках может понадобиться `ldrestart`.
- Фото одно. Если нужна ротация нескольких фото — скажи, добавлю список и смену по таймлайну.
- `.deb` собран из ad-hoc подписи (`codesign --sign -`), без entitlements и provisioning profile.
