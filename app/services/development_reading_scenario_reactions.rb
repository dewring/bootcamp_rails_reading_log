class DevelopmentReadingScenarioReactions
  class ReactionsError < StandardError; end

  ANCHORS = {
    "old_hit" => { "work_key" => "/works/OL17930368W", "likes" => 28, "dislikes" => 2, "recent_likes" => 2 },
    "new_burst" => { "work_key" => "/works/OL1968368W", "likes" => 12, "dislikes" => 1, "recent_likes" => 12 },
    "tie_c" => { "work_key" => "/works/OL18020194W", "likes" => 8, "dislikes" => 3, "recent_likes" => 6 },
    "tie_d" => { "work_key" => "/works/OL2010879W", "likes" => 7, "dislikes" => 2, "recent_likes" => 6 },
    "empty" => { "work_key" => "/works/OL17590212W", "likes" => 0, "dislikes" => 0, "recent_likes" => 0 }
  }.freeze
  COUNTS = { "book_reactions" => 160, "likes" => 120, "dislikes" => 40 }.freeze

  def initialize(snapshot_path: Rails.root.join("db/seeds/open_library_catalog.json"),
    manifest_path: DevelopmentReadingScenarioManifest::DEFAULT_PATH,
    lock_path: DevelopmentReadingScenarioManifest::DEFAULT_LOCK_PATH,
    as_of: DevelopmentReadingScenarioPlan.default_reference_time, manifest: nil)
    @snapshot_path = snapshot_path
    @scenario_manifest = manifest || DevelopmentReadingScenarioManifest.new(path: manifest_path, lock_path: lock_path, as_of: as_of)
  end

  def seed_reactions
    @scenario_manifest.with_exclusive_access do
      prepare_reactions
      @manifest["reactions"] = @reactions
      @scenario_manifest.save_scenario
      @reactions.fetch("records").each { |identity, record| import_reaction(identity, record) }
      rows = @matches.values
      @reactions["actual_counts"] = { "book_reactions" => rows.length, "likes" => rows.count { |row| row.kind == "like" }, "dislikes" => rows.count { |row| row.kind == "dislike" } }
      @reactions["status"] = "complete"
      @scenario_manifest.save_scenario
      @manifest.deep_dup
    end
  end

  private

  def prepare_reactions
    catalog = OpenLibraryCatalogPreflight.new(snapshot_path: @snapshot_path, manifest_path: @scenario_manifest.path).preflight_catalog
    @manifest = @scenario_manifest.prepare_scenario(snapshot_id: catalog.fetch("snapshot_id"))
    unless @manifest.dig("baseline", "status") == "complete"
      raise ReactionsError, "Prepare the Day 1 baseline with db:seed before seeding reactions."
    end
    load_readers
    load_books
    plan = planned_reactions
    @reactions = @manifest["reactions"] || plan
    verify_saved_plan(plan) if @manifest["reactions"]
    verify_inventory
  end

  def load_readers
    identities = (1..30).map { |number| format("reader%02d", number) }
    records = @manifest.fetch("bootstrap").fetch("records").fetch("users").slice(*identities)
    ids = records.values.map { |record| record["id"] }
    unless records.length == 30 && ids.uniq.length == 30
      raise ReactionsError, "The manifest must identify 30 distinct synthetic readers; review before seeding."
    end
    users = User.where(id: ids).index_by(&:id)
    @reader_ids = identities.to_h do |identity|
      record = records.fetch(identity)
      user = users[record["id"]]
      expected = { "email" => record.fetch("expected_attributes").fetch("email"), "role" => "user", "account_status" => "active" }
      unless user&.attributes&.slice(*expected.keys) == expected
        raise ReactionsError, "Synthetic reader #{identity} (ID #{record['id']}) is missing, changed or inactive; no reactions were written."
      end
      [ identity, user.id ]
    end
  end

  def load_books
    records = @manifest.fetch("catalog").fetch("records")
    ids = records.values.map { |pair| pair.fetch("book").fetch("id") }
    unless records.length == 100 && ids.uniq.length == 100
      raise ReactionsError, "The manifest must identify 100 distinct scenario books; review before seeding."
    end
    books = Book.where(id: ids).index_by(&:id)
    @book_ids = records.to_h do |key, pair|
      id = pair.fetch("book").fetch("id")
      raise ReactionsError, "Scenario Work #{key} (ID #{id}) is missing or changed." unless books[id]&.ol_work_key == key

      [ key, id ]
    end
    missing = ANCHORS.values.map { |anchor| anchor.fetch("work_key") } - @book_ids.keys
    raise ReactionsError, "Required reaction anchors are missing from the manifest: #{missing.join(', ')}" if missing.any?
    tie_c_id = @book_ids.fetch(ANCHORS.fetch("tie_c").fetch("work_key"))
    tie_d_id = @book_ids.fetch(ANCHORS.fetch("tie_d").fetch("work_key"))
    unless tie_c_id < tie_d_id
      raise ReactionsError, "Reaction anchors require tie_c.id < tie_d.id; preserve the books and review their identities."
    end
  end

  def planned_reactions
    @random = Random.new(DevelopmentReadingScenarioPlan::SEED)
    @as_of = Time.iso8601(@manifest.fetch("as_of")).utc
    @planned_records = {}
    anchors = ANCHORS.transform_values do |anchor|
      readers = @reader_ids.keys.shuffle(random: @random)
      key = anchor.fetch("work_key")
      readers.first(anchor.fetch("likes")).each_with_index do |reader, index|
        plan_reaction(reader, key, "like", recent: index < anchor.fetch("recent_likes"))
      end
      readers.drop(anchor.fetch("likes")).first(anchor.fetch("dislikes")).each { |reader| plan_reaction(reader, key, "dislike") }
      anchor.merge("book_id" => @book_ids.fetch(key))
    end
    other_keys = (@book_ids.keys - anchors.values.map { |anchor| anchor.fetch("work_key") }).sort.shuffle(random: @random)
    # First 65 likes and last 32 dislikes cover all 95 books; overlaps use different readers.
    other_keys.each_with_index do |key, index|
      readers = @reader_ids.keys.shuffle(random: @random)
      plan_reaction(readers.first, key, "like", recent: @random.rand(2).zero?) if index < 65
      plan_reaction(readers.last, key, "dislike") if index >= other_keys.length - 32
    end
    { "status" => "pending", "expected_counts" => COUNTS.dup, "anchors" => anchors, "records" => @planned_records }
  end

  def plan_reaction(reader, key, kind, recent: false)
    timestamp = (@as_of - (recent ? 1.day : 10.days)).iso8601(6)
    @planned_records["#{reader}/#{key}"] = {
      "id" => nil, "result" => nil,
      "expected_attributes" => {
        "user_id" => @reader_ids.fetch(reader), "book_id" => @book_ids.fetch(key), "kind" => kind,
        "created_at" => timestamp, "updated_at" => timestamp
      }
    }
  end

  def verify_saved_plan(plan)
    expected = plan.fetch("records").transform_values { |record| record.fetch("expected_attributes") }
    saved = @reactions.fetch("records").transform_values { |record| record.fetch("expected_attributes") }
    unless saved == expected && @reactions.slice("anchors", "expected_counts") == plan.slice("anchors", "expected_counts")
      raise ReactionsError, "The recorded reaction plan or anchors changed; no automatic overwrite is allowed."
    end
  end

  def verify_inventory
    saved_ids = @reactions.fetch("records").values.filter_map { |record| record["id"] }
    rows = Reaction.where(user_id: @reader_ids.values).or(Reaction.where(id: saved_ids)).to_a
    if !@manifest["reactions"] && rows.any?
      raise ReactionsError, "Unrecorded synthetic-reader reactions already exist (IDs #{rows.map(&:id)}); no automatic takeover is allowed."
    end
    by_id = rows.index_by(&:id)
    by_pair = rows.index_by { |row| [ row.user_id, row.book_id ] }
    @matches = @reactions.fetch("records").to_h do |identity, record|
      expected = record.fetch("expected_attributes")
      row = record["id"] ? by_id[record.fetch("id")] : by_pair[expected.values_at("user_id", "book_id")]
      raise ReactionsError, "Recorded reaction #{identity} (ID #{record['id']}) is missing; no automatic recreation is allowed." if record["id"] && !row

      verify_reaction(row, identity, record) if row
      [ identity, row ]
    end
    extra_ids = rows.map(&:id) - @matches.values.compact.map(&:id)
    raise ReactionsError, "Unrecorded synthetic-reader reactions: IDs #{extra_ids}; review without deleting data." if extra_ids.any?
  end

  def verify_reaction(row, identity, record)
    unless attributes_for(row) == record.fetch("expected_attributes")
      raise ReactionsError, "Recorded reaction #{identity} (ID #{row.id}) changed; no automatic overwrite is allowed."
    end
  end

  def import_reaction(identity, record)
    row = @matches.fetch(identity)
    result = row ? "reused" : "imported"
    Reaction.transaction(requires_new: true) do
      if row
        row.lock!
        verify_reaction(row, identity, record)
      else
        row = Reaction.create!(record.fetch("expected_attributes"))
      end
    end
    @matches[identity] = row
    record["id"] = row.id
    record["result"] = result
    record.delete("errors")
    @scenario_manifest.save_scenario
  rescue ActiveRecord::RecordInvalid => error
    record["result"] = "failed"
    record["errors"] = error.record.errors.full_messages
    @scenario_manifest.save_scenario
    raise
  end

  def attributes_for(row)
    row.attributes.slice("user_id", "book_id", "kind").merge(
      "created_at" => row.created_at.utc.iso8601(6), "updated_at" => row.updated_at.utc.iso8601(6))
  end
end
