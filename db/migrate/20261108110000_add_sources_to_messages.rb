class AddSourcesToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :sources, :jsonb, null: false, default: []
  end
end
