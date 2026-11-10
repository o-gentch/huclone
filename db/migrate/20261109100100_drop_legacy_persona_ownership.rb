# Шаг 6 плана переноса: убираем старые колонки после проверки данных.
class DropLegacyPersonaOwnership < ActiveRecord::Migration[8.1]
  def up
    remove_reference :recordings, :persona, foreign_key: true, index: true
    remove_reference :contents, :persona, foreign_key: true, index: true
    remove_column :contents, :is_exemplar
    remove_column :contents, :included_in_map
    remove_column :recordings, :summary
    remove_column :speakers, :is_persona
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Восстановите базу из копии"
  end
end
