class BookClubLeaderNotifier < ApplicationNotifier
  required_params :book_club_name, :book_title, :leader_names

  notification_methods do
    def message
      names = params[:leader_names]
      case names.size
      when 0
        "#{params[:book_club_name]} has no ranked readers for #{params[:book_title]}."
      when 1
        "#{names.first} is now first in #{params[:book_club_name]} for #{params[:book_title]}."
      else
        "#{names.to_sentence} share first place in #{params[:book_club_name]} for #{params[:book_title]}."
      end
    end

    def url
      book_club_leaderboard_path(record) if record.present?
    end
  end
end
