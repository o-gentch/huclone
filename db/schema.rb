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

ActiveRecord::Schema[8.1].define(version: 2026_04_07_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "chunks", force: :cascade do |t|
    t.bigint "content_id", null: false
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 1536
    t.integer "position", null: false
    t.text "text", null: false
    t.datetime "updated_at", null: false
    t.index ["content_id", "position"], name: "index_chunks_on_content_id_and_position"
    t.index ["content_id"], name: "index_chunks_on_content_id"
  end

  create_table "contents", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
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

  add_foreign_key "chunks", "contents"
  add_foreign_key "contents", "personas"
  add_foreign_key "conversations", "personas"
  add_foreign_key "messages", "conversations"
end
