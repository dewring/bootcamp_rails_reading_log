require "test_helper"

class DiscoveryExposureTest < ActiveSupport::TestCase
  setup do
    @attributes = {
      user: users(:leika), experiment_key: DiscoveryExposure::EXPERIMENT_KEY,
      variant: "control", shown_book_ids: [ books(:refactoring).id ], exposed_at: Time.current
    }
  end

  test "both variants can store an exposure without a conversion" do
    [ "control", "treatment" ].each do |variant|
      exposure = DiscoveryExposure.new(**@attributes, variant: variant)

      assert exposure.valid?, exposure.errors.full_messages.to_sentence
      assert_nil exposure.converted_at
    end
  end

  test "user experiment variant shown books and exposure time are required" do
    [ :user, :experiment_key, :variant, :shown_book_ids, :exposed_at ].each do |attribute|
      exposure = DiscoveryExposure.new(**@attributes, attribute => nil)

      assert_not exposure.valid?, "Expected #{attribute} to be required"
    end
  end

  test "the database rejects a duplicate user experiment but permits other users and experiments" do
    DiscoveryExposure.create!(@attributes)

    assert_raises(ActiveRecord::RecordNotUnique) do
      DiscoveryExposure.transaction(requires_new: true) do
        DiscoveryExposure.new(@attributes).save!(validate: false)
      end
    end

    assert DiscoveryExposure.create!(**@attributes, user: users(:jaina)).persisted?
    assert DiscoveryExposure.create!(**@attributes, experiment_key: "discovery_v2").persisted?
  end

  test "conversion permits the exact exposure time and excludes the exact 24 hour boundary" do
    exposed_at = @attributes.fetch(:exposed_at)

    assert DiscoveryExposure.new(**@attributes, converted_at: exposed_at).valid?
    assert DiscoveryExposure.new(**@attributes, converted_at: exposed_at + 24.hours - 1.second).valid?
    assert_not DiscoveryExposure.new(**@attributes, converted_at: exposed_at - 1.second).valid?
    assert_not DiscoveryExposure.new(**@attributes, converted_at: exposed_at + 24.hours).valid?
  end

  test "database checks reject blank experiments invalid variants empty books and out of window conversions" do
    invalid_values = [
      { experiment_key: " " }, { variant: "unknown" }, { shown_book_ids: [] },
      { converted_at: @attributes.fetch(:exposed_at) - 1.second },
      { converted_at: @attributes.fetch(:exposed_at) + 24.hours }
    ]

    invalid_values.each do |values|
      assert_raises(ActiveRecord::StatementInvalid) do
        DiscoveryExposure.transaction(requires_new: true) do
          DiscoveryExposure.new(**@attributes, **values).save!(validate: false)
        end
      end
    end
  end

  test "the database rejects an exposure for a missing user" do
    assert_raises(ActiveRecord::InvalidForeignKey) do
      DiscoveryExposure.transaction(requires_new: true) do
        exposure = DiscoveryExposure.new(**@attributes, user: nil, user_id: User.maximum(:id) + 1)
        exposure.save!(validate: false)
      end
    end
  end

  test "deleting an account removes its exposure" do
    reader = User.create!(first_name: "Exposure", last_name: "Reader", nickname: "exposure-reader",
      email: "exposure-reader@example.test", password: "test-password-145")
    exposure = DiscoveryExposure.create!(**@attributes, user: reader)

    reader.destroy!

    assert_not DiscoveryExposure.exists?(exposure.id)
  end
end
