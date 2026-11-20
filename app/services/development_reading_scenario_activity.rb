class DevelopmentReadingScenarioActivity
  def initialize(manifest:, scenario_manifest:)
    @manifest = manifest
    @scenario_manifest = scenario_manifest
    @added = { "reading_sessions" => 0, "reviews" => 0, "reactions" => 0, "club_messages" => 0 }
    @skipped = {}
  end

  def simulate_reading
    require "faker"
    users = @manifest.dig("bootstrap", "records", "users").except("admin")
    ids = users.values.filter_map { |record| record["id"] unless [ "skipped", "failed" ].include?(record["result"]) }
    readers = User.where(id: ids, account_status: "active", role: "user").includes(avatar_attachment: :blob).index_by(&:id)
    book_ids = @manifest.dig("catalog", "records").values.filter_map do |pair|
      book = pair.fetch("book")
      book["id"] unless [ "skipped", "failed" ].include?(book["result"])
    end
    books = Book.where(id: book_ids).index_by(&:id)
    kinds = ReactionType.enabled.pluck(:key)
    if readers.empty? || books.empty?
      @skipped["activity"] = "Reading activity needs an available demo reader and catalog book."
    else
      simulate_reader_activity(readers.values, books, kinds)
      simulate_club_discussions(users, readers, books.values)
    end
    { "added" => @added, "skipped" => @skipped }
  end

  private

  def simulate_reader_activity(readers, books, kinds)
    reviewed = Review.where(user_id: readers, book_id: books.keys).pluck(:user_id, :book_id).group_by(&:first)
    reacted = Reaction.where(user_id: readers, book_id: books.keys).pluck(:user_id, :book_id).group_by(&:first)
    reserved = UserBook.where(user_id: readers, book_id: books.keys, status: "want_to_read").pluck(:user_id, :book_id).group_by(&:first)
    @skipped["reactions"] = "No reaction types are enabled." if kinds.empty?
    readers.each do |reader|
      # The recorder advances want-to-read shelves; preserve the reader's existing selections.
      with_available_book("reading_sessions", reader, books, reserved) do |book|
        session = ReadingSessionRecorder.new(book, reader, read_on: Date.current, pages_read: rand(3..30),
          notes: "Stopped after a few chapters of #{book.title}. It reminds me of #{Faker::Book.title}.").record
        raise ActiveRecord::RecordInvalid, session unless session.persisted?
      end
      with_available_book("reviews", reader, books, reviewed) do |book|
        rating = rand(1..5)
        impression = rating >= 4 ? "I'll look for more by #{book.author}." : "I preferred #{Faker::Book.title}, but I'm glad I tried this one."
        Review.create!(user: reader, book: book, rating: rating, body: "#{book.title} was my book club pick. #{impression}")
      end
      next if kinds.empty?

      with_available_book("reactions", reader, books, reacted) do |book|
        Reaction.create!(user: reader, book: book, kind: kinds.sample)
      end
    end
  end

  def with_available_book(group, reader, books, excluded_pairs)
    used = excluded_pairs.fetch(reader.id, []).map(&:last)
    book_id = (books.keys - used).sample
    if book_id
      add_activity(group, reader) { yield books.fetch(book_id) }
    else
      @skipped["#{group}/#{reader.id}"] = "No eligible books left for this reader."
    end
  end

  def simulate_club_discussions(users, readers, books)
    # Keep the existing club identities and owners when upgrading a Day 1 manifest.
    clubs = @manifest["simulation_clubs"] ||= {}
    [ "steady", "lapsed", "recent", "quiet" ].each_with_index do |identity, index|
      owner = readers[users.dig(format("reader%02d", 7 + index * 6), "id")]
      unless owner
        @skipped["clubs/#{identity}"] = "The demo club owner is unavailable."
        next
      end
      member_ids = (1..5).filter_map { |offset| users.dig(format("reader%02d", 7 + index * 6 + offset), "id") }
      club = find_or_create_club(identity, owner, books.sample, clubs, member_ids & readers.keys)
      next unless club

      members = club.book_club_memberships.where(user_id: readers.keys).pluck(:user_id)
      if members.empty?
        @skipped["clubs/#{identity}"] = "No active demo members."
        next
      end
      author = readers.fetch(members.sample)
      add_activity("club_messages", author) do
        ClubMessage.create!(book_club: club, user: author,
          body: "Has anyone here read #{Faker::Book.title}? I'd love to compare notes at our next meeting.")
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotFound => error
      @skipped["clubs/#{identity}"] = error.class.name.demodulize
    end
  end

  def find_or_create_club(identity, owner, book, clubs, member_ids)
    legacy = @manifest.dig("community", "records", "book_clubs", identity) || {}
    if legacy["result"] == "skipped"
      @skipped["clubs/#{identity}"] = legacy["reason"] || "Previously skipped club."
      return
    end
    id = clubs[identity] || legacy["id"]
    name = "Reading Scenario #{identity.capitalize} Readers"
    if id
      club = BookClub.find_by(id: id)
      return club if club && club.book_club_memberships.where(role: "owner").pluck(:user_id) == [ owner.id ]
    elsif !BookClub.exists?([ "LOWER(name) = ?", name.downcase ])
      club = BookClub.new(name: name, description: "A place to talk about our latest reads.", current_book: book)
      BookClub.transaction(requires_new: true) do
        BookClubCreator.new(book_club: club, owner: owner).create_club(validation_context: :public_creation)
        member_ids.each { |id| club.book_club_memberships.create!(user_id: id, role: "member") }
      end
      clubs[identity] = club.id
      @scenario_manifest.save_scenario
      return club
    end

    @skipped["clubs/#{identity}"] = "Club missing, name in use, or ownership changed."
    nil
  end

  def add_activity(group, reader)
    # The session recorder also updates the shelf. Commit both writes before counting the session.
    ApplicationRecord.transaction(requires_new: true) { yield }
    @added[group] += 1
  rescue ActiveRecord::RecordInvalid => error
    @skipped["#{group}/#{reader.id}"] = error.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotFound
    @skipped["#{group}/#{reader.id}"] = "The reader, book, or existing activity changed during this run."
  end
end
