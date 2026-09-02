module LogsRecordNotFound
  def not_found
    logger.measure_info("book_not_found", payload: { id: params[:id] }) do
      super
    end
  end
end
