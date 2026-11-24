require "capybara/selenium/driver"

# Capybara 3.40.0 resets Chrome between system tests by calling
# Storage.clearDataForOrigin with the wildcard origin "*". Chrome 158 rejects
# that origin ("* is not a valid URL"), so every system test errors in
# teardown and non-transactional tests leave their records behind.
#
# No Capybara release fixes this yet (teamcapybara/capybara#2865). Until one
# does, this replaces only the wildcard call: cookies are cleared for the whole
# browser, and local storage is cleared for the app server's origin, which is
# the only origin the system tests load.
#
# Remove this file once a Capybara release stops sending the wildcard origin.
module ChromeStorageReset
  STORAGE_CLEAR_COMMAND = "Storage.clearDataForOrigin"

  private

  def execute_cdp(cmd, params = {})
    return super unless wildcard_storage_clear?(cmd, params)

    super("Network.clearBrowserCookies")
    return unless local_storage_requested?(params)

    app_origin = Capybara.current_session.server&.base_url
    return if app_origin.nil?

    super(STORAGE_CLEAR_COMMAND, origin: app_origin, storageTypes: "local_storage")
  end

  def wildcard_storage_clear?(cmd, params)
    cmd == STORAGE_CLEAR_COMMAND && params[:origin] == "*"
  end

  def local_storage_requested?(params)
    params[:storageTypes].to_s.split(",").include?("local_storage")
  end
end

Capybara::Selenium::Driver::ChromeDriver.prepend(ChromeStorageReset)
