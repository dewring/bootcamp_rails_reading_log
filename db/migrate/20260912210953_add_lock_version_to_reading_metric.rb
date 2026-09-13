class AddLockVersionToReadingMetric < ActiveRecord::Migration[8.1]
  def change
    add_column :reading_metrics, :lock_version, :integer, default: 0, null: false
  end
end
