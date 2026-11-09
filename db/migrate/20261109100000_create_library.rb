require_relative "../support/library_backfill"

# Библиотека: материалы принадлежат пользователю, к Digital Double подключаются связями (docs/DD_PLAN.md §2–3).
# Старые колонки (persona_id и т.д.) остаются до отдельной миграции после проверки данных.
class CreateLibrary < ActiveRecord::Migration[8.1]
  RECORDING_STATUSES = %w[uploaded extracting_audio transcribing transcribed failed].freeze

  def up
    add_reference :recordings, :user, foreign_key: { on_delete: :cascade }
    add_reference :contents, :user, foreign_key: { on_delete: :cascade }
    add_reference :contents, :speaker, foreign_key: { on_delete: :nullify }
    add_column :speakers, :speech_state, :string, null: false, default: "idle"
    add_check_constraint :speakers, "speech_state IN ('idle', 'building', 'ready')", name: "speakers_speech_state_check"

    change_column_null :recordings, :persona_id, true
    change_column_null :contents, :persona_id, true

    create_table :persona_recordings do |t|
      t.references :persona, null: false, foreign_key: { on_delete: :cascade }
      t.references :recording, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :speaker_ids, array: true, null: false, default: []
      t.string :status, null: false, default: "needs_speakers"
      t.text :summary
      t.timestamps
      t.index %i[persona_id recording_id], unique: true
      t.check_constraint "status IN ('needs_speakers', 'ready')", name: "persona_recordings_status_check"
    end

    create_table :persona_contents do |t|
      t.references :persona, null: false, foreign_key: { on_delete: :cascade }
      t.references :content, null: false, foreign_key: { on_delete: :cascade }
      t.references :persona_recording, foreign_key: { on_delete: :cascade }
      t.string :role, null: false, default: "voice"
      t.boolean :is_exemplar, null: false, default: false
      t.boolean :included_in_map, null: false, default: false
      t.timestamps
      t.index %i[persona_id content_id], unique: true
      t.index %i[persona_id role]
      t.check_constraint "role IN ('voice', 'knowledge')", name: "persona_contents_role_check"
    end

    remove_check_constraint :recordings, name: "recordings_status_check"
    @result = LibraryBackfill.run!(connection)
    add_check_constraint :recordings, "status IN (#{RECORDING_STATUSES.map { |s| "'#{s}'" }.join(', ')})", name: "recordings_status_check"

    change_column_null :recordings, :user_id, false
    change_column_null :contents, :user_id, false
    add_index :recordings, %i[user_id source_checksum], unique: true, where: "source_checksum IS NOT NULL",
              name: "index_recordings_on_user_id_and_source_checksum"

    remove_index :contents, name: "index_contents_on_speech_range"
    add_index :contents, %i[recording_id speaker_id start_ms end_ms], unique: true, where: "kind = 'speech'",
              name: "index_contents_on_speech_range"

    report_duplicates(@result)
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Перенос библиотеки необратим: восстановите базу из копии"
  end

  private

  def report_duplicates(groups)
    return if groups.blank?

    say "Дубли файлов: #{groups.size} групп(ы)"
    groups.each { |g| say "оставлена ##{g[:keeper]}, слито #{g[:merge].inspect}, не склеено (checksum очищен) #{g[:skip].inspect}", true }
  end
end
