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

ActiveRecord::Schema[8.1].define(version: 2026_07_01_040402) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "book_editions", force: :cascade do |t|
    t.integer "book_id", null: false
    t.datetime "created_at", null: false
    t.string "format"
    t.string "isbn"
    t.string "language"
    t.string "ol_edition_key", null: false
    t.integer "page_count"
    t.string "publish_year"
    t.string "publisher"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_book_editions_on_book_id"
    t.index ["isbn"], name: "index_book_editions_on_isbn"
    t.index ["ol_edition_key"], name: "index_book_editions_on_ol_edition_key", unique: true
  end

  create_table "book_genres", force: :cascade do |t|
    t.integer "book_id", null: false
    t.datetime "created_at", null: false
    t.integer "genre_id", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_book_genres_on_book_id"
    t.index ["genre_id"], name: "index_book_genres_on_genre_id"
  end

  create_table "books", force: :cascade do |t|
    t.string "author", default: "", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "ol_work_key"
    t.text "subjects"
    t.string "title", default: "", null: false
    t.integer "total_pages"
    t.datetime "updated_at", null: false
    t.index ["ol_work_key"], name: "index_books_on_ol_work_key", unique: true
  end

  create_table "genres", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "reading_sessions", force: :cascade do |t|
    t.integer "book_edition_id"
    t.integer "book_id", null: false
    t.datetime "created_at", null: false
    t.text "notes"
    t.integer "pages_read", null: false
    t.date "read_on", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["book_edition_id"], name: "index_reading_sessions_on_book_edition_id"
    t.index ["book_id"], name: "index_reading_sessions_on_book_id"
    t.index ["user_id"], name: "index_reading_sessions_on_user_id"
  end

  create_table "reviews", force: :cascade do |t|
    t.text "body"
    t.integer "book_id", null: false
    t.datetime "created_at", null: false
    t.integer "rating", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["book_id"], name: "index_reviews_on_book_id"
    t.index ["user_id"], name: "index_reviews_on_user_id"
  end

  create_table "user_books", force: :cascade do |t|
    t.integer "book_id", null: false
    t.datetime "created_at", null: false
    t.string "status", default: "want_to_read", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["book_id"], name: "index_user_books_on_book_id"
    t.index ["user_id", "book_id"], name: "index_user_books_on_user_id_and_book_id", unique: true
    t.index ["user_id"], name: "index_user_books_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name", default: "", null: false
    t.string "last_name", default: "", null: false
    t.string "nickname", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role", default: "user", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["nickname"], name: "index_users_on_nickname", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "book_editions", "books"
  add_foreign_key "book_genres", "books"
  add_foreign_key "book_genres", "genres"
  add_foreign_key "reading_sessions", "book_editions"
  add_foreign_key "reading_sessions", "books"
  add_foreign_key "reading_sessions", "users"
  add_foreign_key "reviews", "books"
  add_foreign_key "reviews", "users"
  add_foreign_key "user_books", "books"
  add_foreign_key "user_books", "users"
end
