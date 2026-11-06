class AddSadReactionType < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO reaction_types (key, label, emoji, enabled, created_at, updated_at)
      VALUES ('sad', 'Sad', '😢', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
  end

  def down
    execute "DELETE FROM reaction_types WHERE key = 'sad'"
  end
end
