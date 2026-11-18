class DevelopmentReadingScenarioTick::Inventory
  MODELS = { "reading_sessions" => ReadingSession, "club_messages" => ClubMessage }.freeze
  attr_reader :matches

  def initialize(tick:)
    @tick = tick
  end

  def verify_tick
    @matches = MODELS.to_h do |group, model|
      records = @tick.fetch(group)
      rows = model.where(user_id: records.values.map { |record| record.fetch("expected_attributes").fetch("user_id") }).to_a
      [ group, records.to_h do |identity, record|
        [ identity, matching_record(rows, record, group) ]
      end ]
    end
  end

  def checkpoint_saved_record(group, identity, row, result)
    record = @tick.fetch(group).fetch(identity)
    record["id"] = row.id
    record["result"] = result
    record["expected_attributes"] = snapshot_attributes(row)
    record.delete("errors")
    @matches.fetch(group)[identity] = row
  end

  def saved_counts
    @matches.transform_values { |records| records.values.compact.length }
  end

  private

  def matching_record(rows, record, group)
    return if record["result"] == "skipped"

    expected = record.fetch("expected_attributes")
    if record["id"]
      row = rows.find { |candidate| candidate.id == record.fetch("id") }
      keys = group == "reading_sessions" ? [ "user_id", "book_id" ] : [ "user_id", "book_club_id" ]
      return row if row&.attributes&.slice(*keys) == expected.slice(*keys)

      record.merge!("result" => "skipped", "reason" => row ? "tick_identity_changed" : "recorded_tick_row_missing")
      return
    end
    candidates = rows.select { |row| snapshot_attributes(row).slice(*expected.keys) == expected }
    if candidates.length > 1
      record.merge!("result" => "skipped", "reason" => "ambiguous_tick_payload", "record_ids" => candidates.map(&:id).sort)
      return
    end
    candidates.first
  end

  def snapshot_attributes(row)
    row.attributes.except("id", "updated_at").as_json
  end
end
