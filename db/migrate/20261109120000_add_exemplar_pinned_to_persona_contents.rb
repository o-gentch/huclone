class AddExemplarPinnedToPersonaContents < ActiveRecord::Migration[8.1]
  def change
    add_column :persona_contents, :exemplar_pinned, :boolean, null: false, default: false
  end
end
