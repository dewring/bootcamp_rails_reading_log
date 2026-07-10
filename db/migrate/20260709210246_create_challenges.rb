class CreateChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :challenges do |t|
      t.string   :title,      null: false
      t.string   :goal_type,  null: false
      t.integer  :goal_value, null: false
      t.datetime :starts_at,  null: false
      t.datetime :ends_at,    null: false
      t.boolean  :active,     null: false, default: true

      t.timestamps
    end
  end
end
