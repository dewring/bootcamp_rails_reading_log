require "application_system_test_case"

class ReviewSubmissionTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    login_as users(:jaina), scope: :user
    @book = books(:refactoring)
  end

  teardown do
    Warden.test_reset!
  end

  test "submitting a rated review from the book page saves it and shows it on the page" do
    visit book_path(@book)
    click_button "Write a Review"
    find("label[for='book_review_rating_4']").click
    fill_in "review[body]", with: "Clear, practical refactoring steps."
    click_button "Submit Review"

    assert_text "Review added!"
    assert_selector ".book-detail-review-card p", text: "Clear, practical refactoring steps."
    assert_equal 4, users(:jaina).reviews.find_by!(book: @book).rating
  end

  test "the Edit review button in the reader's own card opens the composer and updates that review" do
    review = reviews(:review1)
    login_as review.user, scope: :user

    visit book_path(@book)
    within("##{ActionView::RecordIdentifier.dom_id(review)}") { click_button "Edit review" }
    find("label[for='book_review_rating_5']").click
    fill_in "review[body]", with: "Even better on a second read."
    click_button "Update Review"

    assert_text "Review updated!"
    assert_selector "##{ActionView::RecordIdentifier.dom_id(review)} p", text: "Even better on a second read."
    assert_equal 5, review.reload.rating
  end

  test "submitting a review without a rating is blocked on the book page and keeps the typed text" do
    visit book_path(@book)
    click_button "Write a Review"
    fill_in "review[body]", with: "Forgot to pick stars."
    click_button "Submit Review"

    assert_current_path book_path(@book)
    assert_selector ".book-detail-review-composer:not([hidden])"
    assert_field "review[body]", with: "Forgot to pick stars."
    assert_equal "valueMissing", page.evaluate_script(<<~JS)
      document.querySelector("#book_review_rating_1").validity.valueMissing ? "valueMissing" : "valid"
    JS
    assert_not users(:jaina).reviews.exists?(book: @book)
  end
end
