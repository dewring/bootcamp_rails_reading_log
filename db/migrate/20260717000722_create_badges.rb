class CreateBadges < ActiveRecord::Migration[8.1]
  def change
    create_table :badges do |t|
      # badge_type must be one of the 5 fixed types (first_session, week_streak,
      # bookworm, challenge_complete, page_turner) - enforced in the model via enum
      t.string :badge_type,  null: false
      t.string :name,        null: false
      t.text   :description, null: false

      t.timestamps
    end

    # real guard against duplicate badge types / names, not just a Rails validation
    add_index :badges, :badge_type, unique: true
    add_index :badges, :name,       unique: true
  end
end
