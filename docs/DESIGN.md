# Library API – design notes

The full reasoning behind the API, the decisions and the trade-offs. The [README](../README.md) has the short version and how to run it.

## Endpoints

All endpoints except login need `Authorization: Bearer <token>`.

```
POST   /session                     { email_address, password } -> { token }
DELETE /session

GET    /books                       ?page ?limit ?serial_number
POST   /books                       { serial_number, title, author }
GET    /books/:id                   with the current borrowing
DELETE /books/:id

GET    /books/:book_id/borrowings   ?page ?limit   full borrowing history, newest first

POST   /books/:book_id/borrowing    { reader_card_number }   borrow
DELETE /books/:book_id/borrowing                             return

GET    /readers                     ?page ?limit ?card_number
POST   /readers                     { card_number, full_name, email }
GET    /readers/:id
DELETE /readers/:id                 anonymizes the reader
```

Errors are JSON: `{ "error": "..." }`, or `{ "errors": { field: [...] } }` for validation. Codes: 400 missing params, 401, 404, 409 for conflicts such as borrowing a borrowed book, 422 validation, 429 rate limit.

Lists (books, readers, a book's borrowing history) are paginated. `page` and `limit` (default 25, max 100) go in the query string, and the metadata comes back in response headers: `link` (RFC 8288 first/prev/next/last), `current-page`, `page-limit`, `total-pages`, `total-count`. The body stays a plain array.

The full contract is in `openapi/v1/openapi.yaml` (OpenAPI 3.0.3). It is generated from the request specs, which validate the real responses against it, and CI fails if the committed file differs from what the specs generate.

## Design decisions

- **Borrowing is a resource.** "Update the book status: borrowed / available" is `POST` / `DELETE /books/:book_id/borrowing`. Borrowing and returning take different input (a reader card vs nothing), and every borrowing is also a history entry. A book's status is derived from whether it has an open borrowing, so there is no status column that could disagree with the history.
- **Book details and borrowing history are separate.** `GET /books/:id` returns the book and who has it now, `GET /books/:book_id/borrowings` returns the full history (borrow date, return date, reader) paginated. Together they cover "a specific book together with the full history of its borrowings". A copy's history only grows, so embedding it in the book response would make that response grow without bound.
- **One open borrowing per book is enforced by the database.** A partial unique index on `borrowings(book_id) WHERE returned_at IS NULL` guarantees it. Borrowing also locks the book row, so two librarians can't lend the same copy at the same moment (a threaded spec covers it). An accidental double request never creates a second borrowing: the second one gets 409 "book is already borrowed", and a second return gets 409 "book is not borrowed". A client that retried after a timeout can check the book's status and history to confirm its first request went through.
- **Loan period.** 30 days. The due date is computed in the library time zone.
- **Books are soft deleted** with `discard`, so borrowing history keeps pointing at the right title. A borrowed book can't be removed (409). Serial numbers stay unique across removed books because a number identifies one physical copy.
- **Six digit numbers** are strings validated in the model and by a database check constraint, so leading zeros are kept.
- **Readers are anonymized, not deleted.** `DELETE /readers/:id` clears their personal data and keeps their borrowings for statistics. A reader with a borrowed book can't be anonymized (409).
- **UUID v7 primary keys** come from `uuidv7()` in PostgreSQL 18. They can't be enumerated like `/readers/1`, `/readers/2`, and they still sort by creation time, which keeps pagination simple and indexes compact. UUID v7 embeds the record's creation timestamp. If IDs are exposed outside the system, keep in mind that creation time can be sensitive – UUID v4 or a separate public identifier may be a better fit.
- **Authentication** is a bearer token: a signed session id valid for 12 hours. No token is stored in the database (it is the session id signed with the app's secret) and logging out revokes it immediately. "Users" are library staff. Readers don't log in. There are no roles.
- **Reminders run as a daily sweep plus one job per reminder** rather than jobs scheduled at borrow time:
  - At 08:00 library time `SendReturnRemindersJob` finds borrowings due within 3 days and borrowings due today, then enqueues a `ReturnReminderJob` for each.
  - That job locks the borrowing, checks again that it is still open, the reader isn't anonymized and the reminder wasn't sent, then sends the email and records when it was sent.
  - Returning a book early or changing the rules never leaves stale jobs behind, and running the sweep twice never sends a duplicate.
  - The 3 day reminder catches up after a missed run, which is why its subject says "due soon". The due-today reminder doesn't, because it would no longer be true.
  - Delivery is at-least-once: if the database write fails after the mail went out, a retry can send it again.
  - The history of sent reminders lives on the borrowing itself: `due_soon_reminder_sent_at` and `due_today_reminder_sent_at`. The history of job runs is kept by Solid Queue: finished jobs have `finished_at`, and failures go to `solid_queue_failed_executions` with the error and can be retried.
- **Solid Queue** keeps jobs and recurring tasks in PostgreSQL, so there's no Redis to run. Jobs use Active Job, so moving to Sidekiq would mean changing the adapter, not the job code.
- **Rate limiting** uses Rails' `rate_limit` with counters in Solid Cache, so the limit holds across processes and restarts. Login is limited per IP and per email address.

## Data protection

Borrowing history is sensitive personal data: what someone reads can reveal their health, beliefs or politics. That shaped several decisions:

- **Encryption at rest:** reader names and emails use Active Record Encryption. Email is deterministic and normalized before encryption, so lookups and uniqueness still work. Keys come from the environment and the app refuses to boot without them. The keys in `docker-compose.yml` are for development only.
- **Data minimization:**
  - The book list carries no reader data.
  - The reader list has no email.
  - The email appears only when creating or fetching one reader and in a book's current borrowing and borrowing history.
  - The borrow/return responses carry the card number and name, not the email.
- **Anonymization:** a reader can be anonymized on request. History entries then show `"reader": null`.
- **Retention:** every night borrowings returned more than 2 years ago are detached from their reader, and expired sessions (IP address, user agent) are deleted. Both jobs are idempotent and only log counts.
- **Logs:**
  - Personal data is filtered from request parameters and SQL binds, and a spec captures the logs and checks for it.
  - Mail content is never logged, only which reminder was sent for which borrowing id.
  - Query log tags are off in development: they disable prepared statements, which made SQL values appear inline and unfiltered.
- **Responses never echo database error messages,** because PostgreSQL includes the offending values in them.
- **Email subjects are generic** and don't include the book title, since they show up on lock screens.

## Configuration

| Variable | Default | |
|---|---|---|
| `LIBRARY_TIME_ZONE` | `Europe/Warsaw` | due dates, "today" and the time recurring jobs run |
| `LIBRARY_EMAIL_FROM` | `library@example.com` | sender of reminder emails |
| `ACTIVE_RECORD_ENCRYPTION_*` | — | required at boot outside tests |
| `SMTP_ADDRESS`, `SMTP_PORT` | Mailpit in development | |

Recurring jobs in library time: reminders at 08:00, retention at 03:00, session cleanup at 03:15. 3:00 avoids the hour skipped or repeated on DST changes.

## Tests

```
docker compose exec web bundle exec rspec
docker compose exec web bin/rubocop
docker compose exec web bin/brakeman --no-pager
```

CI runs the same on every pull request against PostgreSQL 18, plus `bundler-audit`.

## Limitations

- No roles: every staff user can do everything, and there is no audit log of who accessed which reader.
- The rate limit is per IP and per email address. The per-email limit lets someone who knows a librarian's email lock them out of logging in for a few minutes.
- PostgreSQL error messages, which are never returned to clients, contain plaintext values such as card numbers. An error tracker would need scrubbing. The same goes for SMTP rejections, which may echo the recipient address into job error logs.
- SQL debug logging stays clean only with prepared statements. Turning them off (e.g. PgBouncer in transaction mode) at debug level would log values inline.
- Reminder emails are sent while the borrowing row is locked, so production needs short SMTP timeouts (development uses 5 seconds). Production SMTP settings are left to the deployment.
- Readers with no activity are never anonymized automatically.
- Solid Queue doesn't replay missed recurring runs. Retention catches up on the next run since it is cumulative, and so does the 3 day reminder.
- The seeded "due in 3 days / due today" borrowings are relative to when the seeds ran. Reset with `docker compose down -v`.

## Ideas

- Roles and an audit log of access to reader data.
- Overdue reminders, and extending a loan (`PATCH /books/:book_id/borrowing`). Overdue reminders can repeat, so they would move the reminder history from two columns into a `reminder_deliveries` table (borrowing, kind, sent at).
- Mission Control – Jobs, behind authentication, to browse finished and failed jobs.
- An `Idempotency-Key` header for borrowing and returning, so a client retrying after a timeout gets the original response instead of 409.
- Filtering the book list by status, title or author. Genres and borrowing statistics, which retention already keeps anonymous.
- Automatic anonymization of readers inactive for N years.
- Sidekiq once job volume needs it, which only changes the Active Job adapter.
