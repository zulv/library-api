class BooksController < ApplicationController
  include Paginated

  before_action :set_book, only: [ :show, :destroy ]

  def index
    @books = paginate(Book.kept.with_serial_number(filters[:serial_number]).order(:id))
  end

  def show
  end

  def create
    @book = Book.create!(book_params)
    render :show, status: :created, location: @book
  end

  def destroy
    @book.discard!
    head :no_content
  end

  private

  def set_book
    @book = Book.kept.find(params[:id])
  end

  def filters
    params.slice(:serial_number).permit(:serial_number)
  end

  def book_params
    params.expect(book: [ :serial_number, :title, :author ])
  end
end
