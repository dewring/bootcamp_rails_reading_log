class AddMissingAdminReportIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Reaction reports filter by the time a reaction was last changed.
    add_index :reactions, :updated_at, algorithm: :concurrently

    # The health panel reads the oldest calculation time and counts saved times.
    add_index :reading_metrics, :calculated_at, algorithm: :concurrently

    # Match the completeness query's expression; the plain ol_work_key index
    # cannot support a lookup on BTRIM(ol_work_key).
    add_index :books, "BTRIM(ol_work_key)",
      name: "index_books_on_trimmed_ol_work_key",
      algorithm: :concurrently
  end
end
