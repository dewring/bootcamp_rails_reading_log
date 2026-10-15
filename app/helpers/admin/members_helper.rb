module Admin::MembersHelper
  def admin_member_deletable?(member)
    policy([ :admin, member ]).update_status? && !@club_owner_ids.include?(member.id)
  end

  def admin_member_activity(member)
    date = @reading_dates[member.id]
    "#{date ? "Last read #{date.strftime('%b %-d, %Y')}" : 'No reading activity'} · #{pluralize(@book_counts.fetch(member.id, 0), 'book')}"
  end
end
