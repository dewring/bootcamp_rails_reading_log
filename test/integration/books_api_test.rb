require "test_helper"

class BooksApiTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  setup do
    @user  = users(:leika)
    @admin = users(:admin)
    @book  = books(:refactoring)
  end

  # --- JSON index ---

  test "GET /books.json returns all books" do
    sign_in @user
    get books_path(format: :json)
    assert_response :ok
    json = JSON.parse(response.body)
    assert json.is_a?(Array)
    assert json.length >= 1
  end

  test "GET /books.json includes genres" do
    sign_in @user
    get books_path(format: :json)
    json = JSON.parse(response.body)
    assert json.first.key?("genres")
  end

  # --- Search ---

  test "GET /books.json?q= filters by title" do
    sign_in @user
    get books_path(format: :json, q: "Refactoring")
    json = JSON.parse(response.body)
    assert json.all? { |b| b["title"].downcase.include?("refactoring") || b["author"].downcase.include?("refactoring") }
  end

  test "GET /books.json?q= with no match returns empty array" do
    sign_in @user
    get books_path(format: :json, q: "zzznomatch")
    json = JSON.parse(response.body)
    assert_equal [], json
  end

  # --- Sort ---

  test "GET /books.json?sort=author sorts by author" do
    sign_in @user
    get books_path(format: :json, sort: "author")
    assert_response :ok
  end

  test "GET /books.json?sort=DROP TABLE ignores unsafe sort" do
    sign_in @user
    get books_path(format: :json, sort: "DROP TABLE books")
    assert_response :ok
  end

  # --- 404 ---

  test "GET /books/9999.json returns 404" do
    sign_in @user
    get book_path(9999, format: :json)
    assert_response :not_found
    json = JSON.parse(response.body)
    assert_equal "Not found", json["error"]
  end

  # --- 403 ---

  test "GET /books/:id/edit.json returns 403 for non-admin" do
    sign_in @user
    get edit_admin_book_path(@book, format: :json)
    assert_response :forbidden
    json = JSON.parse(response.body)
    assert_equal "Forbidden", json["error"]
  end
end
