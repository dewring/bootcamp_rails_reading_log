require "test_helper"

class ReactionTotalsCallbacksTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  setup do
    @reader = users(:leika)
    @book = Book.create!(title: "Committed reaction totals", author: "Test author")
    @review = @book.reviews.create!(user: users(:admin), rating: 4, body: "A reflection")
    @club = BookClub.create!(name: "Committed totals discussion")
    @club.book_club_memberships.create!(user: @reader, role: "member")
    @message = @club.club_messages.create!(user: users(:admin), body: "A thought")
    @targets = [ @book, @review, @message ]
  end

  test "committed selection switching and clearing enqueue one totals refresh for each target" do
    @targets.each do |target|
      service = ReactionSelection.new(user: @reader, target: target)
      expected = [ [ target.class.name, target.id ] ]
      assert_equal expected, enqueued_jobs_for { service.select_kind(kind: "like") }
      assert_equal expected, enqueued_jobs_for { service.select_kind(kind: "love") }
      assert_equal expected, enqueued_jobs_for { service.clear_selection }
    end
  end

  test "same kind retries disabled retries absent clears and timestamp only updates enqueue nothing" do
    @targets.each do |target|
      service = ReactionSelection.new(user: @reader, target: target)
      reaction = service.select_kind(kind: "like")
      assert_no_enqueued_jobs(only: ReactionTotalsJob) do
        service.select_kind(kind: "like")
        reaction.touch
      end
    end
    reaction_types(:like).update!(enabled: false)
    @targets.each do |target|
      service = ReactionSelection.new(user: @reader, target: target)
      assert_no_enqueued_jobs(only: ReactionTotalsJob) { service.select_kind(kind: "like") }
      service.clear_selection
      assert_no_enqueued_jobs(only: ReactionTotalsJob) { service.clear_selection }
    end
  end

  test "unknown and disabled new selections do not enqueue a broadcast" do
    reaction_types(:like).update!(enabled: false)
    @targets.each do |target|
      [ "unknown", "like" ].each do |kind|
        assert_no_enqueued_jobs(only: ReactionTotalsJob) do
          assert_raises(ActiveRecord::RecordInvalid) { ReactionSelection.new(user: @reader, target: target).select_kind(kind: kind) }
        end
      end
    end
  end

  test "rolled back creates switches and clears enqueue no totals jobs" do
    @targets.each do |target|
      assert_no_enqueued_jobs(only: ReactionTotalsJob) do
        target.class.transaction(requires_new: true) do
          ReactionSelection.new(user: @reader, target: target).select_kind(kind: "like")
          raise ActiveRecord::Rollback
        end
      end
      original = ReactionSelection.new(user: @reader, target: target).select_kind(kind: "like")
      assert_no_enqueued_jobs(only: ReactionTotalsJob) do
        target.class.transaction(requires_new: true) do
          ReactionSelection.new(user: @reader, target: target).select_kind(kind: "love")
          raise ActiveRecord::Rollback
        end
        target.class.transaction(requires_new: true) do
          ReactionSelection.new(user: @reader, target: target).clear_selection
          raise ActiveRecord::Rollback
        end
      end
      assert_equal "like", original.reload.kind
    end
  end

  test "eligibility changes refresh all affected targets but unrelated and inactive to inactive changes do not" do
    @targets.each { |target| target.reactions.create!(user: @reader, kind: "like") }
    expected = @targets.map { |target| [ target.class.name, target.id ] }
    [ "suspended", "active", "invited" ].each do |status|
      jobs = enqueued_jobs_for { @reader.update!(account_status: status) }
      assert_equal expected.sort, jobs.sort
    end
    assert_no_enqueued_jobs(only: ReactionTotalsJob) { @reader.update!(account_status: "suspended") }
    assert_no_enqueued_jobs(only: ReactionTotalsJob) { @reader.update!(first_name: "Renamed") }
  end

  test "rolled back eligibility changes and account deletion publish nothing" do
    @targets.each { |target| target.reactions.create!(user: @reader, kind: "like") }
    assert_no_enqueued_jobs(only: ReactionTotalsJob) do
      User.transaction(requires_new: true) do
        @reader.update!(account_status: "suspended")
        raise ActiveRecord::Rollback
      end
      User.transaction(requires_new: true) do
        MemberAccountDeletion.new(member: @reader).delete_account
        raise ActiveRecord::Rollback
      end
    end
    assert_equal "active", User.find(@reader.id).account_status
    @targets.each { |target| assert_equal 1, target.reactions.count }
  end

  test "successful account deletion refreshes surviving targets through dependent reaction cleanup" do
    @targets.each { |target| target.reactions.create!(user: @reader, kind: "like") }

    jobs = enqueued_jobs_for { MemberAccountDeletion.new(member: @reader).delete_account }

    @targets.each do |target|
      assert_includes jobs, [ target.class.name, target.id ]
      assert_empty target.reactions.reload
    end
    assert_not User.exists?(@reader.id)
  end

  private

  def enqueued_jobs_for
    before = enqueued_jobs.size
    yield
    enqueued_jobs.drop(before).select { |job| job[:job] == ReactionTotalsJob }.map { |job| job[:args] }
  end
end
