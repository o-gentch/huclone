class CreateRecordings < ActiveRecord::Migration[8.1]
  STATUSES = %w[uploaded extracting_audio transcribing awaiting_speaker_confirmation confirmed failed].freeze

  def change
    create_table :recordings do |t|
      t.references :persona, null: false, foreign_key: { on_delete: :cascade }
      t.string :title
      t.string :status, null: false, default: "uploaded"
      t.datetime :status_changed_at
      t.integer :duration_ms
      t.string :language, null: false, default: "ru"
      t.text :error_message
      t.string :provider
      t.string :provider_job_id
      t.string :source_checksum
      t.integer :expected_speakers
      t.timestamps
      t.index [ :persona_id, :source_checksum ]
      t.index [ :status, :status_changed_at ]
      t.check_constraint "status IN (#{STATUSES.map { |s| "'#{s}'" }.join(', ')})", name: "recordings_status_check"
    end

    create_table :speakers do |t|
      t.references :recording, null: false, foreign_key: { on_delete: :cascade }
      t.string :label, null: false
      t.string :display_name
      t.boolean :is_persona, null: false, default: false
      t.integer :speech_ms, null: false, default: 0
      t.integer :words_count, null: false, default: 0
      t.timestamps
      t.index [ :recording_id, :label ], unique: true
    end

    create_table :utterances do |t|
      t.references :recording, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :speaker, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.integer :start_ms, null: false
      t.integer :end_ms, null: false
      t.text :text, null: false
      t.float :confidence
      t.timestamps
      t.index [ :recording_id, :position ]
    end

    create_table :usage_events do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :recording, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false
      t.float :quantity, null: false, default: 0
      t.string :unit, null: false, default: "minutes"
      t.float :cost_usd, null: false, default: 0
      t.timestamps
      t.index [ :user_id, :kind, :created_at ]
    end
  end
end
