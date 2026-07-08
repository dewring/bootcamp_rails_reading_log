class CreateReadingMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :reading_metrics do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.integer :pages_today, default: 0
      t.integer :pages_this_week, default: 0
      t.integer :books_in_progress, default: 0
      t.integer :books_finished, default: 0
      t.integer :current_streak, default: 0
      t.datetime :calculated_at

      t.timestamps
    end
  end
end
