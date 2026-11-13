class AddReadOnIndexToReadingSessions < ActiveRecord::Migration[8.1]
  # The admin report filters every reader's sessions by a read_on range.
  # The existing [user_id, read_on] index cannot serve a range that is not
  # scoped to one user.
  def change
    add_index :reading_sessions, :read_on
  end
end
