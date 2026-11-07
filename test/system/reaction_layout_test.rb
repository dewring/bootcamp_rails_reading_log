require "application_system_test_case"

class ReactionLayoutTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    login_as users(:leika), scope: :user
    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    visit book_path(books(:refactoring))
    assert_selector "turbo-frame.reaction-panel"
    # Isolate form layout from the independent initial Cable snapshot refresh.
    page.execute_script('document.querySelector("[data-controller=\'reaction-stream\']").removeAttribute("data-controller")')
    page.execute_script(<<~JS, Rails.root.join("test/fixtures/stylesheets/pico_loading.css").read)
      const style = document.createElement("style")
      style.nonce = document.querySelector('meta[name="csp-nonce"]').content
      style.textContent = arguments[0]
      document.head.append(style)
    JS
    assert page.evaluate_script("document.head.lastElementChild.sheet !== null"), "Local Pico rules must load under CSP"
  end

  teardown do
    Warden.test_reset!
    ActiveJob::Base.queue_adapter = @previous_queue_adapter
  end

  test "selecting and clearing keep reaction frame geometry stable while Turbo marks it busy" do
    frame_id = "reaction_panel_book_#{books(:refactoring).id}"
    within "##{frame_id}" do
      find("summary").click
      observe_frame_geometry(frame_id)
      find(".reaction-choice[aria-label='Like']").click
      assert_selector "button[aria-pressed='true'][aria-label='Like: 1']"
    end
    assert_stable_busy_geometry(frame_id)

    within "##{frame_id}" do
      observe_frame_geometry(frame_id)
      find("button[aria-pressed='true']").click
      assert_no_selector "button[aria-pressed='true']"
    end
    assert_stable_busy_geometry(frame_id)
  end

  private

  def observe_frame_geometry(frame_id)
    page.execute_script(<<~JS, frame_id)
      const id = arguments[0]
      window.reactionLayoutSamples = []
      window.reactionLayoutObserver = new MutationObserver(() => {
        const frame = document.getElementById(id)
        if (!frame) return
        const bounds = frame.getBoundingClientRect()
        const row = frame.querySelector(".reaction-row").getBoundingClientRect()
        window.reactionLayoutSamples.push({
          busy: frame.getAttribute("aria-busy") === "true",
          height: bounds.height,
          rowOffset: row.top - bounds.top,
          rowTop: row.top + window.scrollY
        })
      })
      window.reactionLayoutObserver.observe(document.body, {
        attributes: true, childList: true, subtree: true, attributeFilter: ["aria-busy", "busy"]
      })
    JS
  end

  def assert_stable_busy_geometry(frame_id)
    samples = page.evaluate_script(<<~JS, frame_id)
      (() => {
        window.reactionLayoutObserver.disconnect()
        const frame = document.getElementById(arguments[0])
        const bounds = frame.getBoundingClientRect()
        const row = frame.querySelector(".reaction-row").getBoundingClientRect()
        return {
          busy: window.reactionLayoutSamples.filter(sample => sample.busy),
          final: { height: bounds.height, rowOffset: row.top - bounds.top, rowTop: row.top + window.scrollY }
        }
      })()
    JS
    assert_not_empty samples.fetch("busy"), "The test must observe a real Turbo busy state"
    samples.fetch("busy").each do |sample|
      [ "height", "rowOffset", "rowTop" ].each do |measurement|
        assert_in_delta samples.fetch("final").fetch(measurement), sample.fetch(measurement), 0.5,
          "Reaction #{measurement} changed during submission"
      end
    end
  end
end
