class AddFailedStatusToContents < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE contents
        DROP CONSTRAINT IF EXISTS contents_status_check;

      ALTER TABLE contents
        ADD CONSTRAINT contents_status_check
        CHECK (status IN ('pending', 'processing', 'done', 'failed'));
    SQL
  end

  def down
    execute <<~SQL
      UPDATE contents SET status = 'pending' WHERE status = 'failed';

      ALTER TABLE contents
        DROP CONSTRAINT IF EXISTS contents_status_check;

      ALTER TABLE contents
        ADD CONSTRAINT contents_status_check
        CHECK (status IN ('pending', 'processing', 'done'));
    SQL
  end
end
