require "open-uri"

# ── Genres ─────────────────────────────────────────────────────────────────
Genre::GENRES.each { |name| Genre.find_or_create_by!(name: name) }

# ── Admin user ──────────────────────────────────────────────────────────────
User.find_or_create_by!(nickname: "admin") do |u|
  u.first_name = "Admin"
  u.last_name  = "User"
  u.email      = "admin@thebooks.com"
  u.password   = "password123"
  u.role       = "admin"
end
# ── Regular user ─────────────────────────────────────────────────────────────
user = User.find_or_create_by!(nickname: "chii") do |u|
  u.first_name = "kawa"
  u.last_name  = "chii"
  u.email      = "chiikawa@test.com"
  u.password   = "password123"
  u.role       = "user"
end

# ── Books ───────────────────────────────────────────────────────────────────
# Cover images from Open Library: https://covers.openlibrary.org/b/id/{id}-L.jpg
books_data = [
  # 5 popular English books
  { title: "The Great Gatsby",                       author: "F. Scott Fitzgerald", pages: 185, cover_id: 10590366, genres: [ "Fiction" ] },
  { title: "To Kill a Mockingbird",                  author: "Harper Lee",          pages: 320, cover_id: 14351077, genres: [ "Fiction" ] },
  { title: "Harry Potter and the Philosopher's Stone", author: "J. K. Rowling",    pages: 302, cover_id: 15155833, genres: [ "Fantasy" ] },
  { title: "The Alchemist",                          author: "Paulo Coelho",        pages: 197, cover_id: 7414780,  genres: [ "Fiction" ] },
  { title: "Atomic Habits",                          author: "James Clear",         pages: 322, cover_id: 12539702, genres: [ "Self-Help", "Non-Fiction" ] },

  # 5 popular Korean / Korean-authored books
  { title: "The Vegetarian",                         author: "Han Kang",            pages: 190, cover_id: 7412625,  genres: [ "Fiction" ] },
  { title: "Human Acts",                             author: "Han Kang",            pages: 215, cover_id: 8047485,  genres: [ "Fiction", "History" ] },
  { title: "Kim Jiyoung, Born 1982",                 author: "Cho Nam-Ju",          pages: 176, cover_id: 9338903,  genres: [ "Fiction" ] },
  { title: "Convenience Store Woman",                author: "Sayaka Murata",       pages: 163, cover_id: 9315164,  genres: [ "Fiction" ] },
  { title: "Pachinko",                               author: "Min Jin Lee",         pages: 512, cover_id: 8044605,  genres: [ "Fiction", "History" ] }
]

books_data.each do |data|
  book = Book.find_or_create_by!(title: data[:title], author: data[:author]) do |b|
    b.total_pages = data[:pages]
  end

  # Attach cover only if not already attached
  unless book.cover_image.attached?
    cover_url = "https://covers.openlibrary.org/b/id/#{data[:cover_id]}-L.jpg"
    begin
      image = URI.open(cover_url)
      book.cover_image.attach(
        io: image,
        filename: "#{book.title.parameterize}.jpg",
        content_type: "image/jpeg"
      )
    rescue => e
      puts "  Could not attach cover for #{book.title}: #{e.message}"
    end
  end

  # Always assign genres (idempotent via uniq)
  genre_records = data[:genres].filter_map { |name| Genre.find_by(name: name) }
  book.genres = (book.genres + genre_records).uniq

  puts "  #{book.title} ✓"
end

# ── User books for chii ───────────────────────────────────────────────────
[
  { title: "The Great Gatsby",    status: "reading" },
  { title: "Atomic Habits",       status: "want_to_read" },
  { title: "The Vegetarian",      status: "finished" }
].each do |data|
  book = Book.find_by!(title: data[:title])
  UserBook.find_or_create_by!(user: user, book: book) do |ub|
    ub.status = data[:status]
  end
end

puts "\nSeeding complete: #{Book.count} books, #{Genre.count} genres."
