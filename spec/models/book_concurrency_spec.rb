require "rails_helper"

RSpec.describe Book, "concurrent borrowing", type: :model do
  self.use_transactional_tests = false

  after do
    Borrowing.delete_all
    Book.delete_all
    Reader.delete_all
  end

  it "lets exactly one of two simultaneous borrowers win" do
    book = create(:book)
    readers = create_list(:reader, 2)
    start = Queue.new

    threads = readers.map do |reader|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          Book.find(book.id).borrow_by!(reader)
          :borrowed
        rescue Book::AlreadyBorrowed
          :rejected
        end
      end
    end
    2.times { start << :go }

    expect(threads.map(&:value)).to contain_exactly(:borrowed, :rejected)
    expect(Borrowing.active.where(book_id: book.id).count).to eq(1)
  end

  it "does not anonymize a reader who is borrowing at the same time" do
    book = create(:book)
    reader = create(:reader)
    start = Queue.new

    borrower = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        start.pop
        Book.find(book.id).borrow_by!(reader)
        :borrowed
      rescue ActiveRecord::RecordNotFound
        :rejected
      end
    end
    anonymizer = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        start.pop
        Reader.find(reader.id).anonymize!
        :anonymized
      rescue Reader::HasActiveBorrowing
        :refused
      end
    end
    2.times { start << :go }
    outcomes = [ borrower.value, anonymizer.value ]

    expect(outcomes).to be_in([ %i[borrowed refused], %i[rejected anonymized] ])
    expect(Borrowing.active.joins(:reader).merge(Reader.where.not(anonymized_at: nil))).to be_empty
  end
end
