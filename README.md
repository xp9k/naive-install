# NaiveProxy Auto-Installer

Интерактивный скрипт для автоматической установки NaiveProxy на Linux-сервер.

Скачивает или собирает Caddy с naive-форком forwardproxy, настраивает systemd-сервис, TLS через Let's Encrypt, маскировочный веб-сайт, генерирует логин/пароль и выводит данные для подключения.

## Требования

- Linux (Ubuntu/Debian, CentOS/RHEL, Fedora, Arch)
- Root-доступ
- Домен, указывающий на IP сервера

## Установка

Одной командой:

```bash
bash <(curl -sL https://raw.githubusercontent.com/xp9k/naive-install/main/install.sh)
```

Или:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/xp9k/naive-install/main/install.sh)
```

## Что делает скрипт

1. Интерактивно запрашивает: домен, email, логин/пароль (или генерирует автоматически), порт, web-root
2. Предлагает выбор имени сервиса: `naive` (более скрытный) или `caddy` (стандартный)
3. Предлагает выбор: скачать готовый бинарник или собрать из исходников (при ошибке — пробует второй способ)
4. При сборке из исходников спрашивает, удалить ли Go после установки для экономии места
5. Устанавливает зависимости
6. Скачивает/собирает Caddy с `forwardproxy@naive`
7. Генерирует Caddyfile с `forward_proxy`, `probe_resistance`, маскировкой через `file_server`
8. Создаёт systemd-сервис и пользователя с выбранным именем
9. Спрашивает про открытие портов в файрволе
10. Выводит данные подключения на экран и сохраняет в `/root/.naive.txt`

## Управление сервисом

Имя сервиса — `naive` или `caddy` (по выбору при установке):

```bash
systemctl start naive       # запустить
systemctl stop naive        # остановить
systemctl reload naive      # перезагрузить конфиг
systemctl status naive      # статус
systemctl enable naive      # автозапуск
systemctl disable naive     # убрать из автозапуска
```

## Удаление

Полностью удаляет Caddy, конфиг, сервис и Go (если был установлен скриптом при сборке):

```bash
bash <(curl -sL https://raw.githubusercontent.com/xp9k/naive-install/main/install.sh) uninstall
```

Или на уже установленном сервере:

```bash
bash install.sh uninstall
```

Скрипт спросит имя сервиса для корректного удаления.