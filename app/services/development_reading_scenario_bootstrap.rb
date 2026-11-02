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
      verify_bootstrap_totals
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
    raise BootstrapError, "Scenario bootstrap is only available in development" unless Rails.env.development?

    @scenario_manifest.with_exclusive_access do
      catalog = OpenLibraryCatalogPreflight.new(snapshot_path: @snapshot_path).preflight_catalog
      @plan = DevelopmentReadingScenarioPlan.new(catalog: catalog, as_of: @as_of).build_baseline
      @manifest = @scenario_manifest.prepare_scenario(snapshot_id: catalog.fetch("snapshot_id"))
      @prepared_users = {}
      load_existing_records
      @bootstrap = @manifest["bootstrap"] || planned_bootstrap
      validate_inventory
      verify_recorded_rows
      validate_pending_writes
      yield
    end
  rescue DevelopmentReadingScenarioManifest::ManifestError => error
    raise BootstrapError, error.message
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
      @prepared_users[identity] = user
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

  def validate_inventory
    unless @bootstrap.is_a?(Hash) && @bootstrap["expected_counts"] == expected_counts && @bootstrap["records"].is_a?(Hash)
      raise BootstrapError, "Recorded bootstrap inventory differs from the scenario plan."
    end
    BOOTSTRAP_MODELS.each_key do |group|
      records = @bootstrap.fetch("records")[group]
      unless records.is_a?(Hash) && records.keys.sort == @existing.fetch(group).keys.sort
        raise BootstrapError, "Recorded #{group} identities differ from the scenario plan."
      end
      records.each do |identity, record|
        unless record.is_a?(Hash) && record["expected_attributes"].is_a?(Hash) && [ "imported", "reused" ].include?(record["origin"])
          raise BootstrapError, "Invalid recorded #{group} identity #{identity}."
        end
        if group == "users"
          attributes = @plan.fetch("users").find { |entry| entry.fetch("identity") == identity }.fetch("attributes")
          password_hash = record.fetch("expected_attributes")["encrypted_password"]
          unless record.fetch("expected_attributes").slice(*attributes.keys) == attributes && record["origin"] == "imported" && password_hash.is_a?(String) && password_hash.present?
            raise BootstrapError, "Recorded user #{identity} differs from the synthetic account plan."
          end
        else
          key_name = group == "genres" ? "name" : "badge_type"
          unless record.fetch("expected_attributes")[key_name] == identity
            raise BootstrapError, "Recorded #{group} #{identity} differs from its planned identity."
          end
        end
      end
    end
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
    if record["id"] && (!row || row.id != record.fetch("id"))
      raise BootstrapError, "Recorded #{group} #{identity} (ID #{record.fetch('id')}) is missing or changed; no automatic recreation is allowed."
    end
    return unless row

    expected = record.fetch("expected_attributes")
    unless recorded_attributes(row).slice(*expected.keys) == expected
      raise BootstrapError, "Recorded #{group} #{identity} (ID #{row.id}) changed; no overwrite or account takeover is allowed."
    end
  end

  def validate_pending_writes
    @bootstrap.fetch("records").each do |group, records|
      records.each do |identity, record|
        next if @existing.fetch(group).fetch(identity).any?

        if group == "users"
          @prepared_users[identity] ||= prepare_new_user(record.fetch("expected_attributes"))
        else
          row = BOOTSTRAP_MODELS.fetch(group).new(record.fetch("expected_attributes"))
          raise BootstrapError, "Invalid planned #{group} #{identity}: #{row.errors.full_messages.join(', ')}" unless row.valid?
        end
      end
    end
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
    raise BootstrapError, "Invalid planned synthetic account: #{user.errors.full_messages.join(', ')}" unless user.valid?

    user
  rescue BCrypt::Errors::InvalidHash
    raise BootstrapError, "Recorded scenario credentials are invalid; preserve the manifest and review before retrying."
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
            row = group == "users" ? @prepared_users.fetch(identity) : model.new(record.fetch("expected_attributes"))
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
        raise BootstrapError, "Could not save #{group} #{identity}; previously committed records remain resumable."
      end
    end
  end

  def recorded_attributes(row)
    JSON.parse(row.attributes.except("id", "updated_at", "remember_created_at", "reset_password_token", "reset_password_sent_at").to_json)
  end

  def verify_bootstrap_totals
    actual = BOOTSTRAP_MODELS.to_h do |group, model|
      ids = @bootstrap.fetch("records").fetch(group).values.map { |record| record.fetch("id") }
      [ group, model.where(id: ids).count ]
    end
    raise BootstrapError, "Unexpected bootstrap totals: #{actual.inspect}" unless actual == expected_counts

    @bootstrap["actual_counts"] = actual
  end

  def expected_counts
    { "genres" => @plan.fetch("genres").length, "badges" => @plan.fetch("badges").length, "users" => @plan.fetch("users").length }
  end

  def refuse_collision(group, identity, rows)
    raise BootstrapError, "Identity collision for #{group} #{identity}: record IDs #{rows.map(&:id).join(', ')}. Review explicitly; no automatic merge or account takeover is allowed."
  end
end
