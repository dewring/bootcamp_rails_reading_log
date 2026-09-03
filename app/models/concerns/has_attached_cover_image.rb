module HasAttachedCoverImage
  extend ActiveSupport::Concern

  included do
    has_one_attached :cover_image
  end

  def missing_cover?
    !cover_image.attached?
  end
end
