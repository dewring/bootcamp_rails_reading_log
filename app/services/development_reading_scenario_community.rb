class DevelopmentReadingScenarioCommunity
  class CommunityError < StandardError; end

  MODELS = { "book_clubs" => BookClub, "book_club_memberships" => BookClubMembership, "club_messages" => ClubMessage, "reviews" => Review }.freeze

  def initialize(snapshot_path: Rails.root.join("db/seeds/open_library_catalog.json"),
    manifest_path: Rails.root.join("storage/development_scenarios/week15.json"),
    lock_path: Rails.root.join("storage/development_scenarios/week15.lock"),
    as_of: Time.zone.local(2026, 10, 30, 12), manifest: nil)
    @snapshot_path = snapshot_path
    @as_of = as_of
    @scenario_manifest = manifest || DevelopmentReadingScenarioManifest.new(path: manifest_path, lock_path: lock_path, as_of: as_of)
  end

  def replay_community
    with_community_context do
      @manifest["community"] = @community
      @scenario_manifest.save_scenario
      import_clubs
      [ "book_club_memberships", "club_messages", "reviews" ].each { |group| import_records(group) }
      load_community_rows
      verify_inventory
      verify_final_counts
      @community["status"] = "saved"
      @scenario_manifest.save_scenario
      @manifest.deep_dup
    end
  end

  def preflight_community
    with_community_context { @community.deep_dup }
  end

  private

  def with_community_context
    raise CommunityError, "Scenario community writes are only available in development" unless Rails.env.development?

    @scenario_manifest.with_exclusive_access do
      DevelopmentReadingScenarioActivity.new(snapshot_path: @snapshot_path, as_of: @as_of, manifest: @scenario_manifest).preflight_reading
      catalog = OpenLibraryCatalogPreflight.new(snapshot_path: @snapshot_path).preflight_catalog
      @plan = DevelopmentReadingScenarioPlan.new(catalog: catalog, as_of: @as_of).build_baseline
      @manifest = @scenario_manifest.prepare_scenario(snapshot_id: catalog.fetch("snapshot_id"))
      load_references
      @intended = planned_community
      @community = @manifest["community"] || @intended.deep_dup
      load_community_rows
      reject_existing_community unless @manifest["community"]
      verify_inventory
      yield
    end
  rescue DevelopmentReadingScenarioManifest::ManifestError, DevelopmentReadingScenarioActivity::ActivityError => error
    raise CommunityError, error.message
  end

  def load_references
    users = @manifest.fetch("bootstrap").fetch("records").fetch("users")
    @users = User.where(id: users.values.map { |record| record.fetch("id") }).includes(avatar_attachment: :blob).index_by(&:id)
    @user_ids = users.transform_values { |record| record.fetch("id") }
    @book_ids = @manifest.fetch("catalog").fetch("records").transform_values { |pair| pair.fetch("book").fetch("id") }
  end

  def planned_community
    records = MODELS.to_h do |group, _model|
      [ group, @plan.fetch(group).to_h { |entry| [ entry.fetch("identity"), planned_record(group, entry) ] } ]
    end
    { "status" => "pending", "expected_counts" => { "book_clubs" => 4, "book_club_memberships" => 24, "club_messages" => 80, "reviews" => 20 }, "records" => records }
  end

  def planned_record(group, entry)
    attributes = entry.fetch("attributes").deep_dup
    if group == "book_clubs"
      attributes["current_book_id"] = entry["current_work_key"] && @book_ids.fetch(entry.fetch("current_work_key"))
    else
      attributes["user_id"] = @user_ids.fetch(entry.fetch("reader"))
      attributes["book_id"] = @book_ids.fetch(entry.fetch("work_key")) if group == "reviews"
    end
    record = { "id" => nil, "result" => nil, "expected_attributes" => attributes }
    record["club"] = entry.fetch("club") if entry["club"]
    record["owner_id"] = @user_ids.fetch(entry.fetch("owner")) if group == "book_clubs"
    record
  end

  def load_community_rows
    names = @intended.fetch("records").fetch("book_clubs").values.map { |record| record.fetch("expected_attributes").fetch("name").downcase }
    saved_ids = @community.fetch("records").fetch("book_clubs").values.filter_map { |record| record["id"] }
    clubs = BookClub.where("LOWER(name) IN (?)", names).or(BookClub.where(id: saved_ids)).to_a
    club_ids = clubs.map(&:id)
    actors = @user_ids.values
    @rows = {
      "book_clubs" => clubs,
      "book_club_memberships" => BookClubMembership.where(user_id: actors).or(BookClubMembership.where(book_club_id: club_ids)).to_a,
      "club_messages" => ClubMessage.where(user_id: actors).or(ClubMessage.where(book_club_id: club_ids)).to_a,
      "reviews" => Review.where(user_id: actors).to_a
    }
  end

  def reject_existing_community
    existing = @rows.transform_values { |rows| rows.map(&:id) }.reject { |_group, ids| ids.empty? }
    raise CommunityError, "Unrecorded community data or a club-name collision exists: #{existing.inspect}; no automatic takeover is allowed." if existing.any?
  end

  def verify_inventory
    unless @community["expected_counts"] == @intended.fetch("expected_counts") && @community["records"].is_a?(Hash)
      raise CommunityError, "Community inventory differs from the planned scenario."
    end
    @matches = {}
    MODELS.each_key do |group|
      intended = @intended.fetch("records").fetch(group)
      saved = @community.fetch("records")[group]
      unless saved.is_a?(Hash) && saved.keys.sort == intended.keys.sort
        raise CommunityError, "Recorded #{group} identities differ from the plan."
      end
      @matches[group] = intended.to_h do |identity, expected|
        record = saved.fetch(identity)
        unless record.is_a?(Hash) && record["expected_attributes"].is_a?(Hash) && record.fetch("expected_attributes").slice(*expected.fetch("expected_attributes").keys) == expected.fetch("expected_attributes") && record.values_at("club", "owner_id") == expected.values_at("club", "owner_id")
          raise CommunityError, "Recorded #{group} #{identity} differs from its planned payload."
        end
        [ identity, match_record(group, identity, record) ]
      end
    end
    verify_no_extra_rows
    verify_club_owners
  end

  def match_record(group, identity, record)
    if record["id"]
      row = @rows.fetch(group).find { |candidate| candidate.id == record.fetch("id") }
      raise CommunityError, "Recorded #{group} #{identity} (ID #{record.fetch('id')}) is missing; no automatic recreation is allowed." unless row

      verify_record(row, group, identity, record)
      return row
    end
    expected = resolved_attributes(record)
    return if record["club"] && expected["book_club_id"].nil?

    matches = @rows.fetch(group).select { |row| attributes_for(row).slice(*expected.keys) == expected }
    if matches.length > 1
      raise CommunityError, "Ambiguous #{group} #{identity}: record IDs #{matches.map(&:id)}; review before replaying."
    end
    matches.first
  end

  def resolved_attributes(record)
    attributes = record.fetch("expected_attributes").dup
    attributes["book_club_id"] = @matches.fetch("book_clubs").fetch(record.fetch("club"))&.id if record["club"]
    attributes
  end

  def verify_record(row, group, identity, record)
    expected = resolved_attributes(record)
    unless attributes_for(row).slice(*expected.keys) == expected
      raise CommunityError, "Recorded #{group} #{identity} (ID #{row.id}) changed; no automatic overwrite is allowed."
    end
  end

  def verify_no_extra_rows
    tick_messages = @manifest.fetch("ticks", {}).flat_map do |name, tick|
      tick.fetch("club_messages", {}).map { |identity, record| [ "#{name}/#{identity}", record ] }
    end.to_h
    @tick_messages = tick_messages.to_h do |identity, record|
      [ identity, match_record("club_messages", identity, record) ]
    end
    MODELS.each_key do |group|
      selected = @matches.fetch(group).values.compact.map(&:id)
      selected.concat(@tick_messages.values.compact.map(&:id)) if group == "club_messages"
      raise CommunityError, "Two community identities claim the same #{group} row." if selected.uniq.length != selected.length

      extras = @rows.fetch(group).map(&:id) - selected
      raise CommunityError, "Unrecorded #{group}: record IDs #{extras}; review without deleting data." if extras.any?
    end
  end

  def verify_club_owners
    @matches.fetch("book_clubs").each do |identity, club|
      next unless club

      owner_id = @community.fetch("records").fetch("book_clubs").fetch(identity).fetch("owner_id")
      owners = @rows.fetch("book_club_memberships").select { |row| row.book_club_id == club.id && row.role == "owner" }
      unless owners.length == 1 && owners.first.user_id == owner_id
        raise CommunityError, "Club #{identity} (ID #{club.id}) has an unexpected owner; no automatic takeover is allowed."
      end
    end
  end

  def import_clubs
    @community.fetch("records").fetch("book_clubs").each do |identity, record|
      club = @matches.fetch("book_clubs")[identity]
      result = club ? "reused" : "imported"
      BookClub.transaction(requires_new: true) do
        if club
          club.lock!
          verify_record(club, "book_clubs", identity, record)
        else
          club = BookClubCreator.new(book_club: BookClub.new(record.fetch("expected_attributes")), owner: @users.fetch(record.fetch("owner_id"))).create_club(validation_context: :public_creation)
        end
      end
      @matches.fetch("book_clubs")[identity] = club
      snapshot_record(record, club, result)
      owner = club.book_club_memberships.find_by!(user_id: record.fetch("owner_id"), role: "owner")
      owner_identity = @plan.fetch("book_club_memberships").find { |entry| entry.fetch("club") == identity && entry.fetch("attributes").fetch("role") == "owner" }.fetch("identity")
      @matches.fetch("book_club_memberships")[owner_identity] = owner
      snapshot_record(@community.fetch("records").fetch("book_club_memberships").fetch(owner_identity), owner, result)
      @scenario_manifest.save_scenario
    rescue ActiveRecord::RecordInvalid => error
      record_failure(record, identity, error)
    end
  end

  def import_records(group)
    model = MODELS.fetch(group)
    @community.fetch("records").fetch(group).each do |identity, record|
      row = @matches.fetch(group)[identity]
      result = row ? "reused" : "imported"
      model.transaction(requires_new: true) do
        if row
          row.lock!
          verify_record(row, group, identity, record)
        else
          attributes = resolved_attributes(record)
          row = model.new(attributes)
          row.user = @users.fetch(attributes.fetch("user_id"))
          row.save!
        end
      end
      @matches.fetch(group)[identity] = row
      snapshot_record(record, row, result)
      @scenario_manifest.save_scenario
    rescue ActiveRecord::RecordInvalid => error
      record_failure(record, identity, error)
    end
  end

  def snapshot_record(record, row, result)
    record["id"] = row.id
    record["result"] = result
    record["expected_attributes"] = attributes_for(row)
    record.delete("errors")
  end

  def record_failure(record, identity, error)
    record["result"] = "failed"
    record["errors"] = error.record.errors.full_messages
    @scenario_manifest.save_scenario
    raise CommunityError, "Community record #{identity} failed validation: #{record.fetch('errors').join(', ')}"
  end

  def verify_final_counts
    counts = @matches.transform_values { |records| records.values.compact.length }
    raise CommunityError, "Community counts differ from the plan: #{counts.inspect}" unless counts == @community.fetch("expected_counts")

    @matches.fetch("book_clubs").each_value do |club|
      memberships = @rows.fetch("book_club_memberships").count { |row| row.book_club_id == club.id }
      unless memberships == 6 && club.book_club_memberships_count == memberships
        raise CommunityError, "Club ID #{club.id} membership count or counter cache differs from six."
      end
    end
    @community["actual_counts"] = counts.merge("club_messages_with_ticks" => 80 + @tick_messages.values.compact.length)
  end

  def attributes_for(row)
    JSON.parse(row.attributes.except("id", "updated_at", "book_club_memberships_count").to_json)
  end
end
