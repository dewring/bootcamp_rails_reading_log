require "test_helper"

class HasAttachedCoverImageTest < ActiveSupport::TestCase
  class DummyCoverRecord < ApplicationRecord
    self.table_name = "books"
    include HasAttachedCoverImage
  end

  test "missing_cover? is true when nothing is attached" do
    record = DummyCoverRecord.new

    assert record.missing_cover?
  end

  test "missing_cover? is false once a cover is attached" do
    record = DummyCoverRecord.new
    record.cover_image.attach(io: StringIO.new("fake image data"), filename: "cover.jpg", content_type: "image/jpeg")

    assert_not record.missing_cover?
  end
end
