# premium-cars-infra

Започни оттук. Това репо съдържа локалната база данни (PostgreSQL в Docker) и инструкцията за пускане
на целия проект Premium Cars Import.

| Репо | Какво е | Технология | Порт |
|---|---|---|---|
| `premium-cars-backend` | REST API, импорт по линк, цени, запитвания | Java 21, Spring Boot 3.5, JdbcClient (без JPA), Liquibase | 8080 |
| `premium-cars-frontend` | публичен сайт + админ панел | Next.js 16, React 19, TypeScript, Tailwind CSS 4 | 3000 |
| `premium-cars-infra` | локална база | Docker Compose, PostgreSQL 17 | 5433 |

Дръж трите репота едно до друго в една папка:

```
premium-cars/
├── premium-cars-backend/
├── premium-cars-frontend/
└── premium-cars-infra/
```

---

## 1. Какво да инсталираш (еднократно)

| Програма | Защо |
|---|---|
| JDK 21 (Eclipse Temurin) | бекендът |
| Maven 3.9+ | билд на бекенда (IntelliJ има вграден) |
| Node.js 22 LTS или по-нов LTS | фронтендът |
| Docker Desktop | PostgreSQL и тестовете на бекенда |
| Git | репотата |
| IntelliJ IDEA / VS Code | редактори |

## 2. Локален старт

```bash
# 1. база
cd premium-cars-infra
docker compose up -d
docker compose ps                  # STATUS: healthy

# 2. бекенд (нов терминал)
cd premium-cars-backend
mvn spring-boot:run                # или Run на PremiumCarsApplication в IntelliJ

# 3. фронтенд (нов терминал)
cd premium-cars-frontend
cp .env.example .env.local         # PowerShell: Copy-Item .env.example .env.local
npm install
npm run dev
```

Проверка:

- http://localhost:8080/api/public/cars → JSON с 3 демо коли
- http://localhost:3000 → сайтът
- http://localhost:3000/admin → вход `admin` / `admin123` → постави линк от global.autohome.com.cn → „Импортирай“

База: `localhost:5433`, база/потребител/парола `premiumcars`. Пълно изтриване на данните: `docker compose down -v`.

---

## 3. GitHub и Claude Code

Кодът живее в три частни репота в GitHub. Claude Code работи по тях директно от claude.ai/code
(браузър или телефон): прави клон, промени, пуска тестовете и отваря pull request. Ти го преглеждаш и
натискаш Merge.

Всяко репо има:

- `CLAUDE.md`: как се билдва, тества и какви са правилата (напр. „без JPA, само JdbcClient“). Claude го чете при всяка задача.
- `.github/workflows/ci.yml`: проверки при всеки push и pull request:
  - backend: `mvn verify`, включително тестовете с PostgreSQL в Docker;
  - frontend: `npm run lint` и `npm run build`;
  - infra: проверка на `docker-compose.yml`.

### Работа на твоя компютър след промени от Claude

```bash
cd premium-cars-backend
git pull                 # взимаш merge-натите промени
```

Ако искаш да продължиш локално започната от Claude задача: `claude --teleport` в папката на репото.

### Локален Claude Code (по желание)

Инсталирай Claude Code (виж code.claude.com/docs) и пусни `claude` в папката на репо. Подходящо е за
задачи, при които искаш да гледаш отблизо или да тестваш с локалната база.
