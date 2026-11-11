class CreateDiscoveryExposures < ActiveRecord::Migration[8.1]
  def change
    create_table :discovery_exposures do |table|
      table.references :user, null: false, foreign_key: true, index: false
      table.string :experiment_key, null: false
      table.string :variant, null: false
      # Historical snapshot: array members cannot have ordinary Book foreign keys.
      table.bigint :shown_book_ids, array: true, null: false
      table.datetime :exposed_at, null: false
      table.datetime :converted_at
      table.timestamps

      table.index [ :user_id, :experiment_key ], unique: true
      table.index [ :experiment_key, :variant ]
      table.check_constraint "length(btrim(experiment_key)) > 0", name: "discovery_exposures_experiment_present"
      table.check_constraint "variant IN ('control', 'treatment')", name: "discovery_exposures_variant_allowed"
      table.check_constraint "cardinality(shown_book_ids) > 0", name: "discovery_exposures_books_present"
      table.check_constraint "converted_at IS NULL OR (converted_at >= exposed_at AND converted_at < exposed_at + interval '24 hours')",
        name: "discovery_exposures_conversion_window"
    end
  end
end
