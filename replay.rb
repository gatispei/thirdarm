#require 'framework'
#add_gem_library 'rev-0.2.0'

require 'rubygems'
require 'rev'
require 'tty'


class IOForward < Rev::IO
  def initialize ioin, ioout
    super ioin
    @ioout = ioout
  end

  def on_read(data)
    @ioout.write(data)
    @ioout.flush
  end

  def on_close
#    puts "on close"
    Rev::Loop.default.stop
  end
end


def run_terminal(ioin, ioout, prog)
    x = TTY.forkpty
    if x == 0
        exec prog
        exit
    end

#    TTY.set_canon 0, 0
#    TTY.set_echo 0, 1

    io = IO.new(x)

    IOForward.new(ioin, io).attach(Rev::Loop.default)
    IOForward.new(io, ioout).attach(Rev::Loop.default)

    Rev::Loop.default.run
end

