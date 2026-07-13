class CreateUserChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :user_challenges do |t|
      t.references :user,      null: false, foreign_key: true
      t.references :challenge, null: false, foreign_key: true
      t.string  :status,   null: false, default: "active"
      t.integer :progress, null: false, default: 0

      t.timestamps
    end

    add_index :user_challenges, [ :user_id, :challenge_id ], unique: true
  end
end
