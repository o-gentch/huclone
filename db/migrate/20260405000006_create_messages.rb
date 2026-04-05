class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :role, null: false
      t.text :body, null: false
      t.string :mode, null: false, default: "strict"

      t.timestamps
    end

    add_index :messages, [ :conversation_id, :created_at ]
  end
end
