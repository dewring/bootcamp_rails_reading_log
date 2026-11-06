module ReactionModelTests
  extend ActiveSupport::Concern

  included do
    test "each enabled catalog kind is a valid reaction" do
      ReactionType.enabled.each do |type|
        reaction = reaction_model.new(reaction_attributes.merge(kind: type.key))

        assert reaction.valid?, reaction.errors.full_messages.join(", ")
        assert_equal type, reaction.reaction_type
      end
    end

    test "user target and catalog kind are required" do
      [ :user_id, target_foreign_key, :kind ].each do |attribute|
        reaction = reaction_model.new(reaction_attributes.merge(attribute => nil))

        assert_not reaction.valid?
      end

      assert_not reaction_model.new(reaction_attributes.merge(kind: "unknown")).valid?
    end

    test "a user has one reaction per target regardless of kind" do
      original = reaction_model.create!(reaction_attributes)
      duplicate = reaction_model.new(reaction_attributes.merge(kind: "love"))

      assert_not duplicate.valid?
      assert_includes duplicate.errors[:user_id], "has already been taken"
      assert_equal "like", original.reload.kind
      assert reaction_model.new(reaction_attributes.merge(user: users(:jaina))).valid?
    end

    test "database uniqueness rejects duplicate pairs when validation is bypassed" do
      reaction_model.create!(reaction_attributes)
      duplicate = reaction_model.new(reaction_attributes.merge(kind: "love"))

      assert_raises(ActiveRecord::RecordNotUnique) do
        reaction_model.transaction(requires_new: true) { duplicate.save!(validate: false) }
      end
      assert_equal 1, reaction_model.count
    end

    test "database foreign keys reject missing users targets and catalog kinds" do
      invalid_attributes = [
        { user_id: User.maximum(:id) + 1 },
        { target_foreign_key => reaction_target.class.maximum(:id) + 1 },
        { kind: "unknown" }
      ]
      invalid_attributes.each do |attributes|
        reaction = reaction_model.new(reaction_attributes)
        reaction.assign_attributes(attributes)

        assert_raises(ActiveRecord::InvalidForeignKey) do
          reaction_model.transaction(requires_new: true) { reaction.save!(validate: false) }
        end
      end
      assert_equal 0, reaction_model.count
    end

    test "database required fields reject null values when validation is bypassed" do
      [ :user_id, target_foreign_key, :kind ].each do |attribute|
        reaction = reaction_model.new(reaction_attributes)
        reaction[attribute] = nil

        assert_raises(ActiveRecord::NotNullViolation) do
          reaction_model.transaction(requires_new: true) { reaction.save!(validate: false) }
        end
      end
    end

    test "eligible reactions include only active users even when the catalog kind is disabled" do
      active = reaction_model.create!(reaction_attributes)
      users(:jaina).update!(account_status: "invited")
      users(:admin).update!(account_status: "suspended")
      reaction_model.create!(reaction_attributes.merge(user: users(:jaina)))
      reaction_model.create!(reaction_attributes.merge(user: users(:admin)))
      reaction_types(:like).update!(enabled: false)

      assert_equal [ active.id ], reaction_model.eligible.pluck(:id)

      users(:leika).update!(account_status: "suspended")
      assert_empty reaction_model.eligible
      users(:leika).update!(account_status: "active")
      assert_equal [ active.id ], reaction_model.eligible.pluck(:id)
    end

    test "disabling a kind preserves existing reactions but rejects new selections" do
      original = reaction_model.create!(reaction_attributes)
      before = original.attributes
      reaction_types(:like).update!(enabled: false)

      assert original.reload.valid?
      assert_equal before, original.attributes
      assert_not reaction_model.new(reaction_attributes.merge(user: users(:jaina))).valid?

      other = reaction_model.create!(reaction_attributes.merge(user: users(:jaina), kind: "love"))
      assert_not other.update(kind: "like")
      assert_equal "love", other.reload.kind
      assert original.update(kind: "love")
      assert original.destroy
    end

    test "catalog relabeling does not change reaction identity or timestamps" do
      reaction = reaction_model.create!(reaction_attributes)
      before = reaction.attributes

      travel 1.hour do
        reaction_types(:like).update!(label: "Enjoyed it", emoji: "👨‍👩‍👧‍👦")
      end

      assert_equal before, reaction.reload.attributes
      assert_equal "Enjoyed it", reaction.reaction_type.label
    end

    test "creating changing and clearing a reaction do not touch its target or user" do
      target_before = reaction_target.attributes
      user_before = users(:leika).attributes

      travel 1.hour do
        reaction = reaction_model.create!(reaction_attributes)
        reaction.update!(kind: "love")
        reaction.destroy!
      end

      assert_equal target_before, reaction_target.reload.attributes
      assert_equal user_before, users(:leika).reload.attributes
    end

    test "destroying the target removes its dependent reactions" do
      reaction = reaction_model.create!(reaction_attributes)

      reaction_target.destroy!

      assert_not reaction_model.exists?(reaction.id)
    end

    test "a referenced catalog kind cannot be removed or renamed through SQL" do
      reaction_model.create!(reaction_attributes)
      type = reaction_types(:like)

      deletion_error = assert_raises(ActiveRecord::StatementInvalid) do
        ReactionType.transaction(requires_new: true) { ReactionType.where(id: type.id).delete_all }
      end
      assert_kind_of PG::RestrictViolation, deletion_error.cause
      rename_error = assert_raises(ActiveRecord::StatementInvalid) do
        ReactionType.transaction(requires_new: true) { ReactionType.where(id: type.id).update_all(key: "renamed") }
      end
      assert_kind_of PG::RestrictViolation, rename_error.cause
      assert_not type.destroy
      assert ReactionType.exists?(type.id)
    end
  end

  private

  def reaction_attributes
    { user: users(:leika), target_foreign_key => reaction_target.id, kind: "like" }
  end
end
