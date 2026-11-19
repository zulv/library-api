class ReadersController < ApplicationController
  include Paginated

  before_action :set_reader, only: [ :show, :destroy ]

  def index
    @readers = paginate(Reader.identified.with_card_number(filters[:card_number]).order(:id))
  end

  def show
  end

  def create
    @reader = Reader.create!(reader_params)
    render :show, status: :created, location: @reader
  end

  def destroy
    @reader.anonymize!
    head :no_content
  end

  private

  def set_reader
    @reader = Reader.identified.find(params[:id])
  end

  def filters
    params.slice(:card_number).permit(:card_number)
  end

  def reader_params
    params.expect(reader: [ :card_number, :full_name, :email ])
  end
end
