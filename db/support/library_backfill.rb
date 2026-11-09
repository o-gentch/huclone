# Перенос данных «материалы принадлежат персоне» → «материалы принадлежат пользователю» (docs/DD_PLAN.md §3, §6.4–6.5).
# Работает на «сыром» SQL, чтобы не зависеть от моделей приложения. Используется миграцией
# и задачей `library:dry_run` (отчёт без изменений; запускать до миграции).
module LibraryBackfill
  class OrphanPersonas < StandardError; end

  module_function

  # ---- Отчёт (ничего не меняет) -----------------------------------------------------------------

  def report(c)
    groups = duplicate_groups(c).map { |g| plan_group(c, g) }
    {
      recordings: c.select_value("SELECT count(*) FROM recordings").to_i,
      contents: c.select_value("SELECT count(*) FROM contents").to_i,
      orphan_personas: orphan_personas(c),
      duplicate_groups: groups
    }
  end

  def print_report(report, io = $stdout)
    io.puts "Записей: #{report[:recordings]}, материалов: #{report[:contents]}"
    orphans = report[:orphan_personas]
    io.puts "Персон без владельца: #{orphans.size}#{orphans.any? ? " (#{orphans.map { |id, name| "##{id} #{name}" }.join(', ')})" : ''}"
    groups = report[:duplicate_groups]
    io.puts "Групп дублей файлов: #{groups.size}"
    groups.each do |g|
      io.puts "  • оставляем ##{g[:keeper]}, сливаем #{g[:merge].inspect}, не склеиваем #{g[:skip].inspect}"
    end
  end

  # ---- Перенос ----------------------------------------------------------------------------------

  def run!(c)
    adopt_orphans!(c)

    c.execute("UPDATE recordings r SET user_id = p.user_id FROM personas p WHERE p.id = r.persona_id")
    c.execute("UPDATE contents ct SET user_id = p.user_id FROM personas p WHERE p.id = ct.persona_id")

    c.execute(<<~SQL)
      INSERT INTO persona_recordings (persona_id, recording_id, speaker_ids, status, summary, created_at, updated_at)
      SELECT r.persona_id, r.id,
             COALESCE((SELECT array_agg(s.id ORDER BY s.id) FROM speakers s WHERE s.recording_id = r.id AND s.is_persona), '{}'::bigint[]),
             CASE WHEN r.status = 'confirmed' THEN 'ready' ELSE 'needs_speakers' END,
             r.summary, now(), now()
      FROM recordings r
    SQL

    c.execute(<<~SQL)
      UPDATE contents c SET speaker_id = s.id
      FROM speakers s
      WHERE c.kind = 'speech' AND s.recording_id = c.recording_id AND s.is_persona
    SQL

    c.execute(<<~SQL)
      INSERT INTO persona_contents (persona_id, content_id, persona_recording_id, role, is_exemplar, included_in_map, created_at, updated_at)
      SELECT c.persona_id, c.id, pr.id, 'voice', c.is_exemplar, c.included_in_map, now(), now()
      FROM contents c
      LEFT JOIN persona_recordings pr ON pr.persona_id = c.persona_id AND pr.recording_id = c.recording_id
    SQL

    c.execute("UPDATE recordings SET status = 'transcribed' WHERE status IN ('awaiting_speaker_confirmation', 'confirmed')")

    result = dedupe!(c)
    refresh_speaker_states!(c)
    result
  end

  def refresh_speaker_states!(c)
    c.execute("UPDATE speakers SET speech_state = 'ready' WHERE id IN (SELECT DISTINCT speaker_id FROM contents WHERE speaker_id IS NOT NULL)")
  end

  # ---- Персоны без владельца (§6.4) -------------------------------------------------------------

  def orphan_personas(c) = c.select_rows("SELECT id, name FROM personas WHERE user_id IS NULL")

  def adopt_orphans!(c)
    orphans = orphan_personas(c)
    return if orphans.empty?

    users = c.select_values("SELECT id FROM users")
    unless users.size == 1
      raise OrphanPersonas,
            "Есть персоны без владельца (#{orphans.map { |id, name| "##{id} «#{name}»" }.join(', ')}), " \
            "а пользователей #{users.size}. Привяжите персоны к пользователю вручную и повторите миграцию."
    end
    c.execute("UPDATE personas SET user_id = #{c.quote(users.first)} WHERE user_id IS NULL")
  end

  # ---- Дубли файлов (§6.5) ----------------------------------------------------------------------

  def duplicate_groups(c)
    c.select_values(<<~SQL).map { |ids| ids.split(",").map(&:to_i) }.map { |ids| ordered(c, ids) }
      SELECT string_agg(r.id::text, ',' ORDER BY r.id)
      FROM recordings r JOIN personas p ON p.id = r.persona_id
      WHERE r.source_checksum IS NOT NULL AND p.user_id IS NOT NULL
      GROUP BY p.user_id, r.source_checksum HAVING count(*) > 1
    SQL
  end

  # Хранитель — запись с расшифровкой (самая ранняя), иначе просто самая ранняя
  def ordered(c, ids)
    transcribed = c.select_values("SELECT id FROM recordings WHERE id IN (#{ids.join(',')}) AND status IN ('confirmed', 'awaiting_speaker_confirmation', 'transcribed')").map(&:to_i)
    ids.sort_by { |id| [ transcribed.include?(id) ? 0 : 1, id ] }
  end

  def plan_group(c, ids)
    keeper, *rest = ids
    merge, skip = rest.partition { |id| mergeable?(c, keeper, id) }
    { keeper: keeper, merge: merge, skip: skip }
  end

  def transcript(c, id)
    c.select_rows(<<~SQL)
      SELECT s.label, u.start_ms, u.end_ms, u.text
      FROM utterances u JOIN speakers s ON s.id = u.speaker_id
      WHERE u.recording_id = #{id.to_i} ORDER BY u.position
    SQL
  end

  def mergeable?(c, keeper, dup) = transcript(c, keeper) == transcript(c, dup)

  def dedupe!(c)
    groups = duplicate_groups(c).map { |ids| plan_group(c, ids) }
    groups.each do |g|
      g[:merge].each { |dup| merge!(c, g[:keeper], dup) }
      g[:skip].each { |dup| c.execute("UPDATE recordings SET source_checksum = NULL WHERE id = #{dup.to_i}") }
    end
    groups
  end

  def speakers_by_label(c, recording_id)
    c.select_rows("SELECT label, id FROM speakers WHERE recording_id = #{recording_id.to_i}").to_h.transform_values(&:to_i)
  end

  def merge!(c, keeper, dup)
    keeper_speakers = speakers_by_label(c, keeper)
    speaker_map = c.select_rows("SELECT id, label FROM speakers WHERE recording_id = #{dup.to_i}")
                   .to_h { |id, label| [ id.to_i, keeper_speakers[label] ] }

    c.select_rows("SELECT id, speaker_id, start_ms, end_ms FROM contents WHERE recording_id = #{dup.to_i}").each do |id, speaker_id, start_ms, end_ms|
      new_speaker = speaker_map[speaker_id.to_i]
      match = c.select_value(<<~SQL)
        SELECT id FROM contents
        WHERE recording_id = #{keeper.to_i} AND kind = 'speech' AND speaker_id = #{new_speaker.to_i}
          AND start_ms = #{start_ms.to_i} AND end_ms = #{end_ms.to_i}
      SQL
      if match
        c.execute("DELETE FROM persona_contents d USING persona_contents k WHERE d.content_id = #{id.to_i} AND k.content_id = #{match.to_i} AND k.persona_id = d.persona_id")
        c.execute("UPDATE persona_contents SET content_id = #{match.to_i} WHERE content_id = #{id.to_i}")
        c.execute("DELETE FROM chunks WHERE content_id = #{id.to_i}")
        c.execute("DELETE FROM contents WHERE id = #{id.to_i}")
      else
        c.execute("UPDATE contents SET recording_id = #{keeper.to_i}, speaker_id = #{new_speaker.to_i} WHERE id = #{id.to_i}")
      end
    end

    c.select_rows("SELECT id, persona_id, array_to_string(speaker_ids, ','), status FROM persona_recordings WHERE recording_id = #{dup.to_i}").each do |id, persona_id, ids, status|
      mapped = ids.to_s.split(",").map { |s| speaker_map[s.to_i] }.compact
      existing = c.select_rows("SELECT id, array_to_string(speaker_ids, ','), status FROM persona_recordings WHERE persona_id = #{persona_id.to_i} AND recording_id = #{keeper.to_i}").first
      if existing
        merged = (existing[1].to_s.split(",").map(&:to_i) + mapped).uniq.sort
        status = "ready" if existing[2] == "ready"
        c.execute("UPDATE persona_contents SET persona_recording_id = #{existing[0].to_i} WHERE persona_recording_id = #{id.to_i}")
        c.execute("UPDATE persona_recordings SET speaker_ids = #{array_literal(merged)}, status = #{c.quote(status)} WHERE id = #{existing[0].to_i}")
        c.execute("DELETE FROM persona_recordings WHERE id = #{id.to_i}")
      else
        c.execute("UPDATE persona_recordings SET recording_id = #{keeper.to_i}, speaker_ids = #{array_literal(mapped.sort)} WHERE id = #{id.to_i}")
      end
    end

    c.execute("UPDATE usage_events SET recording_id = #{keeper.to_i} WHERE recording_id = #{dup.to_i}")
    c.execute("DELETE FROM active_storage_attachments WHERE record_type = 'Recording' AND record_id = #{dup.to_i}")
    c.execute("DELETE FROM recordings WHERE id = #{dup.to_i}")
  end

  def array_literal(ids) = "ARRAY[#{ids.map(&:to_i).join(',')}]::bigint[]"
end
