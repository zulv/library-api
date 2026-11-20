class BorrowingsController < ApplicationController
  before_action :set_book

  def create
    @borrowing = @book.borrow_by!(reader)
    render :show, status: :created, location: @book
  end

  def destroy
    @borrowing = @book.return!
    render :show
  end

  private

  def set_book
    @book = Book.kept.find(params[:book_id])
  end

  def reader
    Reader.identified.find_by!(card_number: params.expect(:reader_card_number))
  end
end
