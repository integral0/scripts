#!/bin/bash
# v.2.3

# ======= Настройки ========
URL_FILE="urls.txt"      # список URL
MINS=5                   # интервал между шагами (в минутах)
STEP=10                  # на сколько увеличиваем пользователей каждый шаг
MAX_STEP=10              # сколько шагов максимум
START_RPS=50             # начальное кол-во пользователей
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_DIR="./siege_logs/$TIMESTAMP"
CREDS_FILE="creds.ini"

mkdir -p "$LOG_DIR"

# ======= Авторизация (если есть creds.ini) =======
if [ -f "$CREDS_FILE" ]; then
  source "$CREDS_FILE"


  if [ -n "${LOGIN:-}" ] && [ -n "${PASS:-}" ] && [ -n "${AUTH_URL:-}" ]; then
    COOKIE_FILE=$(mktemp)
    echo "Авторизация на $AUTH_URL пользователем $LOGIN..."

    curl -s -c "$COOKIE_FILE" -d "username=$LOGIN&password=$PASS" "$AUTH_URL" > /dev/null

    # Если COOKIE_NAME не задан, используем "session"
    COOKIE_NAME="${COOKIE_NAME:-session}"

    SESSION_COOKIE=$(grep -i "$COOKIE_NAME" "$COOKIE_FILE" | awk '{print $6"="$7}' | tail -n1)

  else
    echo "В $CREDS_FILE нет LOGIN/PASS/AUTH_URL — пропускаем авторизацию."
  fi

  if [ -n "${BASIC_AUTH}" ]; then
    ADD_OPTS+=(-H "Authorization: Basic ${BASIC_AUTH}" )
  fi

  if [ -n "$SESSION_COOKIE" ]; then
    echo "Кука $COOKIE_NAME получена: $SESSION_COOKIE"
    ADD_OPTS+=(-H "Cookie: $COOKIE_NAME=$SESSION_COOKIE" )
  else
    echo "SESSION_COOKIE не найдена, продолжаем без неё."
  fi

  if [ -n "$USER_AGENT" ]; then
    ADD_OPTS+=(-A "$USER_AGENT")
  else
    echo "UserAgent не найден, продолжаем без него"
  fi
else
  echo "Файл $CREDS_FILE не найден — запускаем без авторизации."
fi

# ======= Проверки =======
if [ ! -f "$URL_FILE" ]; then
  echo "Файл $URL_FILE не найден!"
  exit 1
fi

echo "Стартуем нагрузочное тестирование..."

# ======= Основной цикл =======
for (( i=0; i<$MAX_STEP; i++ ))
do
  USERS=$((START_RPS + i * STEP))
  LOG_FILE="$LOG_DIR/siege_run_${USERS}users.log"

  echo ""
  echo "Шаг $((i+1)): $USERS пользователей, длительность $MINS мин."
  echo "Лог: $LOG_FILE"

  set -x
  siege "${ADD_OPTS[@]}" -f "$URL_FILE" -c "$USERS" -t "${MINS}M" \
        -v --no-follow --no-parser -j 2>&1 | tee "$LOG_FILE"
  set +x

  # Анализ результата
  FAIL_COUNT=$(grep -Eo '"failed_transactions":\s+[0-9]*' "$LOG_FILE" | awk '{sum+=$2} END {print (sum == "" ? 0 : sum)}')

  echo "Ошибок: $FAIL_COUNT"

  if (( FAIL_COUNT > 0 )); then
    echo "Обнаружены ошибки на шаге $((i+1)) — тест остановлен!"
    break
  fi
  sleep 10
done

echo ""
echo "Тест завершён."
