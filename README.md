# Dockerized Laravel + PostgreSQL (pgvector) + MySQL

A self-bootstrapping Docker stack for Laravel. The repository contains **only
Docker files** — no Laravel code. On first `docker compose up -d` the stack
boots a **brand-new, latest Laravel project** for you, with MySQL **or**
PostgreSQL as the primary database, plus an always-on PostgreSQL **pgvector**
database for AI embeddings (RAG / semantic search).

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [What happens on first boot](#what-happens-on-first-boot)
- [Endpoints](#endpoints)
- [Choosing the primary database](#choosing-the-primary-database)
- [Vector database & RAG](#vector-database--rag)
- [PHP configuration](#php-configuration)
- [HTTPS (self-signed)](#https-self-signed)
- [Production deployment](#production-deployment)
- [Environment variables](#environment-variables)
- [Common commands](#common-commands)
- [Troubleshooting](#troubleshooting)
- [Repository layout](#repository-layout)

---

## Features

- **Zero app code in the repo** — a fresh Laravel project is created on first
  boot, so any clone instantly gets today's latest Laravel.
- **Two databases, one toggle** — pick MySQL or PostgreSQL as the primary app
  DB by flipping `DB_CONNECTION` in `.env`. Both servers always run.
- **pgvector always-on** — a dedicated `vector` database with the `pgvector`
  extension pre-created, ready for embeddings.
- **Laravel Horizon** baked in — queue dashboard, workers and scheduler run
  out of the box.
- **Node + Vite dev server** always on for React/Vue/JS compilation with HMR.
- **Redis** for cache, sessions and queues.
- **Mailpit** for catching outgoing mail locally.
- **phpMyAdmin + pgAdmin + RedisInsight** for database browsing.
- **Xdebug** installed but disabled, ready when you need it.
- **Tunable PHP config** via one bind-mounted ini file.
- **HTTPS** (self-signed) built in out of the box.

---

## Requirements

- Docker with Docker Compose v2 (`docker compose version`)
- Git

---

## Quick Start

```bash
git clone <this-repo>
cd dockerized-laravel-php
docker compose up -d
```

Then open:

| What            | URL                          |
| --------------- | ---------------------------- |
| Laravel app     | http://localhost:8080        |
| Laravel app (TLS) | https://localhost:8443     |
| Horizon         | http://localhost:8080/horizon |
| Mailpit         | http://localhost:8025        |
| phpMyAdmin      | http://localhost:8081        |
| pgAdmin (Postgres) | http://localhost:8082     |
| RedisInsight    | http://localhost:5540        |

The first boot takes a few minutes while the image is built and the Laravel
dependencies are installed. Subsequent boots are fast.

---

## What happens on first boot

1. Docker builds the PHP image. It includes a **pre-baked Laravel skeleton**
   (`composer create-project` + Horizon + Laravel AI) at `/opt/laravel`, so no
   clone ever has to download an app through the internet.
2. The `app` container starts and, if `artisan` is missing from the `app_code`
   volume, copies the baked skeleton into `/var/www` **inside a Docker named
   volume** — the repo folder on your disk is never touched and stays
   Docker-only.
3. A `.env` file is created from `docker/.env.docker` (only if one doesn't
   exist yet). Config is patched to add the `vector` database connection.
4. An `APP_KEY` is generated (kept across restarts).
5. Self-signed TLS certs are generated for HTTPS.
6. The entrypoint waits for the primary DB and the vector DB.
7. Migrations run in the background for both the primary DB and the `vector`
   DB, then PHP-FPM starts and nginx serves the site.

Result: a working, latest Laravel app wired to all services with zero setup.

---

## Endpoints

| Service        | Host port | Internal        | Notes                              |
| -------------- | --------- | --------------- | ---------------------------------- |
| Laravel site   | `8080`    | `app:80/9000`   | nginx → PHP-FPM                    |
| Laravel site   | `8443`    | `app:443`       | HTTPS (self-signed)                |
| MySQL          | `3306`    | `mysql:3306`    | user `laravel` / pass `secret`     |
| PostgreSQL     | `5433`    | `postgres:5432` | user `laravel` / pass `secret`     |
| Redis          | —         | `redis:6379`    | no auth                            |
| Mailpit        | `8025`    | `mailpit:1025`  | SMTP on 1025, web UI on 8025       |
| phpMyAdmin     | `8081`    | —               | for MySQL                          |
| pgAdmin        | `8082`    | —               | for PostgreSQL (admin@example.com / admin) |
| RedisInsight   | `5540`    | —               | preloaded with the app's Redis     |
| Vite dev server | `5173`    | `node:5173`     | HMR for React/Vue/JS — see below   |

Database credentials match `.env` defaults:

- MySQL: `laravel` / `laravel` / `secret`
- PostgreSQL: `laravel` / `secret` (both the app `laravel` DB and `vector` DB)

---

## Choosing the primary database

Both database servers run on every boot. Which one the **Laravel app** uses is
controlled by `DB_CONNECTION` in your `.env` (the one next to `docker-compose.yml`,
created from the template at first boot).

### PostgreSQL as primary (recommended for RAG)

Edit `.env`:

```dotenv
DB_CONNECTION=pgsql
DB_HOST=postgres
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=secret
```

Then apply:

```bash
docker compose exec app php artisan config:clear
docker compose exec app php artisan migrate --force
```

The site and migrations now use PostgreSQL. The same instance also hosts the
`vector` database.

### MySQL as primary (default)

The template ships with these values:

```dotenv
DB_CONNECTION=mysql
DB_HOST=mysql
DB_PORT=3306
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=secret
```

The `vector` database is always PostgreSQL — even when MySQL is primary, so
embeddings always live in pgvector.

> You can run both at once: e.g. use MySQL for the app and PostgreSQL for
> vector search. That's the default setup.

---

## Vector database & RAG

The `vector` database runs on `postgres:5432` with the **pgvector** extension
already created (`vector` extension v0.8.6+). It's ready for AI embeddings.

### Laravel AI & OpenAI embeddings

`laravel/ai` ships in the baked skeleton. To generate real embeddings, set a
key in `.env`:

```dotenv
OPENAI_API_KEY=sk-...
AI_EMBEDDINGS_MODEL=text-embedding-3-small
AI_EMBEDDINGS_DIMENSIONS=1536
```

Then work against the `vector` DB connection:

```php
// create
$doc = Document::create([
    'title'     => 'How pgvector works',
    'content'   => '...',
    'embedding' => \Illuminate\Support\Facades\AI::embeddings()->embed('text', 'text-embedding-3-small'),
]);

// search
$needle = \Illuminate\Support\Facades\AI::embeddings()->embed('vector search');
$docs = Document::whereVectorSimilarTo('embedding', $needle)
    ->orderByRaw('embedding <=> ?', [json_encode($needle)])
    ->limit(5)
    ->get();
```

### Adding a documents table

Laravel 13 + Laravel AI support native pgvector columns. Add a migration and
run it against the vector connection only:

```php
// up(): documents table with vector(1536) + HNSW index
Schema::ensureVectorExtensionExists();

Schema::create('documents', function (Blueprint $table) {
    $table->id();
    $table->string('title');
    $table->text('content');
    $table->vector('embedding', 1536)->index(); // HNSW
    $table->timestamps();
});
```

```bash
docker compose exec app php artisan migrate --database=vector --force
```

---

## PHP configuration

Custom PHP settings live in **`docker/php/zz-custom.ini`**, bind-mounted
read-only into the `app`, `horizon` and `scheduler` containers (the `zz-`
prefix makes PHP load it last so it overrides the image defaults). It ships
with sane dev values:

```ini
memory_limit = 256M
upload_max_filesize = 20M
post_max_size = 20M
max_execution_time = 60
display_errors = On
```

Edit the file, restart the PHP processes, and verify:

```bash
docker compose restart app horizon scheduler
docker compose exec app php -i | grep -E 'memory_limit|upload_max_filesize'
```

No rebuild needed. To see all loaded directives: `docker compose exec app php -i`.

---

## HTTPS (self-signed)

HTTPS runs out of the box at **https://localhost:8443**. On the first boot the
app entrypoint auto-generates a self-signed cert into `docker/nginx/certs/`
(git-ignored, one per clone), so every clone gets HTTPS with zero setup.
The cert is served; browsers will still warn that it's untrusted.

To remove the warning, replace the cert with a locally-trusted one via
[mkcert](https://github.com/FiloSottile/mkcert):

```bash
mkcert -install
mkcert -cert-file docker/nginx/certs/localhost.crt \
       -key-file  docker/nginx/certs/localhost.key localhost 127.0.0.1
docker compose restart nginx
```

Or just re-run the generator manually if you ever want to refresh the
self-signed pair:

```bash
docker compose exec -T app sh docker/nginx/tools/generate-ssl.sh
```

---

## Production deployment

The dev stack above is for developing. For production, a different artifact
ships: the app is built **once** in CI into an immutable, non-root image, and
deployed with `docker-compose.prod.yml`. The dev conveniences are gone —
no self-bootstrap, no debug UIs, no host-exposed databases, no self-signed
TLS generation.

```
docker-compose.prod.yml      # hardened single-host deployment
Dockerfile.prod              # CI-built production image (multi-stage)
docker/nginx/prod.conf       # TLS-only nginx (+ security headers, gzip, cache)
docker/.env.prod.example     # template -> .env.prod (git-ignored, real secrets)
docker/backup.sh / restore.sh
```

### The production image (`Dockerfile.prod`)

Built by CI **from your Laravel application repo** (the context is the app, not
this Docker-only repo):

- multi-stage: Composer deps with `--no-dev`, Vite assets pre-built, then a
  lean runtime using `php:8.4-fpm`.
- non-root (`USER www-data`), runs `php-fpm` directly — no boot side effects.
- no Xdebug, no debug/extras, `APP_DEBUG=false` env.

```bash
docker build -f Dockerfile.prod -t ghcr.io/you/app:1.2.3 .
docker push ghcr.io/you/app:1.2.3
```

### Deploy (single host)

```bash
cp docker/.env.prod.example .env.prod    # fill in: APP_KEY, DB/root/redis secrets, SMTP
openssl rand -base64 32                  # use as APP_KEY

# real TLS certs go in docker/nginx/certs/ as server.crt / server.key,
# or terminate TLS at an ingress/CDN in front of 80/443.

export APP_IMAGE=ghcr.io/you/app:1.2.3
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d

# one-shot migrations (also applies vector DB):
docker compose -f docker-compose.prod.yml --env-file .env.prod --profile jobs run --rm migrate
```

Security posture: containers run **read-only rootfs**, non-root, `cap_drop:
ALL`, `no-new-privileges`, `init`, resource limits; only nginx exposes ports
(80/443); MySQL/Postgres/Redis have no host ports; Redis requires a password;
all services log to stdout with rotation; secrets live in the ignored
`.env.prod`.

Backups (cron it on the host):

```bash
./docker/backup.sh            # mysql + postgres (laravel & vector), gzip -> backups/
./docker/backup.sh --all      # + redis snapshot + app storage
./docker/restore.sh           # list, then restore a file to a database
```

### What production **still** needs from you

- Kubernetes (or scale out) instead of one host, with an ingress
  + cert-manager and database on managed services (RDS/Cloud SQL).
- A real CI pipeline: test → build → scan → tag → push.
- Central logging/metrics/tracing and uptime alerts.
- Off-site backups.

This file documents the shape; in a real deploy you'd replace `APP_IMAGE` with
your registry image and run it behind your own network/ingress.

---

## Environment variables

Everything important lives in `.env` (generated from `docker/.env.docker` on
first boot). Container-level defaults (Redis, queue backend) are centralized
once as YAML anchors at the top of `docker-compose.yml` and merged into the
`app`, `horizon`, and `scheduler` services — change a value in one place and
it applies to all three.

| Variable                  | Default                     | Purpose                             |
| ------------------------- | --------------------------- | ----------------------------------- |
| `DB_CONNECTION`           | `mysql`                     | `mysql` or `pgsql` — primary DB     |
| `DB_HOST` / `DB_PORT`     | `mysql` / `3306`            | primary DB host/port (compose name) |
| `DB_DATABASE`             | `laravel`                   | primary DB name                     |
| `DB_USERNAME` / `DB_PASSWORD` | `laravel` / `secret`     | primary DB credentials              |
| `VECTOR_DB_HOST` / `VECTOR_DB_PORT` | `postgres` / `5432` | vector (pgvector) connection       |
| `VECTOR_DB_DATABASE`      | `vector`                    | vector DB name                      |
| `OPENAI_API_KEY`          | *(empty)*                   | required for real embeddings        |
| `CACHE_STORE`, `SESSION_DRIVER`, `QUEUE_CONNECTION` | `redis` | cache/session/queue backend |
| `MAIL_*`                  | Mailpit values              | SMTP catches all mail locally       |

---

## Frontend (Vite)

A `node` service runs `npm install` once and then `npm run dev`, exposing the
dev server at **http://localhost:5173**.

- On first boot it writes `public/hot`, so Laravel automatically serves your
  JS/CSS bundles through the dev server with hot module replacement (HMR) —
  edit your React/Vue components and the browser updates instantly.
- `vite.config.js` is patched at first boot (like `config/database.php`) so the
  dev server binds to `0.0.0.0` inside the container but advertises
  `localhost` in `public/hot` — browsers block `0.0.0.0`, which would leave
  the page unstyled. Accessing from another machine? Change
  `server.hmr.host` in `vite.config.js` to your hostname.
- `npm` packages live inside the `app_code` volume (not on disk).
- For production-style assets instead, stop the `node` service and run a build
  inside the `app` container:

```bash
docker compose stop node
docker compose exec app npm exec -- npm run build
```

---

## Common commands

```bash
docker compose up -d                 # start everything
docker compose down                  # stop (keeps volumes)
docker compose down -v               # stop and wipe database volumes
docker compose build                 # rebuild the PHP image
docker compose logs -f app           # follow app logs
docker compose exec app bash         # shell into the app container
docker compose exec app php artisan migrate --force          # migrate primary DB
docker compose exec app php artisan migrate --database=vector --force  # migrate vector DB

# ---- production (docker-compose.prod.yml) ----
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d   # deploy
docker compose -f docker-compose.prod.yml --env-file .env.prod --profile jobs run --rm migrate   # one-shot migrations
export APP_IMAGE=ghcr.io/you/app:1.2.3                               # pick deployed image
docker/backup.sh && docker/backup.sh --all                            # backups
```

---

## Troubleshooting

**Port 3306 / 8080 / 5433 already in use**
A local MySQL/Postgres/nginx is occupying the host port. Either stop it or
change the `ports:` mapping in `docker-compose.yml`.

**"Connection refused" to mysql / postgres on first boot**
Rare race — the entrypoint already waits for healthy DBs. Check health with
`docker compose ps` and the logs with `docker compose logs app`.

**Want to start from scratch / reset the app**
```bash
docker compose down -v        # deletes app_code + DB volumes; boots a fresh Laravel again
docker compose up -d
```

**Xdebug**
Installed but off by default. Enable via a `php` ini override or a
`docker-compose.override.yml`.

---

## Repository layout

```
.
├── Dockerfile                 # dev PHP image: extensions, composer, baked skeleton
├── Dockerfile.prod            # production image (CI-built, multi-stage, non-root)
├── docker-compose.yml         # dev: all services + volumes + shared env anchors
├── docker-compose.prod.yml    # production: hardened, immutable, one-shot migrate
├── .gitignore                 # ignores generated Laravel files + .env.prod
├── .dockerignore              # keeps generated files out of the build
└── docker/
    ├── .env.docker            # dev .env template (also documents the DB toggle)
    ├── .env.prod.example      # production env template -> .env.prod (secrets)
    ├── entrypoint.sh          # app bootstrap (materialise, .env, key, TLS, migrate)
    ├── worker-bootstrap.sh    # bootstrap for horizon / scheduler
    ├── backup.sh / restore.sh # DB/volume backup & restore (prod)
    ├── php/zz-custom.ini      # custom PHP settings (bind-mounted)
    ├── nginx/
    │   ├── default.conf       # dev vhost: HTTP (80) + HTTPS (443 ssl)
    │   ├── prod.conf          # prod vhost: TLS-only, headers, gzip, caching
    │   ├── certs/             # generated self-signed certs (git-ignored)
    │   └── tools/generate-ssl.sh  # creates the certs
    ├── initdb/01-create-databases.sh  # creates laravel + vector DBs, pgvector
    └── stubs/database.php     # patched config with the vector connection
```