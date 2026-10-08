class Admin::MembersController < ApplicationController
  include RequireAuthenticatedAdmin
  layout "admin"

  def index
    authorize [ :admin, User ]
    load_members
    @is_invitation = params[:invite].present?
    @selected_member = @is_invitation ? User.new : @members_scope.find_by(id: params[:member_id]) || @members.first
    load_activity
  end

  def create
    @selected_member = User.new(member_params.except(:account_status))
    authorize [ :admin, @selected_member ]
    MemberInvitation.new(member: @selected_member).invite_member
    redirect_to admin_members_path(member_id: @selected_member.id), notice: "Invitation sent."
  rescue ActiveRecord::RecordInvalid
    @is_invitation = true
    load_members
    load_activity
    render :index, status: :unprocessable_entity
  end

  def update
    @selected_member = policy_scope([ :admin, User ]).includes(:book_club_memberships).find(params[:id])
    authorize [ :admin, @selected_member ]
    attributes = member_params
    if attributes[:account_status].present? && attributes[:account_status] != @selected_member.account_status
      authorize [ :admin, @selected_member ], :update_status?
    end
    if @selected_member.update(attributes)
      redirect_to admin_members_path(member_id: @selected_member.id, **filter_params), notice: "Member updated."
    else
      load_members
      load_activity
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    member = policy_scope([ :admin, User ]).includes(:book_club_memberships).find(params[:id])
    authorize [ :admin, member ]
    MemberAccountDeletion.new(member: member).delete_account
    redirect_to admin_members_path(**filter_params.except(:page)), notice: "Member account deleted."
  end

  private

  def load_members
    @query = params[:q].to_s.strip
    @status = params[:status].to_s if %w[active invited suspended].include?(params[:status])
    @sort = params[:sort] == "name" ? "name" : "updated"
    @members_scope = policy_scope([ :admin, User ]).matching_member_text(@query).preload(:book_club_memberships)
    @members_scope = @members_scope.where(account_status: @status) if @status
    order = @sort == "name" ? { first_name: :asc, last_name: :asc, id: :asc } : { updated_at: :desc, id: :desc }
    @pagy, @members = pagy(:offset, @members_scope.order(order), limit: 4)
  end

  def load_activity
    ids = (@members.map(&:id) + [ @selected_member&.id ]).compact.uniq
    @book_counts = UserBook.where(user_id: ids).group(:user_id).count
    @reading_dates = ReadingSession.where(user_id: ids).group(:user_id).maximum(:read_on)
  end

  def member_params
    params.require(:user).permit(:first_name, :last_name, :nickname, :email, :account_status)
  end

  def filter_params
    params.permit(:q, :status, :sort, :page).to_h.symbolize_keys
  end
end
