# Прямая загрузка в хранилище — только для вошедших пользователей и с проверкой типа/размера.
class DirectUploadsController < ActiveStorage::DirectUploadsController
  include Authentication

  before_action :validate_blob_params

  private

  def validate_blob_params
    blob = params.expect(blob: [ :byte_size, :content_type ]) rescue (return head(:unprocessable_entity))
    return head(:unprocessable_entity) if blob[:byte_size].to_i > Recording.max_upload_bytes
    head :unprocessable_entity unless Recording::ALLOWED_TYPES.include?(blob[:content_type].to_s)
  end
end
