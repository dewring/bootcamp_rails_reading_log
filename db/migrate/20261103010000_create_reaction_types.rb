class CreateReactionTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :reaction_types do |table|
      table.string :key, null: false
      table.string :label, null: false
      table.string :emoji, null: false
      table.boolean :enabled, null: false, default: true
      table.timestamps

      table.index :key, unique: true
      table.check_constraint "length(btrim(key)) > 0", name: "reaction_types_key_present"
      table.check_constraint "length(btrim(label)) > 0", name: "reaction_types_label_present"
      table.check_constraint "length(btrim(emoji)) > 0", name: "reaction_types_emoji_present"
    end

    reversible do |direction|
      direction.up do
        execute <<~SQL
          INSERT INTO reaction_types (key, label, emoji, enabled, created_at, updated_at)
          VALUES
            ('like', 'Like', '👍', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
            ('dislike', 'Dislike', '👎', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
            ('love', 'Love', '❤️', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
            ('laugh', 'Laugh', '😂', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
            ('wow', 'Wow', '😮', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        SQL
      end
    end
  end
end
