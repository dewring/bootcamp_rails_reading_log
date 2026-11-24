require "application_system_test_case"

# Covers test/support/chrome_storage_reset.rb, which replaces Capybara's
# wildcard-origin storage clear that Chrome 158 rejects.
class BrowserResetTest < ApplicationSystemTestCase
  test "resetting the browser session clears app cookies and local storage without raising" do
    visit root_path
    execute_script("document.cookie = 'reset_probe=1; path=/'")
    execute_script("window.localStorage.setItem('reset_probe', '1')")
    assert_equal "1", evaluate_script("window.localStorage.getItem('reset_probe')")

    Capybara.reset_sessions!
    visit root_path

    assert_not_includes evaluate_script("document.cookie"), "reset_probe"
    assert_nil evaluate_script("window.localStorage.getItem('reset_probe')")
  end
end
