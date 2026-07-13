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

# ── Regular user's challenge ─────────────────────────────────────────────────────────────
challenge = Challenge.find_or_create_by!(title: "streak 7 days") do |c|
  c.goal_type = "streak_days"
  c.goal_value = 7
  c.starts_at = 7.days.ago
  c.ends_at = 7.days.from_now
end

user_challenge = UserChallenge.find_or_create_by!(user: user, challenge: challenge) do |uc|
  uc.status = "in_progress"
end

# ── Books ───────────────────────────────────────────────────────────────────
# Cover images from Open Library: https://covers.openlibrary.org/b/id/{id}-L.jpg
books_data = [
  # English classics & literary fiction
  { title: "The Great Gatsby",                          author: "F. Scott Fitzgerald",    pages: 185,  cover_id: 10590366, genres: [ "Fiction" ] },
  { title: "To Kill a Mockingbird",                     author: "Harper Lee",             pages: 320,  cover_id: 14351077, genres: [ "Fiction" ] },
  { title: "The Alchemist",                             author: "Paulo Coelho",           pages: 197,  cover_id: 7414780,  genres: [ "Fiction" ] },
  { title: "1984",                                      author: "George Orwell",          pages: 328,  cover_id: 8745958,  genres: [ "Fiction", "Science Fiction" ] },
  { title: "Animal Farm",                               author: "George Orwell",          pages: 112,  cover_id: 11261770, genres: [ "Fiction" ] },
  { title: "Brave New World",                           author: "Aldous Huxley",          pages: 311,  cover_id: 8231823,  genres: [ "Fiction", "Science Fiction" ] },
  { title: "The Catcher in the Rye",                    author: "J. D. Salinger",         pages: 277,  cover_id: 9273490,  genres: [ "Fiction" ] },
  { title: "Of Mice and Men",                           author: "John Steinbeck",         pages: 112,  cover_id: 14319003, genres: [ "Fiction" ] },
  { title: "The Grapes of Wrath",                       author: "John Steinbeck",         pages: 464,  cover_id: 12715902, genres: [ "Fiction" ] },
  { title: "Lord of the Flies",                         author: "William Golding",        pages: 224,  cover_id: 8684447,  genres: [ "Fiction" ] },
  { title: "The Old Man and the Sea",                   author: "Ernest Hemingway",       pages: 132,  cover_id: 463307,   genres: [ "Fiction" ] },
  { title: "A Farewell to Arms",                        author: "Ernest Hemingway",       pages: 332,  cover_id: 7226599,  genres: [ "Fiction" ] },
  { title: "Crime and Punishment",                      author: "Fyodor Dostoevsky",      pages: 551,  cover_id: 13116014, genres: [ "Fiction" ] },
  { title: "The Brothers Karamazov",                    author: "Fyodor Dostoevsky",      pages: 796,  cover_id: 11263774, genres: [ "Fiction" ] },
  { title: "Anna Karenina",                             author: "Leo Tolstoy",            pages: 864,  cover_id: 2560652,  genres: [ "Fiction" ] },
  { title: "War and Peace",                             author: "Leo Tolstoy",            pages: 1225, cover_id: 12621906, genres: [ "Fiction", "History" ] },
  { title: "Don Quixote",                               author: "Miguel de Cervantes",    pages: 863,  cover_id: 14428305, genres: [ "Fiction" ] },
  { title: "One Hundred Years of Solitude",             author: "Gabriel García Márquez", pages: 417,  cover_id: 12627383, genres: [ "Fiction" ] },
  { title: "Love in the Time of Cholera",               author: "Gabriel García Márquez", pages: 348,  cover_id: 10096404, genres: [ "Fiction" ] },
  { title: "Lolita",                                    author: "Vladimir Nabokov",       pages: 317,  cover_id: 12984540, genres: [ "Fiction" ] },
  { title: "The Trial",                                 author: "Franz Kafka",            pages: 176,  cover_id: 14910748, genres: [ "Fiction" ] },
  { title: "The Metamorphosis",                         author: "Franz Kafka",            pages: 96,   cover_id: 6889547,  genres: [ "Fiction" ] },
  { title: "Beloved",                                   author: "Toni Morrison",          pages: 321,  cover_id: 8261367,  genres: [ "Fiction" ] },
  { title: "Song of Solomon",                           author: "Toni Morrison",          pages: 337,  cover_id: 9317262,  genres: [ "Fiction" ] },
  { title: "Invisible Man",                             author: "Ralph Ellison",          pages: 581,  cover_id: 998256,   genres: [ "Fiction" ] },
  { title: "Their Eyes Were Watching God",              author: "Zora Neale Hurston",     pages: 286,  cover_id: 12752055, genres: [ "Fiction" ] },
  { title: "The Color Purple",                          author: "Alice Walker",           pages: 295,  cover_id: 8564628,  genres: [ "Fiction" ] },

  # Fantasy & Science Fiction
  { title: "Harry Potter and the Philosopher's Stone",  author: "J. K. Rowling",         pages: 302,  cover_id: 15155833, genres: [ "Fantasy" ] },
  { title: "Harry Potter and the Chamber of Secrets",   author: "J. K. Rowling",         pages: 341,  cover_id: 15158664, genres: [ "Fantasy" ] },
  { title: "Harry Potter and the Prisoner of Azkaban",  author: "J. K. Rowling",         pages: 435,  cover_id: 10580435, genres: [ "Fantasy" ] },
  { title: "The Hobbit",                                author: "J. R. R. Tolkien",      pages: 310,  cover_id: 14627509, genres: [ "Fantasy" ] },
  { title: "The Fellowship of the Ring",                author: "J. R. R. Tolkien",      pages: 423,  cover_id: 14627060, genres: [ "Fantasy" ] },
  { title: "The Two Towers",                            author: "J. R. R. Tolkien",      pages: 352,  cover_id: 14627564, genres: [ "Fantasy" ] },
  { title: "The Return of the King",                    author: "J. R. R. Tolkien",      pages: 416,  cover_id: 14627062, genres: [ "Fantasy" ] },
  { title: "A Game of Thrones",                         author: "George R. R. Martin",   pages: 694,  cover_id: 9269962,  genres: [ "Fantasy" ] },
  { title: "Dune",                                      author: "Frank Herbert",          pages: 412,  cover_id: 11481354, genres: [ "Science Fiction" ] },
  { title: "Ender's Game",                              author: "Orson Scott Card",       pages: 324,  cover_id: 12996033, genres: [ "Science Fiction" ] },
  { title: "The Hitchhiker's Guide to the Galaxy",      author: "Douglas Adams",          pages: 193,  cover_id: 11972784, genres: [ "Science Fiction", "Fiction" ] },
  { title: "Fahrenheit 451",                            author: "Ray Bradbury",           pages: 158,  cover_id: 12993656, genres: [ "Science Fiction", "Fiction" ] },
  { title: "The Handmaid's Tale",                       author: "Margaret Atwood",        pages: 311,  cover_id: 8231851,  genres: [ "Fiction", "Science Fiction" ] },
  { title: "Neuromancer",                               author: "William Gibson",         pages: 271,  cover_id: 283860,   genres: [ "Science Fiction" ] },
  { title: "Foundation",                                author: "Isaac Asimov",           pages: 244,  cover_id: 9261324,  genres: [ "Science Fiction" ] },
  { title: "The Martian",                               author: "Andy Weir",              pages: 369,  cover_id: 11447888, genres: [ "Science Fiction" ] },

  # Non-fiction & Self-help
  { title: "Atomic Habits",                             author: "James Clear",            pages: 322,  cover_id: 12539702, genres: [ "Self-Help", "Non-Fiction" ] },
  { title: "Sapiens",                                   author: "Yuval Noah Harari",      pages: 443,  cover_id: 8634250,  genres: [ "Non-Fiction", "History" ] },
  { title: "Homo Deus",                                 author: "Yuval Noah Harari",      pages: 450,  cover_id: 8846275,  genres: [ "Non-Fiction" ] },
  { title: "21 Lessons for the 21st Century",           author: "Yuval Noah Harari",      pages: 352,  cover_id: 10108277, genres: [ "Non-Fiction" ] },
  { title: "Thinking, Fast and Slow",                   author: "Daniel Kahneman",        pages: 499,  cover_id: 13290711, genres: [ "Non-Fiction", "Psychology" ] },
  { title: "The Power of Habit",                        author: "Charles Duhigg",         pages: 371,  cover_id: 9078085,  genres: [ "Self-Help", "Non-Fiction" ] },
  { title: "Deep Work",                                 author: "Cal Newport",            pages: 296,  cover_id: 7988607,  genres: [ "Self-Help", "Non-Fiction" ] },
  { title: "Man's Search for Meaning",                  author: "Viktor E. Frankl",       pages: 165,  cover_id: 11203708, genres: [ "Non-Fiction", "Psychology" ] },
  { title: "The Subtle Art of Not Giving a F*ck",       author: "Mark Manson",            pages: 212,  cover_id: 8231990,  genres: [ "Self-Help", "Non-Fiction" ] },
  { title: "Outliers",                                  author: "Malcolm Gladwell",       pages: 309,  cover_id: 10021591, genres: [ "Non-Fiction" ] },
  { title: "The Tipping Point",                         author: "Malcolm Gladwell",       pages: 301,  cover_id: 10873292, genres: [ "Non-Fiction" ] },
  { title: "Blink",                                     author: "Malcolm Gladwell",       pages: 277,  cover_id: 14421850, genres: [ "Non-Fiction" ] },
  { title: "Educated",                                  author: "Tara Westover",          pages: 334,  cover_id: 8314077,  genres: [ "Non-Fiction" ] },
  { title: "Becoming",                                  author: "Michelle Obama",         pages: 448,  cover_id: 8824664,  genres: [ "Non-Fiction" ] },
  { title: "The Body Keeps the Score",                  author: "Bessel van der Kolk",    pages: 464,  cover_id: 8315367,  genres: [ "Non-Fiction", "Psychology" ] },
  { title: "Born a Crime",                              author: "Trevor Noah",            pages: 304,  cover_id: 8294078,  genres: [ "Non-Fiction" ] },

  # Mystery & Thriller
  { title: "Gone Girl",                                 author: "Gillian Flynn",          pages: 422,  cover_id: 8368314,  genres: [ "Mystery" ] },
  { title: "The Girl with the Dragon Tattoo",           author: "Stieg Larsson",          pages: 672,  cover_id: 9274740,  genres: [ "Mystery" ] },
  { title: "The Da Vinci Code",                         author: "Dan Brown",              pages: 454,  cover_id: 9255229,  genres: [ "Mystery" ] },
  { title: "And Then There Were None",                  author: "Agatha Christie",        pages: 264,  cover_id: 11172296, genres: [ "Mystery" ] },
  { title: "Murder on the Orient Express",              author: "Agatha Christie",        pages: 256,  cover_id: 11100465, genres: [ "Mystery" ] },
  { title: "The Silence of the Lambs",                  author: "Thomas Harris",          pages: 338,  cover_id: 8580475,  genres: [ "Mystery" ] },
  { title: "In the Woods",                              author: "Tana French",            pages: 429,  cover_id: 1474730,  genres: [ "Mystery" ] },
  { title: "Big Little Lies",                           author: "Liane Moriarty",         pages: 460,  cover_id: 7352410,  genres: [ "Mystery", "Fiction" ] },

  # Romance & Contemporary
  { title: "Pride and Prejudice",                       author: "Jane Austen",            pages: 432,  cover_id: 14348537, genres: [ "Fiction", "Romance" ] },
  { title: "Sense and Sensibility",                     author: "Jane Austen",            pages: 369,  cover_id: 9278292,  genres: [ "Fiction", "Romance" ] },
  { title: "Jane Eyre",                                 author: "Charlotte Brontë",       pages: 507,  cover_id: 8235363,  genres: [ "Fiction", "Romance" ] },
  { title: "Wuthering Heights",                         author: "Emily Brontë",           pages: 342,  cover_id: 12818862, genres: [ "Fiction", "Romance" ] },
  { title: "The Notebook",                              author: "Nicholas Sparks",        pages: 214,  cover_id: 7382153,  genres: [ "Fiction", "Romance" ] },
  { title: "Normal People",                             author: "Sally Rooney",           pages: 266,  cover_id: 8794265,  genres: [ "Fiction", "Romance" ] },
  { title: "Conversations with Friends",                author: "Sally Rooney",           pages: 320,  cover_id: 8199499,  genres: [ "Fiction", "Romance" ] },

  # Korean & East Asian
  { title: "The Vegetarian",                            author: "Han Kang",               pages: 190,  cover_id: 7412625,  genres: [ "Fiction" ] },
  { title: "Human Acts",                                author: "Han Kang",               pages: 215,  cover_id: 8047485,  genres: [ "Fiction", "History" ] },
  { title: "The White Book",                            author: "Han Kang",               pages: 160,  cover_id: 10227226, genres: [ "Fiction" ] },
  { title: "Kim Jiyoung, Born 1982",                    author: "Cho Nam-Ju",             pages: 176,  cover_id: 9338903,  genres: [ "Fiction" ] },
  { title: "Convenience Store Woman",                   author: "Sayaka Murata",          pages: 163,  cover_id: 9315164,  genres: [ "Fiction" ] },
  { title: "Pachinko",                                  author: "Min Jin Lee",            pages: 512,  cover_id: 8044605,  genres: [ "Fiction", "History" ] },
  { title: "The Hen Who Dreamed She Could Fly",         author: "Sun-mi Hwang",           pages: 170,  cover_id: 7277009,  genres: [ "Fiction" ] },
  { title: "I Have the Right to Destroy Myself",        author: "Kim Young-ha",           pages: 128,  cover_id: 10995860, genres: [ "Fiction" ] },
  { title: "Please Look After Mom",                     author: "Kyung-sook Shin",        pages: 272,  cover_id: 6717330,  genres: [ "Fiction" ] },
  { title: "Kafka on the Shore",                        author: "Haruki Murakami",        pages: 505,  cover_id: 11104039, genres: [ "Fiction" ] },
  { title: "Norwegian Wood",                            author: "Haruki Murakami",        pages: 296,  cover_id: 2237620,  genres: [ "Fiction", "Romance" ] },
  { title: "1Q84",                                      author: "Haruki Murakami",        pages: 925,  cover_id: 11153243, genres: [ "Fiction", "Science Fiction" ] },
  { title: "After Dark",                                author: "Haruki Murakami",        pages: 191,  cover_id: 13524033, genres: [ "Fiction" ] },
  { title: "Kokoro",                                    author: "Natsume Soseki",         pages: 248,  cover_id: 3970410,  genres: [ "Fiction" ] },
  { title: "Snow Country",                              author: "Yasunari Kawabata",      pages: 175,  cover_id: 421172,   genres: [ "Fiction" ] },

  # Graphic novels
  { title: "Maus",                                      author: "Art Spiegelman",         pages: 296,  cover_id: 10210168, genres: [ "Non-Fiction", "History" ] },
  { title: "Persepolis",                                author: "Marjane Satrapi",        pages: 343,  cover_id: 12648921, genres: [ "Non-Fiction" ] },

  # More popular contemporary
  { title: "The Kite Runner",                           author: "Khaled Hosseini",        pages: 371,  cover_id: 14846827, genres: [ "Fiction" ] },
  { title: "A Thousand Splendid Suns",                  author: "Khaled Hosseini",        pages: 372,  cover_id: 8579790,  genres: [ "Fiction" ] },
  { title: "The Book Thief",                            author: "Markus Zusak",           pages: 552,  cover_id: 8153054,  genres: [ "Fiction", "History" ] },
  { title: "All the Light We Cannot See",               author: "Anthony Doerr",          pages: 531,  cover_id: 14559680, genres: [ "Fiction", "History" ] },
  { title: "The Nightingale",                           author: "Kristin Hannah",         pages: 440,  cover_id: 8314147,  genres: [ "Fiction", "History" ] },
  { title: "Where the Crawdads Sing",                   author: "Delia Owens",            pages: 368,  cover_id: 8362947,  genres: [ "Fiction", "Mystery" ] },
  { title: "Little Fires Everywhere",                   author: "Celeste Ng",             pages: 338,  cover_id: 8111914,  genres: [ "Fiction" ] },
  { title: "Everything I Never Told You",               author: "Celeste Ng",             pages: 292,  cover_id: 7383473,  genres: [ "Fiction", "Mystery" ] },
  { title: "The Road",                                  author: "Cormac McCarthy",        pages: 287,  cover_id: 198120,   genres: [ "Fiction" ] },
  { title: "No Country for Old Men",                    author: "Cormac McCarthy",        pages: 307,  cover_id: 9296899,  genres: [ "Fiction", "Mystery" ] }
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
