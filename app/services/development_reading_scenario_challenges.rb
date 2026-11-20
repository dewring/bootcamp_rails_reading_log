class DevelopmentReadingScenarioChallenges
  def initialize(plan:, manifest:, scenario_manifest:)
    @plan = plan
    @manifest = manifest
    @scenario_manifest = scenario_manifest
  end

  def seed_challenges
    load_challenge_candidates
    @manifest["challenges"] ||= planned_challenges
    # Save ownership intent before committing so a retry can recognize committed rows after a failed checkpoint.
    @scenario_manifest.save_scenario
    working = @manifest.fetch("challenges")
    user_ids = @manifest.fetch("bootstrap").fetch("records").fetch("users").values.filter_map do |record|
      record["id"] unless [ "skipped", "failed" ].include?(record["result"])
    end
    @available_user_ids = User.where(id: user_ids).pluck(:id).to_set
    recorded_ids = working.dig("records", "user_challenges").values.filter_map { |record| record["id"] }
    enrollments = UserChallenge.where(user_id: user_ids).or(UserChallenge.where(id: recorded_ids)).to_a

    challenges = import_challenges(working)
    import_enrollments(working, challenges, enrollments)

    working["status"] = "complete"
    working["actual_counts"] = working.fetch("records").transform_values do |records|
      records.values.count { |record| record["id"] && record["result"] != "skipped" }
    end
    @scenario_manifest.save_scenario
    @manifest.deep_dup
  end

  private

  def load_challenge_candidates
    titles = @plan.fetch("challenges").map { |entry| entry.fetch("attributes").fetch("title").downcase }
    saved_ids = @manifest.dig("challenges", "records", "challenges")&.values&.filter_map { |record| record["id"] } || []
    @challenge_rows = Challenge.where("LOWER(title) IN (?)", titles).or(Challenge.where(id: saved_ids)).to_a
  end


  def planned_challenges
    challenges = @plan.fetch("challenges").to_h do |entry|
      attributes = entry.fetch("attributes").merge("created_at" => @plan.fetch("as_of"))
      record = planned_record(Challenge, attributes)
      [ entry.fetch("identity"), record ]
    end
    users = @manifest.fetch("bootstrap").fetch("records").fetch("users")
    enrollments = @plan.fetch("user_challenges").to_h do |entry|
      attributes = { "user_id" => users.fetch(entry.fetch("reader")).fetch("id"), "created_at" => @plan.fetch("as_of") }
      record = planned_record(UserChallenge, attributes).merge("challenge" => entry.fetch("challenge"))
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
      row = existing_challenge(record)
      next if record["result"] == "skipped"
      if record["id"] && !row
        record.merge!("result" => "skipped", "reason" => "recorded_challenge_missing")
        next
      end

      row ||= Challenge.create!(expected)
      record["id"] = row.id
      challenges[identity] = row
      record.except!("result", "reason") if record["result"] == "failed"
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      record.merge!("result" => "failed", "reason" => error.class.name.demodulize)
    end
  end

  def existing_challenge(record)
    id = record["id"]
    return matching_challenge(record) unless id

    # Once recorded, the ID identifies the challenge. Its current attributes belong to the application.
    @challenge_rows.find { |row| row.id == id }
  end

  def import_enrollments(working, challenges, rows)
    by_pair = rows.index_by { |row| [ row.user_id, row.challenge_id ] }
    working.fetch("records").fetch("user_challenges").each do |identity, record|
      if [ "account_unavailable", "challenge_skipped" ].include?(record["reason"])
        record.except!("result", "reason")
      end
      next if record["result"] == "skipped"

      reader = identity.split("/").first
      record.fetch("expected_attributes")["user_id"] ||= @manifest.dig("bootstrap", "records", "users", reader, "id")

      unless @available_user_ids.include?(record.dig("expected_attributes", "user_id"))
        record.merge!("result" => "skipped", "reason" => "account_unavailable")
        next
      end

      challenge = challenges[record.fetch("challenge")]
      unless challenge
        record.merge!("result" => "skipped", "reason" => "challenge_skipped")
        next
      end

      expected = record.fetch("expected_attributes").merge("challenge_id" => challenge.id)
      # Progress, status and lock_version belong to normal application activity; replay must not reset them.
      row = if record["id"]
        recorded_enrollment(rows, record, expected)
      else
        by_pair[expected.values_at("user_id", "challenge_id")]
      end
      next if record["result"] == "skipped"

      row ||= UserChallenge.create!(expected)
      record["id"] = row.id
      record["expected_attributes"] = expected
      record.except!("result", "reason") if record["result"] == "failed"
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey => error
      record.merge!("result" => "failed", "reason" => error.class.name.demodulize)
    end
  end

  def recorded_enrollment(rows, record, expected)
    row = rows.find { |candidate| candidate.id == record.fetch("id") }
    if row&.user_id == expected.fetch("user_id") && row&.challenge_id == expected.fetch("challenge_id")
      return row
    end

    reason = row ? "recorded_enrollment_identity_changed" : "recorded_enrollment_missing"
    record.merge!("result" => "skipped", "reason" => reason)
    nil
  end

  def matching_challenge(record)
    expected = record.fetch("expected_attributes").except("created_at")
    collisions = @challenge_rows.select { |row| row.title.casecmp?(expected.fetch("title")) }
    matches = collisions.select { |row| row.attributes.slice(*expected.keys).as_json == expected }
    if matches.one?
      record["result"] = "reused"
      return matches.first
    end

    if collisions.any?
      record.merge!("result" => "skipped", "reason" => "challenge_title_collision", "record_ids" => collisions.map(&:id).sort)
    end
    nil
  end
end
