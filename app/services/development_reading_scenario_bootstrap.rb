class DevelopmentReadingScenarioBootstrap
  class BootstrapError < StandardError; end

  BOOTSTRAP_MODELS = { "genres" => Genre, "badges" => Badge, "users" => User }.freeze

  def initialize(snapshot_path: Rails.root.join("db/seeds/open_library_catalog.json"),
    manifest_path: DevelopmentReadingScenarioManifest::DEFAULT_PATH,
    lock_path: DevelopmentReadingScenarioManifest::DEFAULT_LOCK_PATH,
    as_of: DevelopmentReadingScenarioPlan.default_reference_time, password: ENV["DEVELOPMENT_SCENARIO_PASSWORD"], manifest: nil)
    @snapshot_path = snapshot_path
    @as_of = as_of
    @password = password
    @scenario_manifest = manifest || DevelopmentReadingScenarioManifest.new(path: manifest_path, lock_path: lock_path, as_of: as_of)
  end

  def bootstrap_scenario
    with_bootstrap_context do
      @manifest["bootstrap"] = @bootstrap
      @scenario_manifest.save_scenario
      import_bootstrap_records
      record_bootstrap_counts
      @bootstrap["status"] = "complete"
      @scenario_manifest.save_scenario
      @manifest.deep_dup
    end
  end

  def preflight_bootstrap
    with_bootstrap_context { @bootstrap.deep_dup }
  end

  private

  def with_bootstrap_context
    @scenario_manifest.with_exclusive_access do
      catalog = OpenLibraryCatalogPreflight.new(snapshot_path: @snapshot_path, manifest_path: @scenario_manifest.path).preflight_catalog
      @plan = DevelopmentReadingScenarioPlan.new(catalog: catalog, as_of: @as_of).build_baseline
      @manifest = @scenario_manifest.prepare_scenario(snapshot_id: catalog.fetch("snapshot_id"))
      @prepared_records = BOOTSTRAP_MODELS.transform_values { {} }
      load_existing_records
      @bootstrap = @manifest["bootstrap"] || planned_bootstrap
      verify_recorded_rows
      prepare_pending_records
      yield
    end
  end

  def load_existing_records
    genres = Genre.where(name: @plan.fetch("genres").map { |entry| entry.fetch("name") }).order(:id).to_a
    badges = Badge.where(badge_type: @plan.fetch("badges").map { |entry| entry.fetch("badge_type") })
      .or(Badge.where(name: @plan.fetch("badges").map { |entry| entry.fetch("name") })).order(:id).to_a
    emails = @plan.fetch("users").map { |entry| entry.fetch("attributes").fetch("email") }
    nicknames = @plan.fetch("users").map { |entry| entry.fetch("attributes").fetch("nickname") }
    users = User.where("LOWER(email) IN (?) OR LOWER(nickname) IN (?)", emails, nicknames).order(:id).to_a
    @existing = {
      "genres" => @plan.fetch("genres").to_h { |entry| [ entry.fetch("name"), genres.select { |row| row.name == entry.fetch("name") } ] },
      "badges" => @plan.fetch("badges").to_h { |entry| [ entry.fetch("badge_type"), badges.select { |row| row.badge_type == entry.fetch("badge_type") } ] },
      "users" => @plan.fetch("users").to_h { |entry|
        attributes = entry.fetch("attributes")
        [ entry.fetch("identity"), users.select { |row| row.email.downcase == attributes.fetch("email") || row.nickname.downcase == attributes.fetch("nickname") } ]
      }
    }
    @badge_name_candidates = badges
  end

  def planned_bootstrap
    @existing.fetch("users").each do |identity, rows|
      refuse_collision("users", identity, rows) if rows.any?
    end
    records = { "genres" => {}, "badges" => {}, "users" => {} }
    @plan.fetch("genres").each do |attributes|
      key = attributes.fetch("name")
      records.fetch("genres")[key] = planned_record("genres", key, attributes)
    end
    @plan.fetch("badges").each do |attributes|
      key = attributes.fetch("badge_type")
      rows = @existing.fetch("badges").fetch(key)
      if rows.empty?
        collisions = @badge_name_candidates.select { |row| row.name == attributes.fetch("name") }
        refuse_collision("badges", key, collisions) if collisions.any?
      end
      records.fetch("badges")[key] = planned_record("badges", key, attributes)
    end
    @plan.fetch("users").each do |entry|
      identity = entry.fetch("identity")
      user = prepare_new_user(entry.fetch("attributes"))
      @prepared_records.fetch("users")[identity] = user
      records.fetch("users")[identity] = {
        "id" => nil, "origin" => "imported", "result" => nil,
        "expected_attributes" => recorded_attributes(user).except("created_at")
      }
    end
    { "status" => "pending", "expected_counts" => expected_counts, "records" => records }
  end

  def planned_record(group, identity, attributes)
    rows = @existing.fetch(group).fetch(identity)
    refuse_collision(group, identity, rows) if rows.length > 1
    row = rows.first
    {
      "id" => row&.id, "origin" => row ? "reused" : "imported", "result" => row ? "reused" : nil,
      "expected_attributes" => row ? recorded_attributes(row) : attributes.deep_dup
    }
  end

  def verify_recorded_rows
    @bootstrap.fetch("records").each do |group, records|
      records.each do |identity, record|
        rows = @existing.fetch(group).fetch(identity)
        refuse_collision(group, identity, rows) if rows.length > 1
        verify_recorded_row(group, identity, record, rows.first)
      end
    end
  end

  def verify_recorded_row(group, identity, record, row)
    if group == "users"
      password_hash = record.fetch("expected_attributes")["encrypted_password"]
      unless password_hash.is_a?(String) && password_hash.present?
        raise BootstrapError, "Recorded credentials for #{identity} are missing; no automatic account adoption is allowed."
      end
    end
    if record["id"] && (!row || row.id != record.fetch("id"))
      raise BootstrapError, "Recorded #{group} #{identity} (ID #{record.fetch('id')}) is missing or changed; no automatic recreation is allowed."
    end
    return unless row

    expected = record.fetch("expected_attributes")
    unless recorded_attributes(row).slice(*expected.keys) == expected
      raise BootstrapError, "Recorded #{group} #{identity} (ID #{row.id}) changed; no overwrite or account takeover is allowed."
    end
  end

  def prepare_pending_records
    @bootstrap.fetch("records").each do |group, records|
      records.each do |identity, record|
        next if @existing.fetch(group).fetch(identity).any?

        @prepared_records.fetch(group)[identity] ||= prepare_pending_record(group, record.fetch("expected_attributes"))
      end
    end
  end

  def prepare_pending_record(group, attributes)
    return prepare_new_user(attributes) if group == "users"

    row = BOOTSTRAP_MODELS.fetch(group).new(attributes)
    row.validate!
    row
  end

  def prepare_new_user(attributes)
    unless @password.is_a?(String) && @password.present?
      raise BootstrapError, "Set DEVELOPMENT_SCENARIO_PASSWORD locally before creating synthetic accounts."
    end
    user = User.new(attributes.except("encrypted_password").merge("password" => @password))
    if attributes["encrypted_password"]
      # Retain the Devise-generated hash saved before the first write, so a committed account
      # can be distinguished from an unrelated identity collision after a manifest interruption.
      user.encrypted_password = attributes.fetch("encrypted_password")
      raise BootstrapError, "The local scenario password differs from the planned credentials." unless user.valid_password?(@password)
    end
    user.validate!

    user
  end

  def import_bootstrap_records
    BOOTSTRAP_MODELS.each do |group, model|
      @bootstrap.fetch("records").fetch(group).each do |identity, record|
        row = @existing.fetch(group).fetch(identity).first
        result = row ? "reused" : "imported"
        model.transaction(requires_new: true) do
          if row
            row.lock!
            verify_recorded_row(group, identity, record, row)
          else
            row = @prepared_records.fetch(group).fetch(identity)
            row.save!
          end
        end
        @existing.fetch(group)[identity] = [ row ]
        record["id"] = row.id
        record["result"] = result
        record["expected_attributes"] = recorded_attributes(row)
        record.delete("errors")
        @scenario_manifest.save_scenario
      rescue ActiveRecord::RecordInvalid => error
        record["result"] = "failed"
        record["errors"] = error.record.errors.full_messages
        @scenario_manifest.save_scenario
        raise
      end
    end
  end

  def recorded_attributes(row)
    JSON.parse(row.attributes.except("id", "updated_at", "remember_created_at", "reset_password_token", "reset_password_sent_at").to_json)
  end

  def record_bootstrap_counts
    @bootstrap["actual_counts"] = @existing.transform_values { |records| records.values.sum(&:length) }
  end

  def expected_counts
    { "genres" => @plan.fetch("genres").length, "badges" => @plan.fetch("badges").length, "users" => @plan.fetch("users").length }
  end

  def refuse_collision(group, identity, rows)
    raise BootstrapError, "Identity collision for #{group} #{identity}: record IDs #{rows.map(&:id).join(', ')}. Review explicitly; no automatic merge or account takeover is allowed."
  end
end
