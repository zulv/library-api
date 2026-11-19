if Rails.env.development?
  User.find_or_create_by!(email_address: "librarian@example.com") do |user|
    user.password = "password"
  end

  [
    [ "100001", "Pan Tadeusz", "Adam Mickiewicz" ],
    [ "100002", "Lalka", "Bolesław Prus" ],
    [ "100003", "Quo Vadis", "Henryk Sienkiewicz" ],
    [ "100004", "Ferdydurke", "Witold Gombrowicz" ],
    [ "100005", "Solaris", "Stanisław Lem" ],
    [ "100006", "Chłopi", "Władysław Reymont" ],
    [ "100007", "Przedwiośnie", "Stefan Żeromski" ],
    [ "100008", "Wiedźmin: Ostatnie życzenie", "Andrzej Sapkowski" ],
    [ "100009", "Bieguni", "Olga Tokarczuk" ],
    [ "100010", "Mistrz i Małgorzata", "Michaił Bułhakow" ],
    [ "100011", "Rok 1984", "George Orwell" ],
    [ "100012", "Zbrodnia i kara", "Fiodor Dostojewski" ],
    [ "100013", "Sto lat samotności", "Gabriel García Márquez" ],
    [ "100014", "Proces", "Franz Kafka" ],
    [ "100015", "Mały Książę", "Antoine de Saint-Exupéry" ]
  ].each do |serial_number, title, author|
    Book.find_or_create_by!(serial_number:) do |book|
      book.title = title
      book.author = author
    end
  end
end
