class RefactorContentsSource < ActiveRecord::Migration[8.1]
  def change
    rename_column :contents, :source, :body
    change_column :contents, :body, :text

    add_column :contents, :sources, :jsonb, default: [], null: false
  end
end
