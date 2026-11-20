# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_20_200522) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "books", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "serial_number", null: false
    t.string "title", null: false
    t.string "author", null: false
    t.datetime "discarded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["discarded_at"], name: "index_books_on_discarded_at"
    t.index ["serial_number"], name: "index_books_on_serial_number", unique: true
    t.check_constraint "serial_number::text ~ '^[0-9]{6}$'::text", name: "books_serial_number_format"
  end

  create_table "borrowings", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "book_id", null: false
    t.uuid "reader_id"
    t.datetime "borrowed_at", null: false
    t.date "due_on", null: false
    t.datetime "returned_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_borrowings_on_book_id"
    t.index ["book_id"], name: "index_borrowings_on_book_id_active", unique: true, where: "(returned_at IS NULL)"
    t.index ["reader_id"], name: "index_borrowings_on_reader_id"
    t.check_constraint "returned_at IS NULL OR returned_at >= borrowed_at", name: "borrowings_returned_after_borrowed"
  end

  create_table "readers", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "card_number"
    t.string "full_name"
    t.string "email"
    t.datetime "anonymized_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["card_number"], name: "index_readers_on_card_number", unique: true
    t.index ["email"], name: "index_readers_on_email", unique: true
    t.check_constraint "anonymized_at IS NOT NULL OR card_number IS NOT NULL AND full_name IS NOT NULL AND email IS NOT NULL", name: "readers_identity_present_unless_anonymized"
    t.check_constraint "card_number::text ~ '^[0-9]{6}$'::text", name: "readers_card_number_format"
  end

  create_table "sessions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_sessions_on_created_at"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "borrowings", "books", on_delete: :restrict
  add_foreign_key "borrowings", "readers", on_delete: :restrict
  add_foreign_key "sessions", "users", on_delete: :cascade
end
