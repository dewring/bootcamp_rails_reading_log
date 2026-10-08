module Admin::MembersHelper
  def admin_member_activity(member)
    date = @reading_dates[member.id]
    "#{date ? "Last read #{date.strftime('%b %-d, %Y')}" : 'No reading activity'} · #{pluralize(@book_counts.fetch(member.id, 0), 'book')}"
  end
end
