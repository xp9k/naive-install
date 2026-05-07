# NaiveProxy Auto-Installer

Интерактивный скрипт для автоматической установки NaiveProxy на Linux-сервер.

Собирает Caddy с naive-форком forwardproxy, настраивает systemd-сервис, TLS через Let's Encrypt, маскировочный веб-сайт, генерирует логин/пароль и выводит данные для подключения.

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
2. Устанавливает зависимости и Go (если нет)
3. Собирает Caddy с `forwardproxy@naive` через xcaddy
4. Генерирует Caddyfile с `forward_proxy`, `probe_resistance`, маскировкой через `file_server`
5. Создаёт systemd-сервис и пользователя `caddy`
6. Спрашивает про открытие портов в файрволе
7. Выводит данные подключения на экран и сохраняет в `/root/.naive.txt`

## Удаление

```bash
bash <(curl -sL https://raw.githubusercontent.com/xp9k/naive-install/main/install.sh) uninstall
```

Или на уже установленном сервере:

```bash
bash install.sh uninstall
```