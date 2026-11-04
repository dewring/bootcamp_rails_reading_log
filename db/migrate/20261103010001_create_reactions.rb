class CreateReactions < ActiveRecord::Migration[8.1]
  def change
    create_reaction_table(:reactions, :book)
    create_reaction_table(:review_reactions, :review)
    create_reaction_table(:club_message_reactions, :club_message)
  end

  private

  def create_reaction_table(name, target)
    create_table name do |table|
      table.references :user, null: false, foreign_key: true, index: false
      table.references target, null: false, foreign_key: true
      table.string :kind, null: false
      table.timestamps

      table.index [ :user_id, "#{target}_id" ], unique: true
      table.index :kind
    end

    add_foreign_key name, :reaction_types, column: :kind, primary_key: :key,
      on_delete: :restrict, on_update: :restrict
  end
end
