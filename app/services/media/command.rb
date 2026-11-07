require "open3"

module Media
  class CommandError < StandardError; end
  class TimeoutError < CommandError; end

  # Запуск внешней команды без shell, с таймаутом. stderr попадает в сообщение ошибки.
  class Command
    Result = Struct.new(:stdout, :stderr, keyword_init: true)

    def self.run(*argv, timeout: 600)
      stdout = +""
      stderr = +""
      Open3.popen3(*argv.map(&:to_s)) do |stdin, out, err, wait|
        stdin.close
        readers = [
          Thread.new { stdout << out.read.to_s },
          Thread.new { stderr << err.read.to_s }
        ]
        unless wait.join(timeout)
          Process.kill("KILL", wait.pid) rescue nil
          readers.each(&:kill)
          raise TimeoutError, "#{argv.first} не завершился за #{timeout} с"
        end
        readers.each(&:join)
        raise CommandError, "#{argv.first}: #{stderr.lines.last(3).join.strip}" unless wait.value.success?
      end
      Result.new(stdout: stdout, stderr: stderr)
    rescue Errno::ENOENT
      raise CommandError, "#{argv.first} не установлен на сервере"
    end

    def self.available?(binary)
      ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, binary)) }
    end
  end
end
