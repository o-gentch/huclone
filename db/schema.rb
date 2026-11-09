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

ActiveRecord::Schema[8.1].define(version: 2026_11_09_120000) do
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
    t.integer "start_ms"
    t.text "text", null: false
    t.datetime "updated_at", null: false
    t.index ["content_id", "position"], name: "index_chunks_on_content_id_and_position", unique: true
    t.index ["content_id"], name: "index_chunks_on_content_id"
    t.index ["embedding"], name: "index_chunks_on_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
  end

  create_table "contents", force: :cascade do |t|
    t.text "body"
    t.text "context_text"
    t.datetime "created_at", null: false
    t.integer "end_ms"
    t.string "kind", default: "post", null: false
    t.text "raw_body"
    t.bigint "recording_id"
    t.jsonb "sources", default: [], null: false
    t.bigint "speaker_id"
    t.string "speaker_name"
    t.integer "start_ms"
    t.string "status", default: "pending", null: false
    t.text "summary"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index "to_tsvector('russian'::regconfig, COALESCE(body, ''::text))", name: "index_contents_on_body_tsv", using: :gin
    t.index ["kind"], name: "index_contents_on_kind"
    t.index ["recording_id", "speaker_id", "start_ms", "end_ms"], name: "index_contents_on_speech_range", unique: true, where: "((kind)::text = 'speech'::text)"
    t.index ["recording_id"], name: "index_contents_on_recording_id"
    t.index ["speaker_id"], name: "index_contents_on_speaker_id"
    t.index ["status"], name: "index_contents_on_status"
    t.index ["user_id"], name: "index_contents_on_user_id"
    t.check_constraint "kind::text = ANY (ARRAY['post'::character varying::text, 'speech'::character varying::text])", name: "contents_kind_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'done'::character varying::text, 'failed'::character varying::text])", name: "contents_status_check"
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
    t.jsonb "sources", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "created_at"], name: "index_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
  end

  create_table "persona_contents", force: :cascade do |t|
    t.bigint "content_id", null: false
    t.datetime "created_at", null: false
    t.boolean "exemplar_pinned", default: false, null: false
    t.boolean "included_in_map", default: false, null: false
    t.boolean "is_exemplar", default: false, null: false
    t.bigint "persona_id", null: false
    t.bigint "persona_recording_id"
    t.string "role", default: "voice", null: false
    t.datetime "updated_at", null: false
    t.index ["content_id"], name: "index_persona_contents_on_content_id"
    t.index ["persona_id", "content_id"], name: "index_persona_contents_on_persona_id_and_content_id", unique: true
    t.index ["persona_id", "role"], name: "index_persona_contents_on_persona_id_and_role"
    t.index ["persona_id"], name: "index_persona_contents_on_persona_id"
    t.index ["persona_recording_id"], name: "index_persona_contents_on_persona_recording_id"
    t.check_constraint "role::text = ANY (ARRAY['voice'::character varying::text, 'knowledge'::character varying::text])", name: "persona_contents_role_check"
  end

  create_table "persona_recordings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "persona_id", null: false
    t.bigint "recording_id", null: false
    t.bigint "speaker_ids", default: [], null: false, array: true
    t.string "status", default: "needs_speakers", null: false
    t.text "summary"
    t.datetime "updated_at", null: false
    t.index ["persona_id", "recording_id"], name: "index_persona_recordings_on_persona_id_and_recording_id", unique: true
    t.index ["persona_id"], name: "index_persona_recordings_on_persona_id"
    t.index ["recording_id"], name: "index_persona_recordings_on_recording_id"
    t.check_constraint "status::text = ANY (ARRAY['needs_speakers'::character varying::text, 'ready'::character varying::text])", name: "persona_recordings_status_check"
  end

  create_table "personas", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "linguistics", default: {}
    t.datetime "map_build_scheduled_at"
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
    t.string "provider"
    t.string "provider_job_id"
    t.string "source_checksum"
    t.string "status", default: "uploaded", null: false
    t.datetime "status_changed_at"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["status", "status_changed_at"], name: "index_recordings_on_status_and_status_changed_at"
    t.index ["user_id", "source_checksum"], name: "index_recordings_on_user_id_and_source_checksum", unique: true, where: "(source_checksum IS NOT NULL)"
    t.index ["user_id"], name: "index_recordings_on_user_id"
    t.check_constraint "status::text = ANY (ARRAY['uploaded'::character varying::text, 'extracting_audio'::character varying::text, 'transcribing'::character varying::text, 'transcribed'::character varying::text, 'failed'::character varying::text])", name: "recordings_status_check"
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
    t.string "label", null: false
    t.bigint "recording_id", null: false
    t.integer "speech_ms", default: 0, null: false
    t.string "speech_state", default: "idle", null: false
    t.datetime "updated_at", null: false
    t.integer "words_count", default: 0, null: false
    t.index ["recording_id", "label"], name: "index_speakers_on_recording_id_and_label", unique: true
    t.index ["recording_id"], name: "index_speakers_on_recording_id"
    t.check_constraint "speech_state::text = ANY (ARRAY['idle'::character varying::text, 'building'::character varying::text, 'ready'::character varying::text])", name: "speakers_speech_state_check"
  end

  create_table "topic_chunks", force: :cascade do |t|
    t.bigint "chunk_id", null: false
    t.bigint "topic_id", null: false
    t.index ["chunk_id"], name: "index_topic_chunks_on_chunk_id"
    t.index ["topic_id", "chunk_id"], name: "index_topic_chunks_on_topic_id_and_chunk_id", unique: true
    t.index ["topic_id"], name: "index_topic_chunks_on_topic_id"
  end

  create_table "topics", force: :cascade do |t|
    t.vector "centroid", limit: 1536
    t.datetime "created_at", null: false
    t.integer "depth", default: 0, null: false
    t.bigint "parent_id"
    t.bigint "persona_id", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.text "summary"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_topics_on_parent_id"
    t.index ["persona_id", "slug"], name: "index_topics_on_persona_id_and_slug", unique: true
    t.index ["persona_id"], name: "index_topics_on_persona_id"
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
    t.index "to_tsvector('russian'::regconfig, text)", name: "index_utterances_on_text_tsv", using: :gin
    t.index ["recording_id", "position"], name: "index_utterances_on_recording_id_and_position"
    t.index ["speaker_id"], name: "index_utterances_on_speaker_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "chunks", "contents"
  add_foreign_key "contents", "recordings", on_delete: :cascade
  add_foreign_key "contents", "speakers", on_delete: :nullify
  add_foreign_key "contents", "users", on_delete: :cascade
  add_foreign_key "conversations", "personas"
  add_foreign_key "messages", "conversations"
  add_foreign_key "persona_contents", "contents", on_delete: :cascade
  add_foreign_key "persona_contents", "persona_recordings", on_delete: :cascade
  add_foreign_key "persona_contents", "personas", on_delete: :cascade
  add_foreign_key "persona_recordings", "personas", on_delete: :cascade
  add_foreign_key "persona_recordings", "recordings", on_delete: :cascade
  add_foreign_key "personas", "users"
  add_foreign_key "recordings", "users", on_delete: :cascade
  add_foreign_key "sessions", "users"
  add_foreign_key "speakers", "recordings", on_delete: :cascade
  add_foreign_key "topic_chunks", "chunks", on_delete: :cascade
  add_foreign_key "topic_chunks", "topics", on_delete: :cascade
  add_foreign_key "topics", "personas", on_delete: :cascade
  add_foreign_key "topics", "topics", column: "parent_id", on_delete: :cascade
  add_foreign_key "usage_events", "recordings", on_delete: :nullify
  add_foreign_key "usage_events", "users", on_delete: :cascade
  add_foreign_key "utterances", "recordings", on_delete: :cascade
  add_foreign_key "utterances", "speakers", on_delete: :cascade
end
