module CatalogEntry
  extend ActiveSupport::Concern

  included do
    scope :with_display_title, -> { where.not(title: [ nil, "" ]) }
    scope :missing_display_title, -> { where(title: [ nil, "" ]) }
  end
end
