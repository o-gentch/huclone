class AddIncludedInMapToContents < ActiveRecord::Migration[8.1]
  def up
    add_column :contents, :included_in_map, :boolean, default: false, null: false

    Content
      .joins(:persona)
      .where(status: "done")
      .where.not(personas: { personality_map_built_at: nil })
      .update_all(included_in_map: true)
  end

  def down
    remove_column :contents, :included_in_map
  end
end
