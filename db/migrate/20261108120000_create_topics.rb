class CreateTopics < ActiveRecord::Migration[8.1]
  def change
    create_table :topics do |t|
      t.references :persona, null: false, foreign_key: { on_delete: :cascade }
      t.references :parent, foreign_key: { to_table: :topics, on_delete: :cascade }
      t.string :title, null: false
      t.text :summary
      t.integer :position, null: false, default: 0
      t.integer :depth, null: false, default: 0
      t.string :slug, null: false # стабильный идентификатор для ссылок и экспорта
      t.vector :centroid, limit: 1536
      t.timestamps
      t.index [ :persona_id, :slug ], unique: true
    end

    create_table :topic_chunks do |t|
      t.references :topic, null: false, foreign_key: { on_delete: :cascade }
      t.references :chunk, null: false, foreign_key: { on_delete: :cascade }
      t.index [ :topic_id, :chunk_id ], unique: true
    end
  end
end
