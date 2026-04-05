class CreatePersonas < ActiveRecord::Migration[8.1]
  def change
    create_table :personas do |t|
      t.bigint :user_id
      t.string :name, null: false
      t.text :system_prompt
      t.jsonb :personality_map, default: {}
      t.datetime :personality_map_built_at

      t.timestamps
    end

    add_index :personas, :user_id
  end
end
