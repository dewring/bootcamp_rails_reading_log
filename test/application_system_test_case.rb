require "test_helper"
require "tmpdir"

# Selenium and Capybara communicate with local driver/server HTTP endpoints.
WebMock.disable_net_connect!(allow_localhost: true)
Capybara.save_path = File.join(Dir.tmpdir, "reading-log-system-tests")

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ] do |options|
    # External fonts/CDN styles are excluded; individual tests provide local fixtures.
    options.add_argument("--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE localhost, EXCLUDE 127.0.0.1")
  end
end
