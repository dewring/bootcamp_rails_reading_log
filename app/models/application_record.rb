class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  scope :search_strict, ->(**search_params) do
    return all if search_params.blank?

    # Builds Arel conditions using SQLite's standard case-insensitive LIKE
    conditions = search_params.map do |column, value|
      arel_table[column].matches("%#{value}%")
    end

    where(conditions.reduce(:and))
  end

  scope :search, ->(**search_params) do
    return all if search_params.blank?

    conditions = search_params.map do |column, value|
      arel_table[column].matches("%#{value}%")
    end

    where(conditions.reduce(:or))
  end
end
