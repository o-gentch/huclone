class Recording < ApplicationRecord
  # Оригинал удаляется после успешного извлечения аудио
  KEEP_SOURCE = false
  ALLOWED_TYPES = %w[
    video/mp4 video/quicktime video/webm video/x-matroska
    audio/mpeg audio/mp4 audio/wav audio/x-wav audio/ogg
  ].freeze
  MAX_DURATION_MS = 3.hours.in_milliseconds
  MAX_UPLOAD_BYTES_LOCAL = 500.megabytes
  MAX_UPLOAD_BYTES_REMOTE = 2.gigabytes
  LOW_CONFIDENCE = 0.6

  belongs_to :persona
  has_many :utterances, -> { order(:position) }, dependent: :delete_all
  has_many :speakers, -> { order(:label) }, dependent: :delete_all
  has_many :usage_events, dependent: :nullify

  has_one_attached :source_file, dependent: :purge_later
  has_one_attached :audio_file, dependent: :purge_later

  enum :status, {
    uploaded: "uploaded",
    extracting_audio: "extracting_audio",
    transcribing: "transcribing",
    awaiting_speaker_confirmation: "awaiting_speaker_confirmation",
    confirmed: "confirmed",
    failed: "failed"
  }

  validates :title, presence: true
  validates :expected_speakers, numericality: { only_integer: true, in: 1..10 }, allow_nil: true

  before_save { self.status_changed_at = Time.current if status_changed? || status_changed_at.nil? }
  after_update_commit :broadcast_status, if: :saved_change_to_status?

  # Для списков: не грузим тяжёлые поля
  scope :for_list, -> { select(:id, :persona_id, :title, :status, :duration_ms, :error_message, :created_at, :updated_at, :status_changed_at) }

  def self.max_upload_bytes
    local_storage? ? MAX_UPLOAD_BYTES_LOCAL : MAX_UPLOAD_BYTES_REMOTE
  end

  def self.local_storage?
    ActiveStorage::Blob.service.is_a?(ActiveStorage::Service::DiskService)
  end

  def self.max_upload_label
    "#{max_upload_bytes / 1.megabyte} МБ"
  end

  def in_progress? = uploaded? || extracting_audio? || transcribing?

  def retryable? = failed? && (audio_file.attached? || source_file.attached?)

  def fail!(message)
    update!(status: "failed", error_message: message.to_s.truncate(500))
  end

  def advance!(status)
    update!(status: status, error_message: nil)
  end

  def persona_speaker = speakers.find_by(is_persona: true)

  def speaker_name(speaker)
    speaker.display_name.presence || "Спикер #{speaker.label}"
  end

  def total_speech_ms = speakers.sum(:speech_ms)

  def low_confidence_share
    total = utterances.count
    return 0.0 if total.zero?
    utterances.where("confidence < ?", LOW_CONFIDENCE).count.fdiv(total)
  end

  def duration_label
    return "—" unless duration_ms
    Recording.format_ms(duration_ms)
  end

  def self.format_ms(ms)
    s = ms.to_i / 1000
    h, rem = s.divmod(3600)
    m, sec = rem.divmod(60)
    h.positive? ? format("%d:%02d:%02d", h, m, sec) : format("%d:%02d", m, sec)
  end

  private

  def broadcast_status
    Turbo::StreamsChannel.broadcast_replace_to(
      [ persona, :recordings ], target: ActionView::RecordIdentifier.dom_id(self),
      partial: "recordings/recording", locals: { recording: self, persona: persona }
    )
    Turbo::StreamsChannel.broadcast_refresh_to([ self, :page ])
  end
end
