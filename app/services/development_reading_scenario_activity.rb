class DevelopmentReadingScenarioActivity
  DISCUSSION_POSTS = [
    "I went back to the first page of %{title} after finishing. It reads differently the second time.",
    "Anyone listening to the audiobook? I keep wondering how the narrator says some of these names.",
    "My library hold finally came through! How far is everyone into %{title}?",
    "If you had to give %{title} a different title, what would you call it?",
    "I have a spare copy of %{title}. Happy to bring it to the next meeting if anyone wants it.",
    "What's one line you marked? Mine is still on a scrap of paper somewhere.",
    "Would you hand %{title} to a friend without telling them what it's about first?",
    "I read the first few pages of %{title} on my lunch break and nearly forgot to go back.",
    "Can we save the ending for the second half of the meeting? I'm a few chapters behind.",
    "My paperback has a map inside the cover. What extras did everyone else's edition come with?",
    "Just finished %{title} on the bus. I need a day to sit with it before picking up anything else.",
    "What would you put next to %{title} on a bookshop display? I'd love a slightly odd pairing."
  ].freeze

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
      simulate_club_discussions(users, readers, books)
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
    prompts = DISCUSSION_POSTS.shuffle
    [ "steady", "lapsed", "recent", "quiet" ].each_with_index do |identity, index|
      owner = readers[users.dig(format("reader%02d", 7 + index * 6), "id")]
      unless owner
        @skipped["clubs/#{identity}"] = "The demo club owner is unavailable."
        next
      end
      member_ids = (1..5).filter_map { |offset| users.dig(format("reader%02d", 7 + index * 6 + offset), "id") }
      book = books.values.sample
      club = find_or_create_club(identity, owner, book, clubs, member_ids & readers.keys)
      next unless club

      members = club.book_club_memberships.where(user_id: readers.keys).pluck(:user_id)
      if members.empty?
        @skipped["clubs/#{identity}"] = "No active demo members."
        next
      end
      author = readers.fetch(members.sample)
      add_activity("club_messages", author) do
        title = books.fetch(club.current_book_id, book).title
        body = discussion_post(club, title, prompts)
        ClubMessage.create!(book_club: club, user: author, body: body)
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotFound => error
      @skipped["clubs/#{identity}"] = error.class.name.demodulize
    end
  end

  def discussion_post(club, title, prompts)
    recent = club.club_messages.order(id: :desc).limit(6).pluck(:body)
    prompt = prompts.find { |candidate| !recent.include?(format(candidate, title: title)) }
    prompts.delete(prompt)
    format(prompt, title: title)
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
