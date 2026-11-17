class DevelopmentReadingScenarioChallenges
  class ChallengeError < StandardError; end

  def initialize(plan:, manifest:, scenario_manifest:)
    @plan = plan
    @manifest = manifest
    @scenario_manifest = scenario_manifest
  end

  def preflight_challenges
    titles = @plan.fetch("challenges").map { |entry| entry.fetch("attributes").fetch("title").downcase }
    saved_ids = @manifest.dig("challenges", "records", "challenges")&.values&.filter_map { |record| record["id"] } || []
    @challenge_rows = Challenge.where("LOWER(title) IN (?)", titles).or(Challenge.where(id: saved_ids)).to_a
    @manifest.dig("challenges", "records", "challenges")&.each do |identity, record|
      next if record["result"] == "skipped"

      matching_row(@challenge_rows, record, record.fetch("expected_attributes"), identity)
    end
  end

  def seed_challenges
    preflight_challenges
    @manifest["challenges"] ||= planned_challenges
    # Save ownership intent before committing so a retry can recognize committed rows after a failed checkpoint.
    @scenario_manifest.save_scenario
    working = @manifest.fetch("challenges").deep_dup
    user_ids = @manifest.fetch("bootstrap").fetch("records").fetch("users").values.map { |record| record.fetch("id") }
    enrollments = UserChallenge.where(user_id: user_ids).to_a

    Challenge.transaction(requires_new: true) do
      challenges = import_challenges(working)
      import_enrollments(working, challenges, enrollments)
    end

    working["status"] = "complete"
    working["actual_counts"] = working.fetch("records").transform_values do |records|
      records.values.count { |record| record["id"] }
    end
    @manifest["challenges"] = working
    @scenario_manifest.save_scenario
    @manifest.deep_dup
  end

  private

  def planned_challenges
    challenges = @plan.fetch("challenges").to_h do |entry|
      attributes = entry.fetch("attributes").merge("created_at" => @plan.fetch("as_of"))
      record = planned_record(Challenge, attributes)
      collisions = @challenge_rows.select { |row| row.title.casecmp?(attributes.fetch("title")) }
      if collisions.any?
        record.merge!("result" => "skipped", "reason" => "challenge_title_collision", "record_ids" => collisions.map(&:id).sort)
      end
      [ entry.fetch("identity"), record ]
    end
    users = @manifest.fetch("bootstrap").fetch("records").fetch("users")
    enrollments = @plan.fetch("user_challenges").to_h do |entry|
      attributes = { "user_id" => users.fetch(entry.fetch("reader")).fetch("id"), "created_at" => @plan.fetch("as_of") }
      record = planned_record(UserChallenge, attributes).merge("challenge" => entry.fetch("challenge"))
      if challenges.fetch(record.fetch("challenge"))["result"] == "skipped"
        record.merge!("result" => "skipped", "reason" => "challenge_skipped")
      end
      [ entry.fetch("identity"), record ]
    end
    {
      "status" => "pending", "expected_counts" => { "challenges" => challenges.length, "user_challenges" => enrollments.length },
      "records" => { "challenges" => challenges, "user_challenges" => enrollments }
    }
  end

  def planned_record(model, attributes)
    { "id" => nil, "expected_attributes" => model.new(attributes).attributes.slice(*attributes.keys).as_json }
  end

  def import_challenges(working)
    working.fetch("records").fetch("challenges").each_with_object({}) do |(identity, record), challenges|
      next if record["result"] == "skipped"

      expected = record.fetch("expected_attributes")
      row = matching_row(@challenge_rows, record, expected, identity) || Challenge.create!(expected)
      record["id"] = row.id
      challenges[identity] = row
    end
  end

  def import_enrollments(working, challenges, rows)
    working.fetch("records").fetch("user_challenges").each do |identity, record|
      next if record["result"] == "skipped"

      expected = record.fetch("expected_attributes").merge("challenge_id" => challenges.fetch(record.fetch("challenge")).id)
      # Progress, status and lock_version belong to normal application activity; replay must not reset them.
      row = matching_row(rows, record, expected, identity) || UserChallenge.create!(expected)
      record["id"] = row.id
      record["expected_attributes"] = expected
    end
  end

  def matching_row(rows, record, expected, identity)
    if record["id"]
      row = rows.find { |candidate| candidate.id == record.fetch("id") }
      unless row && row.attributes.slice(*expected.keys).as_json == expected
        raise ChallengeError, "Recorded challenge data #{identity} (ID #{record.fetch('id')}) is missing or changed; no automatic overwrite or recreation is allowed."
      end
      return row
    end

    matches = rows.select { |row| row.attributes.slice(*expected.keys).as_json == expected }
    raise ChallengeError, "Ambiguous challenge data #{identity}: IDs #{matches.map(&:id)}; review before replaying." if matches.length > 1

    matches.first
  end
end
