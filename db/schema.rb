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

ActiveRecord::Schema[8.1].define(version: 2026_11_07_141000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

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

  create_table "chunks", force: :cascade do |t|
    t.bigint "content_id", null: false
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 1536
    t.integer "position", null: false
    t.text "text", null: false
    t.datetime "updated_at", null: false
    t.index ["content_id", "position"], name: "index_chunks_on_content_id_and_position", unique: true
    t.index ["content_id"], name: "index_chunks_on_content_id"
    t.index ["embedding"], name: "index_chunks_on_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
  end

  create_table "contents", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.boolean "included_in_map", default: false, null: false
    t.boolean "is_exemplar", default: false, null: false
    t.bigint "persona_id", null: false
    t.jsonb "sources", default: [], null: false
    t.string "status", default: "pending", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["is_exemplar"], name: "index_contents_on_is_exemplar"
    t.index ["persona_id"], name: "index_contents_on_persona_id"
    t.index ["status"], name: "index_contents_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'processing'::character varying, 'done'::character varying, 'failed'::character varying]::text[])", name: "contents_status_check"
  end

  create_table "conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "persona_id", null: false
    t.datetime "updated_at", null: false
    t.index ["persona_id"], name: "index_conversations_on_persona_id"
  end

  create_table "messages", force: :cascade do |t|
    t.text "body", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "mode", default: "strict", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "created_at"], name: "index_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
  end

  create_table "personas", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "linguistics", default: {}
    t.string "name", null: false
    t.jsonb "personality_map", default: {}
    t.datetime "personality_map_built_at"
    t.text "system_prompt"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["linguistics"], name: "index_personas_on_linguistics", using: :gin
    t.index ["user_id"], name: "index_personas_on_user_id"
  end

  create_table "recordings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.integer "expected_speakers"
    t.string "language", default: "ru", null: false
    t.bigint "persona_id", null: false
    t.string "provider"
    t.string "provider_job_id"
    t.string "source_checksum"
    t.string "status", default: "uploaded", null: false
    t.datetime "status_changed_at"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["persona_id", "source_checksum"], name: "index_recordings_on_persona_id_and_source_checksum"
    t.index ["persona_id"], name: "index_recordings_on_persona_id"
    t.index ["status", "status_changed_at"], name: "index_recordings_on_status_and_status_changed_at"
    t.check_constraint "status::text = ANY (ARRAY['uploaded'::character varying, 'extracting_audio'::character varying, 'transcribing'::character varying, 'awaiting_speaker_confirmation'::character varying, 'confirmed'::character varying, 'failed'::character varying]::text[])", name: "recordings_status_check"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "speakers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name"
    t.boolean "is_persona", default: false, null: false
    t.string "label", null: false
    t.bigint "recording_id", null: false
    t.integer "speech_ms", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "words_count", default: 0, null: false
    t.index ["recording_id", "label"], name: "index_speakers_on_recording_id_and_label", unique: true
    t.index ["recording_id"], name: "index_speakers_on_recording_id"
  end

  create_table "usage_events", force: :cascade do |t|
    t.float "cost_usd", default: 0.0, null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.float "quantity", default: 0.0, null: false
    t.bigint "recording_id"
    t.string "unit", default: "minutes", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["recording_id"], name: "index_usage_events_on_recording_id"
    t.index ["user_id", "kind", "created_at"], name: "index_usage_events_on_user_id_and_kind_and_created_at"
    t.index ["user_id"], name: "index_usage_events_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "utterances", force: :cascade do |t|
    t.float "confidence"
    t.datetime "created_at", null: false
    t.integer "end_ms", null: false
    t.integer "position", null: false
    t.bigint "recording_id", null: false
    t.bigint "speaker_id", null: false
    t.integer "start_ms", null: false
    t.text "text", null: false
    t.datetime "updated_at", null: false
    t.index ["recording_id", "position"], name: "index_utterances_on_recording_id_and_position"
    t.index ["speaker_id"], name: "index_utterances_on_speaker_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "chunks", "contents"
  add_foreign_key "contents", "personas"
  add_foreign_key "conversations", "personas"
  add_foreign_key "messages", "conversations"
  add_foreign_key "personas", "users"
  add_foreign_key "recordings", "personas", on_delete: :cascade
  add_foreign_key "sessions", "users"
  add_foreign_key "speakers", "recordings", on_delete: :cascade
  add_foreign_key "usage_events", "recordings", on_delete: :nullify
  add_foreign_key "usage_events", "users", on_delete: :cascade
  add_foreign_key "utterances", "recordings", on_delete: :cascade
  add_foreign_key "utterances", "speakers", on_delete: :cascade
end
