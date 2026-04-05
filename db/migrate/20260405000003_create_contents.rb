class CreateContents < ActiveRecord::Migration[8.1]
  def change
    create_table :contents do |t|
      t.references :persona, null: false, foreign_key: true
      t.string :title
      t.string :source
      t.string :status, null: false, default: "pending"
      t.boolean :is_exemplar, null: false, default: false

      t.timestamps
    end

    add_index :contents, :status
    add_index :contents, :is_exemplar
  end
end
