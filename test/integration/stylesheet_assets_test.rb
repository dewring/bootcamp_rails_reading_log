require "test_helper"

class StylesheetAssetsTest < ActionDispatch::IntegrationTest
  test "compiled application CSS is served through the asset pipeline" do
    get ActionController::Base.helpers.asset_path("application.css")

    assert_response :success
    assert_equal "text/css", response.media_type
    assert_includes response.body, ".book-club-leaderboard-layout"
    assert_includes response.body, ".reaction-panel"
  end

  test "Sass entry point tokens and feature partials are not public assets" do
    [ "application.scss", "foundation/_tokens.scss", "features/admin/_members.scss" ].each do |path|
      assert_nil Rails.application.assets.load_path.find(path), "#{path} must remain a build input"
    end
  end
end
