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
        [ identity, matching_record(rows, record, group, identity) ]
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

  def verify_saved_record(record, row, identity)
    expected = record.fetch("expected_attributes")
    unless snapshot_attributes(row).slice(*expected.keys) == expected
      raise DevelopmentReadingScenarioTick::TickError, "Recorded tick #{identity} (ID #{row.id}) changed; no automatic overwrite is allowed."
    end
  end

  def matching_record(rows, record, group, identity)
    if record["id"]
      row = rows.find { |candidate| candidate.id == record.fetch("id") }
      raise DevelopmentReadingScenarioTick::TickError, "Recorded tick #{group} #{identity} (ID #{record.fetch('id')}) is missing; no automatic recreation is allowed." unless row

      verify_saved_record(record, row, identity)
      return row
    end
    expected = record.fetch("expected_attributes")
    candidates = rows.select { |row| snapshot_attributes(row).slice(*expected.keys) == expected }
    if candidates.length > 1
      raise DevelopmentReadingScenarioTick::TickError, "Ambiguous tick #{group} #{identity}: record IDs #{candidates.map(&:id)}; no records were changed."
    end
    candidates.first
  end

  def snapshot_attributes(row)
    row.attributes.except("id", "updated_at").as_json
  end
end
