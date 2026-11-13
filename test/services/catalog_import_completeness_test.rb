require "test_helper"

class CatalogImportCompletenessTest < ActiveSupport::TestCase
  def with_snapshot(work_keys)
    file = Tempfile.new([ "open_library_catalog", ".json" ])
    file.write({ "selected" => work_keys.map { |key| { "work_key" => key } } }.to_json)
    file.flush
    yield file.path
  ensure
    file.close!
  end

  test "selected Works count as imported whether the book stores the full or bare work key" do
    Book.create!(title: "Full Key", author: "Author", ol_work_key: "/works/OL1W")
    Book.create!(title: "Bare Key", author: "Author", ol_work_key: "OL2W")

    with_snapshot([ "/works/OL1W", "/works/OL2W", "/works/OL3W" ]) do |path|
      result = CatalogImportCompleteness.new(snapshot_path: path).completeness

      assert_equal 3, result.selected_count
      assert_equal 2, result.imported_count
      assert_equal 1, result.missing_count
    end
  end

  test "books that are not in the selected snapshot do not raise completeness" do
    Book.create!(title: "Unselected", author: "Author", ol_work_key: "/works/OL999W")

    with_snapshot([ "/works/OL1W" ]) do |path|
      result = CatalogImportCompleteness.new(snapshot_path: path).completeness

      assert_equal 0, result.imported_count
    end
  end

  test "a missing snapshot reports zero selected Works instead of raising" do
    result = CatalogImportCompleteness.new(snapshot_path: Rails.root.join("tmp/no_such_snapshot.json")).completeness

    assert_equal 0, result.selected_count
    assert_equal 0, result.imported_count
  end

  test "the committed snapshot selects 100 Works" do
    assert_equal 100, CatalogImportCompleteness.new.completeness.selected_count
  end
end
