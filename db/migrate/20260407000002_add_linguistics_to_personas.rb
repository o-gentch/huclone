class AddLinguisticsToPersonas < ActiveRecord::Migration[8.1]
  def change
    add_column :personas, :linguistics, :jsonb, default: {}
    add_index :personas, :linguistics, using: :gin
  end
end
