require 'rubygems'
require 'rev'
require 'term'
require 'event'

def puts_winsize
    cols, rows = TTY.get_winsize(0)
    puts "cols: #{cols}, rows: #{rows}"
end


class TermInput < Rev::IO
    def initialize ioin, ioout
        super ioin
        @ioout = ioout
    end

    def on_read(data)
        $buffer.input(data)

        @ioout.write(data)
        @ioout.flush

        $events.buffer_changed

#        $log.puts "#{data.size}: #{data}"
#        $log.puts "out: #{data.size} #{$buffer.get_bottom_line}"
    end

    def on_close
        Rev::Loop.default.stop
    end
end


class TermOutput < Rev::IO
    def initialize ioin, ioout
        super ioin
        @ioout = ioout
    end

    def on_read(data)
        data.each_byte { |b|
            x = ' '
            if b > 31 && b < 127
                x[0] = b
            end
            $log.puts "in #{b} -#{x}-"
        }

        (0..data.size).each { |i|
            if data[i].to_i == 10
                data[i] = 13
            end
        }

        @ioout.write(data)
        @ioout.flush
    end

    def on_close
        Rev::Loop.default.stop
    end
end


def on_winch
    puts "winch"
    puts_winsize
end
trap("WINCH", on_winch)

puts_winsize



$log = File.new("out.log", File::CREAT | File::TRUNC | File::WRONLY)

cols, rows = TTY.get_winsize(0)
$buffer = TerminalBuffer.new(cols, rows)
$events = TerminalEventHandler.new($buffer)
$termio = create_terminal

on_password = Proc.new {
    $termio.write("balalaika\n")
    $termio.flush
}
$events.prompt_on("password:", on_password)


TTY.set_canon 0, 0
TTY.set_echo 0, 0

TermInput.new($termio, IO.new(0)).attach(Rev::Loop.default)
TermOutput.new(IO.new(1), $termio).attach(Rev::Loop.default)

Rev::Loop.default.run


TTY.set_canon 0, 1
TTY.set_echo 0, 1

