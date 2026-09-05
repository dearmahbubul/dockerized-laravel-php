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
- **Redis** for cache, sessions and queues.
- **Mailpit** for catching outgoing mail locally.
- **phpMyAdmin + RedisInsight** for database browsing.
- **Xdebug** installed but disabled, ready when you need it.

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
| Horizon         | http://localhost:8080/horizon |
| Mailpit         | http://localhost:8025        |
| phpMyAdmin      | http://localhost:8081        |
| RedisInsight    | http://localhost:5540        |

The first boot takes a few minutes while the image is built and the Laravel
dependencies are installed. Subsequent boots are fast.

---

## What happens on first boot

1. Docker builds the PHP image. It includes a **pre-baked Laravel skeleton**
   (`composer create-project` + Horizon + Laravel AI) at `/opt/laravel`, so no
   clone ever has to download an app through the bind mount itself.
2. The `app` container starts and, if `artisan` is missing from the project
   directory, copies the baked skeleton into `/var/www` (your working
   directory). Existing files are **never overwritten**.
3. A `.env` file is created from `docker/.env.docker` (only if one doesn't
   exist yet). Config is patched to add the `vector` database connection.
4. An `APP_KEY` is generated (kept across restarts).
5. The entrypoint waits for the primary DB and the vector DB.
6. Migrations run in the background for both the primary DB and the `vector`
   DB, then PHP-FPM starts and nginx serves the site.

Result: a working, latest Laravel app wired to all services with zero setup.

---

## Endpoints

| Service        | Host port | Internal        | Notes                              |
| -------------- | --------- | --------------- | ---------------------------------- |
| Laravel site   | `8080`    | `app:80/9000`   | nginx → PHP-FPM                    |
| MySQL          | `3306`    | `mysql:3306`    | user `laravel` / pass `secret`     |
| PostgreSQL     | `5433`    | `postgres:5432` | user `laravel` / pass `secret`     |
| Redis          | —         | `redis:6379`    | no auth                            |
| Mailpit        | `8025`    | `mailpit:1025`  | SMTP on 1025, web UI on 8025       |
| phpMyAdmin     | `8081`    | —               | for MySQL                          |
| RedisInsight   | `5540`    | —               | preloaded with the app's Redis     |

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

## Environment variables

Everything important lives in `.env` (generated from
`docker/.env.docker` on first boot). Container-level overrides are in
`docker-compose.yml` under each service's `environment:`.

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
docker compose down -v        # delete app data (MySQL, Postgres, Redis volumes)
git clean -fdx                # remove generated Laravel files from this folder
docker compose up -d          # boots a fresh Laravel again
```

**Xdebug**
Installed but off by default. Enable via a `php` ini override or a
`docker-compose.override.yml`.

---

## Repository layout

```
.
├── Dockerfile                 # PHP image: extensions, composer, baked skeleton
├── docker-compose.yml         # all services + volumes
├── .gitignore                 # ignores generated Laravel files
├── .dockerignore              # keeps generated files out of the build
└── docker/
    ├── .env.docker            # .env template (also documents the DB toggle)
    ├── entrypoint.sh          # app bootstrap (materialise, .env, key, migrate)
    ├── worker-bootstrap.sh    # bootstrap for horizon / scheduler
    ├── nginx/default.conf     # nginx vhost (root = /var/www/public)
    ├── initdb/01-create-databases.sh  # creates laravel + vector DBs, pgvector
    └── stubs/database.php     # patched config with the vector connection
```