# Аудио отдаётся только владельцу, с поддержкой Range (перемотка в <audio>)
module StreamsAudio
  extend ActiveSupport::Concern

  private

  def stream_audio(recording)
    return head(:not_found) unless recording.audio_file.attached?

    blob = recording.audio_file.blob
    total = blob.byte_size
    range = parse_range(request.headers["Range"], total)

    response.headers["Accept-Ranges"] = "bytes"
    response.headers["Cache-Control"] = "private, max-age=3600"
    if range
      data = blob.service.download_chunk(blob.key, range)
      response.headers["Content-Range"] = "bytes #{range.begin}-#{range.end}/#{total}"
      send_data data, type: blob.content_type, disposition: "inline", status: :partial_content
    else
      send_data blob.download, type: blob.content_type, disposition: "inline"
    end
  end

  def parse_range(header, total)
    m = header.to_s.match(/\Abytes=(\d*)-(\d*)\z/)
    return unless m && (m[1].present? || m[2].present?)

    first, last = if m[1].empty?
      [ [ total - m[2].to_i, 0 ].max, total - 1 ]
    else
      [ m[1].to_i, m[2].present? ? [ m[2].to_i, total - 1 ].min : total - 1 ]
    end
    first <= last && first < total ? (first..last) : nil
  end
end
