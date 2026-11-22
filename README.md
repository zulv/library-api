# Library API

Rails 8.1 API for library staff to manage books, readers and borrowings, with email reminders before a book is due.

Ruby 4.0, PostgreSQL 18, Solid Queue, Solid Cache.

## Highlights

- Borrowing and returning are a resource (`POST` / `DELETE /books/:book_id/borrowing`), and a book's status is derived from its borrowings.
- One open borrowing per book is guaranteed by the database and a row lock, so double requests can't lend a copy twice.
- Reminders 3 days before and on the due date run as a daily job that never sends duplicates.
- Reader data is encrypted at rest, kept out of lists and logs, anonymized on request and detached from history after 2 years.
- The OpenAPI docs are generated from the request specs, and CI checks they are up to date.

The full reasoning and trade-offs are in [docs/DESIGN.md](docs/DESIGN.md).

## Running it

```
docker compose up
```

The first start installs gems, creates the databases and seeds data. The app is ready when `curl localhost:3000/up` returns 200.

| | |
|---|---|
| API | http://localhost:3000 |
| Swagger UI | http://localhost:3000/api-docs |
| Mailpit, catches all outgoing email | http://localhost:8025 |
| Mailer previews | http://localhost:3000/rails/mailers |
| PostgreSQL | `localhost:5433`, user `postgres`, password `postgres`, database `library_api_development` |

- **Staff login:** `librarian@example.com` / `password` (development only).
- **Seeded data:** readers `200001`–`200006`, books `100001`–`100015`, some of them already borrowed.
- **Reset:** `docker compose down -v && docker compose up`.

## Trying it out

- **Postman:** import [`postman_collection.json`](postman_collection.json) and run the **Library API** collection with the Runner, or click through it from the top. It logs in, creates a book and a reader, borrows, returns, anonymizes and removes, with a status test on every request.
- **Swagger UI:** run `POST /session`, click **Authorize**, paste the token.
- **Rate limit:** login allows 10 attempts in 3 minutes per IP. If you hit 429, run `docker compose exec web bin/rails runner 'Rails.cache.clear'`.

Reminders: the seeds contain a borrowing due in 3 days and one due today. Send them and check Mailpit:

```
docker compose exec web bin/rails runner 'SendReturnRemindersJob.perform_now'
```

Running it again sends nothing, because each reminder is sent once. To send them again:

```
docker compose exec web bin/rails runner '
  Borrowing.active.where(due_on: Date.current..(Date.current + 3))
    .update_all(due_soon_reminder_sent_at: nil, due_today_reminder_sent_at: nil)
  SendReturnRemindersJob.perform_now'
```

Retention: the seeds contain a borrowing returned about 2.5 years ago. After this the history of book `100006` shows it with `"reader": null`:

```
docker compose exec web bin/rails runner 'AnonymizeOldBorrowingsJob.perform_now'
```

## Endpoints

All endpoints except login need `Authorization: Bearer <token>`.

```
POST   /session                     { email_address, password } -> { token }
DELETE /session

GET    /books                       ?page ?limit ?serial_number
POST   /books                       { serial_number, title, author }
GET    /books/:id                   with the current borrowing
DELETE /books/:id

GET    /books/:book_id/borrowings   ?page ?limit   full history, newest first
POST   /books/:book_id/borrowing    { reader_card_number }   borrow
DELETE /books/:book_id/borrowing                             return

GET    /readers                     ?page ?limit ?card_number
POST   /readers                     { card_number, full_name, email }
GET    /readers/:id
DELETE /readers/:id                 anonymizes the reader
```

- **Errors:** `{ "error": "..." }`, or `{ "errors": { field: [...] } }` for validation errors (422). A conflict such as borrowing a borrowed book or returning an available one gives 409.
- **Pagination:** `page` and `limit` (default 25, max 100) go in the query string. The metadata comes back in the `link`, `current-page`, `page-limit`, `total-pages` and `total-count` headers.
- **Contract:** [`openapi/v1/openapi.yaml`](openapi/v1/openapi.yaml) (OpenAPI 3.0.3).

## Design decisions

- **Borrowing is a resource.** Borrowing and returning take different input, and every borrowing is a history entry. There is no status column that could disagree with the history.
- **Book details and history are separate.** `GET /books/:id` shows who has the book now. `GET /books/:book_id/borrowings` pages through the full history, which only grows.
- **The database enforces the rules.** A partial unique index allows one open borrowing per book, check constraints validate the six-digit numbers, and borrowing locks the book row.
- **Books are soft deleted and readers are anonymized,** so the history stays intact. Neither is possible while a book is out (409).
- **UUID v7 primary keys** can't be enumerated and still sort by creation time. UUID v7 embeds the record's creation timestamp. If IDs are exposed outside the system, keep in mind that creation time can be sensitive – UUID v4 or a separate public identifier may be a better fit.
- **Reminders.** A daily sweep at 08:00 library time enqueues one job per reminder. Each job locks the borrowing, checks again, sends and records it, so early returns and repeated runs are safe.
- **Infrastructure.** Solid Queue and Solid Cache keep jobs, recurring tasks and rate limit counters in PostgreSQL, so there's no Redis. Authentication is a 12 hour signed bearer token.

## Data protection

Borrowing history can reveal someone's health, beliefs or politics, so reader data is handled carefully:

- **Encryption at rest:** names and emails use Active Record Encryption. Email is deterministic so lookups and uniqueness still work. The app won't boot without the keys.
- **Minimization:** lists carry no email, and the book list carries no reader data at all.
- **Anonymization and retention:** anonymization is available on request. Every night borrowings returned over 2 years ago are detached from readers and expired sessions are deleted.
- **Logs:** personal data and mail content never reach the logs, and a spec checks it.
- **Errors:** responses never echo database errors.
- **Email subjects** don't include the book title.

## Configuration

`LIBRARY_TIME_ZONE` (default `Europe/Warsaw`) sets due dates and when recurring jobs run. `LIBRARY_EMAIL_FROM` (default `library@example.com`) sets the reminder sender. `ACTIVE_RECORD_ENCRYPTION_*` is required. The development keys are in `docker-compose.yml`.

## Tests

```
docker compose exec web bundle exec rspec
docker compose exec web bin/rubocop
docker compose exec web bin/brakeman --no-pager
```

CI runs these on every pull request, plus `bundler-audit` and the OpenAPI check.

## Limitations and next steps

- No roles or audit log of who accessed reader data.
- An idempotency key for borrow and return, so a retry after a timeout gets the original response instead of 409.
- Overdue reminders and loan extensions.
- Filtering books by status, title or author.
- Anonymizing readers inactive for years.
- Production notes: error trackers would need scrubbing, because database and SMTP errors can contain personal data. Short SMTP timeouts are needed, because reminders are sent under a row lock.

More in [docs/DESIGN.md](docs/DESIGN.md).
