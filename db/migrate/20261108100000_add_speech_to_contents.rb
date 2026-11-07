class AddSpeechToContents < ActiveRecord::Migration[8.1]
  def change
    change_table :contents do |t|
      t.string :kind, null: false, default: "post"
      t.references :recording, foreign_key: { on_delete: :cascade }
      t.integer :start_ms
      t.integer :end_ms
      t.text :context_text   # вопрос другого спикера
      t.string :speaker_name # кто задал вопрос
      t.text :raw_body       # текст ответа до LLM-очистки (для карты личности)
      t.text :summary        # краткое резюме (для дерева тем)
    end
    add_check_constraint :contents, "kind IN ('post', 'speech')", name: "contents_kind_check"
    add_index :contents, :kind
    add_index :contents, [ :recording_id, :start_ms, :end_ms ], unique: true,
              where: "kind = 'speech'", name: "index_contents_on_speech_range"

    add_column :chunks, :start_ms, :integer
    add_column :recordings, :summary, :text
    add_column :personas, :map_build_scheduled_at, :datetime
  end
end
