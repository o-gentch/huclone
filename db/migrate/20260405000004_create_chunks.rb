class CreateChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :chunks do |t|
      t.references :content, null: false, foreign_key: true
      t.text :text, null: false
      t.vector :embedding, limit: 1536
      t.integer :position, null: false

      t.timestamps
    end

    add_index :chunks, [ :content_id, :position ]
  end
end
